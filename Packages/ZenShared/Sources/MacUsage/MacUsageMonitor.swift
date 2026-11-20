// The thin AppKit adapter: NSWorkspace notifications and an idle poll, fed to UsageTracker.
// Everything that decides anything is in UsageTracker and IdleWatcher, tested on any platform.
#if canImport(AppKit)
import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
public final class MacUsageMonitor {
    /// Today so far; changes when its whole minutes, pull-backs or day change.
    public private(set) var today: UsageDay
    /// Called with today whenever `today` changes (`finished` false), and once per day that ended,
    /// with its final numbers (`finished` true: publish it with `force: true` so it isn't throttled away).
    @ObservationIgnored public var onDay: ((_ day: UsageDay, _ finished: Bool) -> Void)?

    @ObservationIgnored private var tracker: UsageTracker
    @ObservationIgnored private var idle: IdleWatcher
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private let pollInterval: TimeInterval

    public init(catalog: DistractionCatalog = .default, timeZone: TimeZone = .current, pollInterval: TimeInterval = 5) {
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        tracker = UsageTracker(catalog: catalog, timeZone: timeZone, startingAt: now, frontmost: front)
        idle = IdleWatcher(pollInterval: pollInterval)
        self.pollInterval = pollInterval
        today = tracker.today(now: now)
    }

    /// The catalog in use; changing it re-buckets today at once.
    public var catalog: DistractionCatalog {
        get { tracker.catalog }
        set { tracker.catalog = newValue; publish(Date()) }
    }

    private enum Kind: Sendable { case activated, sleep, wake }

    public func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        let names: [(Notification.Name, Kind)] = [
            (NSWorkspace.didActivateApplicationNotification, .activated),
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.screensDidSleepNotification, .sleep),
            (NSWorkspace.sessionDidResignActiveNotification, .sleep),
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidWakeNotification, .wake),
            (NSWorkspace.sessionDidBecomeActiveNotification, .wake),
        ]
        for (name, kind) in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.received(kind, app: app) }
            })
        }
        poller = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int64(pollInterval * 1_000)))
                self?.poll()
            }
        }
    }

    /// Publishes every change through `sync`: today throttled, a finished day at once, and today
    /// right now (launch). Call `sync.flush()` when the app comes to the foreground.
    public func publish(to sync: MacDaySync) {
        onDay = { [weak sync] day, finished in sync?.submit(day, force: finished) }
        sync.submit(today, force: true)
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
        poller?.cancel()
        poller = nil
    }

    private func received(_ kind: Kind, app: String?) {
        let now = Date()
        switch kind {
        case .activated: if let app { feed(.appActivated(app, at: now)) }
        case .sleep: feed(.sleep(at: now))
        case .wake: feed(.wake(at: now))
        }
    }

    private func poll() {
        let now = Date()
        // Seconds since any keyboard or mouse input in this login session.
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        for event in idle.poll(now: now, secondsSinceInput: seconds) { tracker.handle(event) }
        feed(.tick(at: now))
    }

    private func feed(_ event: UsageEvent) {
        if case .wake(let at) = event { idle.didWake(at: at) }
        tracker.handle(event)
        publish(event.at)
    }

    private func publish(_ now: Date) {
        for day in tracker.drainFinishedDays() { onDay?(day, true) }
        let current = tracker.today(now: now)
        if current.day != today.day || current.countedMinutes != today.countedMinutes || current.pullBacks != today.pullBacks {
            today = current
            onDay?(current, false)
        }
    }
}
#endif
