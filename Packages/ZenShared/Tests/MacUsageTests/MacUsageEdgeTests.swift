// The Mac's tracker and publisher at their edges: sleeping across midnight, a lid closed for days,
// a clock set back over midnight, days that aren't 24 hours, and the publisher recovering after a
// refusal, a sign-out or a throttle that a forced send overtakes. Plus the wall clock itself.
import Foundation
import Testing
import ZenAPI
import ZenLogic
@testable import MacUsage

struct UsageTrackerDayRolloverTests {
    /// 23:40 on 2026-11-20 in India.
    static let lateEvening = Script.start + 13 * 3_600 + 40 * 60

    @Test func sleepingAcrossMidnightFinishesTheDayAtTheSleep() {
        var s = Script(frontmost: Script.youtube, at: Self.lateEvening)
        s.wait(10 * 60)
        s.send { .sleep(at: $0) }
        s.now += 30 * 60 // 00:20 on the 21st
        s.send { .wake(at: $0) }
        #expect(s.tracker.drainFinishedDays() == [UsageDay(day: "2026-11-20", distractingMillis: 600_000, pullBacks: 0)])
        // YouTube is on screen after the wake, but nobody is there until fresh input.
        s.wait(5 * 60)
        #expect(s.today == UsageDay(day: "2026-11-21", distractingMillis: 0, pullBacks: 0))
        s.send { .idleEnded(at: $0) }
        s.wait(10 * 60)
        #expect(s.today.countedMinutes == 10)
    }

    @Test func aLidClosedForDaysFinishesOnlyTheDayItWasUsed() {
        var s = Script(frontmost: Script.youtube)
        s.wait(10 * 60)
        // No events at all for two days and five hours: a sleep the app never heard about.
        s.now += 2 * 86_400 + 5 * 3_600
        s.send { .tick(at: $0) }
        #expect(s.tracker.drainFinishedDays() == [UsageDay(day: "2026-11-20", distractingMillis: 600_000, pullBacks: 0)])
        #expect(s.today == UsageDay(day: "2026-11-22", distractingMillis: 0, pullBacks: 0))
        #expect(!s.tracker.isCounting)
    }

    @Test func aClockSetBackOverMidnightNeverReopensYesterday() {
        var s = Script(frontmost: Script.youtube, at: Self.lateEvening)
        s.wait(25 * 60) // 00:05 on the 21st
        #expect(s.tracker.drainFinishedDays().map(\.day) == ["2026-11-20"])
        // The clock jumps back to 23:58 on the 20th.
        s.tracker.handle(.tick(at: s.now - 7 * 60))
        s.tracker.handle(.appActivated(Script.vlc, at: s.now - 6 * 60))
        #expect(s.tracker.drainFinishedDays().isEmpty)
        #expect(s.tracker.today(now: s.now).day == "2026-11-21")
        #expect(s.tracker.today(now: s.now).countedMinutes == 5)
    }

    @Test func aDayThatEndsWhileIdleFinishesWithWhatCountedBeforeIdle() {
        var s = Script(frontmost: Script.youtube, at: Self.lateEvening)
        s.wait(5 * 60)
        s.send { .idleStarted(at: $0) }
        s.wait(30 * 60) // past midnight, still idle
        #expect(s.tracker.drainFinishedDays() == [UsageDay(day: "2026-11-20", distractingMillis: 300_000, pullBacks: 0)])
        #expect(s.today.distractingMillis == 0)
    }

    @Test func aFallBackDayHoldsTwentyFiveHours() {
        // New York leaves daylight time on 2026-11-01: that day is 25 hours long.
        let newYork = TimeZone(identifier: "America/New_York")!
        let midnight = LocalDate(year: 2026, month: 11, day: 1).startOfDay(in: newYork)
        var tracker = UsageTracker(timeZone: newYork, startingAt: midnight, frontmost: Script.youtube)
        var now = midnight
        let end = LocalDate(year: 2026, month: 11, day: 2).startOfDay(in: newYork)
        #expect(end.timeIntervalSince(midnight) == 25 * 3_600)
        while now < end {
            now += 5
            tracker.handle(.tick(at: now))
        }
        let finished = tracker.drainFinishedDays()
        #expect(finished == [UsageDay(day: "2026-11-01", distractingMillis: 25 * 3_600_000, pullBacks: 0)])
        // The report clamps to the contract's 1500 minutes, which a 25-hour day exactly fills.
        let report = ComputerDayReportBuilder(store: InMemoryKeyValueStore()).report(for: finished[0])
        #expect(report.countedMinutes == ComputerDayReportBuilder.maxCountedMinutes)
    }

    @Test func aSpringForwardDaySplitsAtItsOwnMidnight() {
        // A session across midnight before a 23-hour day splits by real elapsed time.
        let newYork = TimeZone(identifier: "America/New_York")!
        let start = LocalDate(year: 2026, month: 3, day: 8).startOfDay(in: newYork) - 10 * 60
        var s = Script(frontmost: Script.youtube, at: start)
        s.tracker = UsageTracker(timeZone: newYork, startingAt: start, frontmost: Script.youtube)
        s.wait(20 * 60)
        #expect(s.tracker.drainFinishedDays() == [UsageDay(day: "2026-03-07", distractingMillis: 600_000, pullBacks: 0)])
        #expect(s.today == UsageDay(day: "2026-03-08", distractingMillis: 600_000, pullBacks: 0))
        #expect(LocalDate(year: 2026, month: 3, day: 9).startOfDay(in: newYork)
            .timeIntervalSince(LocalDate(year: 2026, month: 3, day: 8).startOfDay(in: newYork)) == 23 * 3_600)
    }

    @Test func pullBacksStartAgainEachDay() {
        var s = Script(frontmost: Script.youtube, at: Self.lateEvening)
        s.wait(5 * 60)
        s.open(Script.xcode)
        s.wait(60)
        s.open(Script.youtube) // 23:46: a pull-back on the 20th
        s.wait(15 * 60)
        let finished = s.tracker.drainFinishedDays()
        #expect(finished.map(\.pullBacks) == [1])
        #expect(s.today.pullBacks == 0)
    }
}

@MainActor
struct MacDaySyncRecoveryTests {
    private func make(_ days: RecordingDays = RecordingDays(), clock: ManualClock = ManualClock(),
                      builder: ComputerDayReportBuilder = SyncFixtures.builder()) -> (MacDaySync, RecordingDays, ManualClock) {
        (MacDaySync(days: days, builder: builder, clock: clock), days, clock)
    }

    @Test func aRefusalDoesNotBlockTheNextChange() async {
        let days = RecordingDays()
        days.failWith = .rejected
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(sync.status == .rejected)
        days.failWith = nil
        clock.advance(30)
        sync.submit(SyncFixtures.day(11))
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [11])
        #expect(sync.status == .upToDate(at: clock.now))
    }

    @Test func afterASignOutTheNextSubmitGoesOutAgain() async {
        let days = RecordingDays()
        days.failWith = .signedOut
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        #expect(sync.status == .signedOut)
        days.failWith = nil
        clock.advance(30)
        sync.submit(SyncFixtures.day(12), force: true)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [12])
        #expect(sync.publishCount == 1)
    }

    @Test func numbersPastTheContractsBoundsAreNoChangeOnceSentClamped() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(1_600, pullBacks: 1_200))
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [1_500])
        #expect(days.computers.map(\.pullBacks) == [1_000])
        clock.advance(60)
        sync.submit(SyncFixtures.day(1_700, pullBacks: 1_300))
        await sync.settle()
        #expect(days.computers.count == 1)
    }

    @Test func aThrottledSendIsOvertakenByAForcedOneAndNeverSentTwice() async {
        let (sync, days, clock) = make()
        sync.submit(SyncFixtures.day(10))
        await sync.settle()
        clock.advance(5)
        sync.submit(SyncFixtures.day(11))
        #expect(sync.status == .waiting(until: SyncFixtures.now + 30))
        sync.flush() // the app came to the foreground
        await sync.settle()
        clock.advance(120)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 11])
        #expect(clock.pendingCount == 0)
    }

    @Test func onlyTheNewestCountOfADayWaitsWhileOneIsInFlight() async {
        let (sync, days, _) = make()
        sync.submit(SyncFixtures.day(10))
        // While the first is in flight, three newer counts of the same day arrive.
        sync.submit(SyncFixtures.day(11), force: true)
        sync.submit(SyncFixtures.day(12), force: true)
        sync.submit(SyncFixtures.day(13), force: true)
        await sync.settle()
        #expect(days.computers.map(\.countedMinutes) == [10, 13])
    }

    @Test func daysQueuedOfflineGoOldestFirstWithGrowingSequences() async {
        let days = RecordingDays()
        days.failWith = .offline
        let (sync, _, clock) = make(days)
        sync.submit(SyncFixtures.day(30, on: "2026-11-18"), force: true)
        await sync.settle()
        sync.submit(SyncFixtures.day(20, on: SyncFixtures.today), force: true)
        await sync.settle()
        sync.submit(SyncFixtures.day(40, on: "2026-11-19"), force: true)
        await sync.settle()
        days.failWith = nil
        for _ in 0..<6 {
            clock.advance(60)
            await sync.settle()
        }
        #expect(days.computers.map(\.day) == ["2026-11-18", "2026-11-19", SyncFixtures.today])
        let sequences = days.computers.map(\.sequence)
        #expect(sequences == sequences.sorted() && Set(sequences).count == sequences.count)
        #expect(sync.lastPublished?.day == SyncFixtures.today)
    }
}

@MainActor
struct SystemClockTests {
    @Test func scheduledWorkRunsAfterItsDelay() async throws {
        let clock = SystemClock()
        var ran = 0
        clock.schedule(after: 0.01) { ran += 1 }
        clock.schedule(after: -5) { ran += 10 } // a past time runs at once
        for _ in 0..<200 where ran < 11 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(ran == 11)
        #expect(abs(clock.now.timeIntervalSinceNow) < 1)
    }

    @Test func cancelledWorkNeverRuns() async throws {
        let clock = SystemClock()
        var ran = false
        let work = clock.schedule(after: 0.02) { ran = true }
        work.cancel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(!ran)
    }
}
