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

    init(_ id: String, _ mode: Mode = .works, end: Mode? = nil) {
        self.id = id
        self.mode = mode
        self.endMode = end ?? mode
    }

    func status() async -> HookStatus {
        switch mode {
        case .notSetUp: .needsSetup("Set me up")
        case .off: .off
        default: .ready
        }
    }

    func onFocusStart(_ session: FocusSession) async throws {
        lock.withLock { _calls.append("start") }
        try await act(mode)
    }

    func onFocusEnd(_ session: FocusSession, kept: Bool) async throws {
        lock.withLock { _calls.append(kept ? "end-kept" : "end-early") }
        try await act(endMode)
    }

    private func act(_ m: Mode) async throws {
        switch m {
        case .throwsError: throw HookFailure("boom")
        case .hangs: try await Task.sleep(for: .seconds(30))
        case .hangsIgnoringCancel: usleep(1_000_000)
        default: break
        }
    }
}

let t0 = Date(timeIntervalSince1970: 1_763_600_000)
func session(_ minutes: Double = 50) -> FocusSession {
    FocusSession(id: "s1", startAt: t0, until: t0.addingTimeInterval(minutes * 60), source: .manual)
}

@Suite("Hook runner")
struct HookRunnerTests {
    let fast = HookRunner(timeout: .milliseconds(150))

    @Test("Every ready hook starts, in parallel, and outcomes keep the hooks' order")
    func parallel() async {
        let hooks = (0..<4).map { FakeHook("h\($0)", .hangs) }
        let clock = ContinuousClock()
        let start = clock.now
        let out = await fast.start(session(), hooks: hooks)
        // Four hooks that each hang hit their deadlines together, not one after another.
        #expect(clock.now - start < .milliseconds(450))
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
        let clock = ContinuousClock()
        let start = clock.now
        let out = await fast.start(session(), hooks: [FakeHook("stuck", .hangsIgnoringCancel)])
        #expect(clock.now - start < .milliseconds(700))
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
