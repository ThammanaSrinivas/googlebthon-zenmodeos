// Combine v1 at its edges: the day boundary between a phone and a computer, a finished day sent
// at midnight, stale devices and the plan's places, and properties that must hold for any mix of
// devices (seeded, so a failure always replays).
import Foundation
import Testing
import ZenAPI
@testable import ZenLogic

struct CombineDayBoundaryTests {
    typealias C = CombineRuleTests
    static let india = TimeZone(identifier: "Asia/Kolkata")!
    static let tomorrow = "2026-11-21"
    static let yesterday = "2026-11-19"

    /// 2026-11-20T19:30:00Z: 01:00 on the 21st in India.
    static let afterMidnight = C.now.addingTimeInterval(13 * C.hour)

    static func phone(day: DayKey, score: Int, hoursAgo: Double) -> PhoneDayInput {
        PhoneDayInput(report: PhoneDayReport(platform: .ios, day: day, score: ZenScore(tenths: score)),
                      writtenAt: afterMidnight.addingTimeInterval(-hoursAgo * C.hour))
    }

    static func mac(day: DayKey, minutes: Int) -> ComputerDayInput {
        ComputerDayInput(report: ComputerDayReport(deviceId: C.A, day: day, countedMinutes: minutes, pullBacks: 0,
                                                   promiseMinutes: 240, sequence: 1),
                         writtenAt: afterMidnight.addingTimeInterval(-30))
    }

    @Test func aFreshPhoneKeepsItsDayWhileAComputerHasRolledPastMidnight() throws {
        // The phone last wrote for the 20th two hours ago; the Mac, past midnight, writes the 21st.
        let day = try #require(CombineRule.combine(phone: Self.phone(day: C.today, score: 70, hoursAgo: 2),
                                                   computers: [Self.mac(day: Self.tomorrow, minutes: 600)], now: Self.afterMidnight))
        #expect(day.day == C.today)
        #expect(day.score == ZenScore(tenths: 70))
        #expect(day.countedDevices.map(\.kind) == [.phone])
        #expect(day.devices.last?.counted == false) // still listed, not counted
    }

    @Test func onceThePhoneGoesStaleTheComputersNewDayDecides() throws {
        let day = try #require(CombineRule.combine(phone: Self.phone(day: C.today, score: 70, hoursAgo: 18.01),
                                                   computers: [Self.mac(day: Self.tomorrow, minutes: 60)], now: Self.afterMidnight))
        #expect(day.day == Self.tomorrow)
        #expect(day.score == ZenScore(tenths: C.score(minutes: 60)))
        #expect(day.devices.first?.kind == .phone)
        #expect(day.devices.first?.counted == false)
    }

    @Test func aFinishedDaySentAtMidnightDoesNotCountAgainstTheNewDay() throws {
        // 00:01 in India: the Mac forces out yesterday's final numbers; the phone is on today.
        let phone = C.phone(.android, day: C.today, score: 90, minutes: 5, ago: 60)
        let mac = C.computer(day: Self.yesterday, minutes: 900, ago: 10)
        let day = try #require(CombineRule.combine(phone: phone, computers: [mac], now: C.now))
        #expect(day.day == C.today)
        #expect(day.score == ZenScore(tenths: 90))
        #expect(day.minutes == 5) // only the Android phone's own minutes
    }

    @Test func withoutAPhoneTheFinishedDayDecidesUntilTodayIsWritten() throws {
        // The free plan's one place goes to the newest write, even when that is yesterday's final.
        let finished = C.computer(C.A, day: Self.yesterday, minutes: 300, ago: 10)
        let alone = try #require(CombineRule.combine(phone: nil, computers: [finished], now: C.now))
        #expect(alone.day == Self.yesterday)
        let today = C.computer(C.A, day: C.today, minutes: 2, ago: 5)
        let next = try #require(CombineRule.combine(phone: nil, computers: [today], now: C.now))
        #expect(next.day == C.today)
        #expect(next.score == ZenScore(tenths: C.score(minutes: 2)))
    }

    @Test func aPhoneStampedAheadOfTheServerClockIsFresh() {
        let ahead = C.phone(ago: -5 * 60)
        #expect(CombineRule.isFresh(ahead, now: C.now))
        #expect(CombineRule.combine(phone: ahead, computers: [], now: C.now)?.score == ZenScore(tenths: 81))
    }

    @Test func theLatestAllowedDayFollowsUTCPlusFourteenAcrossTheDateLine() {
        // 09:59:59 UTC on the 20th is 23:59:59 in Kiribati: the 21st isn't allowed yet.
        let beforeKiribatiMidnight = Date(timeIntervalSince1970: 1_795_168_799)
        #expect(DayKeys.latestAllowed(now: beforeKiribatiMidnight) == C.today)
        #expect(DayKeys.latestAllowed(now: beforeKiribatiMidnight + 1) == Self.tomorrow)
        let early = C.computer(day: Self.tomorrow, minutes: 10, ago: 0)
        #expect(CombineRule.combine(phone: nil, computers: [early], now: beforeKiribatiMidnight) == nil)
        #expect(CombineRule.combine(phone: nil, computers: [early], now: beforeKiribatiMidnight + 1)?.day == Self.tomorrow)
    }
}

struct CombineHolderTests {
    typealias C = CombineRuleTests

    @Test func aStaleComputerNeverTakesAFreshOnesPlace() throws {
        let stale = C.computer(C.A, minutes: 0, ago: 8 * 86_400)
        let fresh = C.computer(C.B, minutes: 120, ago: 30)
        let holders = CombineRule.holders([stale, fresh], deviceLimit: 2, now: C.now)
        #expect(holders.map(\.report.deviceId) == [C.B])
        let day = try #require(CombineRule.combine(phone: nil, computers: [stale, fresh], now: C.now))
        #expect(day.countedDevices.map(\.deviceId) == [C.B])
        #expect(day.devices.count == 2)
    }

    @Test func aComputerOnAnOldDayStillHoldsItsPlaceForAWeek() throws {
        // A Mac that last wrote three days ago keeps the free place; a newer one can't count.
        let older = C.computer(C.A, day: "2026-11-17", minutes: 30, ago: 3 * 86_400)
        let newer = C.computer(C.B, day: C.today, minutes: 30, ago: 3 * 86_400 + 1)
        let day = try #require(CombineRule.combine(phone: nil, computers: [older, newer], now: C.now))
        #expect(day.day == "2026-11-17")
        #expect(day.countedDevices.map(\.deviceId) == [C.A])
    }

    @Test func aLimitOfZeroStillLetsThePhoneCount() throws {
        let day = try #require(CombineRule.combine(phone: C.phone(score: 55), computers: [C.computer(minutes: 600)],
                                                   deviceLimit: 0, now: C.now))
        #expect(day.score == ZenScore(tenths: 55))
        #expect(day.countedDevices.map(\.kind) == [.phone])
        #expect(day.minutes == nil)
    }

    @Test func aBigPlanCountsEveryFreshComputerOnTheDay() throws {
        let ids = ["a", "b", "c", "d", "e"].map { String(repeating: $0, count: 32) }
        let computers = ids.enumerated().map { C.computer($1, minutes: 10, pullBacks: 1, ago: TimeInterval(30 + $0)) }
        let day = try #require(CombineRule.combine(phone: nil, computers: computers, deviceLimit: 16, now: C.now))
        #expect(day.countedDevices.count == 5)
        #expect(day.minutes == 50)
        #expect(day.score == ZenScore(tenths: C.score(minutes: 50, pullBacks: 5)))
    }
}

/// A tiny seeded generator, so a failing case always replays.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct CombinePropertyTests {
    typealias C = CombineRuleTests
    static let days = ["2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22"]
    static let platforms: [DevicePlatform] = [.macos, .windows, .linux]

    private static func scenario(_ rng: inout SplitMix64) -> (PhoneDayInput?, [ComputerDayInput], Int) {
        let phone: PhoneDayInput? = Bool.random(using: &rng) ? nil : PhoneDayInput(
            report: PhoneDayReport(platform: [.ios, .android].randomElement(using: &rng)!,
                                   day: days.randomElement(using: &rng)!,
                                   score: ZenScore(tenths: Int.random(in: 25...100, using: &rng)),
                                   minutes: Bool.random(using: &rng) ? Int.random(in: 0...1_500, using: &rng) : nil),
            writtenAt: C.now.addingTimeInterval(-Double(Int.random(in: -600...(30 * 3_600), using: &rng))))
        let count = Int.random(in: 0...5, using: &rng)
        var ids: [String] = []
        for _ in 0..<count {
            let id = String((0..<32).map { _ in "0123456789abcdef".randomElement(using: &rng)! })
            if !ids.contains(id) { ids.append(id) }
        }
        let computers = ids.map { id in
            ComputerDayInput(
                report: ComputerDayReport(deviceId: id, platform: platforms.randomElement(using: &rng)!,
                                          day: days.randomElement(using: &rng)!,
                                          countedMinutes: Int.random(in: 0...1_500, using: &rng),
                                          pullBacks: Int.random(in: 0...1_000, using: &rng),
                                          promiseMinutes: 60 * Int.random(in: 1...12, using: &rng), sequence: 1),
                writtenAt: C.now.addingTimeInterval(-Double(Int.random(in: 0...(9 * 86_400), using: &rng))))
        }
        return (phone, computers, Int.random(in: 0...6, using: &rng))
    }

    @Test(arguments: [1, 2, 3, 4])
    func invariantsHoldForAnyMixOfDevices(seed: UInt64) {
        var rng = SplitMix64(state: seed)
        var decided = 0
        for _ in 0..<500 {
            let (phone, computers, limit) = Self.scenario(&rng)
            let result = CombineRule.combine(phone: phone, computers: computers, deviceLimit: limit, now: C.now)
            let freshPhone = phone.flatMap { CombineRule.isFresh($0, now: C.now) ? $0 : nil }
            let holders = CombineRule.holders(computers, deviceLimit: limit, now: C.now)
            let latest = DayKeys.latestAllowed(now: C.now)

            // Nothing decides a day only when there is no fresh phone and no holder on an allowed day.
            let canDecide = freshPhone != nil || holders.contains { $0.report.day <= latest }
            #expect((result != nil) == canDecide)
            guard let day = result else { continue }
            decided += 1

            // The order devices arrive in never changes the answer.
            let shuffled = CombineRule.combine(phone: phone, computers: computers.reversed(), deviceLimit: limit, now: C.now)
            #expect(shuffled == day)

            // A fresh phone on the day caps the score; an iPhone hides every minute.
            if let freshPhone, freshPhone.report.day == day.day {
                #expect(day.score <= freshPhone.report.score)
                #expect(day.scoreOnly == freshPhone.report.platform.scoreOnly)
            } else {
                #expect(!day.scoreOnly)
            }
            if day.scoreOnly { #expect(day.minutes == nil) }
            #expect(day.devices.filter { $0.platform.scoreOnly }.allSatisfy { $0.minutes == nil })

            // The places: never more computers than the plan leaves, all holding a place, all on the day.
            let countedComputers = day.countedDevices.filter { $0.kind == .computer }
            #expect(countedComputers.count <= CombineRule.computerSlots(deviceLimit: limit))
            let holderIds = Set(holders.filter { $0.report.day == day.day }.map(\.report.deviceId))
            #expect(Set(countedComputers.compactMap(\.deviceId)) == holderIds)

            // Every device is listed once: the phone first, then computers by device id.
            #expect(day.devices.count == computers.count + (phone == nil ? 0 : 1))
            let ids = day.devices.compactMap(\.deviceId)
            #expect(ids == ids.sorted())
            if phone != nil { #expect(day.devices.first?.kind == .phone) }
            #expect((0...100).contains(day.score.tenths))
        }
        #expect(decided > 100) // the generator really exercises the combine
    }
}

struct LocalDateEdgeTests {
    @Test func weeksStepBySevenDays() {
        let friday = LocalDate(year: 2026, month: 11, day: 20)
        #expect(friday.plusWeeks(2).description == "2026-12-04")
        #expect(friday.minusWeeks(47).description == "2025-12-26")
        #expect(friday.plusWeeks(-1) == friday.minusWeeks(1))
    }

    @Test func daysOfTheWeekOrderMondayFirst() {
        #expect(DayOfWeek.allCases.sorted() == DayOfWeek.allCases)
        #expect(DayOfWeek.monday < DayOfWeek.sunday)
        #expect(LocalDate(year: 2026, month: 11, day: 22).dayOfWeek == .sunday)
        #expect(LocalDate(year: 1969, month: 12, day: 29).dayOfWeek == .monday) // before the epoch
    }

    @Test func keysNameTheirDatesOrNothing() {
        #expect(DayKeys.date("2026-11-20") == LocalDate(year: 2026, month: 11, day: 20))
        #expect(DayKeys.date("2026-02-29") == nil)
        #expect(DayKeys.date("2028-02-29") != nil)
        #expect(DayKeys.adding(1, to: "2026-12-31") == "2027-01-01")
        #expect(DayKeys.adding(1, to: "not a day") == nil)
        #expect(DayKeys.weekStart(of: "2026-11-22") == "2026-11-16")
    }

    @Test func aDayKeyIsTheDayInTheZoneOnEitherSideOfTheDateLine() {
        // 2026-11-20T11:30:00Z: already the 21st in Kiribati (UTC+14), still the 20th in Niue (UTC-11).
        let moment = Date(timeIntervalSince1970: 1_795_174_200)
        #expect(DayKeys.key(for: moment, in: TimeZone(identifier: "Pacific/Kiritimati")!) == "2026-11-21")
        #expect(DayKeys.key(for: moment, in: TimeZone(identifier: "Pacific/Niue")!) == "2026-11-20")
    }
}

struct ScoreSnapshotEdgeTests {
    typealias S = ScoreSnapshotBuilderTests

    @Test func aDeviceThatDidNotCountIsNeverMarkedAsThisOne() throws {
        // This Mac wrote for yesterday; the phone decides today.
        let combined = try #require(CombineRule.combine(
            phone: S.phone(70), computers: [S.computer(day: "2026-11-19", minutes: 30, pullBacks: 1)], now: S.now))
        let snapshot = S.make(combined)
        #expect(snapshot.devices.map(\.id) == [ScoreSnapshotBuilder.phoneLineId])
        #expect(!snapshot.devices.contains { $0.isThisDevice })
    }

    @Test func anAndroidPhoneLineNeverShowsItsMinutes() throws {
        let combined = try #require(CombineRule.combine(phone: S.phone(70, platform: .android, minutes: 400),
                                                        computers: [], now: S.now))
        let snapshot = S.make(combined, this: ScoreSnapshotBuilder.phoneLineId)
        #expect(snapshot.devices.map(\.name) == ["This Android phone"])
        #expect(snapshot.devices.map(\.detail) == ["Counted on the phone"])
    }

    @Test func otherComputersAreNumberedWhenThePhoneIsThisDevice() throws {
        let combined = try #require(CombineRule.combine(
            phone: S.phone(), computers: [S.computer(S.mac, minutes: 10, pullBacks: 0), S.computer(S.studio, minutes: 61, pullBacks: 1)],
            deviceLimit: 3, now: S.now))
        let snapshot = S.make(combined, this: ScoreSnapshotBuilder.phoneLineId)
        #expect(snapshot.devices.map(\.name) == ["This iPhone", "Mac", "Mac 2"])
        #expect(snapshot.devices.map(\.detail) == ["Counted on the phone", "10 m distracting · 0 pull-backs",
                                                   "1 h 1 m distracting · 1 pull-back"])
    }

    @Test func aCombinedDayForTomorrowLeavesTodayUntouched() throws {
        // A computer on a later day than the home zone's today: the week shows nothing after today.
        let combined = try #require(CombineRule.combine(phone: nil, computers: [S.computer(day: "2026-11-21", minutes: 30, pullBacks: 0)],
                                                        now: S.now.addingTimeInterval(12 * 3_600)))
        let snapshot = S.make(combined, history: S.demoHistory)
        #expect(snapshot.score == ZenScoreRule.untouchedDay)
        #expect(snapshot.week.days[5] == nil)
        #expect(snapshot.devices.isEmpty)
        #expect(snapshot.updatedAt == S.now)
    }
}
