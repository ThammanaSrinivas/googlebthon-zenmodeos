import Foundation
import Observation
import ZenAPI

/// One line of the conversation as the notch shows it.
public struct TranscriptLine: Equatable, Sendable, Identifiable {
    public enum Speaker: String, Sendable { case user, zeno }

    public let id: Int
    public let speaker: Speaker
    public var text: String
    /// BCP-47 from Gemini (user lines) or the script.
    public var language: String?
    /// "Tanglish", "Hindi" …, for the small label beside the line.
    public var languageLabel: String?
    public var isFinal: Bool
    /// Zeno was interrupted mid-line.
    public var wasCut: Bool
}

/// What Kamal's notch and island UI binds to. No SwiftUI here: `@Observable` works with any UI.
///
///     let voice = VoiceModel(tokens: services.voiceTokens, scores: services.scores,
///                            cards: services.cards, ledger: ledger, userName: user.firstName,
///                            audio: AVAudioVoiceIO())
///     await voice.start(pickup: true)   // on pickup or a notch tap
///     …
///     await voice.stop()
@MainActor
@Observable
public final class VoiceModel {
    public private(set) var state: VoiceState = .idle
    /// The conversation so far, oldest first. The last user or Zeno line may still be growing.
    public private(set) var lines: [TranscriptLine] = []
    /// The latest tool card: an intent timer, focus, a pause, the status, a Zen Card.
    public private(set) var card: ToolCard?
    /// The tool running right now, by name.
    public private(set) var runningTool: String?
    /// The latest first-audio latency in milliseconds (live sessions only).
    public private(set) var latencyMs: Int?
    public private(set) var error: VoiceError?
    /// The open intent session, for the island timer (from the on-device ledger).
    public private(set) var activeIntent: IntentSession?
    /// The running focus session.
    public private(set) var activeFocus: FocusSession?
    /// The intent whose minutes just ran out, until it ends or another starts.
    public private(set) var timeUp: IntentSession?

    /// True for the offline replay: label every surface "Demo".
    public let isDemo: Bool
    /// The demo's caption for the current moment (1…5), nil outside the demo.
    public private(set) var caption: String?
    public private(set) var demoMoment: Int?
    /// The demo's time skip ("2 minutes later") and the clock it lands on.
    public private(set) var demoClock: String?
    /// Called for each scripted line in the demo, so the app can speak it (TTS) or play its clip.
    public var onDemoLine: (@MainActor (DemoLine) -> Void)?

    public var userLine: TranscriptLine? { lines.last { $0.speaker == .user } }
    public var zenoLine: TranscriptLine? { lines.last { $0.speaker == .zeno } }
    public var isActive: Bool { session != nil }

    public let ledger: OnDeviceLedger

    private enum Backend {
        case live(@Sendable () -> (any LiveTransport)?)
        case demo(pace: Double, sleep: ScriptedLiveTransport.Sleeper, clock: ManualVoiceClock)
    }

    private let backend: Backend
    private let tokens: any VoiceTokenService
    private let toolbox: ZenoToolbox
    private let audio: (any VoiceAudioIO)?
    private let userName: String
    private var session: ZenoSession?
    private var sessionTasks: [Task<Void, Never>] = []
    private var ledgerTask: Task<Void, Never>?
    private var nextLineId = 0
    /// Bumped by every `start` and `stop`. A cancelled task still drains what its stream had
    /// buffered, so each session's tasks check it and drop a stopped session's leftover events and
    /// cues instead of writing them over the next session (or over `.ended`).
    private var run = 0

    /// A live model. `transport` makes the WebSocket for each session; by default it is
    /// `URLSessionLiveTransport` on Apple platforms (and none elsewhere, where `start` fails with
    /// `.unavailable`).
    public init(tokens: any VoiceTokenService, scores: any ScoreService, cards: any ZenCardService,
                ledger: OnDeviceLedger, userName: String, audio: (any VoiceAudioIO)? = nil,
                transport: (@Sendable () -> (any LiveTransport)?)? = nil) {
        self.tokens = tokens
        self.ledger = ledger
        self.toolbox = ZenoToolbox(ledger: ledger, scores: scores, cards: cards)
        self.audio = audio
        self.userName = userName
        self.backend = .live(transport ?? VoiceModel.defaultTransport)
        self.isDemo = false
    }

    private init(scores: any ScoreService, cards: any ZenCardService, userName: String, pace: Double,
                 sleep: @escaping ScriptedLiveTransport.Sleeper) {
        let clock = ManualVoiceClock(Date())
        let ledger = OnDeviceLedger(clock: clock, store: InMemoryKeyValueStore())
        self.tokens = DemoTokens()
        self.ledger = ledger
        self.toolbox = ZenoToolbox(ledger: ledger, scores: scores, cards: cards)
        self.audio = nil
        self.userName = userName
        self.backend = .demo(pace: pace, sleep: sleep, clock: clock)
        self.isDemo = true
    }

    /// The offline replay of the five moments: no mic, no network, a ledger of its own. Pass fakes
    /// (ZenMock's `FakeScores` and `FakeZenCards`) so the demo never writes real cards.
    public static func demo(scores: any ScoreService, cards: any ZenCardService, userName: String = "Kamal",
                            pace: Double = 1,
                            sleep: @escaping ScriptedLiveTransport.Sleeper = { try? await Task.sleep(for: $0) }) -> VoiceModel {
        VoiceModel(scores: scores, cards: cards, userName: userName, pace: pace, sleep: sleep)
    }

    private static let defaultTransport: @Sendable () -> (any LiveTransport)? = {
        #if canImport(Darwin)
        return URLSessionLiveTransport()
        #else
        return nil
        #endif
    }

    // MARK: - Control

    /// Opens a session. With `pickup`, the pickup is counted and Zeno opens with its one question.
    /// Then the mic streams (live) or the five moments play (demo).
    public func start(pickup: Bool = true) async {
        guard session == nil else { return }
        run += 1
        let current = run
        lines = []
        card = nil
        error = nil
        latencyMs = nil
        caption = nil
        demoMoment = nil
        demoClock = nil
        state = .connecting
        watchLedger()

        let transport: any LiveTransport
        switch backend {
        case .live(let make):
            guard let made = make() else { return fail(.unavailable) }
            transport = made
        case .demo(let pace, let sleep, let clock):
            let scripted = ScriptedLiveTransport(user: userName, pace: pace, sleep: sleep,
                                                 advanceClock: { clock.advance(by: $0) })
            transport = scripted
            sessionTasks.append(Task { [weak self] in
                for await cue in scripted.cues {
                    guard let self, self.run == current else { return }
                    self.apply(cue)
                }
            })
        }

        let session = ZenoSession(transport: transport, tools: toolbox, tokens: isDemo ? nil : tokens, user: userName)
        self.session = session
        sessionTasks.append(Task { [weak self] in
            for await event in session.events {
                guard let self, self.run == current else { return }
                self.apply(event)
            }
            self?.sessionFinished(session)
        })

        // After each wait, carry on only if this is still the session: `stop()` may have ended it
        // meanwhile, and then there is no error to show and no mic to open.
        let token: LiveToken
        do { token = try await tokens.liveToken() } catch { return failUnlessStopped(session, error) }
        guard self.session === session else { return }
        // The pickup is counted before connecting: the scripted replay starts playing as soon as
        // the setup is accepted, and its first intent must find the pickup already there.
        if pickup { await ledger.recordPickup() }
        do { try await session.connect(token: token) } catch { return failUnlessStopped(session, error) }
        guard self.session === session else { return }

        if pickup { await session.sendText(ZenoAgent.pickupCue) }
        if let audio, !isDemo, self.session === session { startMic(audio, session: session) }
    }

    /// Ends the session, stops the mic and playback. The model lets go of the session first, so a
    /// `start` still connecting sees the stop instead of reporting the closed session as an error.
    public func stop() async {
        guard let session else { return }
        self.session = nil
        run += 1
        audio?.stop()
        for task in sessionTasks { task.cancel() }
        sessionTasks = []
        state = .ended
        await session.close()
    }

    /// Sends a typed line as the user's turn.
    public func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !trimmed.isEmpty else { return }
        appendLine(.user, text: trimmed, language: nil, isFinal: true)
        await session.sendText(trimmed)
    }

    /// Mutes or unmutes the mic.
    public func setMuted(_ muted: Bool) async { await session?.setMuted(muted) }

    private func startMic(_ audio: any VoiceAudioIO, session: ZenoSession) {
        let (chunks, continuation) = AsyncStream.makeStream(of: MicChunk.self, bufferingPolicy: .bufferingNewest(50))
        sessionTasks.append(Task {
            for await chunk in chunks { await session.sendAudio(chunk) }
        })
        do {
            try audio.start { continuation.yield($0) }
        } catch {
            continuation.finish()
            self.error = .disabled // the mic was refused; typed turns still work
        }
    }

    private func failUnlessStopped(_ attempt: ZenoSession, _ error: VoiceError) {
        if session === attempt { fail(error) }
    }

    private func fail(_ error: VoiceError) {
        self.error = error
        state = .error
        for task in sessionTasks { task.cancel() }
        sessionTasks = []
        audio?.stop()
        session = nil
    }

    private func sessionFinished(_ finished: ZenoSession) {
        guard session === finished else { return }
        audio?.stop()
        session = nil
        if state != .error { state = .ended }
    }

    // MARK: - Events

    func apply(_ event: VoiceEvent) {
        switch event {
        case .state(let new):
            state = new
        case .userTranscript(let text, let language, let isFinal):
            upsert(.user, text: text, language: language, isFinal: isFinal)
        case .zenoTranscript(let text, let isFinal):
            upsert(.zeno, text: text, language: nil, isFinal: isFinal)
        case .audio(let pcm, let rate):
            audio?.play(pcm, sampleRate: rate)
        case .interrupted:
            audio?.flush()
            if let index = lines.lastIndex(where: { $0.speaker == .zeno && !$0.isFinal }) {
                lines[index].isFinal = true
                lines[index].wasCut = true
            }
        case .toolCall(let call):
            runningTool = call.name
        case .toolResult(let result):
            runningTool = nil
            guard let card = result.outcome.card else { break }
            self.card = card
            // Keep the island in step at once (the ledger's events confirm it too).
            switch card {
            case .intent(let session): activeIntent = session
            case .intentEnded(let session) where activeIntent?.id == session.id: activeIntent = nil
            case .focus(let focus): activeFocus = focus
            default: break
            }
        case .latency(let ms):
            if !isDemo { latencyMs = ms }
        case .error(let error):
            self.error = error
        case .toolCancelled, .turnComplete, .usage, .goingAway, .resumed:
            break
        }
    }

    func apply(_ cue: DemoCue) {
        switch cue {
        case .caption(let moment, let text):
            demoMoment = moment == 0 ? nil : moment
            caption = text.isEmpty ? nil : text
        case .pickup(let clock):
            demoClock = clock
        case .line(let line):
            // Only for voicing: the transcript comes from the session's events, which end every
            // Zeno line themselves (turn complete, or interrupted). Cues arrive on their own stream,
            // so ending a line here could cut the line now growing and split it in two.
            onDemoLine?(line)
        case .skip(_, let clock):
            demoClock = clock
        case .finished:
            break
        }
    }

    private func upsert(_ speaker: TranscriptLine.Speaker, text: String, language: String?, isFinal: Bool) {
        if let index = lines.indices.last, lines[index].speaker == speaker, !lines[index].isFinal {
            lines[index].text = text
            if let language {
                lines[index].language = language
                lines[index].languageLabel = LanguageLabel.label(for: language, text: text)
            }
            lines[index].isFinal = isFinal
        } else {
            appendLine(speaker, text: text, language: language, isFinal: isFinal)
        }
    }

    private func appendLine(_ speaker: TranscriptLine.Speaker, text: String, language: String?, isFinal: Bool) {
        nextLineId += 1
        lines.append(TranscriptLine(id: nextLineId, speaker: speaker, text: text, language: language,
                                    languageLabel: LanguageLabel.label(for: language, text: text),
                                    isFinal: isFinal, wasCut: false))
    }

    // MARK: - Ledger

    private func watchLedger() {
        guard ledgerTask == nil else { return }
        let ledger = self.ledger
        ledgerTask = Task { [weak self] in
            let status = await ledger.status()
            self?.activeIntent = status.activeIntent
            self?.activeFocus = status.focus
            for await event in await ledger.events() { self?.apply(event) }
        }
    }

    func apply(_ event: LedgerEvent) {
        switch event {
        case .intentStarted(let session):
            activeIntent = session
            timeUp = nil
        case .intentEnded(let session):
            if activeIntent?.id == session.id { activeIntent = nil }
            if timeUp?.id == session.id { timeUp = nil }
        case .intentTimeUp(let session):
            timeUp = session
        case .focusStarted(let focus):
            activeFocus = focus
        case .focusEnded(let focus):
            if activeFocus?.id == focus.id { activeFocus = nil }
        case .paused, .unpaused, .pickup:
            break
        }
    }
}

/// The demo's token: never sent anywhere (the scripted server ignores it).
private struct DemoTokens: VoiceTokenService {
    func liveToken() async throws(VoiceError) -> LiveToken {
        LiveToken(token: "demo", model: ZenoAgent.defaultModel, voice: ZenoAgent.defaultVoice, expiresAt: .distantFuture,
                  connectBy: .distantFuture)
    }
}
