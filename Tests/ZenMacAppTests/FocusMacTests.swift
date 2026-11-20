import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import ZenAPI
import ZenFocus
@testable import ZenMacApp

/// Slack answered from canned JSON, per method; records what was sent. No network.
final class CannedSlack: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []
    var sent: [String] { lock.withLock { _sent } }
    func send(_ request: URLRequest) async throws -> (Int, Data) {
        let method = request.url!.lastPathComponent
        lock.withLock { _sent.append(method) }
        let body: String = switch method {
        case "auth.test": #"{"ok":true,"user_id":"UME"}"#
        case "search.messages": #"{"ok":true,"messages":{"matches":[{"ts":"1795150000.0001","user":"UR","text":"review?","channel":{"id":"C1"}}]}}"#
        case "conversations.list": #"{"ok":true,"channels":[{"id":"D1"}]}"#
        case "conversations.history": #"{"ok":true,"messages":[{"ts":"1795151000.0002","user":"UP","text":"lunch?"}]}"#
        case "users.info": #"{"ok":true,"user":{"name":"x","profile":{"display_name":"Ravi"}}}"#
        default: #"{"ok":true}"#
        }
        return (200, Data(body.utf8))
    }
}

/// zenoCatchUp answering with a duplicate and an out-of-range ref, or failing.
struct StubWork: ZenoWorkService {
    var fail = false
    func catchUp(_ items: [CatchUpItem]) async throws(ZenoWorkError) -> CatchUpResult {
        if fail { throw .offline }
        return CatchUpResult(items: [CatchUpCard(ref: 1, summary: "Lunch plan", urgency: .now, draftReply: "Yes, 1 works."),
                                     CatchUpCard(ref: 1, summary: "dup", urgency: .later, draftReply: ""),
                                     CatchUpCard(ref: 9, summary: "ghost", urgency: .later, draftReply: "")],
                             line: "Two things.", fallback: false)
    }
    func planDay(_ r: PlanDayRequest) async throws(ZenoWorkError) -> PlanDayResult { throw .offline }
    func wrapUp(_ r: WrapUpRequest) async throws(ZenoWorkError) -> WrapUpResult { throw .offline }
    func ask(cohortId: String, question: String) async throws(ZenoWorkError) -> AskResult { throw .offline }
}

@MainActor
@Suite("Catch-up after focus")
struct CatchUpTests {
    let since = Date(timeIntervalSince1970: 1_795_149_000)

    @Test("No Slack token: asks to connect, reads nothing")
    func notConnected() async {
        let slack = CannedSlack()
        let m = CatchUpModel(token: { nil }, sender: slack)
        await m.focusEnded(since: since)
        #expect(m.state == .notConnected)
        #expect(slack.sent.isEmpty)
    }

    @Test("Messages wait for the tap; nothing goes to Gemini before it")
    func waitsForTap() async {
        let m = CatchUpModel(token: { "xoxp-1" }, sender: CannedSlack())
        await m.focusEnded(since: since)
        #expect(m.state == .waiting(2))
        #expect(m.cards.isEmpty)
    }

    @Test("Cards keep only valid, unique refs; approve sends in Slack; skip doesn't")
    func cards() async {
        let slack = CannedSlack()
        let m = CatchUpModel(token: { "xoxp-1" }, sender: slack)
        await m.focusEnded(since: since)
        await m.catchMeUp(with: StubWork())
        #expect(m.state == .ready && m.fromGemini)
        #expect(m.cards.map(\.summary) == ["Lunch plan"])
        #expect(!slack.sent.contains("chat.postMessage"))
        await m.approve(1)
        #expect(m.cards.first?.status == .sent)
        #expect(slack.sent.last == "chat.postMessage")
        await m.approve(1, at: Date().addingTimeInterval(3600))
        #expect(slack.sent.last == "chat.scheduleMessage")
    }

    @Test("When the call fails, the app's own fallback shows up to 3 cards with no draft")
    func fallback() async {
        let m = CatchUpModel(token: { "xoxp-1" }, sender: CannedSlack())
        await m.focusEnded(since: since)
        await m.catchMeUp(with: StubWork(fail: true))
        #expect(m.state == .ready && !m.fromGemini)
        #expect(m.cards.count == 2 && m.cards.allSatisfy { $0.draft.isEmpty })
        #expect(CatchUpModel.localFallback((0..<5).map { CatchUpItem(source: .slack, fromLabel: "P\($0)", text: "t") }).items.count == 3)
    }
}

@MainActor
@Suite("After-hours guard on the Mac")
struct AfterHoursGuardTests {
    @Test("Work hours are saved in the store, and bad ones are refused")
    func saves() {
        let d = scratchDefaults()
        let g = AfterHoursGuard(defaults: d)
        g.save(WorkHours(start: "10:00", end: "19:00", days: [1, 2, 3], tz: "Asia/Kolkata"))
        g.save(WorkHours(start: "10:00", end: "10:00", days: [1], tz: "Asia/Kolkata"))
        #expect(AfterHoursGuard(defaults: d).hours == WorkHours(start: "10:00", end: "19:00", days: [1, 2, 3], tz: "Asia/Kolkata"))
    }

    @Test("Switched off, nothing is ever after hours")
    func off() {
        let g = AfterHoursGuard(defaults: scratchDefaults())
        g.save(WorkHours(start: "00:00", end: "00:01", days: [1, 2, 3, 4, 5, 6, 7], tz: "Asia/Kolkata"))
        g.enabled = false
        #expect(!g.isAfterHours())
        g.enabled = true
        #expect(g.isAfterHours(Date(timeIntervalSince1970: 1_795_179_600)))
    }
}

@MainActor
@Suite("Focus Mode settings")
struct FocusSettingsTests {
    @Test("Hooks are on by default and come in chip order")
    func defaults() {
        let s = FocusSettings(defaults: scratchDefaults())
        #expect(s.dnd && s.slack && s.calendar)
        #expect(s.hooks().map(\.id) == ["dnd", "slack", "calendar", "webhook"])
        #expect(s.webhook == nil)
    }

    @Test("Until-time suggestions land on a whole or half hour at least 30 minutes away")
    func suggestedUntil() {
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 10, minute: 7, second: 0, of: Date())!
        let u = FocusModel.suggestedUntil(from: base)
        #expect(u.timeIntervalSince(base) >= 30 * 60)
        #expect([0, 30].contains(cal.component(.minute, from: u)))
    }
}
