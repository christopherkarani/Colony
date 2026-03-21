import SwiftUI
import Colony

#if os(macOS)
import AppKit
#endif

@main
struct DeepResearchApp: App {
    @State private var sidebarVM = SidebarViewModel()
    @State private var settingsVM = SettingsViewModel()

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sidebarVM)
                .environment(settingsVM)
                .font(.dsBody)
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environment(settingsVM)
                .font(.dsBody)
        }
    }
}
