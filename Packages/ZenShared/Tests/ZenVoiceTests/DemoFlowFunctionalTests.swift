// Functional tests: the demo end to end through VoiceModel, the way the app runs it. VoiceModel
// drives a real ZenoSession against the scripted Gemini Live server; every tool call runs through
// ZenoToolbox on an OnDeviceLedger and saves or shares through FakeZenCards. The tests check what
// the device ends up holding, what the backend fake received (a note, never a score), and the
// transcript the notch shows. Plus a Hindi and Tamil script case for the language labels.
import Foundation
import Testing
import ZenAPI
import ZenLogic
import ZenMock
@testable import ZenVoice

/// What the notch shows for one transcript line.
private struct Shown: Equatable, CustomStringConvertible {
    let speaker: TranscriptLine.Speaker
    let text: String
    let label: String?
    let cut: Bool

    init(_ speaker: TranscriptLine.Speaker, _ text: String, _ label: String? = nil, cut: Bool = false) {
        self.speaker = speaker
        self.text = text
        self.label = label
        self.cut = cut
    }

    init(_ line: TranscriptLine) { self.init(line.speaker, line.text, line.languageLabel, cut: line.wasCut) }

    var description: String { "\(speaker.rawValue)[\(label ?? "-")\(cut ? ", cut" : "")]: \(text)" }
}

/// The five moments, as the notch shows them with the demo week's score (InstantScores: 8.1).
private let fiveMomentsTranscript: [Shown] = [
    Shown(.zeno, "Hey Kamal. What are you here for?"),
    Shown(.user, "Zeno, Arun anuppuna reel-a paakkanum. Insta-la rendu nimisham mattum.", "Tanglish"),
    Shown(.zeno, "Seri, rendu nimisham. Mudinjadhum naan solren."),
    Shown(.zeno, "Rendu nimisham, correct-a mudinjadhu. Super!"),
    Shown(.user, "Kal subah client demo hai. Mujhe ek ghante ka focus chahiye, aur…", "Hinglish"),
    Shown(.zeno, "Theek hai, ek ghante ka focus shu—", cut: true),
    Shown(.user, "Nahi nahi, 45 minute. Aur WhatsApp pe pause laga do.", "Hinglish"),
    Shown(.zeno, "Ho gaya. 45 minute focus, aur WhatsApp pe 7 second ka pause."),
    Shown(.user, "How's my day looking?", "English"),
    Shown(.zeno, "Zen Score 8.1. 3 of 4 good days, one more wins the week."),
    Shown(.user, "இன்னைக்கு காலையில வாக்கிங் போனேன். டின்னர் அப்போ ஃபோனை தொடவே இல்ல. சர்க்கிளுக்கு ஷேர் பண்ணு.", "Tamil"),
    Shown(.zeno, "சூப்பர்! உங்க Zen Card ரெடி. சர்க்கிளுக்கும் அனுப்பிட்டேன்."),
]

/// Waits (up to 10 s) for the model's session to finish.
@MainActor
private func untilFinished(_ model: VoiceModel) async {
    for _ in 0..<10_000 where model.isActive { try? await Task.sleep(for: .milliseconds(1)) }
    if model.isActive { Issue.record("The session never finished; state \(model.state)") }
}

/// The replay's sleeper: holds the first time skip (900 ms) until the task is cancelled, which is
/// how a test stops the demo mid-way; every other pause, and every later run, just yields.
private final class HoldFirstSkip: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false

    func sleep(_ duration: Duration) async {
        let hold = lock.withLock { () -> Bool in
            guard duration == .milliseconds(900), !held else { return false }
            held = true
            return true
        }
        if hold { try? await Task.sleep(for: .seconds(60)) } else { await Task.yield() }
    }
}

/// A shared card never carries a score: not as a field, and not in its words.
private func expectNoScore(_ card: ZenCard, note: String?, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any] ?? [:]
    #expect(!json.keys.contains { $0.lowercased().contains("score") }, sourceLocation: sourceLocation)
    for text in [card.summary, card.earnedBack, card.drift, note].compactMap({ $0 }) {
        #expect(!text.contains("8.1") && !text.lowercased().contains("zen score"), sourceLocation: sourceLocation)
    }
}

@Suite("Demo flow, end to end through VoiceModel")
@MainActor
struct DemoFlowFunctionalTests {
    @Test("VoiceModel.demo: the five moments leave the ledger, the card and the notch exactly as scripted")
    func fiveMomentsThroughTheDemoModel() async throws {
        let cards = FakeZenCards()
        let model = VoiceModel.demo(scores: InstantScores(), cards: cards, userName: "Kamal", pace: 0,
                                    sleep: { _ in await Task.yield() })
        var voiced: [DemoLine] = []
        model.onDemoLine = { voiced.append($0) }
        await model.start(pickup: true)
        await untilFinished(model)

        #expect(model.state == .ended)
        #expect(model.error == nil)

        // The notch: every line, in order, with its label; only the barged-in line is cut.
        let shown = model.lines.map(Shown.init)
        #expect(shown == fiveMomentsTranscript)
        #expect(model.lines.allSatisfy { $0.isFinal })
        #expect(model.lines.map(\.id) == Array(1...12))
        #expect(!model.lines.contains { $0.text.contains(ZenoAgent.pickupCue) }) // the cue is never shown
        #expect(voiced.map(\.text) == fiveMomentsTranscript.map(\.text)) // what the app voices matches

        // The ledger: one Instagram intent, ended on time after its two minutes.
        let ledger = model.ledger
        let intents = await ledger.intents
        #expect(intents.count == 1)
        let intent = try #require(intents.first)
        #expect(intent.app == "Instagram" && intent.purpose == "Watch the reel Arun sent" && intent.minutes == 2)
        #expect(intent.endReason == .ended && intent.onTime == true && intent.overrunMinutes == 0)
        #expect(intent.endedAt.map { $0.timeIntervalSince(intent.startedAt) } == 120)
        #expect(await ledger.activeIntent == nil)

        // Focus started for 45 minutes and still running at 22:41; WhatsApp paused for 7 seconds.
        let focus = try #require(await ledger.status().focus)
        #expect(focus.minutes == 45 && focus.label == "Client demo prep" && focus.quietApps.isEmpty)
        #expect(await ledger.pauses.map(\.app) == ["WhatsApp"])
        #expect(await ledger.pauseSeconds(for: "whatsapp") == 7)

        // One pickup, and it had an intent.
        let pickups = await ledger.today()
        #expect(pickups.total == 1 && pickups.withIntent == 1)

        // The reflection became a card, then that card was shared with the note only.
        let saved = try await cards.recent()
        #expect(saved.count == 1)
        let card = try #require(saved.first)
        #expect(await ledger.lastCardId == card.id)
        #expect(card.summary == "காலையில வாக்கிங், டின்னர் அப்போ ஃபோன் இல்ல")
        #expect(card.mood == .happy && card.language == "ta")
        #expect(card.earnedBack == "A phone-free dinner" && card.drift == nil)
        #expect(card.isShared)
        #expect(cards.notes == [card.id: "Phone-free dinner tonight"])
        try expectNoScore(card, note: cards.notes[card.id])

        // The island's last state.
        #expect(model.card == .zenCard(card))
        #expect(model.activeIntent == nil)
        #expect(model.activeFocus?.id == focus.id)
        #expect(model.timeUp == nil)
        #expect(model.runningTool == nil)
        #expect(model.demoClock == "22:41")
    }

    @Test("The live path on the scripted server: real token flow, the ledger's clock, the real protocol")
    func fiveMomentsThroughTheLiveModel() async throws {
        let clock = ManualVoiceClock(T.now) // 22:02 in India
        let ledger = T.ledger(clock)
        let cards = FakeZenCards(now: { clock.now })
        let server = ScriptedLiveTransport(user: "Kamal", pace: 0, sleep: { _ in await Task.yield() },
                                           advanceClock: { clock.advance(by: $0) })
        let model = VoiceModel(tokens: FakeVoiceTokens(), scores: InstantScores(), cards: cards, ledger: ledger,
                               userName: "Kamal", transport: { server })
        #expect(!model.isDemo)
        await model.start(pickup: true)
        await untilFinished(model)

        #expect(model.state == .ended)
        #expect(model.error == nil)
        #expect(model.lines.map(Shown.init) == fiveMomentsTranscript)
        #expect(model.latencyMs == nil) // the replay sends no audio, so there is no first-audio time

        // The token opened the connection, and only the URL carried it.
        let url = try #require(await server.connectedURL)
        #expect(url.absoluteString.hasSuffix("BidiGenerateContentConstrained?access_token=\(FakeVoiceTokens.demoToken)"))
        let received = await server.received
        guard case .setup(let setup) = received.first else { Issue.record("the setup goes first"); return }
        #expect(setup.model == "models/gemini-3.8-live")
        // The pickup cue went once. (The scripted server doesn't wait for it as Gemini does, so
        // where it lands among the tool responses isn't fixed.)
        let texts = received.compactMap { if case .clientContent(let c) = $0 { c.turns.first?.parts.first?.text } else { nil } }
        #expect(texts == [ZenoAgent.pickupCue])
        #expect(received.filter { if case .toolResponse = $0 { true } else { false } }.count == 7)
        for message in received { #expect(!(try message.jsonString()).contains(FakeVoiceTokens.demoToken)) }

        // What Gemini was told: every tool succeeded; the share says no score went with it.
        let results = await server.toolResults
        #expect(results.map(\.name) == ["set_intent", "end_session", "start_focus", "pause_app", "get_zen_status",
                                        "log_reflection", "share_with_circle"])
        #expect(results.allSatisfy { $0.result["ok"] == true })
        let share = try #require(results.last?.result)
        #expect(share["score_included"] == false && share["shared"] == true)
        #expect(share["note"] == "Phone-free dinner tonight")
        #expect(results[4].result["pickups_with_intent"] == 1)

        // The ledger moved with the script's clock: 22:02 → 22:04 → 22:41.
        let intent = try #require(await ledger.intents.first)
        #expect(intent.startedAt == T.now && intent.endedAt == T.now.addingTimeInterval(120))
        let focus = try #require(await ledger.status().focus)
        #expect(focus.startedAt == T.now.addingTimeInterval(120))
        #expect(focus.endsAt == T.now.addingTimeInterval(120 + 45 * 60))
        #expect(clock.now == T.now.addingTimeInterval(120 + 37 * 60))
        #expect(await ledger.checkTimers().isEmpty) // nothing overdue at 22:41: the intent ended, focus runs to 22:49
        #expect(await ledger.today() == PickupTally(day: DayKeys.key(for: T.now, in: T.india), total: 1, withIntent: 1))

        // The card was written at 22:41 and shared at once, with the note only.
        let card = try #require(try await cards.recent().first)
        #expect(card.createdAt == clock.now && card.sharedAt == clock.now)
        try expectNoScore(card, note: cards.notes[card.id])
        #expect(model.card == .zenCard(card))
        #expect(model.activeFocus == focus)
    }

    @Test("On stage: stop the demo mid-way, replay it, and the second run is clean")
    func stopThenReplay() async throws {
        let hold = HoldFirstSkip()
        let cards = FakeZenCards()
        let model = VoiceModel.demo(scores: InstantScores(), cards: cards, userName: "Kamal", pace: 1,
                                    sleep: { await hold.sleep($0) })

        // The first run stops at moment 2's time skip, with the Instagram timer running.
        await model.start(pickup: true)
        await until("moment 2's skip") { model.demoClock == "22:04" && model.lines.count == 3 }
        #expect(model.activeIntent?.app == "Instagram")
        await model.stop()
        #expect(model.state == .ended && !model.isActive && model.error == nil)

        // The replay starts from a clean notch and plays all five moments.
        await model.start(pickup: true)
        await untilFinished(model)
        #expect(model.state == .ended && model.error == nil)
        #expect(model.lines.map(Shown.init) == fiveMomentsTranscript)
        #expect(model.lines.allSatisfy { $0.isFinal })

        // The open intent from the stopped run was replaced, the replay's ended on time.
        let intents = await model.ledger.intents
        #expect(intents.map(\.endReason) == [.replaced, .ended])
        #expect(intents.last?.onTime == true)
        #expect(await model.ledger.today().total == 2)
        #expect(await model.ledger.today().withIntent == 2)
        let saved = try await cards.recent()
        #expect(saved.count == 1 && saved[0].isShared) // the stopped run never reached moment 5
        #expect(model.activeIntent == nil)
    }

    @Test("Hindi and Tamil in their own scripts get their own labels; Latin-script Tamil reads as Tanglish")
    func hindiAndTamil() async throws {
        func line(_ speaker: DemoLine.Speaker, _ language: String, _ text: String) -> DemoLine {
            DemoLine(speaker: speaker, text: text, language: language, tag: nil, clip: nil, milliseconds: 0, cut: false)
        }
        let script: [DemoStep] = [
            .pickup(clock: "21:30"),
            .zeno(line(.zeno, "en", "Hey {user}. What are you here for?")),
            .user(line(.user, "hi", "आज खाने के समय मैंने फ़ोन नहीं छुआ।")),
            .tool(name: "log_reflection", args: [
                "summary": "खाने के समय फ़ोन नहीं छुआ", "mood": "pleasant", "language": "hi",
                "earned_back": "A quiet dinner",
            ]),
            .zeno(line(.zeno, "hi", "बहुत बढ़िया! आपका Zen Card तैयार है।")),
            .user(line(.user, "ta", "சர்க்கிளுக்கு ஷேர் பண்ணு.")),
            // The prototype's include_score is ignored: a shared card never carries a score.
            .tool(name: "share_with_circle", args: ["note": "Dinner without the phone", "include_score": true]),
            .zeno(line(.zeno, "ta", "அனுப்பிட்டேன்!")),
            .user(line(.user, "ta", "Romba nandri Zeno.")),
            .zeno(line(.zeno, "ta-Latn", "Seri Priya, good night.")),
        ]
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        let cards = FakeZenCards(now: { clock.now })
        let server = ScriptedLiveTransport(script: script, user: "Priya", pace: 0, sleep: { _ in await Task.yield() },
                                           advanceClock: { clock.advance(by: $0) })
        let model = VoiceModel(tokens: FakeVoiceTokens(), scores: InstantScores(), cards: cards, ledger: ledger,
                               userName: "Priya", transport: { server })
        await model.start(pickup: true)
        await untilFinished(model)

        #expect(model.state == .ended && model.error == nil)
        #expect(model.lines.map(Shown.init) == [
            Shown(.zeno, "Hey Priya. What are you here for?"),
            Shown(.user, "आज खाने के समय मैंने फ़ोन नहीं छुआ।", "Hindi"),
            Shown(.zeno, "बहुत बढ़िया! आपका Zen Card तैयार है।"),
            Shown(.user, "சர்க்கிளுக்கு ஷேர் பண்ணு.", "Tamil"),
            Shown(.zeno, "அனுப்பிட்டேன்!"),
            Shown(.user, "Romba nandri Zeno.", "Tanglish"),
            Shown(.zeno, "Seri Priya, good night."),
        ])
        #expect(model.lines.filter { $0.speaker == .user }.map(\.language) == ["hi", "ta", "ta"])

        let card = try #require(try await cards.recent().first)
        #expect(card.summary == "खाने के समय फ़ोन नहीं छुआ" && card.language == "hi" && card.mood == .pleasant)
        #expect(card.isShared)
        #expect(cards.notes == [card.id: "Dinner without the phone"])
        try expectNoScore(card, note: cards.notes[card.id])
        #expect(await server.toolResults.last?.result["score_included"] == false)
        #expect(await ledger.intents.isEmpty) // a reflection touches no timers
        #expect(await ledger.today().total == 1)
    }
}
