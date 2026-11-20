// Combine v1, branch by branch. The shared vectors (CombineVectorsTests) hold the server to the
// same rule.
import Foundation
import Testing
import ZenAPI
@testable import ZenLogic

struct CombineRuleTests {
    static let A = String(repeating: "a", count: 32)
    static let B = String(repeating: "b", count: 32)
    static let C = String(repeating: "c", count: 32)
    /// 2026-11-20T06:30:00Z (noon in India).
    static let now = Date(timeIntervalSince1970: 1_795_156_200)
    static let today = "2026-11-20"
    static let hour: TimeInterval = 3_600

    static func phone(_ platform: DevicePlatform = .ios, day: DayKey = today, score: Int = 81, minutes: Int? = nil,
                      ago: TimeInterval = 60) -> PhoneDayInput {
        PhoneDayInput(report: PhoneDayReport(platform: platform, day: day, score: ZenScore(tenths: score), minutes: minutes),
                      writtenAt: now.addingTimeInterval(-ago))
    }

    static func computer(_ id: String = A, day: DayKey = today, minutes: Int = 60, pullBacks: Int = 0,
                         promiseHours: Int = 4, ago: TimeInterval = 30) -> ComputerDayInput {
        ComputerDayInput(report: ComputerDayReport(deviceId: id, day: day, countedMinutes: minutes, pullBacks: pullBacks,
                                                   promiseMinutes: promiseHours * 60, sequence: 1),
                         writtenAt: now.addingTimeInterval(-ago))
    }

    static func score(minutes: Int, pullBacks: Int = 0, promiseHours: Int = 4) -> Int {
        ZenScoreRule.compute(screenTimeMillis: minutes * 60_000, distractedSessions: pullBacks, promiseHours: promiseHours)
    }

    func combine(_ phone: PhoneDayInput?, _ computers: [ComputerDayInput], limit: Int = 2) -> CombinedDay? {
        CombineRule.combine(phone: phone, computers: computers, deviceLimit: limit, now: Self.now)
    }

    // ── No day ────────────────────────────────────────────────────

    @Test func noDevicesNoDay() {
        #expect(combine(nil, []) == nil)
    }

    @Test func aStalePhoneAloneDecidesNothing() {
        #expect(combine(Self.phone(ago: 19 * Self.hour), []) == nil)
    }

    @Test func aComputerPastItsWeekDecidesNothing() {
        #expect(combine(nil, [Self.computer(ago: 7 * 86_400 + 1)]) == nil)
    }

    // ── The phone alone ───────────────────────────────────────────

    @Test func aFreshIPhoneAloneIsItsOwnScoreAndScoreOnly() throws {
        let day = try #require(combine(Self.phone(score: 81), []))
        #expect(day.day == Self.today)
        #expect(day.score.tenths == 81)
        #expect(day.scoreOnly)
        #expect(day.minutes == nil)
        #expect(day.updatedAt == Self.now)
        #expect(day.devices == [DeviceContribution(kind: .phone, platform: .ios, counted: true, score: ZenScore(tenths: 81),
                                                   lastSeen: Self.now.addingTimeInterval(-60))])
    }

    @Test func aFreshAndroidPhoneShowsItsMinutes() throws {
        let day = try #require(combine(Self.phone(.android, score: 74, minutes: 200), []))
        #expect(day.score.tenths == 74)
        #expect(!day.scoreOnly)
        #expect(day.minutes == 200)
        #expect(day.devices.first?.minutes == 200)
    }

    @Test func anAndroidPhoneWithoutMinutesShowsNone() throws {
        let day = try #require(combine(Self.phone(.android, score: 74, minutes: nil), []))
        #expect(day.minutes == nil)
        #expect(!day.scoreOnly)
    }

    @Test func anIPhoneNeverCarriesMinutesEvenIfGivenSome() {
        #expect(Self.phone(.ios, minutes: 300).report.minutes == nil)
    }

    // ── The phone and a computer ──────────────────────────────────

    @Test func theLowerOfPhoneAndComputerWins() throws {
        // 6 h of distraction on a 4 h promise scores well under the phone's 8.1.
        let low = try #require(combine(Self.phone(score: 81), [Self.computer(minutes: 360)]))
        #expect(low.score.tenths == Self.score(minutes: 360))
        #expect(low.score.tenths < 81)
        // An idle computer scores 10; the phone's 6.5 stands.
        let high = try #require(combine(Self.phone(score: 65), [Self.computer(minutes: 0)]))
        #expect(high.score.tenths == 65)
    }

    @Test func anIPhoneThatCountsHidesTheComputersMinutes() throws {
        let day = try #require(combine(Self.phone(.ios), [Self.computer(minutes: 42)]))
        #expect(day.scoreOnly)
        #expect(day.minutes == nil)
        // The computer's own row may still show its own minutes, on its own device.
        #expect(day.devices.last?.minutes == 42)
    }

    @Test func anAndroidPhonesMinutesAddToTheComputers() throws {
        let day = try #require(combine(Self.phone(.android, score: 100, minutes: 100), [Self.computer(minutes: 50, pullBacks: 2)]))
        #expect(day.minutes == 150)
        #expect(day.score.tenths == Self.score(minutes: 150, pullBacks: 2))
        #expect(!day.scoreOnly)
    }

    @Test func aStalePhoneLeavesTheDayToTheComputer() throws {
        let day = try #require(combine(Self.phone(.ios, day: "2026-11-19", score: 30, ago: 20 * Self.hour), [Self.computer(minutes: 42)]))
        #expect(day.day == Self.today)
        #expect(day.score.tenths == Self.score(minutes: 42))
        #expect(!day.scoreOnly)
        #expect(day.minutes == 42)
        #expect(day.devices.first { $0.kind == .phone }?.counted == false)
    }

    @Test func aComputerOnAnotherDayThanTheFreshPhoneDoesNotCount() throws {
        let day = try #require(combine(Self.phone(score: 81), [Self.computer(day: "2026-11-19", minutes: 600)]))
        #expect(day.score.tenths == 81)
        #expect(day.devices.first { $0.kind == .computer }?.counted == false)
    }

    @Test func theFreshPhoneDecidesTheDayEvenWhenAComputerIsAhead() throws {
        let day = try #require(combine(Self.phone(day: "2026-11-19", score: 70), [Self.computer(day: Self.today, minutes: 600)]))
        #expect(day.day == "2026-11-19")
        #expect(day.score.tenths == 70)
    }

    // ── Freshness and places, at their edges ──────────────────────

    @Test func freshnessIncludesItsEdge() {
        #expect(CombineRule.isFresh(Self.phone(ago: 18 * Self.hour), now: Self.now))
        #expect(!CombineRule.isFresh(Self.phone(ago: 18 * Self.hour + 1), now: Self.now))
        #expect(CombineRule.isFresh(Self.phone(ago: -300), now: Self.now)) // a clock ahead
    }

    @Test func aPlaceIsHeldForExactlyAWeek() {
        let edge = Self.computer(ago: 7 * 86_400)
        let past = Self.computer(Self.B, ago: 7 * 86_400 + 1)
        #expect(CombineRule.holders([edge, past], deviceLimit: 16, now: Self.now) == [edge])
    }

    @Test func theFreePlanCountsOnlyTheNewestComputer() throws {
        let older = Self.computer(Self.A, minutes: 300, ago: 600)
        let newer = Self.computer(Self.B, minutes: 30, ago: 60)
        let day = try #require(combine(nil, [older, newer], limit: 2))
        #expect(day.score.tenths == Self.score(minutes: 30))
        #expect(day.devices.map(\.deviceId) == [Self.A, Self.B])
        #expect(day.devices.map(\.counted) == [false, true])
    }

    @Test func aBiggerLimitSumsMinutesAndPullBacksAndTakesTheLargestPromise() throws {
        let a = Self.computer(Self.A, minutes: 100, pullBacks: 2, promiseHours: 3, ago: 60)
        let b = Self.computer(Self.B, minutes: 80, pullBacks: 3, promiseHours: 5, ago: 120)
        let day = try #require(combine(nil, [a, b], limit: 3))
        #expect(day.minutes == 180)
        #expect(day.score.tenths == Self.score(minutes: 180, pullBacks: 5, promiseHours: 5))
        #expect(day.countedDevices.count == 2)
    }

    @Test func aTieInWriteTimeGoesToTheLowerDeviceId() {
        let b = Self.computer(Self.B, ago: 60)
        let a = Self.computer(Self.A, ago: 60)
        #expect(CombineRule.holders([b, a], deviceLimit: 2, now: Self.now) == [a])
    }

    @Test func aLimitOfOneOrLessLeavesTheComputersNoPlace() {
        #expect(CombineRule.computerSlots(deviceLimit: 1) == 0)
        #expect(CombineRule.computerSlots(deviceLimit: 0) == 0)
        #expect(CombineRule.computerSlots(deviceLimit: -3) == 0)
        #expect(combine(nil, [Self.computer()], limit: 1) == nil)
    }

    @Test func theLatestHolderDayIsTheDay() throws {
        let yesterday = Self.computer(Self.A, day: "2026-11-19", minutes: 500, ago: 60)
        let today = Self.computer(Self.B, day: Self.today, minutes: 20, ago: 3_600)
        let day = try #require(combine(nil, [yesterday, today], limit: 3))
        #expect(day.day == Self.today)
        #expect(day.minutes == 20)
    }

    @Test func aDayNoTimeZoneHasReachedIsIgnored() throws {
        // At 06:30 UTC on the 20th, UTC+14 is 20:30 on the 20th: the 21st is a wrong clock.
        #expect(DayKeys.latestAllowed(now: Self.now) == Self.today)
        let wrongClock = Self.computer(Self.A, day: "2026-11-21", minutes: 500, ago: 60)
        let honest = Self.computer(Self.B, day: Self.today, minutes: 20, ago: 120)
        let day = try #require(combine(nil, [wrongClock, honest], limit: 3))
        #expect(day.day == Self.today)
        #expect(day.minutes == 20)
        #expect(combine(nil, [wrongClock], limit: 3) == nil)
    }

    @Test func devicesListThePhoneThenEveryComputerByDeviceId() throws {
        let stale = Self.computer(Self.C, ago: 8 * 86_400)
        let day = try #require(combine(Self.phone(), [stale, Self.computer(Self.A, ago: 30)], limit: 2))
        #expect(day.devices.map(\.kind) == [.phone, .computer, .computer])
        #expect(day.devices.map(\.deviceId) == [nil, Self.A, Self.C])
        #expect(day.devices.map(\.counted) == [true, true, false])
        #expect(day.devices[1].score == CombineRule.ownScore(Self.computer().report))
        #expect(day.devices[1].pullBacks == 0)
        #expect(day.devices[0].pullBacks == nil)
    }

    @Test func aComputersOwnScoreIsItsMinutesAgainstItsPromise() {
        let report = Self.computer(minutes: 300, pullBacks: 4, promiseHours: 2).report
        #expect(CombineRule.ownScore(report).tenths == Self.score(minutes: 300, pullBacks: 4, promiseHours: 2))
    }

    @Test func theDefaultLimitIsTheFreePlans() throws {
        let day = try #require(CombineRule.combine(phone: nil, computers: [Self.computer(Self.A, ago: 10), Self.computer(Self.B, ago: 20)], now: Self.now))
        #expect(day.countedDevices.map(\.deviceId) == [Self.A])
    }
}
