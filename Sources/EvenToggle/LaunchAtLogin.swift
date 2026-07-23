//
//  LaunchAtLogin.swift
//  A checkbox that registers/unregisters the app as a macOS Login Item,
//  so it starts automatically every time you log in.
//

import SwiftUI
import ServiceManagement

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else        { try SMAppService.mainApp.unregister() }
                    enabled = newValue
                } catch {
                    NSLog("Login-item change failed: \(error)")
                }
            }
        ))
    }
}
