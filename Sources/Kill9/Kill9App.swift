import SwiftUI
import AppKit

@main
struct Kill9App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PortStore()

    var body: some Scene {
        MenuBarExtra("Kill9", systemImage: "9.circle.fill") {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep it a menu-bar-only app, even when launched via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        AppMover.moveToApplicationsIfNeeded()
    }
}
