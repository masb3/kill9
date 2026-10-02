import AppKit

/// Offers to move the app into Applications when it's launched from somewhere else
/// (Downloads, a mounted DMG, the build folder), then relaunches it from there.
enum AppMover {
    private static let suppressKey = "suppressMoveToApplications"

    static func moveToApplicationsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: suppressKey) else { return }

        // `swift run` launches the bare executable, not a .app bundle.
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return }

        let source = originalURL(of: bundleURL)
        guard !isInApplicationsFolder(source) else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText = "Kill9 is running from “\(source.deletingLastPathComponent().path)”. "
            + "In Applications it's easy to find in Spotlight, and Launch at login keeps working."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Do Not Move")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { defaults.set(true, forKey: suppressKey) }
        guard response == .alertFirstButtonReturn else { return }

        do {
            relaunch(at: try move(source))
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Couldn't move Kill9 to Applications"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    // MARK: Moving

    private static func move(_ source: URL) throws -> URL {
        let fm = FileManager.default
        let destination = try applicationsFolder().appendingPathComponent(source.lastPathComponent)

        // Replace an older copy, quitting it first so there's only one menu-bar icon.
        if fm.fileExists(atPath: destination.path) {
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0 != .current }
                .forEach { $0.terminate() }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }

        try fm.copyItem(at: source, to: destination)
        removeQuarantine(destination)

        // A mounted DMG is read-only; anywhere else, don't leave a second copy behind.
        if !source.path.hasPrefix("/Volumes/") {
            try? fm.trashItem(at: source, resultingItemURL: nil)
        }
        return destination
    }

    /// /Applications when the user can write to it (admins), otherwise ~/Applications.
    private static func applicationsFolder() throws -> URL {
        let fm = FileManager.default
        if fm.isWritableFile(atPath: "/Applications") { return URL(fileURLWithPath: "/Applications") }
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try fm.createDirectory(at: userApps, withIntermediateDirectories: true)
        return userApps
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
            .contains { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }

    /// The user already approved this app by opening it; the moved copy shouldn't ask again.
    private static func removeQuarantine(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? task.run()
        task.waitUntilExit()
    }

    /// Waits for this process to exit, then opens the moved copy.
    private static func relaunch(at url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: App Translocation

    /// Quarantined apps opened in place run from a random read-only path
    /// (…/AppTranslocation/…). Map it back to where the user actually put the app.
    private static func originalURL(of url: URL) -> URL {
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return url }

        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(symbol, to: Fn.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
    }
}
