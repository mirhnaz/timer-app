import SwiftUI

@main
struct StopwatchApp: App {
    // The AppDelegate owns the status item, popover, and models. SwiftUI just hosts
    // the Settings scene below; everything menu-bar-related is AppKit-driven now so
    // NSPopover can auto-track the status button when it moves.
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    @AppStorage("appearance") private var appearance: AppearanceMode = .system

    var body: some Scene {
        Settings {
            PreferencesView()
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: appearance) { _, new in new.apply() }
        }
    }
}
