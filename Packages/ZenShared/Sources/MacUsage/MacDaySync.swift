// Sends this Mac's day to the backend without flooding it: when it changed, at most every 30 s,
// at once when forced (the app came to the foreground, someone signed in, a day finished at
// midnight), and again with backoff while offline. Pure: the service, the report builder and the
// clock come in, so every path tests without a network or a wait.
//
// Wiring on a Mac (MacUsageMonitor does the first two lines in `publish(to:)`):
//     monitor.onDay = { day, finished in sync.submit(day, force: finished) }
//     sync.submit(monitor.today, force: true)          // launch, sign-in
//     sync.flush()                                     // the app came to the foreground
import Foundation
import Observation
import ZenAPI

@MainActor
@Observable
public final class MacDaySync {
    public enum Status: Equatable, Sendable {
        case idle
        /// Throttled: the report goes at this time.
        case waiting(until: Date)
        case publishing
        case upToDate(at: Date)
        /// Offline (or the backend unavailable): trying again at this time.
        case offline(retryAt: Date)
        /// Nobody is signed in; what was waiting was dropped.
        case signedOut
        /// The backend refused the report; it isn't retried.
        case rejected
    }

    /// At most one publish this often, unless forced.
    public static let defaultMinimumInterval: TimeInterval = 30
    /// Waits between retries while offline; the last one repeats.
    public static let retryBackoff: [TimeInterval] = [2, 4, 8, 16, 30, 60]

    public private(set) var status: Status = .idle
    /// The last report the backend took.
    public private(set) var lastPublished: ComputerDayReport?
    public private(set) var lastPublishedAt: Date?
    /// Successful publishes, for the debug overlay and tests.
    public private(set) var publishCount = 0

    @ObservationIgnored private let days: any DaySyncService
    @ObservationIgnored private let builder: ComputerDayReportBuilder
    @ObservationIgnored private let clock: any SchedulingClock
    @ObservationIgnored private let minimumInterval: TimeInterval
    /// Days waiting to go, oldest first, at most one per day: a finished day is never lost to the
    /// next one, and a newer count of the same day replaces the older.
    @ObservationIgnored private var queue: [UsageDay] = []
    /// The day most recently handed over, for `flush()`.
    @ObservationIgnored private var latest: UsageDay?
    @ObservationIgnored private var lastAttemptAt: Date?
    @ObservationIgnored private var timer: (any ScheduledWork)?
    @ObservationIgnored private var retrying = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var forceAfterFlight = false

    public init(days: any DaySyncService, builder: ComputerDayReportBuilder, clock: any SchedulingClock,
                minimumInterval: TimeInterval = MacDaySync.defaultMinimumInterval) {
        self.days = days
        self.builder = builder
        self.clock = clock
        self.minimumInterval = minimumInterval
    }

    /// Hand over the Mac's latest day. It goes out when it differs from what was last sent (the
    /// promise included), throttled, or at once with `force`.
    public func submit(_ day: UsageDay, force: Bool = false) {
        latest = day
        if !force, queue.isEmpty, inFlight == nil, let sent = lastPublished, sameContent(day, as: sent) { return }
        enqueue(day)
        schedule(force: force)
    }

    /// Send what's waiting now, or the latest day again: on app foreground or sign-in.
    public func flush() {
        if queue.isEmpty, let latest { enqueue(latest) }
        guard !queue.isEmpty else { return }
        schedule(force: true)
    }

    /// Waits until nothing is being sent (tests, and before the app quits).
    public func settle() async {
        while let task = inFlight { await task.value }
    }

    /// The same day in the same numbers as a report already sent. The sequence grows with every
    /// report, so it isn't a change by itself.
    func sameContent(_ day: UsageDay, as sent: ComputerDayReport) -> Bool {
        sent.day == day.day
            && sent.countedMinutes == min(max(day.countedMinutes, 0), ComputerDayReportBuilder.maxCountedMinutes)
            && sent.pullBacks == min(max(day.pullBacks, 0), ComputerDayReportBuilder.maxPullBacks)
            && sent.promiseMinutes == builder.promiseHours * 60
    }

    // MARK: - Internals

    private func enqueue(_ day: UsageDay) {
        if let i = queue.firstIndex(where: { $0.day == day.day }) {
            queue[i] = day
        } else {
            queue.append(day)
            queue.sort { $0.day < $1.day } // yyyy-MM-dd sorts as text in date order
        }
    }

    private func schedule(force: Bool) {
        guard !queue.isEmpty else { return }
        if inFlight != nil {
            // The one in flight finishes first; then this goes, forced or throttled.
            forceAfterFlight = forceAfterFlight || force
            return
        }
        if force {
            cancelTimer()
            retrying = false
            send()
            return
        }
        if retrying { return } // the retry timer sends the newest
        let due = (lastAttemptAt ?? .distantPast).addingTimeInterval(minimumInterval)
        if clock.now >= due {
            cancelTimer()
            send()
        } else if timer == nil {
            status = .waiting(until: due)
            timer = clock.schedule(after: due.timeIntervalSince(clock.now)) { [weak self] in
                self?.timer = nil
                self?.send()
            }
        }
    }

    private func send() {
        guard inFlight == nil, !queue.isEmpty else { return }
        let day = queue.removeFirst()
        let report = builder.report(for: day)
        lastAttemptAt = clock.now
        status = .publishing
        let days = self.days
        inFlight = Task { [weak self] in
            do throws(SyncError) {
                try await days.publish(computer: report)
                self?.succeeded(report)
            } catch {
                self?.failed(day, error)
            }
        }
    }

    private func succeeded(_ report: ComputerDayReport) {
        inFlight = nil
        failures = 0
        retrying = false
        lastPublished = report
        lastPublishedAt = clock.now
        publishCount += 1
        status = .upToDate(at: clock.now)
        afterFlight()
    }

    private func failed(_ day: UsageDay, _ error: SyncError) {
        inFlight = nil
        switch error {
        case .offline, .unavailable:
            // Keep the day (unless a newer count of it arrived meanwhile) and retry with backoff.
            if !queue.contains(where: { $0.day == day.day }) { enqueue(day) }
            let wait = Self.retryBackoff[min(failures, Self.retryBackoff.count - 1)]
            failures += 1
            retrying = true
            status = .offline(retryAt: clock.now.addingTimeInterval(wait))
            forceAfterFlight = false
            cancelTimer()
            timer = clock.schedule(after: wait) { [weak self] in
                guard let self else { return }
                self.timer = nil
                self.retrying = false
                self.send()
            }
        case .signedOut:
            queue = []
            status = .signedOut
            forceAfterFlight = false
        case .rejected:
            status = .rejected
            afterFlight()
        }
    }

    private func afterFlight() {
        let force = forceAfterFlight
        forceAfterFlight = false
        if !queue.isEmpty { schedule(force: force) }
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}
