import Foundation
import ZenAPI

/// What the notch shows Zeno doing.
public enum VoiceState: String, Equatable, Sendable {
    case idle, connecting, listening, thinking, speaking, ended, error
}

public struct ToolCallInfo: Equatable, Sendable {
    public let id: String?
    public let name: String
    public let args: JSONValue
}

public struct ToolResultInfo: Equatable, Sendable {
    public let id: String?
    public let name: String
    public let outcome: ToolOutcome
    /// How long the tool took on the device (and the backend, for cards).
    public let milliseconds: Int
}

/// Everything a session reports, in order.
public enum VoiceEvent: Equatable, Sendable {
    case state(VoiceState)
    /// What the user is saying, growing as it's transcribed; `isFinal` once Zeno answers.
    case userTranscript(text: String, language: String?, isFinal: Bool)
    case zenoTranscript(text: String, isFinal: Bool)
    /// Zeno's voice: PCM16 mono at `sampleRate` (24 kHz), to queue for playback.
    case audio(Data, sampleRate: Int)
    /// The user spoke over Zeno: flush playback now.
    case interrupted
    case toolCall(ToolCallInfo)
    case toolResult(ToolResultInfo)
    /// The server dropped these calls (usually after an interruption); their responses aren't sent.
    case toolCancelled(ids: [String])
    case turnComplete
    /// From the end of the user's speech (or a text turn, or a tool response) to Zeno's first audio.
    case latency(milliseconds: Int)
    case usage(LiveUsageMetadata)
    /// The server will close soon; the session resumes on a new connection if it can.
    case goingAway(secondsLeft: Double?)
    /// The session continued on a new connection with its resumption handle.
    case resumed
    case error(VoiceError)
}

/// One conversation with Zeno over Gemini Live: connects with an ephemeral token, sends the setup,
/// streams the mic, runs tool calls through the toolbox, and reports everything as `events`.
/// Barge-in is the server's (`START_OF_ACTIVITY_INTERRUPTS`): on `interrupted` the app flushes
/// playback. On `goAway`, or a dropped connection, it resumes on a fresh token with the last
/// resumption handle.
public actor ZenoSession {
    public struct Options: Sendable {
        public var setupTimeout: Duration
        public var maxReconnects: Int
        /// Mic RMS above this counts as speech for the local end-of-speech timer (latency only).
        public var voicedRMS: Float
        /// Silence after speech before the user's turn counts as ended, locally.
        public var endOfSpeechSeconds: TimeInterval
        public var host: String

        public init(setupTimeout: Duration = .seconds(10), maxReconnects: Int = 3, voicedRMS: Float = 0.02,
                    endOfSpeechSeconds: TimeInterval = 0.25, host: String = LiveEndpoint.host) {
            self.setupTimeout = setupTimeout
            self.maxReconnects = maxReconnects
            self.voicedRMS = voicedRMS
            self.endOfSpeechSeconds = endOfSpeechSeconds
            self.host = host
        }
    }

    public nonisolated let events: AsyncStream<VoiceEvent>
    private let continuation: AsyncStream<VoiceEvent>.Continuation

    private let transport: any LiveTransport
    private let tools: any ZenoToolExecutor
    private let tokens: (any VoiceTokenService)?
    private let user: String
    private let clock: any VoiceClock
    private let options: Options

    public private(set) var state: VoiceState = .idle
    /// The latest handle the server said can resume this session.
    public private(set) var resumptionHandle: String?
    public private(set) var reconnects = 0
    private var ready = false
    private var closing = false
    private var muted = false
    private var generation = 0
    private var receiveTask: Task<Void, Never>?
    private var setupWaiter: CheckedContinuation<Void, any Error>?
    private var resuming = false

    // The turn in progress.
    private var inText = ""
    private var inLanguage: String?
    private var outText = ""
    private var userSpeaking = false
    private var lastVoiceAt: Date?
    private var awaitingFirstAudio = false
    private var turnStartedAt: Date?
    private var cancelledToolIds: Set<String> = []

    /// - Parameters:
    ///   - tokens: mints the fresh token a resumed connection needs (tokens are single-use). Without
    ///     it the session ends when the connection does.
    ///   - user: the first name Zeno greets, as in the system instruction.
    public init(transport: any LiveTransport, tools: any ZenoToolExecutor, tokens: (any VoiceTokenService)? = nil,
                user: String, clock: any VoiceClock = SystemVoiceClock(), options: Options = Options()) {
        self.transport = transport
        self.tools = tools
        self.tokens = tokens
        self.user = user
        self.clock = clock
        self.options = options
        (events, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
    }

    // MARK: - Connecting

    /// Connects, sends the setup and waits for the server to accept it. The session is then
    /// listening: send mic chunks with `sendAudio`, or a text turn with `sendText`. A token past
    /// its `connectBy` is swapped for a fresh one first (when the session has a token service).
    public func connect(token: LiveToken) async throws(VoiceError) {
        guard state == .idle else { throw .unavailable }
        setState(.connecting)
        do {
            try await open(token: try await usable(token), handle: nil)
        } catch {
            emit(.error(error))
            setState(.error)
            finish()
            throw error
        }
        setState(.listening)
    }

    /// The token if it can still open a session, else a fresh one.
    private func usable(_ token: LiveToken) async throws(VoiceError) -> LiveToken {
        if token.canConnect(at: clock.now) { return token }
        guard let tokens else { throw .unavailable }
        let fresh = try await tokens.liveToken()
        guard fresh.canConnect(at: clock.now) else { throw .unavailable }
        return fresh
    }

    private func open(token: LiveToken, handle: String?) async throws(VoiceError) {
        guard token.canConnect(at: clock.now) else { throw .unavailable }
        generation += 1
        let current = generation
        let url = LiveEndpoint.constrainedURL(token: token.token, host: options.host)
        let setup = LiveClientMessage.setup(ZenoAgent.setup(model: token.model, voice: token.voice, user: user,
                                                            resumptionHandle: handle))
        do {
            try await transport.connect(to: url)
            try await transport.send(try setup.jsonString())
        } catch {
            throw .offline
        }
        receiveTask = Task { await self.receiveLoop(current) }
        do {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
                setupWaiter = waiter
                let timeout = options.setupTimeout
                Task {
                    try? await Task.sleep(for: timeout)
                    self.setupTimedOut(current)
                }
            }
        } catch let error as VoiceError {
            throw error
        } catch {
            throw .unavailable
        }
        ready = true
    }

    private func setupTimedOut(_ current: Int) {
        guard current == generation, let waiter = setupWaiter else { return }
        setupWaiter = nil
        waiter.resume(throwing: VoiceError.unavailable)
    }

    private func receiveLoop(_ current: Int) async {
        do {
            while let frame = try await transport.receive() {
                guard current == generation else { return }
                handle(frame)
            }
            guard current == generation else { return }
            connectionEnded(failed: false)
        } catch {
            guard current == generation else { return }
            connectionEnded(failed: true)
        }
    }

    private var canResume: Bool {
        resumptionHandle != nil && tokens != nil && reconnects < options.maxReconnects && !closing
    }

    private func connectionEnded(failed: Bool) {
        guard !closing else { return }
        ready = false
        if let waiter = setupWaiter {
            setupWaiter = nil
            waiter.resume(throwing: failed ? VoiceError.offline : VoiceError.unavailable)
            return
        }
        if canResume {
            // A new task: this one (the old connection's reader) is about to be cancelled.
            Task { await self.resume() }
            return
        }
        if failed {
            emit(.error(.offline))
            setState(.error)
        } else {
            setState(.ended)
        }
        finish()
    }

    /// Moves the session to a new connection with a fresh token and the last resumption handle.
    private func resume() async {
        guard !resuming, canResume, let tokens, let handle = resumptionHandle else { return }
        resuming = true
        defer { resuming = false }
        reconnects += 1
        ready = false
        generation += 1 // the old connection's reader stops here
        receiveTask?.cancel()
        resetTurn()
        setState(.connecting)
        await transport.close()
        do {
            let token = try await usable(tokens.liveToken())
            try await open(token: token, handle: handle)
        } catch {
            guard !closing else { return }
            emit(.error(error))
            setState(.error)
            finish()
            return
        }
        emit(.resumed)
        setState(.listening)
    }

    /// Ends the session and closes the connection.
    public func close() async {
        guard !closing else { return }
        closing = true
        ready = false
        generation += 1
        if let waiter = setupWaiter {
            setupWaiter = nil
            waiter.resume(throwing: VoiceError.unavailable)
        }
        receiveTask?.cancel()
        await transport.close()
        setState(.ended)
        finish()
    }

    // MARK: - Sending

    /// 40 ms of 16 kHz PCM16 from the mic. Dropped while not connected or muted.
    public func sendAudio(_ chunk: MicChunk) async {
        // A muted mic isn't speech: muted by the person, or waiting while Zeno talks, when what it
        // picks up is Zeno's own voice. Tracking it would end a turn nobody spoke ("Thinking" for good).
        guard !muted else { return }
        trackLocalSpeech(rms: chunk.rms)
        guard ready else { return }
        await send(.audio(chunk.pcm))
    }

    /// A complete user turn in text: the pickup cue, or something typed.
    public func sendText(_ text: String) async {
        guard ready else { return }
        startTurnTimer()
        if state == .listening { setState(.thinking) }
        await send(.userText(text))
    }

    /// Mutes the mic; the server is told the audio stream ended so it closes the user's turn.
    public func setMuted(_ muted: Bool) async {
        self.muted = muted
        if muted, ready { await send(.audioStreamEnd) }
    }

    private func send(_ message: LiveClientMessage) async {
        guard let frame = try? message.jsonString() else { return }
        try? await transport.send(frame) // a failed send shows up as a dropped connection
    }

    /// The local end-of-speech timer, as the prototype's: a voiced chunk marks speech, 250 ms of
    /// quiet after it ends the turn locally, and the latency clock starts at the last voiced chunk.
    private func trackLocalSpeech(rms: Float) {
        let now = clock.now
        if rms > options.voicedRMS {
            lastVoiceAt = now
            userSpeaking = true
        } else if userSpeaking, let last = lastVoiceAt, now.timeIntervalSince(last) > options.endOfSpeechSeconds {
            userSpeaking = false
            awaitingFirstAudio = true
            turnStartedAt = last
            if state == .listening { setState(.thinking) }
        }
    }

    private func startTurnTimer() {
        awaitingFirstAudio = true
        turnStartedAt = clock.now
    }

    // MARK: - Receiving

    private func handle(_ frame: String) {
        guard let message = try? LiveServerMessage.parse(frame) else { return }
        if message.setupComplete != nil, let waiter = setupWaiter {
            setupWaiter = nil
            waiter.resume()
        }
        if let update = message.sessionResumptionUpdate, update.resumable == true, let handle = update.newHandle,
           !handle.isEmpty {
            resumptionHandle = handle
        }
        if let usage = message.usageMetadata { emit(.usage(usage)) }
        if let content = message.serverContent { handle(content) }
        if let call = message.toolCall, !call.functionCalls.isEmpty { startTools(call.functionCalls) }
        if let cancellation = message.toolCallCancellation {
            cancelledToolIds.formUnion(cancellation.ids)
            emit(.toolCancelled(ids: cancellation.ids))
        }
        if let goAway = message.goAway {
            emit(.goingAway(secondsLeft: goAway.secondsLeft))
            if canResume { Task { await self.resume() } }
        }
    }

    private func handle(_ content: LiveServerContent) {
        if content.interrupted == true {
            outText = ""
            emit(.interrupted)
            setState(.listening)
        }
        if let heard = content.inputTranscription, let text = heard.text, !text.isEmpty {
            inText += text
            if let language = heard.languageCode, !language.isEmpty { inLanguage = language }
            emit(.userTranscript(text: inText, language: inLanguage, isFinal: false))
        }
        if let spoken = content.outputTranscription, let text = spoken.text, !text.isEmpty {
            finishUserLine()
            outText += text
            emit(.zenoTranscript(text: outText, isFinal: false))
            setState(.speaking)
        }
        for part in content.modelTurn?.parts ?? [] where part.thought != true {
            guard let blob = part.inlineData, blob.isAudio, let bytes = blob.bytes, !bytes.isEmpty else { continue }
            if awaitingFirstAudio {
                awaitingFirstAudio = false
                if let start = turnStartedAt {
                    emit(.latency(milliseconds: max(0, Int((clock.now.timeIntervalSince(start) * 1_000).rounded()))))
                }
            }
            finishUserLine()
            setState(.speaking)
            emit(.audio(bytes, sampleRate: blob.sampleRate ?? liveOutputSampleRate))
        }
        if content.turnComplete == true {
            finishUserLine()
            if !outText.isEmpty { emit(.zenoTranscript(text: outText, isFinal: true)) }
            outText = ""
            emit(.turnComplete)
            setState(.listening)
        }
    }

    private func finishUserLine() {
        guard !inText.isEmpty else { return }
        emit(.userTranscript(text: inText, language: inLanguage, isFinal: true))
        inText = ""
    }

    private func resetTurn() {
        inText = ""
        outText = ""
        awaitingFirstAudio = false
        turnStartedAt = nil
        userSpeaking = false
    }

    // MARK: - Tools

    private func startTools(_ calls: [LiveFunctionCall]) {
        finishUserLine()
        setState(.thinking)
        Task { await self.runTools(calls) }
    }

    private func runTools(_ calls: [LiveFunctionCall]) async {
        var responses: [LiveFunctionResponse] = []
        for call in calls {
            let args = call.args ?? .object([:])
            emit(.toolCall(ToolCallInfo(id: call.id, name: call.name, args: args)))
            let started = clock.now
            let outcome = await tools.call(call.name, args: args)
            let ms = max(0, Int((clock.now.timeIntervalSince(started) * 1_000).rounded()))
            emit(.toolResult(ToolResultInfo(id: call.id, name: call.name, outcome: outcome, milliseconds: ms)))
            if let id = call.id, cancelledToolIds.contains(id) { continue }
            responses.append(LiveFunctionResponse(id: call.id, name: call.name, response: ["result": outcome.result]))
        }
        guard !responses.isEmpty, ready else { return }
        // Latency stays measured from the end of the user's speech, so it includes the tool round trip.
        if !awaitingFirstAudio { startTurnTimer() }
        await send(.toolResponse(LiveToolResponse(functionResponses: responses)))
    }

    // MARK: - Events

    private func setState(_ new: VoiceState) {
        guard new != state else { return }
        state = new
        emit(.state(new))
    }

    private func emit(_ event: VoiceEvent) { continuation.yield(event) }

    private func finish() { continuation.finish() }
}
