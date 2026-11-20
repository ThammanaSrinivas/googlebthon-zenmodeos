// The session's state machine against a fake Live server: setup → listening → a tool call round
// trip → barge-in flush → turn complete → goAway and resumption, plus the failure paths.
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

private struct Rig {
    let clock = ManualVoiceClock(T.now)
    let server = FakeLiveServer()
    let ledger: OnDeviceLedger
    let session: ZenoSession
    let events: EventRecorder

    init(tools: (any ZenoToolExecutor)? = nil, tokens: (any VoiceTokenService)? = nil,
         options: ZenoSession.Options = ZenoSession.Options()) {
        ledger = T.ledger(clock)
        let toolbox = tools ?? ZenoToolbox(ledger: ledger, scores: InstantScores(), cards: FakeZenCards())
        let clock = self.clock
        session = ZenoSession(transport: server, tools: toolbox,
                              tokens: tokens ?? FakeVoiceTokens(now: { clock.now }), user: "Kamal",
                              clock: clock, options: options)
        events = EventRecorder(session.events)
    }

    func connect() async throws {
        try await session.connect(token: T.token(clock: clock))
    }
}

private func audioFrame(_ samples: [Int16]) -> LiveServerMessage {
    LiveServerMessage(serverContent: LiveServerContent(modelTurn: LiveContent(role: "model", parts: [
        LivePart(inlineData: LiveBlob(mimeType: "audio/pcm;rate=24000", bytes: PCM.int16LE(samples))),
    ])))
}

@Suite("Zeno session")
struct ZenoSessionTests {
    @Test("Connecting opens the constrained endpoint, sends the setup first and waits for setupComplete")
    func connects() async throws {
        let rig = Rig()
        try await rig.connect()
        #expect(await rig.session.state == .listening)
        await rig.events.wait("listening") { $0.contains(.state(.listening)) }
        #expect(rig.events.states == [.connecting, .listening])
        let urls = await rig.server.urls
        #expect(urls.map(\.absoluteString) == [
            "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained?access_token=auth_tokens%2Fabc",
        ])
        let setups = await rig.server.setups
        #expect(setups == [ZenoAgent.setup(model: "gemini-3.8-live", voice: "Kore", user: "Kamal")])
        #expect(await rig.server.sent.count == 1)
    }

    @Test("No setupComplete in time is an error")
    func setupTimesOut() async {
        let rig = Rig(options: .init(setupTimeout: .milliseconds(30)))
        await rig.server.setAnswersSetup(false)
        await #expect(throws: VoiceError.unavailable) { try await rig.connect() }
        #expect(await rig.session.state == .error)
        await rig.events.waitForFinish()
        #expect(rig.events.events.contains(.error(.unavailable)))
    }

    @Test("A token past its connect-by is swapped for a fresh one before connecting")
    func staleTokenIsReplaced() async throws {
        let rig = Rig()
        let stale = T.token("auth_tokens/stale", clock: rig.clock)
        rig.clock.advance(by: 61)
        try await rig.session.connect(token: stale)
        let urls = await rig.server.urls
        #expect(urls.count == 1)
        #expect(urls[0].absoluteString.hasSuffix("access_token=\(FakeVoiceTokens.demoToken)"))
    }

    @Test("Without a token service, a stale token never connects")
    func staleTokenWithoutService() async {
        let clock = ManualVoiceClock(T.now)
        let server = FakeLiveServer()
        let session = ZenoSession(transport: server, tools: GatedTools(), user: "Kamal", clock: clock)
        let token = T.token(clock: clock)
        clock.advance(by: 60)
        await #expect(throws: VoiceError.unavailable) { try await session.connect(token: token) }
        #expect(await server.urls.isEmpty)
    }

    @Test("A whole turn: pickup cue, Tanglish transcript, set_intent round trip, audio with latency, turn complete")
    func toolRoundTrip() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.session.sendText(ZenoAgent.pickupCue)
        #expect(await rig.server.texts == [ZenoAgent.pickupCue])
        #expect(await rig.session.state == .thinking)

        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(
            inputTranscription: LiveTranscription(text: "Insta-la", languageCode: "ta-Latn"))))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(
            inputTranscription: LiveTranscription(text: " rendu nimisham"))))
        await rig.server.push(LiveServerMessage(toolCall: LiveToolCall(functionCalls: [
            LiveFunctionCall(id: "fc-1", name: "set_intent", args: ["app": "Instagram", "minutes": 2]),
        ])))
        await eventually("the tool response") { await !rig.server.toolResponses.isEmpty }
        let response = try #require(await rig.server.toolResponses.first?.functionResponses.first)
        #expect(response.id == "fc-1")
        #expect(response.name == "set_intent")
        #expect(response.response["result"]?["minutes"] == 2)
        #expect(response.response["result"]?["ok"] == true)
        #expect(await rig.ledger.activeIntent?.app == "Instagram")

        rig.clock.advance(by: 0.42)
        await rig.server.push(audioFrame([100, -100]))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(outputTranscription: LiveTranscription(text: "Seri, rendu nimisham."))))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(turnComplete: true)))
        await rig.events.wait("turn complete") { $0.contains(.turnComplete) }

        let events = rig.events.events
        #expect(events.contains(.userTranscript(text: "Insta-la", language: "ta-Latn", isFinal: false)))
        #expect(events.contains(.userTranscript(text: "Insta-la rendu nimisham", language: "ta-Latn", isFinal: true)))
        #expect(events.contains(.toolCall(ToolCallInfo(id: "fc-1", name: "set_intent", args: ["app": "Instagram", "minutes": 2]))))
        #expect(events.contains { if case .toolResult(let r) = $0 { r.name == "set_intent" && r.outcome.ok } else { false } })
        #expect(events.contains(.latency(milliseconds: 420)))
        #expect(events.contains(.audio(PCM.int16LE([Int16(100), -100]), sampleRate: 24_000)))
        #expect(events.contains(.zenoTranscript(text: "Seri, rendu nimisham.", isFinal: true)))
        #expect(rig.events.states == [.connecting, .listening, .thinking, .speaking, .listening])
    }

    @Test("Barge-in: interrupted flushes Zeno's line and goes back to listening")
    func bargeIn() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(outputTranscription: LiveTranscription(text: "Theek hai, ek ghante ka"))))
        await rig.server.push(audioFrame([1, 2, 3]))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(interrupted: true)))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(
            inputTranscription: LiveTranscription(text: "Nahi nahi, 45 minute", languageCode: "hi-Latn"))))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(outputTranscription: LiveTranscription(text: "Ho gaya."))))
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(turnComplete: true)))
        await rig.events.wait("turn complete") { $0.contains(.turnComplete) }
        let events = rig.events.events
        #expect(events.filter { $0 == .interrupted }.count == 1)
        let interruptedAt = events.firstIndex(of: .interrupted)!
        #expect(events[interruptedAt + 1] == .state(.listening))
        // The cut line never comes back as final; the next line starts fresh.
        #expect(!events.contains(.zenoTranscript(text: "Theek hai, ek ghante ka", isFinal: true)))
        #expect(events.contains(.zenoTranscript(text: "Ho gaya.", isFinal: true)))
        #expect(events.contains(.userTranscript(text: "Nahi nahi, 45 minute", language: "hi-Latn", isFinal: true)))
    }

    @Test("The mic streams 16 kHz chunks; local end of speech starts the latency clock")
    func micAndLatency() async throws {
        let rig = Rig()
        try await rig.connect()
        let voiced = MicChunk(samples: Array(repeating: 8_000, count: 640))
        let quiet = MicChunk(samples: Array(repeating: 0, count: 640))
        await rig.session.sendAudio(voiced)
        rig.clock.advance(by: 0.04)
        await rig.session.sendAudio(voiced) // speech ends here
        for _ in 0..<7 {
            rig.clock.advance(by: 0.04)
            await rig.session.sendAudio(quiet)
        }
        #expect(await rig.session.state == .thinking)
        #expect(await rig.server.audioChunks.count == 9)
        #expect(await rig.server.audioChunks.first == LiveBlob(mimeType: "audio/pcm;rate=16000", bytes: voiced.pcm))
        rig.clock.advance(by: 0.5)
        await rig.server.push(audioFrame([5]))
        await rig.events.wait("latency") { $0.contains { if case .latency = $0 { true } else { false } } }
        #expect(rig.events.events.contains(.latency(milliseconds: 780))) // 7 × 40 ms of quiet + 500 ms
    }

    @Test("Muting stops the mic and tells the server the stream ended")
    func mute() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.session.setMuted(true)
        await rig.session.sendAudio(MicChunk(samples: [1, 2, 3]))
        #expect(await rig.server.audioChunks.isEmpty)
        #expect(await rig.server.streamEnds == 1)
        await rig.session.setMuted(false)
        await rig.session.sendAudio(MicChunk(samples: [1, 2, 3]))
        #expect(await rig.server.audioChunks.count == 1)
    }

    @Test("A cancelled tool call still runs on the device but sends no response")
    func toolCancellation() async throws {
        let tools = GatedTools()
        let rig = Rig(tools: tools)
        try await rig.connect()
        await rig.server.push(LiveServerMessage(toolCall: LiveToolCall(functionCalls: [
            LiveFunctionCall(id: "a", name: "pause_app", args: ["app": "WhatsApp"]),
            LiveFunctionCall(id: "b", name: "start_focus", args: ["minutes": 45]),
        ])))
        await eventually("the first tool to start") { await tools.waiting }
        await rig.server.push(LiveServerMessage(toolCallCancellation: LiveToolCallCancellation(ids: ["a"])))
        await rig.events.wait("the cancellation") { $0.contains(.toolCancelled(ids: ["a"])) }
        await tools.release()
        await eventually("the tool response") { await !rig.server.toolResponses.isEmpty }
        let responses = await rig.server.toolResponses
        #expect(responses.count == 1)
        #expect(responses[0].functionResponses.map(\.id) == ["b"])
        #expect(await tools.calls == ["pause_app", "start_focus"])
    }

    @Test("goAway: the session resumes on a fresh token with the last resumption handle")
    func goAwayResumes() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.server.push(LiveServerMessage(sessionResumptionUpdate: LiveSessionResumptionUpdate(newHandle: "h-1", resumable: true)))
        await rig.server.push(LiveServerMessage(sessionResumptionUpdate: LiveSessionResumptionUpdate(newHandle: "h-2", resumable: false)))
        await rig.server.push(LiveServerMessage(goAway: LiveGoAway(timeLeft: "5s")))
        await rig.events.wait("resumed") { $0.contains(.resumed) }

        #expect(rig.events.events.contains(.goingAway(secondsLeft: 5)))
        let urls = await rig.server.urls
        #expect(urls.count == 2)
        #expect(urls[1].absoluteString.hasSuffix("access_token=\(FakeVoiceTokens.demoToken)"))
        let setups = await rig.server.setups
        #expect(setups.count == 2)
        #expect(setups[0].sessionResumption == LiveSetup.SessionResumption(handle: nil))
        #expect(setups[1].sessionResumption == LiveSetup.SessionResumption(handle: "h-1"))
        #expect(await rig.session.state == .listening)
        #expect(await rig.session.reconnects == 1)

        // The resumed connection works like the first.
        await rig.server.push(LiveServerMessage(serverContent: LiveServerContent(turnComplete: true)))
        await rig.events.wait("turn complete") { $0.contains(.turnComplete) }
    }

    @Test("A dropped connection with a handle resumes too")
    func dropResumes() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.server.push(LiveServerMessage(sessionResumptionUpdate: LiveSessionResumptionUpdate(newHandle: "h-1", resumable: true)))
        await eventually("the handle stored") { await rig.session.resumptionHandle == "h-1" }
        await rig.server.hangUp(failing: true)
        await rig.events.wait("resumed") { $0.contains(.resumed) }
        #expect(await rig.server.setups.last?.sessionResumption?.handle == "h-1")
    }

    @Test("Without a handle, a clean hang-up ends the session and a failure is an error")
    func endsWithoutHandle() async throws {
        let clean = Rig()
        try await clean.connect()
        await clean.server.hangUp()
        await clean.events.waitForFinish()
        #expect(clean.events.states.last == .ended)

        let failed = Rig()
        try await failed.connect()
        await failed.server.hangUp(failing: true)
        await failed.events.waitForFinish()
        #expect(failed.events.events.contains(.error(.offline)))
        #expect(failed.events.states.last == .error)
    }

    @Test("If no new token comes, the resume fails cleanly")
    func resumeWithoutToken() async throws {
        let rig = Rig(tokens: FakeVoiceTokens(failure: .rateLimited))
        try await rig.connect()
        await rig.server.push(LiveServerMessage(sessionResumptionUpdate: LiveSessionResumptionUpdate(newHandle: "h-1", resumable: true)))
        await rig.server.push(LiveServerMessage(goAway: LiveGoAway(timeLeft: "1s")))
        await rig.events.waitForFinish()
        #expect(rig.events.events.contains(.error(.rateLimited)))
        #expect(rig.events.states.last == .error)
    }

    @Test("Garbage frames are ignored; usage is reported")
    func garbageAndUsage() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.server.pushRaw("not json")
        await rig.server.pushRaw(#"{"somethingNew":{}}"#)
        await rig.server.push(LiveServerMessage(usageMetadata: LiveUsageMetadata(totalTokenCount: 321)))
        await rig.events.wait("usage") { $0.contains(.usage(LiveUsageMetadata(totalTokenCount: 321))) }
        #expect(await rig.session.state == .listening)
    }

    @Test("Closing ends the session, finishes the events and stops sending")
    func close() async throws {
        let rig = Rig()
        try await rig.connect()
        await rig.session.close()
        await rig.events.waitForFinish()
        #expect(rig.events.states.last == .ended)
        await rig.session.sendText("hello?")
        #expect(await rig.server.texts.isEmpty)
    }
}

extension ZenoSessionTests {
    @Test("A muted mic isn't speech: its chunks never end a turn (Zeno's own echo while the mic waits)")
    func mutedChunksAreNotSpeech() async throws {
        let rig = Rig()
        try await rig.connect()
        #expect(await rig.session.state == .listening)
        await rig.session.setMuted(true)
        await rig.session.sendAudio(MicChunk(samples: [9_000, -9_000])) // loud: Zeno through the speakers
        rig.clock.advance(by: 1)
        await rig.session.sendAudio(MicChunk(samples: [0, 0]))           // then quiet
        #expect(await rig.session.state == .listening)
        #expect(await rig.server.audioChunks.isEmpty)

        await rig.session.setMuted(false)
        await rig.session.sendAudio(MicChunk(samples: [9_000, -9_000])) // the person speaks
        rig.clock.advance(by: 1)
        await rig.session.sendAudio(MicChunk(samples: [0, 0]))
        #expect(await rig.session.state == .thinking)
    }
}

