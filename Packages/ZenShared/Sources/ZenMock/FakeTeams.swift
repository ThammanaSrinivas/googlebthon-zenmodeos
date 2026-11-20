import Foundation
import ZenAPI

/// Focus sync on this device only: keeps what was written and plays `live/focus` back to listeners
/// (the open-source build, the demo, the tests).
public final class FakeFocusSync: FocusSyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var _live: LiveFocus = .idle
    private var _records: [FocusRecord] = []
    private var _daily: [String: DailyFocus] = [:]
    private var _hours: WorkHours?
    private var listeners: [UUID: AsyncStream<LiveFocus>.Continuation] = [:]

    public init() {}

    public var live: LiveFocus { lock.withLock { _live } }
    public var records: [FocusRecord] { lock.withLock { _records } }
    public var daily: [String: DailyFocus] { lock.withLock { _daily } }
    public var workHours: WorkHours? { lock.withLock { _hours } }

    public func setLive(_ live: LiveFocus) async throws(FocusSyncError) {
        let targets = lock.withLock { _live = live; return Array(listeners.values) }
        targets.forEach { $0.yield(live) }
    }

    public func save(_ record: FocusRecord) async throws(FocusSyncError) {
        lock.withLock { _records.append(record) }
    }

    public func saveDaily(_ daily: DailyFocus, day: String) async throws(FocusSyncError) {
        lock.withLock { _daily[day] = daily.clamped }
    }

    public func saveWorkHours(_ hours: WorkHours) async throws(FocusSyncError) {
        lock.withLock { _hours = hours }
    }

    public func liveFocus() -> AsyncStream<LiveFocus> {
        AsyncStream { continuation in
            let id = UUID()
            let current = lock.withLock { listeners[id] = continuation; return _live }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { _ = self?.listeners.removeValue(forKey: id) } }
        }
    }
}

/// Zeno's work callables, answered on the device with fixed, kind text (marked as the fallback, so
/// the app never credits Gemini for them).
public struct FakeZenoWork: ZenoWorkService {
    public init() {}

    public func catchUp(_ items: [CatchUpItem]) async throws(ZenoWorkError) -> CatchUpResult {
        let cards = items.prefix(3).enumerated().map { i, item in
            CatchUpCard(ref: i, summary: String("\(item.fromLabel) sent you a message".prefix(80)),
                        urgency: i == 0 ? .now : .today, draftReply: "Thanks, I was focusing. Looking at this now.")
        }
        return CatchUpResult(items: cards, line: "Here's what came in.", fallback: true)
    }

    public func planDay(_ request: PlanDayRequest) async throws(ZenoWorkError) -> PlanDayResult {
        let top = request.tasks.prefix(3).map { String($0.prefix(60)) }
        let blocks = DayPlanner.slots(now: request.now, dayEnd: request.dayEnd, busy: request.events, count: 3)
            .enumerated().map { i, b in DayBlock(start: b.start, end: b.end, title: i < top.count ? "Focus: \(top[i])".prefixed(60) : "Focus block") }
        return PlanDayResult(top3: Array(top), blocks: blocks, line: "Three things, one at a time.", fallback: true)
    }

    public func wrapUp(_ request: WrapUpRequest) async throws(ZenoWorkError) -> WrapUpResult {
        let summary = "You finished \(request.done.count) and kept \(request.blocksKept) focus blocks today."
        return WrapUpResult(summary: summary, moveToTomorrow: Array(request.open.prefix(3)), line: "Good work. Time to log off.", fallback: true)
    }

    public func ask(cohortId: String, question: String) async throws(ZenoWorkError) -> AskResult {
        AskResult(answer: AskResult.notInNotes, grounded: false, fallback: true)
    }
}

/// A demo team with a gold sponsor.
public struct FakeTeam: TeamService {
    public init() {}

    public func myTeam() async throws(TeamError) -> TeamInfo? {
        TeamInfo(cohortId: "demo", name: "Payments", goldSponsorInr: 250, hasNotes: true)
    }

    public func focusReportLink(isoWeek: String, showName: Bool) async throws(TeamError) -> FocusReportLink {
        FocusReportLink(url: URL(string: "https://example.com/r/demo")!, expiresAt: Date().addingTimeInterval(30 * 86_400))
    }

    public func claimGold(cohortId: String, isoWeek: String) async throws(TeamError) -> Int { 250 }
}

private extension String {
    func prefixed(_ n: Int) -> String { String(prefix(n)) }
}
