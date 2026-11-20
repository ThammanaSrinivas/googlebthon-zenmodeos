import Foundation

// The offline demo: the five moments from the prototype's replay (zeno-voice/src/demo.js), played
// as a fake Gemini Live server. No network, no mic, no key. The session talks to it exactly as it
// talks to Gemini, so every tool call still runs for real on the ledger and the toolbox; only the
// user's and Zeno's words are scripted. Voices are the app's job: it can speak `DemoCue.line`
// with on-device TTS or play the named clip.

/// One line of the replay, for captions and optional TTS.
public struct DemoLine: Equatable, Sendable {
    public enum Speaker: String, Sendable { case user, zeno }

    public let speaker: Speaker
    public let text: String
    /// BCP-47, e.g. "ta-Latn" for Tanglish.
    public let language: String
    /// The prototype's label for the mix ("Tanglish", "Hinglish", "தமிழ்").
    public let tag: String?
    /// The prototype's voice clip name (`demo/voice/<clip>.mp3`), if the app bundles them.
    public let clip: String?
    /// About how long the line takes to say.
    public let milliseconds: Int
    /// Zeno was cut off mid-line (moment 3).
    public let cut: Bool
}

public enum DemoStep: Equatable, Sendable {
    /// The moment's caption; moment 0 clears it.
    case caption(moment: Int, text: String)
    case pickup(clock: String)
    case zeno(DemoLine)
    case user(DemoLine)
    case tool(name: String, args: JSONValue)
    /// The user speaks over Zeno.
    case interrupt
    /// Time passes: the ledger's clock moves on, so timers end and sessions finish on time.
    case skip(label: String, seconds: TimeInterval, clock: String)
}

/// What the replay shows besides the protocol: captions, lines to voice, time skips.
public enum DemoCue: Equatable, Sendable {
    case caption(moment: Int, text: String)
    case pickup(clock: String)
    case line(DemoLine)
    case skip(label: String, clock: String)
    case finished
}

public enum ZenoDemo {
    /// The five moments, in order. `{user}`, `{score}` and `{week_line}` are filled in as they play,
    /// the last two from what `get_zen_status` really returned.
    public static func script(user: String = "Kamal") -> [DemoStep] {
        func zeno(_ language: String, _ text: String, _ ms: Int, _ clip: String, cut: Bool = false) -> DemoStep {
            .zeno(DemoLine(speaker: .zeno, text: text, language: language, tag: nil, clip: clip, milliseconds: ms, cut: cut))
        }
        func said(_ language: String, _ tag: String, _ text: String, _ ms: Int, _ clip: String) -> DemoStep {
            .user(DemoLine(speaker: .user, text: text, language: language, tag: tag, clip: clip, milliseconds: ms, cut: false))
        }
        return [
            .caption(moment: 1, text: "Pickup at 10:02 PM. Zeno asks one question."),
            .pickup(clock: "22:02"),
            zeno("en", "Hey {user}. What are you here for?", 1900, "z_hey"),

            .caption(moment: 2, text: "Tanglish in, action out: a 2-minute Instagram intent."),
            said("ta-Latn", "Tanglish", "Zeno, Arun anuppuna reel-a paakkanum. Insta-la rendu nimisham mattum.", 3200, "k_insta"),
            .tool(name: "set_intent", args: ["app": "Instagram", "purpose": "Watch the reel Arun sent", "minutes": 2]),
            zeno("ta-Latn", "Seri, rendu nimisham. Mudinjadhum naan solren.", 2300, "z_seri"),
            .skip(label: "2 minutes later", seconds: 120, clock: "22:04"),
            .tool(name: "end_session", args: [:]),
            zeno("ta-Latn", "Rendu nimisham, correct-a mudinjadhu. Super!", 2000, "z_done"),

            .caption(moment: 3, text: "Hinglish, cut off mid-sentence. Zeno stops, takes the new number, acts."),
            said("hi-Latn", "Hinglish", "Kal subah client demo hai. Mujhe ek ghante ka focus chahiye, aur…", 2900, "k_focus"),
            zeno("hi-Latn", "Theek hai, ek ghante ka focus shu—", 3400, "z_cut", cut: true),
            .interrupt,
            said("hi-Latn", "Hinglish", "Nahi nahi, 45 minute. Aur WhatsApp pe pause laga do.", 2600, "k_nahi"),
            .tool(name: "start_focus", args: ["minutes": 45, "label": "Client demo prep"]),
            .tool(name: "pause_app", args: ["app": "WhatsApp", "seconds": 7]),
            zeno("hi-Latn", "Ho gaya. 45 minute focus, aur WhatsApp pe 7 second ka pause.", 2800, "z_hogaya"),

            .caption(moment: 4, text: "A question about the day reads the live Zen Score."),
            said("en", "English", "How's my day looking?", 1500, "k_day"),
            .tool(name: "get_zen_status", args: [:]),
            zeno("en", "Zen Score {score}. {week_line}.", 3000, "z_score"),

            .caption(moment: 5, text: "Tamil evening note becomes a Zen Card, shared with the circle."),
            .skip(label: "Later that night", seconds: 37 * 60, clock: "22:41"),
            said("ta", "தமிழ்", "இன்னைக்கு காலையில வாக்கிங் போனேன். டின்னர் அப்போ ஃபோனை தொடவே இல்ல. சர்க்கிளுக்கு ஷேர் பண்ணு.", 3600, "k_tamil"),
            .tool(name: "log_reflection", args: [
                "summary": "காலையில வாக்கிங், டின்னர் அப்போ ஃபோன் இல்ல", "mood": "happy", "language": "ta",
                "earned_back": "A phone-free dinner", "drift": "",
            ]),
            .tool(name: "share_with_circle", args: ["note": "Phone-free dinner tonight"]),
            zeno("ta", "சூப்பர்! உங்க Zen Card ரெடி. சர்க்கிளுக்கும் அனுப்பிட்டேன்.", 2800, "z_tamil"),
            .caption(moment: 0, text: ""),
        ]
    }

    /// Fills `{user}`, `{score}` and `{week_line}`.
    static func fill(_ text: String, user: String, status: JSONValue?) -> String {
        let score = status?["score_text"]?.stringValue ?? "not in yet"
        let week = (status?["week_line"]?.stringValue ?? "the week is still open").replacingOccurrences(of: " · ", with: ", ")
        return text.replacingOccurrences(of: "{user}", with: user)
            .replacingOccurrences(of: "{score}", with: score)
            .replacingOccurrences(of: "{week_line}", with: week)
    }
}

/// A fake Gemini Live server that plays `ZenoDemo.script`. Speak to it with a normal `ZenoSession`.
public actor ScriptedLiveTransport: LiveTransport {
    public typealias Sleeper = @Sendable (Duration) async -> Void

    public nonisolated let cues: AsyncStream<DemoCue>
    private let cueContinuation: AsyncStream<DemoCue>.Continuation

    private let script: [DemoStep]
    private let user: String
    private let pace: Double
    private let sleep: Sleeper
    private let advanceClock: @Sendable (TimeInterval) -> Void
    private let toolTimeout: Duration

    private let outbox = LiveFrameQueue()
    private var runner: Task<Void, Never>?
    private var responses: [String: JSONValue] = [:]
    private var waiting: (id: String, continuation: CheckedContinuation<JSONValue?, Never>)?
    private var started = false

    /// Every frame the client sent, in order (setup, the pickup cue, tool responses …).
    public private(set) var received: [LiveClientMessage] = []
    public private(set) var connectedURL: URL?
    /// The tool steps that got a response, with the result the toolbox returned.
    public private(set) var toolResults: [(name: String, result: JSONValue)] = []

    /// - Parameters:
    ///   - pace: 1 plays the lines at the prototype's speed, 0 as fast as possible.
    ///   - sleep: how to wait; tests pass one that returns at once.
    ///   - advanceClock: moves the ledger's clock on a time skip (a `ManualVoiceClock`'s `advance`).
    public init(script: [DemoStep]? = nil, user: String = "Kamal", pace: Double = 1,
                sleep: @escaping Sleeper = { try? await Task.sleep(for: $0) },
                advanceClock: @escaping @Sendable (TimeInterval) -> Void = { _ in },
                toolTimeout: Duration = .seconds(10)) {
        self.script = script ?? ZenoDemo.script(user: user)
        self.user = user
        self.pace = max(0, pace)
        self.sleep = sleep
        self.advanceClock = advanceClock
        self.toolTimeout = toolTimeout
        (cues, cueContinuation) = AsyncStream.makeStream(of: DemoCue.self)
    }

    public func connect(to url: URL) async throws {
        connectedURL = url
        await outbox.reset()
    }

    public func send(_ frame: String) async throws {
        guard let message = try? LiveClientMessage.parse(frame) else { return }
        received.append(message)
        switch message {
        case .setup:
            guard !started else { return }
            started = true
            await push(LiveServerMessage(setupComplete: LiveEmpty()))
            runner = Task { await self.play() }
        case .toolResponse(let response):
            for item in response.functionResponses {
                let result = item.response["result"] ?? item.response
                if let id = item.id { deliver(id: id, result: result) }
            }
        default:
            break
        }
    }

    public func receive() async throws -> String? { await outbox.next() }

    public func close() async {
        runner?.cancel()
        runner = nil
        if let waiting {
            self.waiting = nil
            waiting.continuation.resume(returning: nil)
        }
        await outbox.finish()
        cueContinuation.finish()
    }

    // MARK: Playing

    private func play() async {
        var status: JSONValue?
        var toolCount = 0
        for step in script {
            if Task.isCancelled { return }
            switch step {
            case .caption(let moment, let text):
                cue(.caption(moment: moment, text: text))
            case .pickup(let clock):
                cue(.pickup(clock: clock))
            case .user(let line):
                cue(.line(line))
                await stream(line) { LiveServerContent(inputTranscription: LiveTranscription(text: $0, languageCode: line.language)) }
            case .zeno(let line):
                let filled = DemoLine(speaker: .zeno, text: ZenoDemo.fill(line.text, user: user, status: status),
                                      language: line.language, tag: line.tag, clip: line.clip,
                                      milliseconds: line.milliseconds, cut: line.cut)
                cue(.line(filled))
                await stream(filled) { LiveServerContent(outputTranscription: LiveTranscription(text: $0, languageCode: line.language)) }
                if !line.cut { await push(LiveServerMessage(serverContent: LiveServerContent(turnComplete: true))) }
            case .tool(let name, let args):
                toolCount += 1
                let id = "demo-\(toolCount)"
                await push(LiveServerMessage(toolCall: LiveToolCall(functionCalls: [LiveFunctionCall(id: id, name: name, args: args)])))
                guard let result = await response(for: id) else { return }
                toolResults.append((name, result))
                if name == ZenoAgent.ToolName.getZenStatus.rawValue { status = result }
            case .interrupt:
                await push(LiveServerMessage(serverContent: LiveServerContent(interrupted: true)))
            case .skip(let label, let seconds, let clock):
                advanceClock(seconds)
                cue(.skip(label: label, clock: clock))
                await pause(milliseconds: 900)
            }
        }
        cue(.finished)
        cueContinuation.finish()
        await outbox.finish()
    }

    /// Sends a line word by word, at the pace of the prototype's clip.
    private func stream(_ line: DemoLine, content: (String) -> LiveServerContent) async {
        let words = line.text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return }
        let each = Double(line.milliseconds) / Double(words.count)
        for (index, word) in words.enumerated() {
            if Task.isCancelled { return }
            await push(LiveServerMessage(serverContent: content(index == 0 ? String(word) : " " + word)))
            await pause(milliseconds: each)
        }
    }

    private func pause(milliseconds: Double) async {
        let scaled = milliseconds * pace
        guard scaled > 0 else { await sleep(.zero); return }
        await sleep(.milliseconds(Int64(scaled)))
    }

    private func response(for id: String) async -> JSONValue? {
        if let ready = responses.removeValue(forKey: id) { return ready }
        let timeout = toolTimeout
        Task {
            try? await Task.sleep(for: timeout)
            self.timeOut(id)
        }
        return await withCheckedContinuation { waiting = (id, $0) }
    }

    private func deliver(id: String, result: JSONValue) {
        if let waiting, waiting.id == id {
            self.waiting = nil
            waiting.continuation.resume(returning: result)
        } else {
            responses[id] = result
        }
    }

    private func timeOut(_ id: String) {
        guard let waiting, waiting.id == id else { return }
        self.waiting = nil
        waiting.continuation.resume(returning: nil)
    }

    private func push(_ message: LiveServerMessage) async {
        guard let frame = try? message.jsonString() else { return }
        await outbox.push(frame)
    }

    private func cue(_ cue: DemoCue) { cueContinuation.yield(cue) }
}
