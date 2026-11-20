// Zeno's seven tools against whatever the model might send: wrong types, empty and huge strings,
// numbers far out of range, NaN-like text, arrays and objects where a scalar belongs. Every call
// must come back as a well-formed answer inside the tool's limits, never a crash.
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

private struct Box {
    let clock = ManualVoiceClock(T.now)
    let ledger: OnDeviceLedger
    let cards = FakeZenCards(now: { T.now })
    let toolbox: ZenoToolbox

    init(scores: any ScoreService = InstantScores(), scoreTimeout: Duration = .seconds(4)) {
        ledger = T.ledger(clock)
        toolbox = ZenoToolbox(ledger: ledger, scores: scores, cards: cards, scoreTimeout: scoreTimeout)
    }

    func call(_ name: String, _ args: JSONValue = [:]) async -> ToolOutcome { await toolbox.call(name, args: args) }
}

/// A score service that never answers in time.
private struct HangingScores: ScoreService {
    func today() async throws -> ScoreSnapshot {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
    func updates() -> AsyncStream<ScoreSnapshot> { AsyncStream { $0.finish() } }
}

private let garbage: [JSONValue] = [
    .null, true, false, 0, -1, 2.5, 1e20, -1e20, 1.5e300, -0.0,
    "", "   ", "abc", "NaN", "Infinity", "-Infinity", "1e400", "0x10", " 7 ",
    .string(String(repeating: "x", count: 5_000)), .string("🧘‍♀️" + String(repeating: "த", count: 300)),
    [], [1, "two", .null], ["nested": ["deeper": 1]],
]

private let argKeys: [ZenoAgent.ToolName: [String]] = [
    .getZenStatus: ["anything"],
    .setIntent: ["app", "purpose", "minutes"],
    .endSession: ["session_id", "overrun_minutes"],
    .startFocus: ["minutes", "label", "quiet_apps"],
    .pauseApp: ["app", "seconds"],
    .logReflection: ["summary", "mood", "language", "earned_back", "drift"],
    .shareWithCircle: ["note", "include_score"],
]

private func string(_ value: JSONValue?) -> String? { value?.stringValue }

@Suite("Zeno's tools with malformed arguments")
struct ZenoToolboxMalformedArgsTests {
    @Test("Every tool answers well-formed JSON inside its limits, whatever one argument holds",
          arguments: ZenoAgent.ToolName.allCases)
    func everyToolSurvivesGarbage(tool: ZenoAgent.ToolName) async throws {
        for key in try #require(argKeys[tool]) {
            for value in garbage {
                let box = Box()
                // What each tool needs to have something to act on.
                if tool == .endSession { await box.ledger.startIntent(app: "Instagram", purpose: "", minutes: 2) }
                if tool == .shareWithCircle {
                    _ = await box.call("log_reflection", ["summary": "A quiet evening", "mood": "happy", "language": "en"])
                }
                var args: [String: JSONValue] = [:]
                if tool == .logReflection, key != "summary" { args["summary"] = "A quiet evening" }
                args[key] = value
                let outcome = await box.call(tool.rawValue, .object(args))
                let where_ = "\(tool.rawValue).\(key) = \(value.jsonString().prefix(40))"
                #expect(outcome.result.jsonString() != "null", "\(where_): the answer isn't JSON")
                #expect(outcome.result["ok"]?.boolValue != nil, "\(where_): no ok flag")
                check(tool, key: key, value: value, outcome, where_)
            }
        }
    }

    private func check(_ tool: ZenoAgent.ToolName, key: String, value: JSONValue, _ outcome: ToolOutcome, _ where_: String) {
        let r = outcome.result
        switch tool {
        case .getZenStatus:
            #expect(outcome.ok, "\(where_)")
        case .setIntent:
            #expect(outcome.ok, "\(where_)")
            #expect(ZenoLimits.intentMinutes.contains(Int(r["minutes"]?.doubleValue ?? -1)), "\(where_)")
            let app = string(r["app"]) ?? ""
            #expect(!app.isEmpty && app.count <= ZenoLimits.maxAppNameLength, "\(where_)")
            if case .intent(let session) = outcome.card {
                #expect(session.purpose.count <= ZenoLimits.maxPurposeLength, "\(where_)")
            } else {
                Issue.record("\(where_): no intent card")
            }
        case .endSession:
            #expect(outcome.ok, "\(where_)") // the open intent ends, whatever the id says
            #expect(ZenoLimits.overrunMinutes.contains(Int(r["overrun_minutes"]?.doubleValue ?? -1)), "\(where_)")
        case .startFocus:
            #expect(outcome.ok, "\(where_)")
            #expect(ZenoLimits.focusMinutes.contains(Int(r["minutes"]?.doubleValue ?? -1)), "\(where_)")
            let label = string(r["label"]) ?? ""
            #expect(!label.isEmpty && label.count <= ZenoLimits.maxLabelLength, "\(where_)")
            let quiet = r["quiet_apps"]?.arrayValue ?? []
            #expect(quiet.count <= ZenoLimits.maxQuietApps, "\(where_)")
            #expect(quiet.allSatisfy { ($0.stringValue?.count ?? 99) <= ZenoLimits.maxAppNameLength }, "\(where_)")
        case .pauseApp:
            #expect(outcome.ok, "\(where_)")
            #expect(ZenoLimits.pauseSeconds.contains(Int(r["seconds"]?.doubleValue ?? -1)), "\(where_)")
            #expect((string(r["app"])?.count ?? 0) <= ZenoLimits.maxAppNameLength, "\(where_)")
        case .logReflection:
            let hasSummary = ZenoToolbox.text(key == "summary" ? value : "A quiet evening", limit: 280) != nil
            #expect(outcome.ok == hasSummary, "\(where_)")
            guard case .zenCard(let card) = outcome.card else {
                #expect(!hasSummary, "\(where_): no card")
                return
            }
            #expect(card.summary.count <= ZenCardDraft.maxSummaryLength, "\(where_)")
            #expect(ZenCardDraft.isLanguageTag(card.language) || card.language == ZenCardDraft.unknownLanguage, "\(where_)")
            #expect((card.earnedBack?.count ?? 0) <= ZenCardDraft.maxEarnedBackLength, "\(where_)")
            #expect((card.drift?.count ?? 0) <= ZenCardDraft.maxDriftLength, "\(where_)")
            #expect(r["card"]?["score"] == nil, "\(where_)")
        case .shareWithCircle:
            #expect(outcome.ok, "\(where_)")
            #expect(r["score_included"] == false, "\(where_)")
            #expect((string(r["note"])?.count ?? 0) <= ZenCardDraft.maxNoteLength, "\(where_)")
        }
    }

    @Test("Arguments that aren't an object count as none, for every tool",
          arguments: [JSONValue.null, "set_intent", 42, [1, 2], true])
    func nonObjectArguments(args: JSONValue) async {
        for tool in ZenoAgent.ToolName.allCases {
            let box = Box()
            if tool == .endSession { await box.ledger.startIntent(app: "Instagram", purpose: "", minutes: 2) }
            let outcome = await box.call(tool.rawValue, args)
            switch tool {
            case .logReflection: #expect(outcome.result == ["ok": false, "error": "the note is empty"])
            case .shareWithCircle: #expect(outcome.result == ["ok": false, "error": "no Zen Card to share yet"])
            default: #expect(outcome.ok, "\(tool.rawValue)")
            }
        }
    }

    @Test("A number far too big for an integer is written out, not a crash")
    func hugeNumbersAsText() async {
        let box = Box()
        let outcome = await box.call("set_intent", ["app": 1e20, "purpose": -3e19, "minutes": 1e20])
        #expect(outcome.result["app"] == "1e+20")
        #expect(outcome.result["minutes"] == 180)
        #expect(await box.ledger.activeIntent?.purpose == "-3e+19")
        #expect(ZenoToolbox.text(.number(9.0e15), limit: 40).flatMap(Double.init) == 9.0e15)
        #expect(ZenoToolbox.text(.number(8_999_999_999_999_998), limit: 40) == "8999999999999998")
        #expect(ZenoToolbox.text(.number(-0.0), limit: 40) == "0")
    }

    @Test("Numbers read the way JavaScript's Number() reads them", arguments: [
        (JSONValue.string("1e3"), 180), ("Infinity", 5), ("-Infinity", 5), ("NaN", 5), ("-0", 5), (" 7 ", 7), ("0x10", 16),
        ("1_000", 5), ([], 5), (["a": 1], 5), (false, 5), (179.5, 180), (-0.5, 1),
    ] as [(JSONValue, Int)])
    func javaScriptNumbers(given: JSONValue, minutes: Int) async {
        #expect(await Box().call("set_intent", ["minutes": given]).result["minutes"] == .int(minutes))
    }

    @Test("end_session: a bad id ends the open session; the overrun is clamped to 0…720")
    func endSessionArguments() async {
        for (overrun, expected) in [(JSONValue.string("abc"), 0), (1e9, 720), (-50, 0), ("12", 12), (2.5, 3)] as [(JSONValue, Int)] {
            let box = Box()
            await box.ledger.startIntent(app: "Instagram", purpose: "", minutes: 2)
            let outcome = await box.call("end_session", ["session_id": ["s1"], "overrun_minutes": overrun])
            #expect(outcome.result["session_id"] == "s1")
            #expect(outcome.result["overrun_minutes"] == .int(expected), "overrun \(overrun.jsonString())")
            #expect(outcome.result["on_time"] == .bool(expected == 0))
        }
    }

    @Test("start_focus keeps only text quiet apps, once each, at most ten")
    func quietApps() async {
        let mixed: JSONValue = ["Instagram", 42, .null, ["a": 1], "instagram", "   ", "YouTube", [], true]
        #expect(await Box().call("start_focus", ["quiet_apps": mixed]).result["quiet_apps"] == ["Instagram", "42", "YouTube"])
        let many = JSONValue.array((1...15).map { .string("App \($0)") })
        let capped = await Box().call("start_focus", ["quiet_apps": many]).result["quiet_apps"]?.arrayValue
        #expect(capped?.count == 10)
        #expect(await Box().call("start_focus", ["quiet_apps": "Instagram"]).result["quiet_apps"] == [])
        let long = await Box().call("start_focus", ["quiet_apps": [.string(String(repeating: "a", count: 90))], "label": 7])
        #expect(long.result["quiet_apps"]?.arrayValue?.first?.stringValue?.count == 40)
        #expect(long.result["label"] == "7")
    }

    @Test("log_reflection: a number is a note, an array isn't; moods ignore case; odd languages fall back")
    func reflectionArguments() async {
        let number = await Box().call("log_reflection", ["summary": 42, "mood": "HAPPY", "language": ""])
        #expect(number.result["card"]?["summary"] == "42")
        #expect(number.result["card"]?["mood"] == "happy")
        #expect(number.result["card"]?["language"] == "en")
        #expect(await Box().call("log_reflection", ["summary": ["a note"]]).result["error"] == "the note is empty")
        let odd = await Box().call("log_reflection", ["summary": "ok", "mood": 3, "language": 5,
                                                      "earned_back": .string(String(repeating: "e", count: 300))])
        #expect(odd.result["card"]?["mood"] == "pleasant")
        #expect(odd.result["card"]?["language"] == "und")
        #expect(odd.result["card"]?["earned_back"]?.stringValue?.count == ZenCardDraft.maxEarnedBackLength)
    }

    @Test("share_with_circle: a note that isn't text is no note; a long one is cut to 120")
    func shareArguments() async {
        let box = Box()
        _ = await box.call("log_reflection", ["summary": "Dinner without phones", "mood": "happy", "language": "en"])
        #expect(await box.call("share_with_circle", ["note": ["text": "hi"]]).result["note"] == .null)
        let long = await box.call("share_with_circle", ["note": .string(String(repeating: "n", count: 500)), "include_score": "yes"])
        #expect(long.result["note"]?.stringValue?.count == ZenCardDraft.maxNoteLength)
        #expect(long.result["score_included"] == false)
        #expect(box.cards.notes["card-1"]?.count == ZenCardDraft.maxNoteLength)
    }

    @Test("get_zen_status answers from the device when the score service hangs")
    func statusWhenTheScoreHangs() async {
        let box = Box(scores: HangingScores(), scoreTimeout: .milliseconds(30))
        await box.ledger.recordPickup()
        let started = ContinuousClock.now
        let outcome = await box.call("get_zen_status", ["unexpected": [1, 2, 3]])
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(outcome.ok)
        #expect(outcome.result["score_available"] == false)
        #expect(outcome.result["score"] == nil)
        #expect(outcome.result["pickups_today"] == 1)
    }

    @Test("The change since yesterday needs both days")
    func changeSinceYesterday() {
        let days: [ZenScore?] = [ZenScore(tenths: 70), nil, ZenScore(tenths: 64), nil, nil, nil, nil]
        #expect(ZenoToolbox.changeSinceYesterday(WeekProgress(days: days, todayIndex: 0, streakBefore: 0)) == nil)
        #expect(ZenoToolbox.changeSinceYesterday(WeekProgress(days: days, todayIndex: 1, streakBefore: 0)) == nil)
        #expect(ZenoToolbox.changeSinceYesterday(WeekProgress(days: days, todayIndex: 2, streakBefore: 0)) == nil)
        #expect(ZenoToolbox.changeSinceYesterday(WeekProgress(days: days, todayIndex: nil, streakBefore: 0)) == nil)
        let twoDays: [ZenScore?] = [ZenScore(tenths: 70), ZenScore(tenths: 64), nil, nil, nil, nil, nil]
        #expect(ZenoToolbox.changeSinceYesterday(WeekProgress(days: twoDays, todayIndex: 1, streakBefore: 0)) == -0.6)
    }
}
