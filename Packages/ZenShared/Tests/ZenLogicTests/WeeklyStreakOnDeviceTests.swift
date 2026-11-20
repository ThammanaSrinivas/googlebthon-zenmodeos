import Foundation
import Testing
import ZenAPI
@testable import ZenLogic

/// #8, the weekly streak computed on the device: the Monday boundary in IST, and the week as the
/// Mac builds it from day scores (good day > 6.0; won at 4; the week in progress never breaks it).
@Suite("Weekly streak on the device")
struct WeeklyStreakOnDeviceTests {
    let ist = TimeZone(identifier: "Asia/Kolkata")!

    @Test("Sunday 23:59 IST and Monday 00:00 IST fall in different weeks")
    func mondayBoundaryIST() {
        // Mon 23 Nov 2026 00:00 IST = Sun 22 Nov 18:30 UTC.
        let monday = Date(timeIntervalSince1970: 1_795_372_200)
        let sundayNight = monday.addingTimeInterval(-60)
        let mon = LocalDate.today(in: ist, now: monday), sun = LocalDate.today(in: ist, now: sundayNight)
        #expect(mon.description == "2026-11-23" && sun.description == "2026-11-22")
        #expect(mon.weekStart.description == "2026-11-23")
        #expect(sun.weekStart.description == "2026-11-16")
        // The same instant is still Sunday in UTC: the home zone decides, not the clock's.
        #expect(LocalDate.today(in: TimeZone(identifier: "UTC")!, now: monday).description == "2026-11-22")
    }

    @Test("A week in progress with 3 good days keeps the streak; the 4th wins it at once")
    func inProgress() {
        let three = ["2026-11-16": 72, "2026-11-17": 65, "2026-11-18": 61]
        let w = ScoreSnapshotBuilder.week(byDay: three, today: "2026-11-19", streakBefore: 9)
        #expect(w.goodDays == 3 && !w.isWon && w.weeklyStreak == 9)
        var four = three
        four["2026-11-19"] = 80
        #expect(ScoreSnapshotBuilder.week(byDay: four, today: "2026-11-19", streakBefore: 9).weeklyStreak == 10)
    }

    @Test("6.0 exactly and a day with no data don't count; neither is a zero")
    func noDataAndThreshold() {
        let days = ["2026-11-16": 60, "2026-11-17": 72, "2026-11-19": 70, "2026-11-20": 66]
        let w = ScoreSnapshotBuilder.week(byDay: days, today: "2026-11-20", streakBefore: 2)
        #expect(w.goodDays == 3)
        #expect(w.days[2] == nil)
        #expect(w.weeklyStreak == 2)
    }

    @Test("A finished week of 3 good days resets the streak to 0")
    func finishedShort() {
        let w = WeekProgress(days: [ZenScore(tenths: 70), ZenScore(tenths: 70), ZenScore(tenths: 70), nil, nil, nil, nil],
                             todayIndex: nil, streakBefore: 5)
        #expect(w.weeklyStreak == 0)
    }
}
