// The offline demo: all five moments play through a real ZenoSession, every tool call runs on the
// ledger and the toolbox, and VoiceModel shows it the way the notch will.
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

@Suite("The scripted replay")
struct ScriptedReplayTests {
    @Test("All five moments play, with every tool call executed for real")
    func fiveMoments() async throws {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        let cards = FakeZenCards(now: { clock.now })
        let toolbox = ZenoToolbox(ledger: ledger, scores: InstantScores(), cards: cards)
        let transport = ScriptedLiveTransport(user: "Kamal", pace: 0, sleep: { _ in await Task.yield() },
                                              advanceClock: { clock.advance(by: $0) })
        let session = ZenoSession(transport: transport, tools: toolbox, user: "Kamal", clock: clock)
        let events = EventRecorder(session.events)
        let cueTask = Task { () -> [DemoCue] in
            var cues: [DemoCue] = []
            for await cue in transport.cues { cues.append(cue) }
            return cues
        }

        await ledger.recordPickup()
        try await session.connect(token: T.token(clock: clock))
        await session.sendText(ZenoAgent.pickupCue)
        await events.waitForFinish()
        let cues = await cueTask.value

        // The session ran the script to its end and closed cleanly.
        #expect(events.states.last == .ended)
        #expect(cues.last == .finished)
        #expect(cues.compactMap { if case .caption(let n, _) = $0 { n } else { nil } } == [1, 2, 3, 4, 5, 0])

        // Every tool ran, in order, and succeeded.
        let results = await transport.toolResults
        #expect(results.map(\.name) == ["set_intent", "end_session", "start_focus", "pause_app", "get_zen_status",
                                        "log_reflection", "share_with_circle"])
        #expect(results.allSatisfy { $0.result["ok"] == true })
        #expect(results[1].result["on_time"] == true) // two minutes later, exactly on time

        // Moment 2: the Instagram intent ended on time. Moment 3: 45 min focus, WhatsApp paused.
        let intents = await ledger.intents
        #expect(intents.map(\.app) == ["Instagram"])
        #expect(intents[0].minutes == 2 && intents[0].onTime == true)
        let focus = try #require(await ledger.status().focus)
        #expect(focus.minutes == 45 && focus.label == "Client demo prep")
        #expect(await ledger.pauseSeconds(for: "WhatsApp") == 7)
        #expect(await ledger.today().withIntent == 1)

        // Moment 4: Zeno's line uses what get_zen_status returned.
        let zenoLines = events.events.compactMap { if case .zenoTranscript(let text, true) = $0 { text } else { nil } }
        #expect(zenoLines.contains("Zen Score 8.1. 3 of 4 good days, one more wins the week."))
        #expect(zenoLines.first == "Hey Kamal. What are you here for?")

        // Moment 3's interruption, once, and the cut line never finishes.
        #expect(events.events.filter { $0 == .interrupted }.count == 1)
        #expect(!zenoLines.contains("Theek hai, ek ghante ka focus shu—"))

        // Every user line is transcribed with its language.
        let heard = events.events.compactMap { if case .userTranscript(let text, let language, true) = $0 { (text, language) } else { nil } }
        #expect(heard.map(\.1) == ["ta-Latn", "hi-Latn", "hi-Latn", "en", "ta"])
        #expect(heard[3].0 == "How's my day looking?")

        // Moment 5: the Tamil note became a Zen Card and was shared, with no score.
        let saved = try await cards.recent()
        #expect(saved.count == 1)
        #expect(saved[0].language == "ta" && saved[0].mood == .happy && saved[0].isShared)
        #expect(saved[0].earnedBack == "A phone-free dinner")
        #expect(cards.notes == ["card-1": "Phone-free dinner tonight"])

        // The client spoke the real protocol: setup, the pickup cue, seven tool responses.
        let received = await transport.received
        guard case .setup(let setup) = received.first else { Issue.record("setup first"); return }
        #expect(setup.model == "models/gemini-3.8-live")
        #expect(received.filter { if case .toolResponse = $0 { true } else { false } }.count == 7)
    }

    @Test("Time skips move the ledger's clock: 2 minutes, then later that night")
    func skips() {
        let skips = ZenoDemo.script().compactMap { if case .skip(_, let seconds, _) = $0 { seconds } else { nil } }
        #expect(skips == [120, 37 * 60])
    }

    @Test("Templates fall back gracefully when the status had no score")
    func templateFallback() {
        #expect(ZenoDemo.fill("Zen Score {score}. {week_line}.", user: "Asha", status: ["ok": true])
            == "Zen Score not in yet. the week is still open.")
        #expect(ZenoDemo.fill("Hey {user}.", user: "Asha", status: nil) == "Hey Asha.")
    }
}

@Suite("VoiceModel")
@MainActor
struct VoiceModelTests {
    @Test("The demo plays to the end: transcripts with language labels, the shared Zen Card, captions")
    func demo() async throws {
        let cards = FakeZenCards()
        let model = VoiceModel.demo(scores: InstantScores(), cards: cards, userName: "Kamal", pace: 0,
                                    sleep: { _ in await Task.yield() })
        var spoken: [DemoLine] = []
        model.onDemoLine = { spoken.append($0) }
        #expect(model.isDemo)
        await model.start(pickup: true)
        for _ in 0..<3_000 where model.isActive { try await Task.sleep(for: .milliseconds(1)) }

        #expect(!model.isActive)
        #expect(model.state == .ended)
        #expect(model.error == nil)
        #expect(model.latencyMs == nil) // a replay has no real latency to show
        #expect(model.caption == nil && model.demoMoment == nil)
        #expect(model.demoClock == "22:41")
        guard case .zenCard(let card) = model.card else { Issue.record("expected the Zen Card last"); return }
        #expect(card.isShared)

        let users = model.lines.filter { $0.speaker == .user }
        #expect(users.map(\.languageLabel) == ["Tanglish", "Hinglish", "Hinglish", "English", "Tamil"])
        #expect(model.lines.allSatisfy { $0.isFinal })
        #expect(model.lines.filter(\.wasCut).map(\.text) == ["Theek hai, ek ghante ka focus shu—"])
        #expect(model.zenoLine?.text == "சூப்பர்! உங்க Zen Card ரெடி. சர்க்கிளுக்கும் அனுப்பிட்டேன்.")
        #expect(spoken.count == 12)
        #expect(spoken.first?.clip == "z_hey")
        #expect(model.activeFocus?.minutes == 45)
        #expect(model.activeIntent == nil)
    }

    @Test("A live model with no transport (Linux) fails cleanly")
    func noTransport() async {
        let model = VoiceModel(tokens: FakeVoiceTokens(), scores: InstantScores(), cards: FakeZenCards(),
                               ledger: OnDeviceLedger(), userName: "Kamal", transport: { nil })
        await model.start()
        #expect(model.state == .error)
        #expect(model.error == .unavailable)
        #expect(!model.isActive)
    }

    @Test("A token the backend refuses shows its reason")
    func tokenRefused() async {
        let model = VoiceModel(tokens: FakeVoiceTokens(failure: .signedOut), scores: InstantScores(),
                               cards: FakeZenCards(), ledger: OnDeviceLedger(), userName: "Kamal",
                               transport: { FakeLiveServer() })
        await model.start()
        #expect(model.state == .error)
        #expect(model.error == .signedOut)
    }

    @Test("A live session: pickup counted, cue sent, events shown, typed text, stop")
    func live() async throws {
        let server = FakeLiveServer()
        let ledger = OnDeviceLedger(clock: ManualVoiceClock(T.now), timeZone: T.india)
        let audio = RecordingAudio()
        let model = VoiceModel(tokens: FakeVoiceTokens(), scores: InstantScores(), cards: FakeZenCards(),
                               ledger: ledger, userName: "Kamal", audio: audio, transport: { server })
        await model.start(pickup: true)
        for _ in 0..<3_000 where model.state != .thinking { try await Task.sleep(for: .milliseconds(1)) }
        #expect(model.state == .thinking)
        #expect(await ledger.today().total == 1)
        #expect(await server.texts == [ZenoAgent.pickupCue])
        #expect(audio.started)

        audio.speak(MicChunk(samples: [9, 9]))
        await eventually("the mic chunk") { await server.audioChunks.count == 1 }

        await server.push(LiveServerMessage(serverContent: LiveServerContent(
            inputTranscription: LiveTranscription(text: "Mujhe focus chahiye", languageCode: "hi"))))
        await server.push(LiveServerMessage(serverContent: LiveServerContent(modelTurn: LiveContent(parts: [
            LivePart(inlineData: LiveBlob(mimeType: "audio/pcm;rate=24000", bytes: Data([1, 0]))),
        ]))))
        await server.push(LiveServerMessage(serverContent: LiveServerContent(interrupted: true)))
        for _ in 0..<3_000 where audio.flushes == 0 { try await Task.sleep(for: .milliseconds(1)) }
        #expect(audio.played == [Data([1, 0])])
        #expect(audio.flushes == 1)
        #expect(model.userLine?.languageLabel == "Hinglish")
        #expect(model.latencyMs != nil)

        await model.sendText("45 minutes please")
        #expect(model.lines.last?.text == "45 minutes please")
        #expect(await server.texts.last == "45 minutes please")

        await model.stop()
        #expect(model.state == .ended)
        #expect(audio.stopped)
        #expect(!model.isActive)
    }
}

/// Stands in for AVAudioVoiceIO.
final class RecordingAudio: VoiceAudioIO, @unchecked Sendable {
    private let lock = NSLock()
    private var onChunk: (@Sendable (MicChunk) -> Void)?
    private var _played: [Data] = []
    private var _flushes = 0
    private var _started = false
    private var _stopped = false

    var played: [Data] { lock.withLock { _played } }
    var flushes: Int { lock.withLock { _flushes } }
    var started: Bool { lock.withLock { _started } }
    var stopped: Bool { lock.withLock { _stopped } }

    func start(onChunk: @escaping @Sendable (MicChunk) -> Void) throws {
        lock.withLock {
            self.onChunk = onChunk
            _started = true
        }
    }

    func speak(_ chunk: MicChunk) { lock.withLock { onChunk }?(chunk) }
    func play(_ pcm: Data, sampleRate: Int) { lock.withLock { _played.append(pcm) } }
    func flush() { lock.withLock { _flushes += 1 } }
    func stop() { lock.withLock { _stopped = true } }
}
