//
//  MenuContent.swift
//  What you see when you click the 👓 in the menu bar.
//

import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var server: ServerController

    var body: some View {
        // A plain status line.
        Text(server.isRunning
             ? "● Running — port \(server.port)"
             : "○ Stopped")

        // The main toggle. Calls start() or stop() on the controller.
        Button(server.isRunning ? "Turn Off" : "Turn On") {
            server.toggle()
        }
        .keyboardShortcut("t")

        Divider()

        // Opens the Settings window (macOS 14+).
        SettingsLink { Text("Settings…") }

        // Adds/removes the app from macOS Login Items.
        LaunchAtLoginToggle()

        Divider()

        Button("Quit EvenToggle") {
            server.stop()                      // be tidy: stop the server first
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
