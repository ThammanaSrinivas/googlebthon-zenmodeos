import Foundation
import Testing
import ZenAPI
@testable import ZenFocus

/// Records every write; can pretend to be signed out or hang (offline).
final class RecordingSync: FocusSyncService, @unchecked Sendable {
    enum Mode { case works, signedOut, hangs }
    private let lock = NSLock()
    private var _live: [LiveFocus] = []
    private var _records: [FocusRecord] = []
    private var _daily: [String: DailyFocus] = [:]
    var live: [LiveFocus] { lock.withLock { _live } }
    var records: [FocusRecord] { lock.withLock { _records } }
    var daily: [String: DailyFocus] { lock.withLock { _daily } }
    var mode: Mode
    init(_ mode: Mode = .works) { self.mode = mode }

    private func gate() async throws(FocusSyncError) {
        switch mode {
        case .works: return
        case .signedOut: throw .signedOut
        case .hangs: try? await Task.sleep(for: .seconds(30))
        }
    }
    func setLive(_ live: LiveFocus) async throws(FocusSyncError) {
        try await gate()
        lock.withLock { _live.append(live) }
    }
    func save(_ record: FocusRecord) async throws(FocusSyncError) {
        try await gate()
        lock.withLock { _records.append(record) }
    }
    func saveDaily(_ daily: DailyFocus, day: String) async throws(FocusSyncError) {
        try await gate()
        lock.withLock { _daily[day] = daily }
    }
    func saveWorkHours(_ hours: WorkHours) async throws(FocusSyncError) {}
    func liveFocus() -> AsyncStream<LiveFocus> { AsyncStream { $0.finish() } }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(minutes: Double) { lock.withLock { _now = _now.addingTimeInterval(minutes * 60) } }
}

@Suite("Focus engine")
struct FocusEngineTests {
    let ist = TimeZone(identifier: "Asia/Kolkata")!

    func engine(_ hooks: [any FocusHook], sync: RecordingSync?, store: MemoryFocusStore = MemoryFocusStore(), clock: Clock) -> FocusEngine {
        FocusEngine(runner: HookRunner(timeout: .milliseconds(200)), hooks: { hooks }, store: store,
                    sync: { sync }, now: { clock.now }, timeZone: ist)
    }

    @Test("Start runs the hooks and marks live focus; an on-time end keeps the block and writes the day")
    func keptBlock() async throws {
        let clock = Clock(t0)
        let sync = RecordingSync()
        let ok = FakeHook("dnd"), bad = FakeHook("slack", .throwsError, end: .works)
        let e = engine([ok, bad], sync: sync, clock: clock)
        let (s, outcomes) = await e.start(until: t0.addingTimeInterval(50 * 60), source: .manual)
        #expect(outcomes.map(\.state) == [.on, .failed])
        #expect(sync.live.last == LiveFocus(active: true, until: s.until))
        clock.advance(minutes: 50)
        let ended = try #require(await e.end())
        #expect(ended.record.kept)
        #expect(ended.record.hooks == ["dnd": .on, "slack": .failed])
        #expect(ended.record.focusedMin == 50)
        #expect(sync.live.last == .idle)
        #expect(sync.records.count == 1)
        #expect(sync.daily[ended.day] == DailyFocus(focusMin: 50, blocksStarted: 1, blocksKept: 1))
        #expect(ok.calls == ["start", "end-kept"])
        #expect(await e.active == nil)
    }

    @Test("An early stop is not kept, and still ends every hook")
    func earlyStop() async throws {
        let clock = Clock(t0)
        let hook = FakeHook("dnd")
        let e = engine([hook], sync: RecordingSync(), clock: clock)
        _ = await e.start(until: t0.addingTimeInterval(50 * 60), source: .voice)
        clock.advance(minutes: 20)
        let ended = try #require(await e.end())
        #expect(!ended.record.kept)
        #expect(ended.record.focusedMin == 20)
        #expect(ended.daily == DailyFocus(focusMin: 20, blocksStarted: 1, blocksKept: 0))
        #expect(hook.calls == ["start", "end-early"])
    }

    @Test("A failing hook never stops focus from starting")
    func failingNeverStops() async {
        let clock = Clock(t0)
        let e = engine([FakeHook("a", .throwsError), FakeHook("b", .hangs)], sync: nil, clock: clock)
        let (s, outcomes) = await e.start(until: t0.addingTimeInterval(25 * 60), source: .manual)
        #expect(outcomes.allSatisfy { $0.state == .failed })
        #expect(await e.active?.session == s)
    }

    @Test("After a crash, the next launch ends the block with every hook (kept if its time ran out)")
    func recoveryAfterCrash() async throws {
        let clock = Clock(t0)
        let store = MemoryFocusStore()
        let hook = FakeHook("slack")
        _ = await engine([hook], sync: RecordingSync(), store: store, clock: clock)
            .start(until: t0.addingTimeInterval(25 * 60), source: .manual)
        // The app dies; an hour later it launches again with a new engine on the same store.
        clock.advance(minutes: 60)
        let sync = RecordingSync()
        let relaunched = engine([hook], sync: sync, store: store, clock: clock)
        let ended = try #require(await relaunched.recover())
        #expect(ended.record.kept)
        #expect(ended.record.focusedMin == 25)
        #expect(hook.calls == ["start", "end-kept"])
        #expect(sync.live.last == .idle)
        #expect(await relaunched.recover() == nil)
    }

    @Test("A crash in the middle of the start still ends every hook on relaunch")
    func crashDuringStart() async throws {
        let clock = Clock(t0)
        let store = MemoryFocusStore()
        let s = FocusBlock(id: "x", startAt: t0, until: t0.addingTimeInterval(1500), source: .manual)
        store.set(try JSONEncoder().encode(ActiveFocus(session: s, started: [:])), forKey: FocusEngine.activeKey)
        let hook = FakeHook("dnd")
        clock.advance(minutes: 10)
        let ended = try #require(await engine([hook], sync: nil, store: store, clock: clock).recover())
        #expect(!ended.record.kept)
        #expect(hook.calls == ["end-early"])
    }

    @Test("Offline: writes give up after the deadline and focus still ends")
    func offline() async throws {
        let clock = Clock(t0)
        let e = FocusEngine(runner: HookRunner(timeout: .milliseconds(100)), hooks: { [] }, store: MemoryFocusStore(),
                            sync: { RecordingSync(.hangs) }, now: { clock.now }, timeZone: ist)
        // writeDeadline is 4 s; the engine must still come back.
        _ = await e.start(until: t0.addingTimeInterval(60), source: .manual)
        clock.advance(minutes: 1)
        #expect(try #require(await e.end()).record.kept)
    }

    @Test("Signed out: the session waits in the outbox and goes up after sign-in")
    func outbox() async throws {
        let clock = Clock(t0)
        let store = MemoryFocusStore()
        let sync = RecordingSync(.signedOut)
        let e = engine([], sync: sync, store: store, clock: clock)
        _ = await e.start(until: t0.addingTimeInterval(25 * 60), source: .manual)
        clock.advance(minutes: 25)
        _ = await e.end()
        #expect(sync.records.isEmpty)
        sync.mode = .works
        await e.flushOutbox()
        #expect(sync.records.count == 1)
        await e.flushOutbox()
        #expect(sync.records.count == 1)
    }

    @Test("Two blocks add up on the day; after-hours minutes add to the same day")
    func dayAddsUp() async throws {
        let clock = Clock(t0)
        let sync = RecordingSync()
        let e = engine([], sync: sync, clock: clock)
        _ = await e.start(until: clock.now.addingTimeInterval(25 * 60), source: .manual)
        clock.advance(minutes: 25)
        let first = try #require(await e.end())
        _ = await e.start(until: clock.now.addingTimeInterval(50 * 60), source: .plan)
        clock.advance(minutes: 10)
        _ = await e.end()
        await e.addAfterHours(minutes: 12, day: first.day)
        #expect(sync.daily[first.day] == DailyFocus(focusMin: 35, blocksStarted: 2, blocksKept: 1, afterHoursMin: 12))
    }

    @Test("The day's Zen Score is written once per change and kept with the focus numbers")
    func zenScore() async throws {
        let clock = Clock(t0)
        let sync = RecordingSync()
        let e = engine([], sync: sync, clock: clock)
        let day = await e.dayKey(t0)
        await e.setZenScore(72, day: day)
        await e.setZenScore(72, day: day)
        await e.setZenScore(10, day: day)
        #expect(sync.daily[day]?.zenScoreTenths == 72)
        _ = await e.start(until: t0.addingTimeInterval(25 * 60), source: .manual)
        clock.advance(minutes: 25)
        _ = await e.end()
        #expect(sync.daily[day] == DailyFocus(focusMin: 25, blocksStarted: 1, blocksKept: 1, zenScoreTenths: 72))
    }

    @Test("Starting twice returns the running block")
    func startTwice() async {
        let clock = Clock(t0)
        let e = engine([], sync: nil, clock: clock)
        let (a, _) = await e.start(until: t0.addingTimeInterval(600), source: .manual)
        let (b, _) = await e.start(until: t0.addingTimeInterval(9000), source: .manual)
        #expect(a == b)
    }

    @Test("Day keys are in the person's time zone (IST midnight)")
    func dayKey() async {
        let e = engine([], sync: nil, clock: Clock(t0))
        // 2026-11-19 18:30 UTC is 00:00 on 20 Nov in IST.
        let midnight = Date(timeIntervalSince1970: 1_795_113_000)
        #expect(await e.dayKey(midnight) == "2026-11-20")
        #expect(await e.dayKey(midnight.addingTimeInterval(-1)) == "2026-11-19")
    }

    @Test("DailyFocus clamps to what the rules accept")
    func clamps() {
        let d = DailyFocus(focusMin: 2000, blocksStarted: 3, blocksKept: 9, afterHoursMin: -4, zenScoreTenths: 12).clamped
        #expect(d == DailyFocus(focusMin: 1440, blocksStarted: 3, blocksKept: 3, afterHoursMin: 0, zenScoreTenths: 25))
    }

    @Test("A session's id matches the rules' pattern; planned minutes are clamped")
    func sessionShape() {
        let s = FocusBlock(startAt: t0, until: t0.addingTimeInterval(50 * 60), source: .manual)
        #expect(s.id.count <= 64 && s.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        #expect(s.plannedMin == 50)
        #expect(FocusBlock(startAt: t0, until: t0.addingTimeInterval(-60), source: .manual).plannedMin == 0)
        #expect(FocusBlock(startAt: t0, until: t0.addingTimeInterval(86_400), source: .manual).plannedMin == 720)
        #expect(LiveFocus(active: false, until: t0).until == nil)
        #expect(LiveFocus(active: true, until: t0).isFocusing(at: t0.addingTimeInterval(-1)))
        #expect(!LiveFocus(active: true, until: t0).isFocusing(at: t0.addingTimeInterval(1)))
    }
}
