import Foundation

// ZenMode OS for Teams (contract v4, 20 Nov 2026): Focus Mode, its sync, and Zeno's work callables.
// Firestore names: the private repo's functions/src/schema.ts (v4) and FirestoreSchema.swift. The
// Mac writes focus_sessions, daily and live/focus; the iPhone only reads live/focus.

/// Where a focus block was started from.
public enum FocusSource: String, Codable, Sendable, CaseIterable {
    case manual, voice, plan
}

/// What one integration did for one block.
public enum HookState: String, Codable, Sendable {
    /// It ran.
    case on
    /// It was ready, but errored or timed out. Focus went on without it.
    case failed
    /// It isn't set up, or it's switched off.
    case skipped
}

/// One focus block: from now until a clock time. People see the end time, never a countdown.
public struct FocusBlock: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// `[A-Za-z0-9_-]{1,64}` (the rules check it).
    public let id: String
    public let startAt: Date
    public let until: Date
    public let source: FocusSource

    public init(id: String = FocusBlock.newId(), startAt: Date, until: Date, source: FocusSource) {
        self.id = id
        self.startAt = startAt
        self.until = max(until, startAt)
        self.source = source
    }

    /// Whole minutes planned, 0…720.
    public var plannedMin: Int { min(max(Int((until.timeIntervalSince(startAt) / 60).rounded()), 0), 720) }

    /// A random id the rules accept.
    public static func newId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// A finished block, as the backend keeps it (one record per block).
public struct FocusRecord: Codable, Equatable, Sendable {
    public let session: FocusBlock
    public let endAt: Date
    /// Ran to its end time (or past it). An early stop is not kept.
    public let kept: Bool
    /// Hook id → what it did at the start.
    public let hooks: [String: HookState]

    public init(session: FocusBlock, endAt: Date, kept: Bool, hooks: [String: HookState]) {
        self.session = session
        self.endAt = max(endAt, session.startAt)
        self.kept = kept
        self.hooks = hooks
    }

    /// Minutes actually focused.
    public var focusedMin: Int { min(max(Int((endAt.timeIntervalSince(session.startAt) / 60).rounded()), 0), 1440) }
}

/// The person's live focus state: what the iPhone's Island shows.
public struct LiveFocus: Equatable, Sendable {
    public let active: Bool
    public let until: Date?

    public init(active: Bool, until: Date?) {
        self.active = active
        self.until = active ? until : nil
    }

    public static let idle = LiveFocus(active: false, until: nil)

    /// Active and not yet past its end (a Mac that crashed mid-block leaves `active` set).
    public func isFocusing(at now: Date) -> Bool {
        guard active, let until else { return false }
        return until > now
    }
}

/// The Mac's day of focus, one per local day. No other value, ever (no app names).
public struct DailyFocus: Codable, Equatable, Sendable {
    public var focusMin: Int
    public var blocksStarted: Int
    public var blocksKept: Int
    public var afterHoursMin: Int
    /// Tenths, 25…100, when the Mac has a score for the day.
    public var zenScoreTenths: Int?

    public init(focusMin: Int = 0, blocksStarted: Int = 0, blocksKept: Int = 0, afterHoursMin: Int = 0, zenScoreTenths: Int? = nil) {
        self.focusMin = focusMin
        self.blocksStarted = blocksStarted
        self.blocksKept = blocksKept
        self.afterHoursMin = afterHoursMin
        self.zenScoreTenths = zenScoreTenths
    }

    /// Clamped to what the rules accept: minutes 0…1440, blocks 0…100, kept ≤ started, score 25…100.
    public var clamped: DailyFocus {
        let started = min(max(blocksStarted, 0), 100)
        return DailyFocus(focusMin: min(max(focusMin, 0), 1440), blocksStarted: started,
                          blocksKept: min(max(blocksKept, 0), started), afterHoursMin: min(max(afterHoursMin, 0), 1440),
                          zenScoreTenths: zenScoreTenths.map { min(max($0, 25), 100) })
    }
}

/// The person's work hours. Days are 1 = Monday … 7 = Sunday.
public struct WorkHours: Codable, Equatable, Sendable {
    /// "HH:mm", 24-hour.
    public var start: String
    public var end: String
    public var days: [Int]
    /// IANA, e.g. "Asia/Kolkata".
    public var tz: String

    public init(start: String = "09:30", end: String = "18:30", days: [Int] = [1, 2, 3, 4, 5], tz: String = TimeZone.current.identifier) {
        self.start = start
        self.end = end
        self.days = days
        self.tz = tz
    }
}

public enum FocusSyncError: Error, Equatable, Sendable {
    case signedOut, offline, rejected
}

/// Where the Mac's focus goes (Firestore in the private package, a recorder in the fakes). Writes
/// are queued while offline and land later; nothing here blocks focus from starting or ending.
public protocol FocusSyncService: Sendable {
    /// `live/focus`, on every start and end.
    func setLive(_ live: LiveFocus) async throws(FocusSyncError)
    /// `focus_sessions/{id}`, on end.
    func save(_ record: FocusRecord) async throws(FocusSyncError)
    /// `daily/{day}` (day = "yyyy-MM-dd" in the person's time zone), on end and after hours.
    func saveDaily(_ daily: DailyFocus, day: String) async throws(FocusSyncError)
    /// `settings/work_hours`.
    func saveWorkHours(_ hours: WorkHours) async throws(FocusSyncError)
    /// The signed-in person's `live/focus`, as it changes (the iPhone's Island follows it).
    func liveFocus() -> AsyncStream<LiveFocus>
}

// MARK: - Zeno's work callables (Gemini Flash, server side; the Mac only calls them)

/// One message that came in during focus. The text goes to Gemini on the person's tap and is never
/// stored or logged.
public struct CatchUpItem: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case slack, mail }
    public let source: Source
    /// "Ravi" or "#payments", ≤ 60.
    public let fromLabel: String
    /// ≤ 1,000 characters.
    public let text: String

    public init(source: Source, fromLabel: String, text: String) {
        self.source = source
        self.fromLabel = String(fromLabel.prefix(60))
        self.text = String(text.prefix(1000))
    }

    enum CodingKeys: String, CodingKey { case source, fromLabel = "from_label", text }
}

/// One card: what needs the person, how soon, and a reply they can approve.
public struct CatchUpCard: Codable, Equatable, Sendable, Identifiable {
    public enum Urgency: String, Codable, Sendable { case now, today, later }
    /// Index into the items sent.
    public let ref: Int
    public let summary: String
    public let urgency: Urgency
    /// May be empty (the fallback has none).
    public let draftReply: String

    public var id: Int { ref }

    public init(ref: Int, summary: String, urgency: Urgency, draftReply: String) {
        self.ref = ref
        self.summary = summary
        self.urgency = urgency
        self.draftReply = draftReply
    }

    enum CodingKeys: String, CodingKey { case ref, summary, urgency, draftReply = "draft_reply" }
}

public struct CatchUpResult: Codable, Equatable, Sendable {
    /// At most 3, most urgent first.
    public let items: [CatchUpCard]
    public let line: String
    public let fallback: Bool

    public init(items: [CatchUpCard], line: String, fallback: Bool) {
        self.items = items
        self.line = line
        self.fallback = fallback
    }
}

/// A span of today, "HH:mm" to "HH:mm" (local time).
public struct DayBlock: Codable, Equatable, Hashable, Sendable {
    public let start: String
    public let end: String
    public let title: String

    public init(start: String, end: String, title: String) {
        self.start = start
        self.end = end
        self.title = title
    }
}

public struct PlanDayRequest: Codable, Equatable, Sendable {
    public let events: [DayBlock]
    public let tasks: [String]
    public let now: String
    public let dayEnd: String
    public let cohortId: String?

    public init(events: [DayBlock], tasks: [String], now: String, dayEnd: String, cohortId: String? = nil) {
        self.events = Array(events.prefix(20))
        self.tasks = Array(tasks.prefix(20).map { String($0.prefix(100)) })
        self.now = now
        self.dayEnd = dayEnd
        self.cohortId = cohortId
    }

    enum CodingKeys: String, CodingKey { case events, tasks, now, dayEnd = "day_end", cohortId }
}

public struct PlanDayResult: Codable, Equatable, Sendable {
    public let top3: [String]
    public let blocks: [DayBlock]
    public let line: String
    public let fallback: Bool

    public init(top3: [String], blocks: [DayBlock], line: String, fallback: Bool) {
        self.top3 = top3
        self.blocks = blocks
        self.line = line
        self.fallback = fallback
    }
}

public struct WrapUpRequest: Codable, Equatable, Sendable {
    public let done: [String]
    public let open: [String]
    public let focusMin: Int
    public let blocksKept: Int

    public init(done: [String], open: [String], focusMin: Int, blocksKept: Int) {
        self.done = Array(done.prefix(20).map { String($0.prefix(100)) })
        self.open = Array(open.prefix(20).map { String($0.prefix(100)) })
        self.focusMin = min(max(focusMin, 0), 1440)
        self.blocksKept = min(max(blocksKept, 0), 100)
    }

    enum CodingKeys: String, CodingKey { case done, open, focusMin = "focus_min", blocksKept = "blocks_kept" }
}

public struct WrapUpResult: Codable, Equatable, Sendable {
    public let summary: String
    public let moveToTomorrow: [String]
    public let line: String
    public let fallback: Bool

    public init(summary: String, moveToTomorrow: [String], line: String, fallback: Bool) {
        self.summary = summary
        self.moveToTomorrow = moveToTomorrow
        self.line = line
        self.fallback = fallback
    }

    enum CodingKeys: String, CodingKey { case summary, moveToTomorrow = "move_to_tomorrow", line, fallback }
}

public struct AskResult: Codable, Equatable, Sendable {
    public let answer: String
    /// True only when the answer comes from the team's notes (the server checks the quote is there).
    public let grounded: Bool
    public let quote: String?
    public let fallback: Bool

    public init(answer: String, grounded: Bool, quote: String? = nil, fallback: Bool) {
        self.answer = answer
        self.grounded = grounded
        self.quote = quote
        self.fallback = fallback
    }

    public static let notInNotes = "I don't have that in the team's notes."
}

public enum ZenoWorkError: Error, Equatable, Sendable {
    case signedOut, notAMember, invalid, offline
}

/// zenoCatchUp, zenoPlanDay, zenoWrapUp, zenoAsk. Each answers with a fixed fallback on the server
/// when Gemini is off, slow or wrong; the app adds its own when the call can't be made at all.
public protocol ZenoWorkService: Sendable {
    func catchUp(_ items: [CatchUpItem]) async throws(ZenoWorkError) -> CatchUpResult
    func planDay(_ request: PlanDayRequest) async throws(ZenoWorkError) -> PlanDayResult
    func wrapUp(_ request: WrapUpRequest) async throws(ZenoWorkError) -> WrapUpResult
    func ask(cohortId: String, question: String) async throws(ZenoWorkError) -> AskResult
}

// MARK: - Srinivas's team callables the Mac calls (glue)

public struct FocusReportLink: Equatable, Sendable {
    public let url: URL
    public let expiresAt: Date

    public init(url: URL, expiresAt: Date) {
        self.url = url
        self.expiresAt = expiresAt
    }
}

public enum TeamError: Error, Equatable, Sendable {
    case signedOut, notAMember, notAGoldWeek, invalid, offline
}

/// The team's side of the Mac: what the cohort offers (sponsor, notes) and the two callables.
public struct TeamInfo: Equatable, Sendable {
    public let cohortId: String
    public let name: String
    public let goldSponsorInr: Int
    public let hasNotes: Bool

    public init(cohortId: String, name: String, goldSponsorInr: Int, hasNotes: Bool) {
        self.cohortId = cohortId
        self.name = name
        self.goldSponsorInr = goldSponsorInr
        self.hasNotes = hasNotes
    }
}

public protocol TeamService: Sendable {
    /// The person's cohort, or nil when they're in none.
    func myTeam() async throws(TeamError) -> TeamInfo?
    /// createFocusReportLink.
    func focusReportLink(isoWeek: String, showName: Bool) async throws(TeamError) -> FocusReportLink
    /// claimTeamGold; the sponsor's rupees. Idempotent.
    func claimGold(cohortId: String, isoWeek: String) async throws(TeamError) -> Int
}

/// The team web pages. The apps only open these. Their address belongs to the backend: the app
/// target sets `base` at launch from the private package; with the fakes there are none.
public enum TeamWeb {
    nonisolated(unsafe) public static var base: URL?
    public static var privacy: URL? { base?.appending(path: "privacy") }
    public static func join(token: String) -> URL? { base?.appending(path: "join").appending(path: token) }
    public static func challenge(_ id: String) -> URL? { base?.appending(path: "challenge").appending(path: id) }
}
