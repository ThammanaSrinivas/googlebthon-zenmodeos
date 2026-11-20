// The Mac's usage tracker, pure: feed it what happened (an app came to the front, the person went
// idle or came back, the Mac slept or woke, the clock ticked) and it keeps today's distracting
// minutes and pull-backs. No AppKit, so it tests anywhere; `MacUsageMonitor` feeds it on a Mac.
//
// The semantics are the ZenMode OS desktop tracker's:
// - Time counts while an app is in front, the Mac is awake and someone is there. Only distracting
//   apps' and sites' time is counted against the promise.
// - Distracting video is watched hands-free, so it keeps counting until 30 minutes without input.
// - After a wake (or a gap in the events long enough to be a sleep), nothing counts again until
//   fresh input: a Mac waking to YouTube on screen isn't someone watching it.
// - A pull-back is coming back to distracting use less than 5 minutes after leaving it. Moving from
//   one distracting app straight to another isn't leaving; a gap under 15 s is a blip; a visit
//   under 30 s (a window grabbing focus) is no starting point.
// - The day rolls over at local midnight: a session across it counts in both days, each its part.
import Foundation
import ZenAPI
import ZenLogic

/// Something that happened, and when.
public enum UsageEvent: Sendable, Equatable {
    /// An app (lowercased bundle id, or a site key from `DistractionCatalog.key`) came to the front.
    case appActivated(String, at: Date)
    /// No input for the idle threshold: counting stops at `at` (the moment it crossed).
    case idleStarted(at: Date)
    /// Input again (also the fresh input a wake waits for).
    case idleEnded(at: Date)
    case sleep(at: Date)
    case wake(at: Date)
    /// Time passing; the adapter ticks every few seconds so gaps and midnight are noticed.
    case tick(at: Date)

    public var at: Date {
        switch self {
        case .appActivated(_, let at), .idleStarted(let at), .idleEnded(let at), .sleep(let at), .wake(let at), .tick(let at):
            return at
        }
    }
}

/// One day of a computer's distracting use.
public struct UsageDay: Sendable, Equatable {
    public let day: DayKey
    public let distractingMillis: Int
    public let pullBacks: Int

    public init(day: DayKey, distractingMillis: Int, pullBacks: Int) {
        self.day = day
        self.distractingMillis = distractingMillis
        self.pullBacks = pullBacks
    }

    /// Whole minutes, as the score and the report take them.
    public var countedMinutes: Int { distractingMillis / 60_000 }
}

public struct UsageTracker: Sendable {
    /// Distracting use counts until this long without input.
    public static let distractingIdleThreshold: TimeInterval = 30 * 60
    /// More than this between two events is a sleep (or a suspended app): what was counting stops
    /// at the earlier event. The adapter ticks well inside it.
    public static let suspendGap: TimeInterval = 60
    static let minAwayMillis = 15_000
    static let minFeedVisitMillis = 30_000
    /// Visits shorter than one sampling tick of the desktop tracker never registered there.
    static let minVisitMillis = 5_000

    struct Session: Sendable, Equatable {
        let key: String
        let start: Date
        let end: Date
    }

    public var catalog: DistractionCatalog
    public let timeZone: TimeZone

    public private(set) var currentDay: LocalDate
    private var frontmost: String?
    private var asleep = false
    private var idle = false
    private var open: (key: String, start: Date)?
    private var sessions: [Session] = []
    private var lastEventAt: Date
    private var finished: [UsageDay] = []

    public init(catalog: DistractionCatalog = .default, timeZone: TimeZone, startingAt now: Date, frontmost: String? = nil) {
        self.catalog = catalog
        self.timeZone = timeZone
        self.currentDay = LocalDate.today(in: timeZone, now: now)
        self.lastEventAt = now
        self.frontmost = frontmost?.lowercased()
        recount(at: now)
    }

    /// What's in front now, and whether its time is being counted.
    public var frontmostApp: String? { frontmost }
    public var isCounting: Bool { open.map { catalog.isDistracting($0.key) } ?? false }

    public mutating func handle(_ event: UsageEvent) {
        // A clock set back never pulls time backwards.
        let at = max(event.at, lastEventAt)
        if at.timeIntervalSince(lastEventAt) > Self.suspendGap {
            switch event {
            case .sleep, .wake: break
            default:
                // The events stopped: the Mac slept or the app was suspended. Whatever counted
                // stops at the last event, and only fresh input starts it again.
                close(at: lastEventAt)
                idle = true
            }
        }
        roll(to: at)
        switch event {
        case .appActivated(let id, _):
            frontmost = id.lowercased()
            idle = false // bringing an app to the front is input
        case .idleStarted: idle = true
        case .idleEnded: idle = false
        case .sleep: asleep = true
        case .wake:
            asleep = false
            idle = true
        case .tick: break
        }
        recount(at: at)
        lastEventAt = at
    }

    /// Today so far, the open session counted up to `now`.
    public func today(now: Date) -> UsageDay {
        summary(of: currentDay, until: max(now, lastEventAt))
    }

    /// Days that ended since the last call, oldest first: publish their final numbers.
    public mutating func drainFinishedDays() -> [UsageDay] {
        defer { finished = [] }
        return finished
    }

    // MARK: - Internals

    private mutating func recount(at: Date) {
        let counting = !asleep && !idle ? frontmost : nil
        if let current = open, current.key != counting { close(at: at) }
        if open == nil, let key = counting { open = (key, at) }
    }

    private mutating func close(at end: Date) {
        guard let current = open else { return }
        open = nil
        if end > current.start { sessions.append(Session(key: current.key, start: current.start, end: end)) }
    }

    /// Past midnight: the day that ended is finished, and only today's sessions are kept.
    private mutating func roll(to at: Date) {
        let day = LocalDate.today(in: timeZone, now: at)
        guard day > currentDay else { return }
        let ended = currentDay.plusDays(1).startOfDay(in: timeZone)
        finished.append(summary(of: currentDay, until: ended))
        let start = day.startOfDay(in: timeZone)
        sessions.removeAll { $0.end <= start }
        currentDay = day
    }

    func summary(of day: LocalDate, until now: Date) -> UsageDay {
        let from = day.startOfDay(in: timeZone)
        let to = day.plusDays(1).startOfDay(in: timeZone)
        var all = sessions
        if let current = open, now > current.start { all.append(Session(key: current.key, start: current.start, end: now)) }
        let clipped = all.compactMap { s -> Session? in
            let start = max(s.start, from), end = min(s.end, to)
            return end > start ? Session(key: s.key, start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        let distracting = clipped.filter { catalog.isDistracting($0.key) }
            .reduce(0) { $0 + millis($1.end.timeIntervalSince($1.start)) }
        return UsageDay(day: day.description, distractingMillis: distracting, pullBacks: pullBacks(clipped))
    }

    /// The desktop's pull-back rule over one day's sessions, oldest first.
    func pullBacks(_ sessions: [Session]) -> Int {
        var count = 0
        var lastDistractingEnd: Date?
        var leftDistraction = false
        for s in sessions where millis(s.end.timeIntervalSince(s.start)) >= Self.minVisitMillis {
            if catalog.isDistracting(s.key) {
                let gap = lastDistractingEnd.map { millis(s.start.timeIntervalSince($0)) }
                let cameBack = leftDistraction || (gap.map { $0 > Self.minAwayMillis } ?? false)
                if let gap, cameBack, gap < CoreConstants.RAPID_REOPEN_GAP_MS { count += 1 }
                if millis(s.end.timeIntervalSince(s.start)) >= Self.minFeedVisitMillis {
                    lastDistractingEnd = s.end
                    leftDistraction = false
                }
            } else if lastDistractingEnd != nil {
                leftDistraction = true
            }
        }
        return count
    }

    private func millis(_ seconds: TimeInterval) -> Int { Int((seconds * 1_000).rounded()) }
}

/// Turns polled "seconds since the last input" into idle events, the way the tracker wants them.
/// Pure, so the AppKit adapter stays a few lines.
public struct IdleWatcher: Sendable {
    public let threshold: TimeInterval
    public let pollInterval: TimeInterval
    private var isIdle = false
    private var wokeAt: Date?

    public init(threshold: TimeInterval = UsageTracker.distractingIdleThreshold, pollInterval: TimeInterval = 5) {
        self.threshold = threshold
        self.pollInterval = pollInterval
    }

    /// After a wake only input from then on (less a poll, for clocks that disagree) counts as fresh.
    public mutating func didWake(at date: Date) {
        wokeAt = date
        isIdle = true
    }

    /// One poll: the events to feed the tracker (none, usually).
    public mutating func poll(now: Date, secondsSinceInput: TimeInterval) -> [UsageEvent] {
        let lastInput = now.addingTimeInterval(-max(secondsSinceInput, 0))
        if let woke = wokeAt {
            guard lastInput >= woke.addingTimeInterval(-pollInterval) else { return [] }
            wokeAt = nil
            isIdle = false
            return [.idleEnded(at: max(lastInput, woke))]
        }
        if !isIdle, secondsSinceInput >= threshold {
            isIdle = true
            return [.idleStarted(at: lastInput.addingTimeInterval(threshold))]
        }
        if isIdle, secondsSinceInput < threshold {
            isIdle = false
            return [.idleEnded(at: lastInput)]
        }
        return []
    }
}
