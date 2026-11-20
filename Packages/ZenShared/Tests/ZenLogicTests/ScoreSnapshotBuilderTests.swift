// ScoreSnapshotBuilder: the combined day and its history as every device shows them.
import Foundation
import Testing
import ZenAPI
@testable import ZenLogic

struct ScoreSnapshotBuilderTests {
    static let mac = String(repeating: "a", count: 32)
    static let studio = String(repeating: "b", count: 32)
    static let third = String(repeating: "c", count: 32)
    /// 2026-11-20T06:30:00Z, a Friday (index 4), noon in India.
    static let now = Date(timeIntervalSince1970: 1_795_156_200)
    static let today = "2026-11-20"

    static func phone(_ tenths: Int = 81, platform: DevicePlatform = .ios, minutes: Int? = nil) -> PhoneDayInput {
        PhoneDayInput(report: PhoneDayReport(platform: platform, day: today, score: ZenScore(tenths: tenths), minutes: minutes),
                      writtenAt: now.addingTimeInterval(-60))
    }

    static func computer(_ id: String = mac, day: DayKey = today, minutes: Int, pullBacks: Int, ago: TimeInterval = 30) -> ComputerDayInput {
        ComputerDayInput(report: ComputerDayReport(deviceId: id, day: day, countedMinutes: minutes, pullBacks: pullBacks,
                                                   promiseMinutes: 240, sequence: 1),
                         writtenAt: now.addingTimeInterval(-ago))
    }

    static func make(_ combined: CombinedDay?, history: [DayKey: Int] = [:], streak: Int = 9,
                     this: String? = mac) -> ScoreSnapshot {
        ScoreSnapshotBuilder.make(combined: combined, history: history, streakBefore: streak, today: today,
                                  thisDeviceId: this, now: now)
    }

    /// Kamal's demo week: Monday 7.2 · Tuesday 5.8 · Wednesday 8.1 · Thursday 5.4.
    static let demoHistory: [DayKey: Int] = ["2026-11-16": 72, "2026-11-17": 58, "2026-11-18": 81, "2026-11-19": 54]

    @Test func theDemoDayReadsLikeTheFakes() throws {
        let combined = try #require(CombineRule.combine(phone: Self.phone(81), computers: [Self.computer(minutes: 38, pullBacks: 4)],
                                                        deviceLimit: 2, now: Self.now))
        let snapshot = Self.make(combined, history: Self.demoHistory)
        #expect(snapshot.score == ZenScore(tenths: 81))
        #expect(snapshot.week.days == [72, 58, 81, 54, 81, nil, nil].map { $0.map(ZenScore.init(tenths:)) })
        #expect(snapshot.week.todayIndex == 4)
        #expect(snapshot.week.streakBefore == 9)
        #expect(snapshot.week.statusLine == "3 of 4 good days · one more wins the week")
        #expect(snapshot.devices == [
            DeviceLine(id: ScoreSnapshotBuilder.phoneLineId, kind: .iPhone, name: "iPhone", detail: "Counted on the phone", isThisDevice: false),
            DeviceLine(id: Self.mac, kind: .mac, name: "This Mac", detail: "38 m distracting · 4 pull-backs", isThisDevice: true),
        ])
        #expect(snapshot.updatedAt == Self.now)
    }

    @Test func anIPhoneLineNeverShowsMinutesEvenFromAnAndroidStyleReport() throws {
        let combined = try #require(CombineRule.combine(phone: Self.phone(70, minutes: 300), computers: [], now: Self.now))
        let line = try #require(Self.make(combined).devices.first)
        #expect(line.detail == "Counted on the phone")
        #expect(!line.detail.contains("m "))
    }

    @Test func thePhoneCanBeThisDevice() throws {
        let combined = try #require(CombineRule.combine(phone: Self.phone(), computers: [], now: Self.now))
        let lines = Self.make(combined, this: ScoreSnapshotBuilder.phoneLineId).devices
        #expect(lines.map(\.name) == ["This iPhone"])
        #expect(lines.map(\.isThisDevice) == [true])
    }

    @Test func otherComputersAreNumberedAndThisOneIsNamed() throws {
        let combined = try #require(CombineRule.combine(
            phone: nil,
            computers: [Self.computer(Self.mac, minutes: 10, pullBacks: 1), Self.computer(Self.studio, minutes: 70, pullBacks: 0),
                        Self.computer(Self.third, minutes: 120, pullBacks: 2)],
            deviceLimit: 4, now: Self.now))
        let lines = Self.make(combined, this: Self.studio).devices
        #expect(lines.map(\.name) == ["Mac", "This Mac", "Mac 2"])
        #expect(lines.map(\.detail) == ["10 m distracting · 1 pull-back", "1 h 10 m distracting · 0 pull-backs",
                                        "2 h distracting · 2 pull-backs"])
    }

    @Test func onlyDevicesThatCountedAreListed() throws {
        let older = Self.computer(Self.studio, minutes: 300, pullBacks: 0, ago: 600)
        let combined = try #require(CombineRule.combine(phone: nil, computers: [Self.computer(minutes: 30, pullBacks: 0), older],
                                                        deviceLimit: 2, now: Self.now))
        #expect(Self.make(combined).devices.map(\.id) == [Self.mac])
    }

    @Test func nothingYetTodayReadsAsAnUntouchedDayWithAnEmptyToday() {
        let snapshot = Self.make(nil, history: Self.demoHistory)
        #expect(snapshot.score == ZenScore(tenths: 100))
        #expect(snapshot.week.days[4] == nil)
        #expect(snapshot.week.goodDays == 2)
        #expect(snapshot.devices.isEmpty)
        #expect(snapshot.updatedAt == Self.now)
    }

    @Test func aCombinedDayFromYesterdayFillsYesterdayNotToday() throws {
        let yesterday = try #require(CombineRule.combine(
            phone: nil, computers: [Self.computer(day: "2026-11-19", minutes: 30, pullBacks: 0)], now: Self.now))
        #expect(yesterday.day == "2026-11-19")
        let snapshot = Self.make(yesterday, history: ["2026-11-19": 40])
        #expect(snapshot.week.days[3] == yesterday.score) // the combined day wins for its own day
        #expect(snapshot.week.days[4] == nil)
        #expect(snapshot.devices.isEmpty)
        #expect(snapshot.score == ZenScoreRule.untouchedDay)
    }

    @Test func historyOutsideThisWeekAndAfterTodayIsIgnored() {
        let week = ScoreSnapshotBuilder.week(byDay: ["2026-11-15": 90, "2026-11-21": 90, "2026-11-16": 61],
                                             today: Self.today, streakBefore: 0)
        #expect(week.days == [ZenScore(tenths: 61), nil, nil, nil, nil, nil, nil])
        #expect(week.todayIndex == 4)
    }

    @Test func sundayIsTheLastDayOfTheWeek() {
        let week = ScoreSnapshotBuilder.week(byDay: ["2026-11-22": 70, "2026-11-16": 70], today: "2026-11-22", streakBefore: 2)
        #expect(week.todayIndex == 6)
        #expect(week.days.first == ZenScore(tenths: 70))
        #expect(week.days.last == ZenScore(tenths: 70))
    }

    @Test func aWonWeekCarriesTheStreak() throws {
        let combined = try #require(CombineRule.combine(phone: Self.phone(81), computers: [], now: Self.now))
        let snapshot = Self.make(combined, history: ["2026-11-16": 72, "2026-11-17": 65, "2026-11-18": 81], streak: 9)
        #expect(snapshot.week.isWon)
        #expect(snapshot.week.weeklyStreak == 10)
    }

    @Test func aMalformedTodayGivesAnEmptyFinishedWeek() {
        let week = ScoreSnapshotBuilder.week(byDay: [:], today: "nonsense", streakBefore: 3)
        #expect(week.days.allSatisfy { $0 == nil })
        #expect(week.todayIndex == nil)
    }

    @Test func durationsReadInMinutesThenHours() {
        #expect(ScoreSnapshotBuilder.duration(minutes: 0) == "0 m")
        #expect(ScoreSnapshotBuilder.duration(minutes: 59) == "59 m")
        #expect(ScoreSnapshotBuilder.duration(minutes: 60) == "1 h")
        #expect(ScoreSnapshotBuilder.duration(minutes: 125) == "2 h 5 m")
        #expect(ScoreSnapshotBuilder.duration(minutes: -4) == "0 m")
    }

    @Test func everyPlatformHasAKindAndAName() {
        for platform in DevicePlatform.allCases {
            #expect(!ScoreSnapshotBuilder.name(platform, isThisDevice: false, ordinal: 1).isEmpty)
        }
        #expect(ScoreSnapshotBuilder.lineKind(.windows) == .windows)
        #expect(ScoreSnapshotBuilder.lineKind(.android) == .android)
        #expect(ScoreSnapshotBuilder.name(.windows, isThisDevice: true, ordinal: 1) == "This Windows PC")
    }
}
