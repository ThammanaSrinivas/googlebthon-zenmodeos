// MacDaySync: throttled, forced, retried, and end to end through the fake backend.
import Foundation
import Testing
import ZenAPI
import ZenLogic
import ZenMock
@testable import MacUsage

/// A clock the test moves by hand: scheduled work runs inside `advance`.
@MainActor
final class ManualClock: SchedulingClock {
    final class Work: ScheduledWork {
        let at: Date
        let run: @MainActor () -> Void
        var cancelled = false
        init(at: Date, run: @escaping @MainActor () -> Void) { self.at = at; self.run = run }
        func cancel() { cancelled = true }
    }

    var now: Date
    private var queue: [Work] = []

    init(_ now: Date = SyncFixtures.now) { self.now = now }

    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = Work(at: now.addingTimeInterval(max(seconds, 0)), run: work)
        queue.append(item)
        return item
    }

    /// Moves time on, running what falls due in order.
    func advance(_ seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = queue.filter({ !$0.cancelled && $0.at <= end }).min(by: { $0.at < $1.at }) {
            queue.removeAll { $0 === next }
            now = next.at
            next.run()
        }
        now = end
    }

    var pendingCount: Int { queue.filter { !$0.cancelled }.count }
}

/// A DaySyncService that records publishes and fails on demand.
final class RecordingDays: DaySyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var _computers: [ComputerDayReport] = []
    private var _failWith: SyncError?
    private var _attempts = 0

    var computers: [ComputerDayReport] { lock.withLock { _computers } }
    var attempts: Int { lock.withLock { _attempts } }
    var failWith: SyncError? {
        get { lock.withLock { _failWith } }
        set { lock.withLock { _failWith = newValue } }
    }

    func publish(phone: PhoneDayReport) async throws(SyncError) { throw .rejected }

    func publish(computer: ComputerDayReport) async throws(SyncError) {
        let error = lock.withLock { () -> SyncError? in _attempts += 1; return _failWith }
        if let error { throw error }
        lock.withLock { _computers.append(computer) }
    }
}

enum SyncFixtures {
    /// 2026-11-20T06:30:00Z, noon in India.
    static let now = Date(timeIntervalSince1970: 1_795_156_200)
    static let today = "2026-11-20"

    static func day(_ minutes: Int, pullBacks: Int = 0, on day: DayKey = today) -> UsageDay {
        UsageDay(day: day, distractingMillis: minutes * 60_000, pullBacks: pullBacks)
    }

    static func builder() -> ComputerDayReportBuilder { ComputerDayReportBuilder(store: InMemoryKeyValueStore()) }
}

@MainActor
struct MacDaySyncTests {
    private func make(_ days: RecordingDays = RecordingDays(), clock: ManualClock = ManualClock(),
                      builder: ComputerDayReportBuilder = SyncFixtures.builder()) -> (MacDaySync, RecordingDays, ManualClock) {
        (MacDaySync(days: days, builder: builder, clock: clock), days, clock)
    }

    @Test func theFirstDayGoesAtOnce() async {
        let (sync, days, _) = make()
        sync.submit(SyncFixtures.day(10, pullBacks: 2))
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10])
        #expect(days.computers.map(\.pullBacks) == [2])
        #expect(days.computers.map(\.promiseMinutes) == [240])
        #expect(sync.status == .upToDate(at: SyncFixtures.now))
        #expect(sync.publishCount == 1)
        #expect(sync.lastPublished?.sequence == 1)
    }

    @Test func changesWithinThirtySecondsWaitAndOnlyTheNewestGoes() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        clock.advance(5)
        sync.submit(SyncFixtures.day(11))
        sync.submit(SyncFixtures.day(12))
        #expect(sync.status == .waiting(until: SyncFixtures.now + 30))
        clock.advance(24)
        await sync.settle()
        #expect(days.computers.count == 1)
        clock.advance(1)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 12])
        // Only sent reports take a sequence number.
        #expect(days.computers.map(\.sequence) == [1, 2])
    }

    @Test func anUnchangedDayIsNotSentAgain() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        clock.advance(60)
        // Seconds that don't make a whole minute are no change.
        sync.submit(UsageDay(day: SyncFixtures.today, distractingMillis: 10 * 60_000 + 30_000, pullBacks: 0))
        await sync.settle()
        #expect(days.computers.count == 1)
        #expect(clock.pendingCount == 0)
    }

    @Test func aNewPromiseIsAChange() async {
        let builder = SyncFixtures.builder()
        let (sync, days, clock) = make(builder: builder)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        clock.advance(60)
        builder.promiseHours = 6
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(days.computers.map(\.promiseMinutes) == [240, 360])
    }

    @Test func forceSkipsTheThrottle() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        clock.advance(1)
        sync.submit(SyncFixtures.day(11))
        sync.submit(SyncFixtures.day(12), force: true)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 12])
        #expect(clock.pendingCount == 0) // the throttle timer was cancelled
    }

    @Test func flushResendsTheLatestDayOnForeground() async {
        let (sync, days, _) = make()
        sync.flush() // nothing yet: nothing to send
        await sync.settle()
        #expect(days.attempts == 0)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        sync.flush()
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 10])
        #expect(days.computers.map(\.sequence) == [1, 2])
    }

    @Test func aFinishedDayGoesAtOnceAndTodayFollowsThrottled() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(40, on: "2026-11-19"))
        await sync.settle()
        clock.advance(10)
        // Midnight: the monitor hands over the finished day (forced), then the new one.
        sync.submit(SyncFixtures.day(45, on: "2026-11-19"), force: true)
        sync.submit(SyncFixtures.day(0, on: SyncFixtures.today))
        await sync.settle()
        #expect(days.computers.map(\.day) == ["2026-11-19", "2026-11-19"])
        clock.advance(30)
        await sync.settle()
        #expect(days.computers.map(\.day) == ["2026-11-19", "2026-11-19", SyncFixtures.today])
        #expect(days.computers.map(\.countedMinutes) == [40, 45, 0])
    }

    @Test func aFinishedDayIsNotLostWhileOffline() async {
        let days = RecordingDays()
        days.failWith = .offline
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(45, on: "2026-11-19"), force: true)
        await sync.settle()
        sync.submit(SyncFixtures.day(3, on: SyncFixtures.today))
        sync.submit(SyncFixtures.day(4, on: SyncFixtures.today))
        days.failWith = nil
        clock.advance(2)
        await sync.settle()
        clock.advance(30)
        await sync.settle()
        #expect(days.computers.map(\.day) == ["2026-11-19", SyncFixtures.today])
        #expect(days.computers.map(\.countedMinutes) == [45, 4])
    }

    @Test func offlineRetriesWithBackoffThenSucceeds() async {
        let days = RecordingDays()
        days.failWith = .offline
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(sync.status == .offline(retryAt: SyncFixtures.now + 2))
        clock.advance(2)
        await sync.settle()
        #expect(days.attempts == 2)
        #expect(sync.status == .offline(retryAt: SyncFixtures.now + 6))
        // A newer count while offline waits for the retry rather than going now.
        sync.submit(SyncFixtures.day(15))
        await sync.settle()
        #expect(days.attempts == 2)
        days.failWith = nil
        clock.advance(4)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [15])
        #expect(sync.status == .upToDate(at: SyncFixtures.now + 6))
    }

    @Test func theBackoffStopsGrowingAtAMinute() async {
        let days = RecordingDays()
        days.failWith = .unavailable
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        var waits: [TimeInterval] = []
        for _ in 0..<8 {
            guard case .offline(let at) = sync.status else { break }
            waits.append(at.timeIntervalSince(clock.now))
            clock.advance(at.timeIntervalSince(clock.now))
            await sync.settle()
        }
        #expect(waits == [2, 4, 8, 16, 30, 60, 60, 60])
    }

    @Test func aForcedSendCutsTheBackoffShort() async {
        let days = RecordingDays()
        days.failWith = .offline
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        days.failWith = nil
        sync.flush() // the app came to the foreground: try now
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10])
        #expect(clock.pendingCount == 0)
    }

    @Test func aRefusedReportIsNotRetried() async {
        let days = RecordingDays()
        days.failWith = .rejected
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(sync.status == .rejected)
        clock.advance(600)
        await sync.settle()
        #expect(days.attempts == 1)
    }

    @Test func signedOutDropsWhatWasWaiting() async {
        let days = RecordingDays()
        days.failWith = .signedOut
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(sync.status == .signedOut)
        clock.advance(600)
        #expect(clock.pendingCount == 0)
        // Signing in again forces the latest day out.
        days.failWith = nil
        sync.flush()
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10])
    }

    @Test func aDaySubmittedMidFlightFollowsIt() async {
        let (sync, days, _) = make()
        sync.submit(SyncFixtures.day(10))
        sync.submit(SyncFixtures.day(11), force: true) // the first is still in flight
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 11])
    }

    @Test func endToEndTheFakeBackendCombinesWhatTheMacSends() async throws {
        let builder = SyncFixtures.builder()
        let backend = FakeSync(thisDeviceId: builder.deviceId, timeZone: TimeZone(identifier: "Asia/Kolkata")!,
                               now: { SyncFixtures.now })
        let sync = MacDaySync(days: backend, builder: builder, clock: ManualClock())
        sync.submit(SyncFixtures.day(38, pullBacks: 4))
        await sync.settle()
        try await backend.publish(phone: PhoneDayReport(platform: .ios, day: SyncFixtures.today, score: ZenScore(tenths: 81)))
        let snapshot = try await backend.today()
        #expect(snapshot.score == ZenScore(tenths: 81)) // lowest wins: the Mac alone scores 9.5
        #expect(snapshot.devices.map(\.detail) == ["Counted on the phone", "38 m distracting · 4 pull-backs"])
        #expect(snapshot.devices.last?.isThisDevice == true)
    }
}
