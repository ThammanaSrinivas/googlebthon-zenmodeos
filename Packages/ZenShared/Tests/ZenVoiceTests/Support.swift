// Shared test doubles for ZenVoice: a scriptable Live server, a score service that answers at once,
// a gated tool executor, and an event recorder that waits for what a test expects.
import Foundation
import Testing
import ZenAPI
@testable import ZenVoice

enum T {
    /// 2026-11-20T16:32:00Z: 22:02 in India, a Friday.
    static let now = Date(timeIntervalSince1970: 1_795_192_320)
    static let india = TimeZone(identifier: "Asia/Kolkata")!

    static func token(_ value: String = "auth_tokens/abc", clock: ManualVoiceClock) -> LiveToken {
        LiveToken(token: value, model: "gemini-3.8-live", voice: "Kore", expiresAt: clock.now.addingTimeInterval(30 * 60),
                  connectBy: clock.now.addingTimeInterval(60))
    }

    static func ledger(_ clock: ManualVoiceClock, store: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> OnDeviceLedger {
        OnDeviceLedger(clock: clock, store: store, timeZone: india)
    }

    static func frame(_ message: LiveServerMessage) -> String { try! message.jsonString() }
}

/// The demo week, at once: Mon 7.2, Tue 5.8, Wed 8.1, Thu 5.4, today 8.1, a 9-week streak.
struct InstantScores: ScoreService {
    var fail = false

    func today() async throws -> ScoreSnapshot {
        if fail { throw URLError(.notConnectedToInternet) }
        let today = ZenScore(tenths: 81)
        let week = WeekProgress(days: [ZenScore(tenths: 72), ZenScore(tenths: 58), ZenScore(tenths: 81),
                                       ZenScore(tenths: 54), today, nil, nil], todayIndex: 4, streakBefore: 9)
        return ScoreSnapshot(score: today, week: week, devices: [], updatedAt: T.now)
    }

    func updates() -> AsyncStream<ScoreSnapshot> { AsyncStream { $0.finish() } }
}

/// A Live server under the test's control. It answers a setup with `setupComplete` (unless told not
/// to) and otherwise sends only what the test pushes.
actor FakeLiveServer: LiveTransport {
    private(set) var urls: [URL] = []
    private(set) var sent: [LiveClientMessage] = []
    private var queue = LiveFrameQueue()
    var answersSetup = true
    private var failNextReceive = false

    func connect(to url: URL) async throws {
        urls.append(url)
        queue = LiveFrameQueue()
    }

    func send(_ frame: String) async throws {
        let message = try LiveClientMessage.parse(frame)
        sent.append(message)
        if case .setup = message, answersSetup { await queue.push(T.frame(LiveServerMessage(setupComplete: LiveEmpty()))) }
    }

    func receive() async throws -> String? {
        let next = await queue.next()
        if next == nil, failNextReceive {
            failNextReceive = false
            throw URLError(.networkConnectionLost)
        }
        return next
    }

    func close() async { await queue.finish() }

    // Test controls.

    func setAnswersSetup(_ value: Bool) { answersSetup = value }

    func push(_ message: LiveServerMessage) async { await queue.push(T.frame(message)) }

    func pushRaw(_ text: String) async { await queue.push(text) }

    /// The server hangs up (cleanly, or with an error).
    func hangUp(failing: Bool = false) async {
        failNextReceive = failing
        await queue.finish()
    }

    var setups: [LiveSetup] { sent.compactMap { if case .setup(let s) = $0 { s } else { nil } } }
    var toolResponses: [LiveToolResponse] { sent.compactMap { if case .toolResponse(let r) = $0 { r } else { nil } } }
    var audioChunks: [LiveBlob] {
        sent.compactMap { if case .realtimeInput(let input) = $0 { input.audio } else { nil } }
    }
    var streamEnds: Int {
        sent.filter { if case .realtimeInput(let input) = $0 { input.audioStreamEnd == true } else { false } }.count
    }
    var texts: [String] {
        sent.compactMap { if case .clientContent(let c) = $0 { c.turns.first?.parts.first?.text } else { nil } }
    }
}

/// Runs tools only when the test opens the gate.
actor GatedTools: ZenoToolExecutor {
    private var gate: CheckedContinuation<Void, Never>?
    private var open = false
    private(set) var calls: [String] = []

    func call(_ name: String, args: JSONValue) async -> ToolOutcome {
        calls.append(name)
        if !open { await withCheckedContinuation { gate = $0 } }
        return ToolOutcome(result: ["ok": true, "tool": .string(name)])
    }

    func release() {
        open = true
        gate?.resume()
        gate = nil
    }

    var waiting: Bool { gate != nil }
}

/// Records a session's events as they arrive and waits for the ones a test expects.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [VoiceEvent] = []
    private var done = false

    init(_ stream: AsyncStream<VoiceEvent>) {
        Task {
            for await event in stream { self.lock.withLock { self.recorded.append(event) } }
            self.lock.withLock { self.done = true }
        }
    }

    var events: [VoiceEvent] { lock.withLock { recorded } }
    var finished: Bool { lock.withLock { done } }

    var states: [VoiceState] { events.compactMap { if case .state(let s) = $0 { s } else { nil } } }

    /// Waits (up to 3 s) until `condition` holds over the events so far.
    @discardableResult
    func wait(_ what: Comment = "events", until condition: ([VoiceEvent]) -> Bool) async -> Bool {
        for _ in 0..<3_000 {
            if condition(events) { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for \(what); got \(events)")
        return false
    }

    func waitForFinish() async {
        for _ in 0..<3_000 where !finished { try? await Task.sleep(for: .milliseconds(1)) }
        if !finished { Issue.record("The event stream never finished") }
    }
}

/// Polls an async condition (up to 3 s).
func eventually(_ what: Comment = "condition", _ condition: @Sendable () async -> Bool) async {
    for _ in 0..<3_000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for \(what)")
}
