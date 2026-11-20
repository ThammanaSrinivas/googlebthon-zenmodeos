import AppKit
import ApplicationServices

/// Keeps sampling alive in the background: without this, App Nap stalls the timers that measure
/// the day as soon as the window is hidden. Info.plist also sets NSAppSleepDisabled.
@MainActor
enum AppNap {
    private static var activity: NSObjectProtocol?

    static func holdOff() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "ZenMode OS measures the day while it runs in the background")
    }
}

/// Accessibility lets the app read the front window's title, which is how a browser tab on
/// YouTube is told apart from one on Docs. Titles are read, never stored.
@MainActor
enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once and opens the right pane of System Settings.
    static func request() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The app in front, kept current by activation notifications rather than polling, so it stays
/// right in the packaged app and in the background.
@MainActor
@Observable
final class FrontmostTracker {
    struct App: Equatable {
        let name: String
        let bundleID: String
        /// Where the time goes, by kind. Never the title itself.
        let kind: Kind
    }

    enum Kind: String {
        case work = "Work", browser = "Browser", social = "Social", video = "Video", other = "Other"
    }

    private(set) var current: App?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.update(app) }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        current = App(name: app.localizedName ?? id, bundleID: id, kind: Self.kind(of: id, pid: app.processIdentifier))
    }

    /// Browsers need the front tab's title to know what kind of time it is; the title is read
    /// here, classified, and dropped.
    private static func kind(of bundleID: String, pid: pid_t) -> Kind {
        let browsers = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac"]
        let work = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.figma.Desktop", "com.apple.Terminal", "com.googlecode.iterm2", "com.jetbrains", "notion.id", "com.apple.iWork"]
        if work.contains(where: bundleID.hasPrefix) { return .work }
        guard browsers.contains(bundleID) else { return .other }
        guard AXIsProcessTrusted(), let title = frontWindowTitle(pid: pid)?.lowercased() else { return .browser }
        if ["youtube", "netflix", "prime video", "hotstar", "twitch"].contains(where: title.contains) { return .video }
        if ["instagram", "x.com", "twitter", "reddit", "facebook", "linkedin"].contains(where: title.contains) { return .social }
        if ["docs", "github", "gmail", "calendar", "notion", "figma", "stack overflow", "classroom"].contains(where: title.contains) { return .work }
        return .browser
    }

    private static func frontWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}
