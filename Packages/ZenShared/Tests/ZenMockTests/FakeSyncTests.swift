// The fakes: FakeSync runs the real combine on every publish; FakeScores streams the demo day and
// can add a second device; FakeAuth pairs and signs out.
import Foundation
import Testing
import ZenAPI
import ZenLogic
@testable import ZenMock

/// A clock tests move by hand, readable from any isolation.
final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

enum Demo {
    /// 2026-11-20T06:30:00Z, a Friday, noon in India.
    static let now = Date(timeIntervalSince1970: 1_795_156_200)
    static let today = "2026-11-20"
    static let india = TimeZone(identifier: "Asia/Kolkata")!
    static let mac = String(repeating: "a", count: 32)
    static let studio = String(repeating: "b", count: 32)

    static func computer(_ id: String = mac, minutes: Int, pullBacks: Int = 0, sequence: Int64 = 1,
                         day: DayKey = today) -> ComputerDayReport {
        ComputerDayReport(deviceId: id, day: day, countedMinutes: minutes, pullBacks: pullBacks, promiseMinutes: 240, sequence: sequence)
    }

    static func iPhone(_ tenths: Int, day: DayKey = today) -> PhoneDayReport {
        PhoneDayReport(platform: .ios, day: day, score: ZenScore(tenths: tenths))
    }

    static func sync(_ clock: TestNow = TestNow(now), this: String? = mac, deviceLimit: Int = 2) -> FakeSync {
        FakeSync(thisDeviceId: this, deviceLimit: deviceLimit, timeZone: india, now: { clock.now })
    }
}

/// Collects a stream's values in the background.
final class Collected<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Value] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Value>) {
        task = Task { [weak self] in
            for await value in stream { self?.lock.withLock { self?._values.append(value) } }
        }
    }

    var values: [Value] { lock.withLock { _values } }

    func cancel() { task?.cancel() }

    /// Waits (briefly) until `count` values have arrived.
    func wait(for count: Int) async -> [Value] {
        let deadline = ContinuousClock.now + .seconds(2)
        while values.count < count, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        return values
    }
}

struct FakeSyncTests {
    @Test func nothingPublishedReadsAsAnUntouchedDay() async throws {
        let snapshot = try await Demo.sync().today()
        #expect(snapshot.score == ZenScoreRule.untouchedDay)
        #expect(snapshot.devices.isEmpty)
        #expect(snapshot.week.todayIndex == 4)
    }

    @Test func lowestScoreWinsAcrossThePhoneAndTheMac() async throws {
        let sync = Demo.sync()
        try await sync.publish(computer: Demo.computer(minutes: 38, pullBacks: 4))
        #expect(try await sync.today().score == CombineRule.ownScore(Demo.computer(minutes: 38, pullBacks: 4)))
        try await sync.publish(phone: Demo.iPhone(81))
        let snapshot = try await sync.today()
        #expect(snapshot.score == ZenScore(tenths: 81))
        #expect(snapshot.devices.map(\.name) == ["iPhone", "This Mac"])
        #expect(snapshot.devices.map(\.detail) == ["Counted on the phone", "38 m distracting · 4 pull-backs"])
        // A heavy Mac day drags the account under the phone's 8.1.
        try await sync.publish(computer: Demo.computer(minutes: 400, pullBacks: 4, sequence: 2))
        #expect(try await sync.today().score < ZenScore(tenths: 81))
    }

    @Test func theCombinedDayCarriesNoMinutesOnceAnIPhoneCounts() async throws {
        let sync = Demo.sync()
        try await sync.publish(computer: Demo.computer(minutes: 42))
        #expect(await sync.combinedDay()?.minutes == 42)
        try await sync.publish(phone: Demo.iPhone(75))
        let combined = try #require(await sync.combinedDay())
        #expect(combined.scoreOnly)
        #expect(combined.minutes == nil)
    }

    @Test func anOlderSequenceNeverReplacesANewerOne() async throws {
        let sync = Demo.sync()
        try await sync.publish(computer: Demo.computer(minutes: 50, sequence: 5))
        try await sync.publish(computer: Demo.computer(minutes: 10, sequence: 4))
        #expect(await sync.combinedDay()?.minutes == 50)
    }

    @Test func theFreePlanCountsTheNewestComputerOnly() async throws {
        let clock = TestNow(Demo.now)
        let sync = Demo.sync(clock)
        try await sync.publish(computer: Demo.computer(Demo.mac, minutes: 300))
        clock.advance(60)
        try await sync.publish(computer: Demo.computer(Demo.studio, minutes: 20))
        #expect(await sync.combinedDay()?.minutes == 20)
        #expect(try await sync.today().devices.map(\.name) == ["Mac"]) // this Mac didn't count
        await sync.setDeviceLimit(3)
        #expect(await sync.combinedDay()?.minutes == 320)
        #expect(try await sync.today().devices.map(\.name) == ["This Mac", "Mac"])
    }

    @Test func badReportsAreRejectedLikeTheBackendDoes() async {
        let sync = Demo.sync()
        let android = PhoneDayReport(platform: .android, day: Demo.today, score: ZenScore(tenths: 70), minutes: 2_000)
        await #expect(throws: SyncError.rejected) { try await sync.publish(phone: android) }
        await #expect(throws: SyncError.rejected) {
            try await sync.publish(phone: PhoneDayReport(platform: .macos, day: Demo.today, score: ZenScore(tenths: 70)))
        }
        await #expect(throws: SyncError.rejected) { try await sync.publish(phone: Demo.iPhone(20)) }
        await #expect(throws: SyncError.rejected) { try await sync.publish(phone: Demo.iPhone(70, day: "2026-11-22")) }
        await #expect(throws: SyncError.rejected) { try await sync.publish(computer: Demo.computer("not-hex", minutes: 1)) }
        await #expect(throws: SyncError.rejected) { try await sync.publish(computer: Demo.computer(minutes: 1_501)) }
        await #expect(throws: SyncError.rejected) {
            try await sync.publish(computer: ComputerDayReport(deviceId: Demo.mac, platform: .ios, day: Demo.today, countedMinutes: 1,
                                                               pullBacks: 0, promiseMinutes: 240, sequence: 1))
        }
        await #expect(throws: SyncError.rejected) {
            try await sync.publish(computer: ComputerDayReport(deviceId: Demo.mac, day: Demo.today, countedMinutes: 1,
                                                               pullBacks: 0, promiseMinutes: 90, sequence: 1))
        }
        #expect(await sync.combinedDay() == nil)
    }

    @Test func offlineAndSignedOutThrowTheContractsErrors() async throws {
        let sync = Demo.sync()
        await sync.setOffline(true)
        await #expect(throws: SyncError.offline) { try await sync.publish(phone: Demo.iPhone(70)) }
        await #expect(throws: SyncError.offline) { try await sync.today() }
        await sync.setOffline(false)
        try await sync.publish(phone: Demo.iPhone(70))
        await sync.setSignedIn(false)
        await #expect(throws: SyncError.signedOut) { try await sync.publish(phone: Demo.iPhone(70)) }
        await sync.setSignedIn(true)
        #expect(await sync.combinedDay() == nil) // signing out forgot the devices
    }

    @Test func theComputerCapIsSixteen() async throws {
        let sync = Demo.sync()
        let hex = Array("0123456789abcdef")
        for i in 0..<FakeSync.maxComputers {
            try await sync.publish(computer: Demo.computer(String(repeating: hex[i], count: 32), minutes: 1))
        }
        await #expect(throws: SyncError.rejected) {
            try await sync.publish(computer: Demo.computer(String(repeating: "0", count: 31) + "1", minutes: 1))
        }
    }

    @Test func aPhoneGoesStaleAfterEighteenHours() async throws {
        let clock = TestNow(Demo.now)
        let sync = Demo.sync(clock)
        try await sync.publish(phone: Demo.iPhone(81))
        clock.advance(18 * 3_600 + 1)
        #expect(await sync.combinedDay() == nil)
    }

    @Test func everyPublishStreamsANewSnapshot() async throws {
        let sync = Demo.sync()
        let updates = Collected(sync.updates())
        _ = await updates.wait(for: 1)
        try await sync.publish(computer: Demo.computer(minutes: 38, pullBacks: 4))
        try await sync.publish(phone: Demo.iPhone(70))
        let values = await updates.wait(for: 3)
        #expect(values.count == 3)
        #expect(values.map(\.devices.count) == [0, 1, 2])
        #expect(values.last?.score == ZenScore(tenths: 70))
        updates.cancel()
    }

    @Test func aStreamThatEndsUnsubscribes() async throws {
        let sync = Demo.sync()
        let updates = Collected(sync.updates())
        _ = await updates.wait(for: 1)
        #expect(await sync.subscriberCount == 1)
        updates.cancel()
        let deadline = ContinuousClock.now + .seconds(2)
        while await sync.subscriberCount > 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await sync.subscriberCount == 0)
    }

    @Test func theCombinedDayFillsTheWeek() async throws {
        let clock = TestNow(Demo.now)
        let sync = FakeSync(thisDeviceId: Demo.mac, history: FakeSync.demoWeek(before: Demo.today), streakBefore: 9,
                            timeZone: Demo.india, now: { clock.now })
        try await sync.publish(phone: Demo.iPhone(81))
        let week = try await sync.today().week
        #expect(week.days == [72, 58, 81, 54, 81, nil, nil].map { $0.map(ZenScore.init(tenths:)) })
        #expect(week.statusLine == "3 of 4 good days · one more wins the week")
    }

    @Test func theSimulatorsStandInForTheOtherDevices() async throws {
        let sync = Demo.sync(this: ScoreSnapshotBuilder.phoneLineId, deviceLimit: 3)
        try await sync.simulatePhone(score: 81)
        try await sync.simulateComputer(minutes: 30)
        let snapshot = try await sync.simulateComputer(minutes: 300) // the same computer, a newer sequence
        #expect(await sync.combinedDay()?.devices.count == 2)
        #expect(snapshot.devices.first?.name == "This iPhone")
        #expect(snapshot.score < ZenScore(tenths: 81))
    }

    @Test func theDemoIsSeededBeforeToday() async throws {
        let sync = FakeSync.demo(timeZone: Demo.india, now: { Demo.now })
        let week = try await sync.today().week
        #expect(week.streakBefore == 9)
        #expect(week.days.prefix(4).compactMap { $0?.tenths } == [72, 58, 81, 54])
        #expect(week.days[4] == nil)
        #expect(FakeSync.demoWeek(before: "2026-11-16").isEmpty) // Monday has no days before it
        #expect(FakeSync.demoWeek(before: "nonsense").isEmpty)
    }
}

struct FakeScoresTests {
    @Test func theStaticDemoIsUnchanged() {
        let snapshot = FakeScores.snapshot(now: Demo.now)
        #expect(snapshot.score == ZenScore(tenths: 81))
        #expect(snapshot.week.statusLine == "3 of 4 good days · one more wins the week")
        #expect(snapshot.devices.map(\.name) == ["Kamal's iPhone", "This Mac"])
    }

    @Test func theDemoMacsOwnNumbersAgreeWithTheDemoScore() {
        // This Mac alone scores above the phone's 8.1, so the combined 8.1 is the phone's.
        let mac = ZenScoreRule.score(minutes: FakeScores.macMinutes, pullBacks: FakeScores.macPullBacks,
                                     promiseMinutes: FakeScores.promiseMinutes)
        #expect(mac > ZenScore(tenths: FakeScores.phoneTenths))
    }

    @Test func updatesStartWithTheDemoThenFollowASecondDevice() async {
        let scores = FakeScores()
        let updates = Collected(scores.updates())
        _ = await updates.wait(for: 1)
        let added = scores.simulateSecondDevice()
        #expect(added.score == ZenScore(tenths: 65))
        #expect(added.devices.last?.detail == "4 h 20 m distracting · 3 pull-backs")
        #expect(added.week.days[4] == ZenScore(tenths: 65))
        let removed = scores.removeSecondDevice()
        #expect(removed.score == ZenScore(tenths: 81))
        let values = await updates.wait(for: 3)
        #expect(values.map(\.score.tenths) == [81, 65, 81])
        #expect(values.map(\.devices.count) == [2, 3, 2])
        updates.cancel()
    }

    @Test func aLightSecondDeviceLeavesThePhonesScore() async throws {
        let scores = FakeScores()
        #expect(scores.simulateSecondDevice(minutes: 10, pullBacks: 0).score == ZenScore(tenths: 81))
        #expect(try await scores.today().devices.count == 3)
    }
}

struct FakeAuthTests {
    @Test func thePhoneApprovesAPairingCode() async throws {
        let auth = FakeAuth()
        let code = try await auth.newPairingCode()
        try await auth.approvePairing(code: code.code)
        try await auth.signOut()
    }

    @Test func pairingCodesExpireInFiveMinutesAndOpenThePairLink() async throws {
        let code = try await FakeAuth().newPairingCode()
        #expect(code.expiresAt.timeIntervalSinceNow > 4 * 60)
        #expect(code.url.absoluteString.hasSuffix("/pair/K4M7QX"))
    }

    @Test func approvalArrivesForAFreshCode() async throws {
        let auth = FakeAuth(approvalDelay: .milliseconds(10))
        let user = try await auth.waitForApproval(of: try await auth.newPairingCode())
        #expect(user == ZenMock.demoUser)
        let expired = PairingCode(code: JoinCode("K4M7QX")!, expiresAt: Date().addingTimeInterval(-1))
        await #expect(throws: AuthError.codeExpired) { try await auth.waitForApproval(of: expired) }
    }
}
