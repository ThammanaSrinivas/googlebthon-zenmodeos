import Foundation
import Testing
import ZenAPI
@testable import ZenFocus

/// A hook that records what ran and can fail, hang or be unset.
final class FakeHook: FocusHook, @unchecked Sendable {
    enum Mode { case works, throwsError, hangs, hangsIgnoringCancel, notSetUp, off }
    let id: String
    var displayName: String { id.capitalized }
    let mode: Mode
    let endMode: Mode
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    private var _finished = false
    /// A hang that ignores cancellation got to its end.
    var finished: Bool { lock.withLock { _finished } }
    /// Shared by hooks in one test: how many were inside a call at once, at most.
    let gauge: Gauge?

    init(_ id: String, _ mode: Mode = .works, end: Mode? = nil, gauge: Gauge? = nil) {
        self.id = id
        self.mode = mode
        self.endMode = end ?? mode
        self.gauge = gauge
    }

    func status() async -> HookStatus {
        switch mode {
        case .notSetUp: .needsSetup("Set me up")
        case .off: .off
        default: .ready
        }
    }

    func onFocusStart(_ session: FocusBlock) async throws {
        lock.withLock { _calls.append("start") }
        try await act(mode)
    }

    func onFocusEnd(_ session: FocusBlock, kept: Bool) async throws {
        lock.withLock { _calls.append(kept ? "end-kept" : "end-early") }
        try await act(endMode)
    }

    private func act(_ m: Mode) async throws {
        gauge?.enter()
        defer { gauge?.leave() }
        switch m {
        case .throwsError: throw HookFailure("boom")
        case .hangs: try await Task.sleep(for: .seconds(30))
        // Ignores cancellation without holding a thread of the shared pool (a blocking sleep
        // would starve every other test on a small CI runner).
        case .hangsIgnoringCancel:
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) { c.resume() }
            }
            lock.withLock { _finished = true }
        default: break
        }
    }
}

/// Counts calls in flight.
final class Gauge: @unchecked Sendable {
    private let lock = NSLock()
    private var now = 0
    private var _peak = 0
    var peak: Int { lock.withLock { _peak } }
    func enter() { lock.withLock { now += 1; _peak = max(_peak, now) } }
    func leave() { lock.withLock { now -= 1 } }
}

let t0 = Date(timeIntervalSince1970: 1_763_600_000)
func session(_ minutes: Double = 50) -> FocusBlock {
    FocusBlock(id: "s1", startAt: t0, until: t0.addingTimeInterval(minutes * 60), source: .manual)
}

@Suite("Hook runner")
struct HookRunnerTests {
    let fast = HookRunner(timeout: .milliseconds(150))

    @Test("Every ready hook starts, in parallel, and outcomes keep the hooks' order")
    func parallel() async {
        let gauge = Gauge()
        let hooks = (0..<4).map { FakeHook("h\($0)", .hangs, gauge: gauge) }
        let out = await HookRunner(timeout: .seconds(1)).start(session(), hooks: hooks)
        // All four were inside their calls at the same time: they ran together, not in turn.
        #expect(gauge.peak == 4)
        #expect(out.map(\.id) == ["h0", "h1", "h2", "h3"])
        #expect(out.allSatisfy { $0.state == .failed })
    }

    @Test("A failing hook is marked failed and the others still run")
    func failingHook() async {
        let hooks = [FakeHook("ok"), FakeHook("bad", .throwsError), FakeHook("ok2")]
        let out = await fast.start(session(), hooks: hooks)
        #expect(out.map(\.state) == [.on, .failed, .on])
        #expect(out[1].note == "boom")
    }

    @Test("A hook that isn't set up is skipped and never called")
    func skipped() async {
        let unset = FakeHook("unset", .notSetUp)
        let off = FakeHook("off", .off)
        let out = await fast.start(session(), hooks: [unset, off])
        #expect(out.map(\.state) == [.skipped, .skipped])
        #expect(out[0].note == "Set me up")
        #expect(unset.calls.isEmpty && off.calls.isEmpty)
    }

    @Test("The timeout holds even when a hook ignores cancellation")
    func timeoutIgnoringCancel() async {
        let stuck = FakeHook("stuck", .hangsIgnoringCancel)
        let out = await fast.start(session(), hooks: [stuck])
        // The hook holds on for 10 s whatever happens; the runner has already answered without it
        // (no wall-clock bound, so a busy CI runner can't make this flaky).
        #expect(!stuck.finished)
        #expect(out.first?.state == .failed)
        #expect(out.first?.note == "Took too long")
    }

    @Test("End runs for hooks that started or failed, not for skipped ones")
    func endRunsForStarted() async {
        let ok = FakeHook("ok"), bad = FakeHook("bad", .throwsError, end: .works), unset = FakeHook("unset", .notSetUp)
        let hooks = [ok, bad, unset]
        let started = await fast.start(session(), hooks: hooks)
        let ended = await fast.end(session(), kept: false, hooks: hooks, started: started)
        #expect(ok.calls == ["start", "end-early"])
        #expect(bad.calls == ["start", "end-early"])
        #expect(unset.calls.isEmpty)
        #expect(ended.map(\.id) == ["ok", "bad"])
        #expect(ended.allSatisfy { $0.state == .on })
    }

    @Test("A failing end is reported and never throws")
    func failingEnd() async {
        let hooks = [FakeHook("a", .works, end: .throwsError), FakeHook("b")]
        let started = await fast.start(session(), hooks: hooks)
        let ended = await fast.end(session(), kept: true, hooks: hooks, started: started)
        #expect(ended.map(\.state) == [.failed, .on])
    }

    @Test("endAll (crash recovery) ends every ready hook")
    func endAll() async {
        let a = FakeHook("a"), b = FakeHook("b", .notSetUp)
        let out = await fast.endAll(session(), kept: true, hooks: [a, b])
        #expect(a.calls == ["end-kept"])
        #expect(out.map(\.state) == [.on, .skipped])
    }

    @Test("withDeadline returns the value, the error, or timedOut")
    func deadline() async {
        if case .finished(let v) = await withDeadline(.seconds(1), { 7 }) { #expect(v == 7) } else { Issue.record("expected a value") }
        let failed = await withDeadline(.seconds(1)) { () async throws -> Int in throw HookFailure("x") }
        if case .failed = failed {} else { Issue.record("expected failed") }
        let slow = await withDeadline(.milliseconds(50)) { () async throws -> Int in
            try await Task.sleep(for: .seconds(5)); return 1
        }
        if case .timedOut = slow {} else { Issue.record("expected timedOut") }
    }
}
