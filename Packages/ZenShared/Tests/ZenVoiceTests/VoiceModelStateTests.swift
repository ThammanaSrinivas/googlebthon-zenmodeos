// VoiceModel, unit by unit, against a fake Live server: every state the notch shows, the token and
// transport failures, mic refusal, mute and stop, transcripts as they grow, barge-in, tool cards and
// the island's timers, a reconnect, and that the Live token never reaches anything the UI binds to.
// Time is a ManualVoiceClock on the ledger; the only waiting is for conditions, never for time.
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

/// Mints tokens valid against the real clock (the ZenoSession inside VoiceModel reads the system
/// clock). It can hold the first answer until released, fail a few times first, and counts asks.
actor TestTokens: VoiceTokenService {
    let value: String
    private var failures: [VoiceError]
    private var gated: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var asked = 0

    init(_ value: String = "auth_tokens/model-test", failures: [VoiceError] = [], gated: Bool = false) {
        self.value = value
        self.failures = failures
        self.gated = gated
    }

    func liveToken() async throws(VoiceError) -> LiveToken {
        asked += 1
        if gated { await withCheckedContinuation { waiter = $0 } }
        if !failures.isEmpty { throw failures.removeFirst() }
        return LiveToken(token: value, model: "gemini-3.8-live", voice: "Kore",
                         expiresAt: Date().addingTimeInterval(30 * 60), connectBy: Date().addingTimeInterval(60))
    }

    func release() {
        gated = false
        waiter?.resume()
        waiter = nil
    }

    var waiting: Bool { waiter != nil }
}

/// A WebSocket that can't be opened (no network).
private actor UnreachableTransport: LiveTransport {
    private(set) var attempts = 0
    func connect(to url: URL) async throws {
        attempts += 1
        throw URLError(.notConnectedToInternet)
    }
    func send(_ frame: String) async throws { throw URLError(.notConnectedToInternet) }
    func receive() async throws -> String? { nil }
    func close() async {}
}

/// The demo week's score, held until the test lets it through: shows the tool that is running.
private actor GatedScores: ScoreService {
    private var waiter: CheckedContinuation<Void, Never>?
    private var open = false

    func today() async throws -> ScoreSnapshot {
        if !open { await withCheckedContinuation { waiter = $0 } }
        return try await InstantScores().today()
    }

    nonisolated func updates() -> AsyncStream<ScoreSnapshot> { AsyncStream { $0.finish() } }

    func release() {
        open = true
        waiter?.resume()
        waiter = nil
    }

    var waiting: Bool { waiter != nil }
}

/// A mic the person refused.
private final class RefusedMic: VoiceAudioIO, @unchecked Sendable {
    struct Refused: Error {}
    func start(onChunk: @escaping @Sendable (MicChunk) -> Void) throws { throw Refused() }
    func play(_ pcm: Data, sampleRate: Int) {}
    func flush() {}
    func stop() {}
}

/// Waits (up to 5 s) for something the model shows.
@MainActor
func until(_ what: Comment, _ condition: () -> Bool) async {
    for _ in 0..<5_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for \(what)")
}

@MainActor
private struct ModelRig {
    let clock = ManualVoiceClock(T.now)
    let server = FakeLiveServer()
    let audio = RecordingAudio()
    let ledger: OnDeviceLedger
    let model: VoiceModel

    init(tokens: any VoiceTokenService = TestTokens(), scores: any ScoreService = InstantScores(),
         mic: (any VoiceAudioIO)? = nil, transport: (any LiveTransport)? = nil) {
        ledger = T.ledger(clock)
        let clock = self.clock
        let live: any LiveTransport = transport ?? server
        model = VoiceModel(tokens: tokens, scores: scores, cards: FakeZenCards(now: { clock.now }), ledger: ledger,
                           userName: "Kamal", audio: mic ?? audio, transport: { live })
    }

    /// Starts without the pickup cue and waits until Zeno is listening.
    func listening() async {
        await model.start(pickup: false)
        await until("listening") { model.state == .listening }
    }

    func push(_ content: LiveServerContent) async { await server.push(LiveServerMessage(serverContent: content)) }

    func heard(_ text: String, _ language: String? = nil) async {
        await push(LiveServerContent(inputTranscription: LiveTranscription(text: text, languageCode: language)))
    }

    func said(_ text: String) async { await push(LiveServerContent(outputTranscription: LiveTranscription(text: text))) }

    func tool(_ id: String, _ name: String, _ args: JSONValue = [:]) async {
        await server.push(LiveServerMessage(toolCall: LiveToolCall(functionCalls: [LiveFunctionCall(id: id, name: name, args: args)])))
    }
}

@Suite("VoiceModel: states, failures and controls")
@MainActor
struct VoiceModelStateTests {
    @Test("Before start: idle, nothing shown, and every control is a no-op")
    func idle() async {
        let rig = ModelRig()
        #expect(rig.model.state == .idle)
        #expect(!rig.model.isActive && !rig.model.isDemo)
        #expect(rig.model.lines.isEmpty && rig.model.userLine == nil && rig.model.zenoLine == nil)
        #expect(rig.model.card == nil && rig.model.error == nil && rig.model.runningTool == nil)

        await rig.model.sendText("hello")
        await rig.model.setMuted(true)
        await rig.model.stop()
        #expect(rig.model.state == .idle)
        #expect(rig.model.lines.isEmpty)
        #expect(await rig.server.urls.isEmpty)
    }

    @Test("idle → connecting → listening → thinking → speaking → listening → ended")
    func everyState() async {
        let tokens = TestTokens(gated: true)
        let rig = ModelRig(tokens: tokens)
        let starting = Task { await rig.model.start(pickup: false) }

        await until("connecting") { rig.model.state == .connecting }
        #expect(rig.model.isActive)
        await eventually("the token asked for") { await tokens.waiting }
        #expect(await rig.server.urls.isEmpty) // nothing opens before there is a token

        await tokens.release()
        await starting.value
        await until("listening") { rig.model.state == .listening }
        #expect(rig.audio.started)

        await rig.model.sendText("I want to check one message")
        await until("thinking") { rig.model.state == .thinking }

        await rig.said("Sure.")
        await until("speaking") { rig.model.state == .speaking }

        await rig.push(LiveServerContent(turnComplete: true))
        await until("listening again") { rig.model.state == .listening && rig.model.zenoLine?.isFinal == true }

        await rig.model.stop()
        #expect(rig.model.state == .ended)
        #expect(!rig.model.isActive)
        #expect(rig.audio.stopped)
        #expect(rig.model.error == nil)
    }

    @Test("A token the backend refuses: error state, its reason, and nothing opened", arguments: [
        VoiceError.signedOut, .offline, .disabled, .rateLimited, .unavailable,
    ])
    func tokenRefused(reason: VoiceError) async {
        let rig = ModelRig(tokens: TestTokens(failures: [reason]))
        await rig.model.start(pickup: true)
        #expect(rig.model.state == .error)
        #expect(rig.model.error == reason)
        #expect(!rig.model.isActive)
        #expect(await rig.server.urls.isEmpty)
        #expect(await rig.server.sent.isEmpty)
        #expect(!rig.audio.started)
    }

    @Test("After an error, the next start connects and clears it")
    func recoversAfterError() async {
        let rig = ModelRig(tokens: TestTokens(failures: [.rateLimited]))
        await rig.model.start(pickup: false)
        #expect(rig.model.error == .rateLimited)

        await rig.listening()
        #expect(rig.model.error == nil)
        #expect(rig.model.isActive)
        #expect(await rig.server.urls.count == 1)
    }

    @Test("A WebSocket that can't open is offline; the mic never starts")
    func transportUnreachable() async {
        let transport = UnreachableTransport()
        let rig = ModelRig(transport: transport)
        await rig.model.start(pickup: true)
        #expect(rig.model.state == .error)
        #expect(rig.model.error == .offline)
        #expect(!rig.model.isActive)
        #expect(!rig.audio.started)
        #expect(await transport.attempts == 1)
        #expect(await rig.ledger.today().total == 1) // the pickup happened; it is counted before connecting
    }

    @Test("A dropped connection with nothing to resume is offline; the transcript stays on screen")
    func droppedMidSession() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.heard("Insta-la rendu nimisham", "ta-Latn")
        await until("the user line") { rig.model.userLine != nil }

        await rig.server.hangUp(failing: true)
        await until("the session over") { rig.model.state == .error && !rig.model.isActive }
        #expect(rig.model.error == .offline)
        #expect(!rig.model.isActive)
        #expect(rig.audio.stopped)
        #expect(rig.model.lines.map(\.text) == ["Insta-la rendu nimisham"])
    }

    @Test("A clean hang-up ends the session without an error")
    func cleanHangUp() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.server.hangUp()
        await until("the session over") { rig.model.state == .ended && !rig.model.isActive }
        #expect(rig.model.error == nil)
        #expect(!rig.model.isActive)
        #expect(rig.audio.stopped)
    }

    @Test("A refused mic shows .disabled but the session stays up for typed turns")
    func micRefused() async {
        let rig = ModelRig(mic: RefusedMic())
        await rig.listening()
        #expect(rig.model.error == .disabled)
        #expect(rig.model.isActive)
        #expect(rig.model.state == .listening)

        await rig.model.sendText("45 minutes of focus")
        #expect(await rig.server.texts == ["45 minutes of focus"])
    }

    @Test("Mute tells the server the stream ended; unmuted chunks flow again")
    func mute() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.model.setMuted(true)
        #expect(await rig.server.streamEnds == 1)
        await rig.model.setMuted(false)
        #expect(await rig.server.streamEnds == 1)

        rig.audio.speak(MicChunk(samples: [7, -7]))
        await eventually("the chunk") { await rig.server.audioChunks.count == 1 }
        #expect(await rig.server.audioChunks.first?.bytes == PCM.int16LE([Int16(7), -7]))
    }

    @Test("Stop ends once: a second stop and later typing do nothing")
    func stopIsFinal() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.model.stop()
        await rig.model.stop()
        #expect(rig.model.state == .ended)

        await rig.model.sendText("still there?")
        #expect(rig.model.lines.isEmpty)
        #expect(await rig.server.texts.isEmpty)
    }

    @Test("Stopping while the token is still coming ends quietly and never connects")
    func stopWhileConnecting() async {
        let tokens = TestTokens(gated: true)
        let rig = ModelRig(tokens: tokens)
        let starting = Task { await rig.model.start(pickup: true) }
        await until("connecting") { rig.model.state == .connecting }
        await eventually("the token asked for") { await tokens.waiting }

        await rig.model.stop()
        #expect(rig.model.state == .ended)
        await tokens.release()
        await starting.value

        #expect(rig.model.state == .ended)
        #expect(rig.model.error == nil)
        #expect(!rig.model.isActive)
        #expect(await rig.server.urls.isEmpty)
        #expect(!rig.audio.started) // the mic never opens after a stop
        #expect(await rig.ledger.today().total == 0)
    }

    @Test("Stopping while the server hasn't accepted the setup ends quietly too")
    func stopDuringSetup() async {
        let rig = ModelRig()
        await rig.server.setAnswersSetup(false)
        let starting = Task { await rig.model.start(pickup: true) }
        await eventually("the setup sent") { await !rig.server.setups.isEmpty }

        await rig.model.stop()
        await starting.value
        #expect(rig.model.state == .ended)
        #expect(rig.model.error == nil)
        #expect(!rig.model.isActive)
        #expect(!rig.audio.started)
        #expect(await rig.server.texts.isEmpty)
    }

    @Test("A second start while active is ignored")
    func startTwice() async {
        let rig = ModelRig()
        await rig.model.start(pickup: true)
        await rig.model.start(pickup: true)
        #expect(await rig.server.urls.count == 1)
        #expect(await rig.ledger.today().total == 1)
        #expect(await rig.server.texts == [ZenoAgent.pickupCue])
    }

    @Test("A new session after stop starts clean: no old lines, no old card")
    func restart() async {
        let rig = ModelRig()
        await rig.model.start(pickup: true)
        await rig.tool("fc-1", "pause_app", ["app": "WhatsApp"])
        await rig.said("Paused.")
        await until("the card") { rig.model.card != nil && !rig.model.lines.isEmpty }
        await rig.model.stop()

        await rig.model.start(pickup: true)
        #expect(rig.model.lines.isEmpty)
        #expect(rig.model.card == nil)
        #expect(rig.model.error == nil)
        await until("thinking") { rig.model.state == .thinking }
        #expect(await rig.server.urls.count == 2)
        #expect(await rig.ledger.today().total == 2)
    }

    @Test("goAway: the session moves to a fresh token and the transcript survives")
    func reconnect() async {
        let tokens = TestTokens()
        let rig = ModelRig(tokens: tokens)
        await rig.listening()
        await rig.heard("Kal subah client demo hai", "hi-Latn")
        await rig.server.push(LiveServerMessage(sessionResumptionUpdate: LiveSessionResumptionUpdate(newHandle: "h-1", resumable: true)))
        await rig.server.push(LiveServerMessage(goAway: LiveGoAway(timeLeft: "2s")))
        await eventually("the second connection's setup") { await rig.server.setups.count == 2 }
        await until("listening again") { rig.model.state == .listening }

        #expect(rig.model.isActive)
        #expect(rig.model.error == nil)
        #expect(await tokens.asked == 2)
        #expect(await rig.server.setups.last?.sessionResumption?.handle == "h-1")
        #expect(rig.model.lines.map(\.text) == ["Kal subah client demo hai"])
    }
}

@Suite("VoiceModel: transcripts, barge-in and tool cards")
@MainActor
struct VoiceModelTranscriptTests {
    @Test("A user line grows in place, takes its language label, and is final once Zeno answers")
    func accumulation() async {
        let rig = ModelRig()
        await rig.listening()

        await rig.heard("Zeno,", "ta-Latn")
        await rig.heard(" Insta-la")
        await rig.heard(" rendu nimisham")
        await until("the whole user line") { rig.model.userLine?.text == "Zeno, Insta-la rendu nimisham" }
        #expect(rig.model.lines.count == 1)
        #expect(rig.model.userLine?.isFinal == false)
        #expect(rig.model.userLine?.language == "ta-Latn")
        #expect(rig.model.userLine?.languageLabel == "Tanglish")

        await rig.said("Seri,")
        await rig.said(" rendu nimisham.")
        await until("Zeno's line") { rig.model.zenoLine?.text == "Seri, rendu nimisham." }
        #expect(rig.model.userLine?.isFinal == true)
        #expect(rig.model.zenoLine?.isFinal == false)

        await rig.push(LiveServerContent(turnComplete: true))
        await until("Zeno's line final") { rig.model.zenoLine?.isFinal == true }

        // The next turn starts new lines rather than growing the old ones.
        await rig.heard("How's my day looking?", "en")
        await until("the second user line") { rig.model.lines.count == 3 }
        let lines = rig.model.lines
        #expect(lines.map(\.speaker) == [.user, .zeno, .user])
        #expect(lines.map(\.text) == ["Zeno, Insta-la rendu nimisham", "Seri, rendu nimisham.", "How's my day looking?"])
        #expect(lines[2].languageLabel == "English")
        #expect(Set(lines.map(\.id)).count == 3)
        #expect(lines.map(\.id) == lines.map(\.id).sorted())
        #expect(lines.allSatisfy { !$0.wasCut })
    }

    @Test("Typed text is a final user line, trimmed; blank text is ignored")
    func typed() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.model.sendText("   \n ")
        #expect(rig.model.lines.isEmpty)

        await rig.model.sendText("  pause WhatsApp \n")
        #expect(rig.model.lines.count == 1)
        #expect(rig.model.userLine?.text == "pause WhatsApp")
        #expect(rig.model.userLine?.isFinal == true)
        #expect(rig.model.userLine?.languageLabel == nil)
        #expect(await rig.server.texts == ["pause WhatsApp"])
    }

    @Test("Barge-in: playback flushes, Zeno's line is cut, and the next reply is a new line")
    func bargeIn() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.heard("Mujhe ek ghante ka focus chahiye", "hi-Latn")
        await rig.said("Theek hai,")
        await rig.said(" ek ghante ka focus shu")
        await rig.push(LiveServerContent(modelTurn: LiveContent(parts: [
            LivePart(inlineData: LiveBlob(mimeType: "audio/pcm;rate=24000", bytes: Data([1, 2, 3, 4]))),
        ])))
        await until("speaking with audio") { rig.model.state == .speaking && rig.audio.played.count == 1 }

        await rig.push(LiveServerContent(interrupted: true))
        await until("the flush") { rig.audio.flushes == 1 }
        await until("listening") { rig.model.state == .listening }
        let cut = rig.model.zenoLine
        #expect(cut?.text == "Theek hai, ek ghante ka focus shu")
        #expect(cut?.wasCut == true && cut?.isFinal == true)

        await rig.heard("Nahi nahi, 45 minute", "hi-Latn")
        await rig.said("Ho gaya.")
        await rig.push(LiveServerContent(turnComplete: true))
        await until("the new reply") { rig.model.lines.count == 4 && rig.model.zenoLine?.isFinal == true }

        let lines = rig.model.lines
        #expect(lines.map(\.speaker) == [.user, .zeno, .user, .zeno])
        #expect(lines[3].text == "Ho gaya.") // not glued to the cut line
        #expect(!lines[3].wasCut)
        #expect(lines.filter(\.wasCut).count == 1)
        #expect(lines[2].languageLabel == "Hinglish" && lines[2].isFinal)
        #expect(rig.audio.flushes == 1)
    }

    @Test("Tool cards and the island: running tool, intent, time's up, end, focus, pause")
    func toolCards() async {
        let scores = GatedScores()
        let rig = ModelRig(scores: scores)
        await rig.listening()

        // A slow tool shows by name while it runs.
        await rig.tool("fc-1", "get_zen_status")
        await until("the running tool") { rig.model.runningTool == "get_zen_status" }
        #expect(rig.model.state == .thinking)
        await eventually("the score read") { await scores.waiting }
        await scores.release()
        await until("the status card") { rig.model.runningTool == nil && rig.model.card != nil }
        guard case .status(let status) = rig.model.card else { Issue.record("expected the status card"); return }
        #expect(status.score == ZenScore(tenths: 81))

        // set_intent puts a timer on the island.
        await rig.tool("fc-2", "set_intent", ["app": "Instagram", "purpose": "Arun's reel", "minutes": 2])
        // The island hears of it twice (the ledger's event and the tool result), in either order.
        await until("the intent and its card") {
            if case .intent = rig.model.card { rig.model.activeIntent != nil } else { false }
        }
        let intent = rig.model.activeIntent
        #expect(intent?.app == "Instagram")
        #expect(intent.map { rig.model.card == .intent($0) } == true)

        // The minutes run out (the app's timer loop calls checkTimers).
        rig.clock.advance(by: 121)
        await rig.ledger.checkTimers()
        await until("time's up") { rig.model.timeUp != nil }
        #expect(rig.model.timeUp?.id == intent?.id)

        await rig.tool("fc-3", "end_session")
        await until("the intent ended") {
            if case .intentEnded = rig.model.card { rig.model.activeIntent == nil && rig.model.timeUp == nil } else { false }
        }
        guard case .intentEnded(let ended) = rig.model.card else { Issue.record("expected the ended card"); return }
        #expect(ended.onTime == true)

        // Focus from Zeno, then ended from the island (outside the session).
        await rig.tool("fc-4", "start_focus", ["minutes": 45, "label": "Client demo prep"])
        await until("focus and its card") {
            if case .focus = rig.model.card { rig.model.activeFocus != nil } else { false }
        }
        #expect(rig.model.activeFocus?.minutes == 45)
        await rig.ledger.endFocus()
        await until("focus ended") { rig.model.activeFocus == nil }

        await rig.tool("fc-5", "pause_app", ["app": "WhatsApp", "seconds": 7])
        await until("the pause card") { if case .pause = rig.model.card { true } else { false } }
        #expect(rig.model.card == .pause(AppPause(app: "WhatsApp", seconds: 7, since: rig.clock.now)))
        await eventually("five tool responses") { await rig.server.toolResponses.count == 5 }
        #expect(rig.model.runningTool == nil)
    }

    @Test("A failed tool leaves the last card and shows no new one")
    func failedTool() async {
        let rig = ModelRig()
        await rig.listening()
        await rig.tool("fc-1", "pause_app", ["app": "WhatsApp"])
        await until("the pause card") { rig.model.card != nil }
        let before = rig.model.card

        await rig.tool("fc-2", "share_with_circle", ["note": "hi"]) // no card saved yet
        await eventually("the response") { await rig.server.toolResponses.count == 2 }
        // Zeno's next words come after the tool's result on the same stream: once they show, the
        // failed result has been applied too.
        await rig.said("There's no card to share yet.")
        await until("Zeno's reply") { rig.model.zenoLine?.text == "There's no card to share yet." }
        #expect(rig.model.runningTool == nil)
        #expect(rig.model.card == before)
        #expect(await rig.server.toolResponses.last?.functionResponses.first?.response["result"]?["ok"] == false)
    }

    @Test("The Live token never reaches anything the UI binds to")
    func tokenNeverShown() async {
        // A fake token with a marker the test can search for everywhere.
        let rig = ModelRig(tokens: TestTokens("fake-live-token-never-shown"))
        let marker = "never-shown"
        await rig.model.start(pickup: true)
        await rig.heard("How's my day looking?", "en")
        await rig.tool("fc-1", "get_zen_status")
        await rig.said("Zen Score 8.1.")
        await rig.push(LiveServerContent(turnComplete: true))
        await until("the reply") { rig.model.zenoLine?.isFinal == true && rig.model.card != nil }

        // The token was used, only to open the connection …
        let url = await rig.server.urls.first?.absoluteString ?? ""
        #expect(url.hasSuffix("access_token=fake-live-token-never-shown"))
        // … appears in no frame sent over it …
        for message in await rig.server.sent {
            #expect(!((try? message.jsonString()) ?? "").contains(marker))
        }
        // … and in nothing the model shows or stores.
        let shown = String(describing: (rig.model.state, rig.model.lines, rig.model.card, rig.model.runningTool,
                                        rig.model.latencyMs, rig.model.error, rig.model.activeIntent,
                                        rig.model.activeFocus, rig.model.timeUp, rig.model.caption,
                                        rig.model.demoMoment, rig.model.demoClock))
        #expect(!shown.contains(marker))
        for child in Mirror(reflecting: rig.model).children {
            #expect(!(child.value is LiveToken), "VoiceModel stores a LiveToken in \(child.label ?? "?")")
            if let text = child.value as? String { #expect(!text.contains(marker)) }
        }

        await rig.model.stop()
    }
}
