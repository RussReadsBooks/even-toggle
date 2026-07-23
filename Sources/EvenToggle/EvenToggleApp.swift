//
//  EvenToggleApp.swift
//  The app's entry point. Declares two "scenes":
//   1) a MenuBarExtra — the 👓 icon and its dropdown menu, and
//   2) a Settings window (opened via "Settings…" or Cmd-,).
//
//  This app is a *supervisor*: it does not contain the server. It starts and
//  stops the `even-terminal` CLI as a child process using your saved settings.
//  Quitting the app stops the server (that's the supervisor model — simplest,
//  and the menu bar light always tells the truth).
//

import SwiftUI

@main
struct EvenToggleApp: App {
    // One shared controller for the whole app.
    @StateObject private var server = ServerController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(server)
        } label: {
            // The menu bar item is simply the glasses emoji.
            Text("👓")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(server)
        }
    }
}
