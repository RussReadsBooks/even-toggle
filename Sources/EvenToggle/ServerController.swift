//
//  ServerController.swift
//  The brain of the app. Holds your settings (saved automatically) and
//  starts/stops the `even-terminal` server as a child process.
//
//  Mental model: this is like typing the `even-terminal ...` command for you,
//  with your saved token/port/folder/model filled in — and killing it when you
//  toggle off. Because the token and port never change, the host you paired on
//  your glasses keeps working across restarts. Pair once, reuse forever.
//
//  IMPORTANT (why this file is more than a one-liner): a GUI app launched from
//  Finder does NOT inherit your Terminal's PATH. Tools installed via nvm, Volta,
//  asdf, fnm, or Homebrew live in directories the app can't see, so `node` and
//  `even-terminal` appear "not found". To fix this for everyone, the app asks
//  your login shell for its real PATH (exactly what Terminal uses) and finds
//  even-terminal automatically. No symlinks or manual paths required.
//

import SwiftUI
import Foundation

@MainActor
final class ServerController: ObservableObject {

    // Live state (drives the menu bar + status line).
    @Published private(set) var isRunning = false
    @Published var lastLog = ""

    // Persisted settings. @AppStorage saves these to disk automatically.
    @AppStorage("token")            var token = ""
    @AppStorage("port")             var port = "3456"
    @AppStorage("provider")         var provider = "claude"        // "claude" or "codex"
    @AppStorage("model")            var model = "default"          // default|sonnet|opus|haiku|fable|custom
    @AppStorage("customModel")      var customModel = ""
    @AppStorage("projectPath")      var projectPath = ""
    @AppStorage("useTailscale")     var useTailscale = true
    @AppStorage("keepAwake")        var keepAwake = true
    // Leave blank to auto-detect. Only set this to override the detected path.
    @AppStorage("evenTerminalPath") var evenTerminalPath = ""

    private var process: Process?
    private var cachedPATH: String?

    init() {
        // Stop the server when the app quits, so it never keeps running orphaned
        // while the menu bar icon says "off".
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.process?.terminate() }
        }
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning else { return }
        guard !token.isEmpty else {
            lastLog = "Set an auth token in Settings first."
            return
        }
        guard !projectPath.isEmpty else {
            lastLog = "Choose a project folder in Settings first."
            return
        }

        // 1) Figure out the real PATH (same as your Terminal), then find the CLI.
        let path = resolvedPATH()
        guard let etPath = resolveEvenTerminal(searchPATH: path) else {
            lastLog = """
            Couldn't find even-terminal. Install it with:
              npm install -g @evenrealities/even-terminal
            or set its full path in Settings (run:  which even-terminal ).
            """
            return
        }
        // Remember what we found so the Settings field shows it.
        if evenTerminalPath != etPath { evenTerminalPath = etPath }

        let project = (projectPath as NSString).expandingTildeInPath

        // Make sure the folder actually exists before launching.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project, isDirectory: &isDir), isDir.boolValue else {
            lastLog = "Project folder not found:\n  \(project)\nChoose it again in Settings."
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: etPath)

        // CRITICAL: a Finder-launched app runs in "/" by default. Set the working
        // directory explicitly so Claude Code actually opens in your project —
        // passing -d alone isn't enough if the inner process uses its own cwd.
        p.currentDirectoryURL = URL(fileURLWithPath: project, isDirectory: true)

        // Build the same command you'd type by hand:
        //   even-terminal --provider claude -t <token> -p <port> -d <folder> [--tailscale]
        var args = ["--provider", provider, "-t", token, "-p", port, "-d", project]
        if useTailscale { args.append("--tailscale") }
        p.arguments = args

        // Give the child the real PATH, with even-terminal's own directory first
        // (that's where `node` lives for nvm/Volta/etc., so the shebang resolves).
        var env = ProcessInfo.processInfo.environment
        let etDir = URL(fileURLWithPath: etPath).deletingLastPathComponent().path
        env["PATH"] = etDir + ":" + path

        // Model selection. We do TWO things so the choice sticks even on the
        // voice-only glasses (where you can't type /model):
        //   1) set ANTHROPIC_MODEL for this session, and
        //   2) write the model into ~/.claude/settings.json (a saved default
        //      there is respected and can otherwise override the env var).
        // "Default" removes our override so Claude Code decides for itself.
        if model != "default" {
            let chosen = (model == "custom") ? customModel : model
            env["ANTHROPIC_MODEL"] = chosen
            applyModelToClaudeSettings(chosen)
        } else {
            applyModelToClaudeSettings(nil)   // remove the saved default
        }
        p.environment = env

        // Capture output so we can show it in Settings → Advanced (incl. the
        // pairing QR the very first time, and any error explaining a failure).
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.lastLog = text }
        }

        // When the process ends (crash, kill, reboot), flip our state back.
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.process = nil
            }
        }

        do {
            try p.run()
            process = p
            isRunning = true
            let modelNote = (model == "default")
                ? "Model: Claude Code default"
                : "Model: \(model == "custom" ? customModel : model) (via ANTHROPIC_MODEL)"
            lastLog = """
            Started even-terminal on port \(port).
            Folder: \(project)
            \(modelNote)
            """

            // Optionally keep the Mac awake for as long as the server runs.
            // `caffeinate -w <pid>` exits by itself once that pid exits.
            if keepAwake {
                let c = Process()
                c.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                c.arguments = ["-s", "-w", String(p.processIdentifier)]
                try? c.run()
            }
        } catch {
            lastLog = "Failed to start: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
        lastLog = "Stopped."
    }

    // MARK: - Claude model default

    /// Writes (or removes) the "model" key in ~/.claude/settings.json without
    /// disturbing other settings. Passing nil removes the key. This is what makes
    /// the app's model choice stick on the voice-only glasses, where /model can't
    /// be typed.
    private func applyModelToClaudeSettings(_ model: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir  = home.appendingPathComponent(".claude", isDirectory: true)
        let file = dir.appendingPathComponent("settings.json")

        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: file),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let parsed = obj as? [String: Any] {
            dict = parsed
        }

        if let model, !model.isEmpty {
            dict["model"] = model
        } else {
            dict.removeValue(forKey: "model")
        }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = try JSONSerialization.data(withJSONObject: dict,
                                                 options: [.prettyPrinted, .sortedKeys])
            try out.write(to: file, options: .atomic)
        } catch {
            NSLog("Could not update ~/.claude/settings.json: \(error)")
        }
    }

    // MARK: - Environment resolution

    /// The PATH your login shell actually uses (so nvm/Volta/Homebrew tools are
    /// visible), merged with sensible fallbacks. Cached after the first call.
    private func resolvedPATH() -> String {
        if let cached = cachedPATH { return cached }
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // A marker lets us ignore any noise a shell's startup files print.
        if let out = Self.loginShellOutput(#"printf '___P___%s' "$PATH""#),
           let r = out.range(of: "___P___") {
            let shellPath = out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let merged = shellPath.isEmpty ? fallback : shellPath + ":" + fallback
            cachedPATH = merged
            return merged
        }
        cachedPATH = fallback
        return fallback
    }

    /// Find even-terminal: honor an explicit override, else search the PATH,
    /// else ask the login shell directly.
    private func resolveEvenTerminal(searchPATH: String) -> String? {
        let fm = FileManager.default
        if !evenTerminalPath.isEmpty, fm.isExecutableFile(atPath: evenTerminalPath) {
            return evenTerminalPath
        }
        for dir in searchPATH.split(separator: ":") {
            let candidate = String(dir) + "/even-terminal"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        if let out = Self.loginShellOutput(#"printf '___E___%s' "$(command -v even-terminal)""#),
           let r = out.range(of: "___E___") {
            let p = out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty, fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Run a command in the user's login shell and return stdout, with a timeout
    /// so a misbehaving startup file can't hang the app.
    private static func loginShellOutput(_ command: String, timeout: TimeInterval = 5) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-ilc", command]   // interactive+login so nvm/rc files load
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()          // discard startup-file noise
        do { try p.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
