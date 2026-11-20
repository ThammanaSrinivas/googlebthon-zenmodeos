// Zeno's seven tools: argument validation and clamping exactly as the prototype's ledger, the JSON
// each returns, the live score, and the Zen Card calls (never with a score).
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

private struct Fixture {
    let clock = ManualVoiceClock(T.now)
    let ledger: OnDeviceLedger
    let cards: FakeZenCards
    let toolbox: ZenoToolbox

    init(scores: InstantScores = InstantScores(), failingCards: Bool = false) {
        ledger = T.ledger(clock)
        cards = FakeZenCards(failing: failingCards, now: { T.now })
        toolbox = ZenoToolbox(ledger: ledger, scores: scores, cards: cards)
    }

    func call(_ name: String, _ args: JSONValue = [:]) async -> ToolOutcome { await toolbox.call(name, args: args) }
}

@Suite("Zeno's tools")
struct ZenoToolboxTests {
    // MARK: set_intent

    @Test("set_intent returns the prototype's shape and shows a timer card")
    func setIntent() async throws {
        let f = Fixture()
        let outcome = await f.call("set_intent", ["app": "Instagram", "purpose": "Watch the reel Arun sent", "minutes": 2])
        #expect(outcome.result == [
            "ok": true, "session_id": "s1", "app": "Instagram", "minutes": 2, "ends_at": "2026-11-20T16:34:00Z",
        ])
        guard case .intent(let session) = outcome.card else { Issue.record("expected an intent card"); return }
        #expect(session.purpose == "Watch the reel Arun sent")
        #expect(await f.ledger.activeIntent == session)
    }

    @Test("set_intent minutes: Math.round(Number(x) || 5), clamped to 1…180", arguments: [
        (JSONValue.null, 5), (0, 5), ("", 5), ("abc", 5), (2.5, 3), (2.4, 2), ("45", 45), (-3, 1), (500, 180), (true, 1),
    ] as [(JSONValue, Int)])
    func intentMinutes(given: JSONValue, expected: Int) async {
        let outcome = await Fixture().call("set_intent", ["app": "YouTube", "minutes": given])
        #expect(outcome.result["minutes"] == .int(expected))
    }

    @Test("set_intent defaults: the app is Phone, missing minutes are 5")
    func intentDefaults() async {
        let outcome = await Fixture().call("set_intent")
        #expect(outcome.result["app"] == "Phone")
        #expect(outcome.result["minutes"] == 5)
    }

    @Test("A second intent replaces the first and says so")
    func intentReplaces() async {
        let f = Fixture()
        _ = await f.call("set_intent", ["app": "Instagram", "minutes": 2])
        let second = await f.call("set_intent", ["app": "YouTube", "minutes": 10])
        #expect(second.result["replaced_session_id"] == "s1")
    }

    // MARK: end_session

    @Test("end_session with nothing open is an error the model can say")
    func endNothing() async {
        #expect(await Fixture().call("end_session").result == ["ok": false, "error": "no open session"])
    }

    @Test("end_session on time, and past the minutes")
    func endSession() async {
        let f = Fixture()
        _ = await f.call("set_intent", ["app": "Instagram", "minutes": 2])
        f.clock.advance(by: 120)
        #expect(await f.call("end_session").result == [
            "ok": true, "session_id": "s1", "app": "Instagram", "minutes": 2, "on_time": true, "overrun_minutes": 0,
        ])
        _ = await f.call("set_intent", ["app": "YouTube", "minutes": 5])
        let late = await f.call("end_session", ["session_id": "s2", "overrun_minutes": "4"])
        #expect(late.result["on_time"] == false)
        #expect(late.result["overrun_minutes"] == 4)
        guard case .intentEnded = late.card else { Issue.record("expected an ended card"); return }
    }

    // MARK: start_focus

    @Test("start_focus minutes clamp to 5…240 with 25 by default", arguments: [
        (JSONValue.null, 25), (1, 5), (45, 45), (1_000, 240), ("60", 60),
    ] as [(JSONValue, Int)])
    func focusMinutes(given: JSONValue, expected: Int) async {
        let outcome = await Fixture().call("start_focus", ["minutes": given, "label": "Study"])
        #expect(outcome.result["minutes"] == .int(expected))
    }

    @Test("start_focus: label default, quiet apps de-duplicated, this device only")
    func focus() async {
        let f = Fixture()
        let outcome = await f.call("start_focus", ["minutes": 45, "quiet_apps": ["WhatsApp", "whatsapp", " Slack ", 7, ""]])
        #expect(outcome.result == [
            "ok": true, "focus_id": "f1", "minutes": 45, "label": "Focus", "ends_at": "2026-11-20T17:17:00Z",
            "quiet_apps": ["WhatsApp", "Slack", "7"], "scope": "this device",
        ])
        #expect(await f.ledger.activeFocus?.quietApps == ["WhatsApp", "Slack", "7"])
    }

    // MARK: pause_app

    @Test("pause_app seconds clamp to 3…30 with 7 by default", arguments: [
        (JSONValue.null, 7), (1, 3), (12, 12), (100, 30),
    ] as [(JSONValue, Int)])
    func pauseSeconds(given: JSONValue, expected: Int) async {
        let outcome = await Fixture().call("pause_app", ["app": "WhatsApp", "seconds": given])
        #expect(outcome.result["seconds"] == .int(expected))
    }

    @Test("pause_app lists every paused app; the default app is Instagram")
    func pause() async {
        let f = Fixture()
        _ = await f.call("pause_app")
        let outcome = await f.call("pause_app", ["app": "WhatsApp"])
        #expect(outcome.result == ["ok": true, "app": "WhatsApp", "seconds": 7, "paused_apps": ["Instagram", "WhatsApp"]])
    }

    // MARK: get_zen_status

    @Test("get_zen_status reads the live combined score and the device's ledger")
    func status() async {
        let f = Fixture()
        await f.ledger.recordPickup()
        _ = await f.call("set_intent", ["app": "Instagram", "minutes": 2])
        _ = await f.call("pause_app", ["app": "WhatsApp"])
        let outcome = await f.call("get_zen_status")
        #expect(outcome.result == [
            "ok": true, "score_available": true, "score": 8.1, "score_text": "8.1", "good_day": true,
            "good_day_threshold": 6.0, "good_days_this_week": 3, "good_days_needed_to_win_week": 4, "week_won": false,
            "weekly_streak_weeks": 9, "week_line": "3 of 4 good days · one more wins the week",
            "change_since_yesterday": 2.7, "pickups_today": 1, "pickups_with_intent": 1,
            "active_session": ["session_id": "s1", "app": "Instagram", "purpose": "", "minutes": 2, "ends_at": "2026-11-20T16:34:00Z"],
            "focus": nil, "paused_apps": ["WhatsApp"],
        ])
        guard case .status(let status) = outcome.card else { Issue.record("expected a status card"); return }
        #expect(status.score == ZenScore(tenths: 81))
    }

    @Test("Without a score (offline) the status says so and still reports the device")
    func statusOffline() async {
        let outcome = await Fixture(scores: InstantScores(fail: true)).call("get_zen_status")
        #expect(outcome.result["score_available"] == false)
        #expect(outcome.result["score"] == nil)
        #expect(outcome.result["pickups_today"] == 0)
    }

    // MARK: log_reflection and share_with_circle

    @Test("log_reflection saves a Zen Card through the card service")
    func reflection() async throws {
        let f = Fixture()
        let outcome = await f.call("log_reflection", [
            "summary": "காலையில வாக்கிங், டின்னர் அப்போ ஃபோன் இல்ல", "mood": "happy", "language": "ta",
            "earned_back": "A phone-free dinner, and a long walk by the lake", "drift": "",
        ])
        #expect(outcome.result == [
            "ok": true, "question": "What did you earn back today?",
            "card": ["id": "card-1", "summary": "காலையில வாக்கிங், டின்னர் அப்போ ஃபோன் இல்ல", "mood": "happy", "language": "ta",
                     "earned_back": "A phone-free dinner, and a long walk by", "drift": nil, "shared": false],
        ])
        let saved = try await f.cards.recent()
        #expect(saved.count == 1)
        #expect((saved[0].earnedBack?.count ?? 0) <= ZenCardDraft.maxEarnedBackLength)
        #expect(await f.ledger.lastCardId == "card-1")
    }

    @Test("A mood outside the five becomes pleasant; a bad language tag becomes und")
    func reflectionCleansUp() async throws {
        let f = Fixture()
        _ = await f.call("log_reflection", ["summary": "Okay day", "mood": "ANGRY", "language": "tamil language"])
        let card = try #require(try await f.cards.recent().first)
        #expect(card.mood == .pleasant)
        #expect(card.language == "und")
    }

    @Test("An empty note makes no card")
    func emptyReflection() async throws {
        let f = Fixture()
        #expect(await f.call("log_reflection", ["summary": "  ", "mood": "happy", "language": "en"]).result
            == ["ok": false, "error": "the note is empty"])
        #expect(try await f.cards.recent().isEmpty)
    }

    @Test("share_with_circle shares the latest card, never with a score")
    func share() async throws {
        let f = Fixture()
        #expect(await f.call("share_with_circle").result == ["ok": false, "error": "no Zen Card to share yet"])
        _ = await f.call("log_reflection", ["summary": "Walked, no phone at dinner", "mood": "happy", "language": "en"])
        let outcome = await f.call("share_with_circle", ["note": "Phone-free dinner tonight", "include_score": true])
        #expect(outcome.result == [
            "ok": true, "card_id": "card-1", "shared": true, "score_included": false, "note": "Phone-free dinner tonight",
        ])
        guard case .zenCard(let card) = outcome.card else { Issue.record("expected a Zen Card"); return }
        #expect(card.isShared)
        #expect(f.cards.notes == ["card-1": "Phone-free dinner tonight"])
    }

    @Test("Card failures come back as errors, not crashes")
    func cardFailures() async {
        let f = Fixture(failingCards: true)
        #expect(await f.call("log_reflection", ["summary": "x", "mood": "happy", "language": "en"]).result
            == ["ok": false, "error": "could not save the Zen Card"])
        await f.ledger.setLastCard(id: "card-9")
        #expect(await f.call("share_with_circle").result == ["ok": false, "error": "could not share the Zen Card"])
    }

    @Test("No card result ever carries a score")
    func cardsCarryNoScore() async {
        let f = Fixture()
        let saved = await f.call("log_reflection", ["summary": "Good day", "mood": "happy", "language": "en"])
        let shared = await f.call("share_with_circle", ["include_score": true])
        for result in [saved.result, shared.result] {
            #expect(!result.jsonString().contains("8.1"))
            #expect(result["score"] == nil && result["card"]?["score"] == nil)
        }
    }

    // MARK: Unknown

    @Test("An unknown tool is an error response")
    func unknown() async {
        #expect(await Fixture().call("delete_everything").result == ["ok": false, "error": "unknown tool delete_everything"])
    }

    @Test("Arguments that aren't an object count as none")
    func nonObjectArgs() async {
        #expect(await Fixture().call("set_intent", "Instagram").result["app"] == "Phone")
    }
}
