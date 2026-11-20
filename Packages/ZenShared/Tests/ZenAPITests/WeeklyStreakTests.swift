import Testing
@testable import ZenAPI

@Suite("The weekly streak: good days above 6.0, four win the week")
struct WeeklyStreakTests {
    private func week(_ tenths: [Int?], today: Int? = nil, streak: Int = 0) -> WeekProgress {
        WeekProgress(days: tenths.map { $0.map(ZenScore.init(tenths:)) }, todayIndex: today, streakBefore: streak)
    }

    @Test("6.0 exactly is not a good day; 6.1 is")
    func threshold() {
        #expect(!ZenScore(tenths: 60).isGoodDay)
        #expect(ZenScore(tenths: 61).isGoodDay)
    }

    @Test("Scores are clamped to 0–10 and always show one decimal")
    func text() {
        #expect(ZenScore(tenths: 81).text == "8.1")
        #expect(ZenScore(tenths: 70).text == "7.0")
        #expect(ZenScore(tenths: 140).tenths == 100)
        #expect(ZenScore(tenths: -3).text == "0.0")
    }

    @Test("The book's week 45: won on Saturday, Sunday can't undo it")
    func bookExample() {
        let w = week([72, 58, 81, 64, nil, 70, 51], streak: 9)
        #expect(w.goodDays == 4)
        #expect(w.isWon)
        #expect(w.winningDayIndex == 5)
        #expect(w.weeklyStreak == 10)
        #expect(w.statusLine == "Week won · 10-week streak")
    }

    @Test("A day with no data is neither good nor a zero")
    func noData() {
        let w = week([nil, nil, 81, nil, nil, nil, nil], today: 2)
        #expect(w.goodDays == 1)
        #expect(w.statusLine == "1 of 4 good days this week")
    }

    @Test("The week in progress never breaks the streak")
    func inProgress() {
        let w = week([72, 58, 81, nil, nil, nil, nil], today: 3, streak: 6)
        #expect(!w.isWon)
        #expect(w.weeklyStreak == 6)
    }

    @Test("A finished week of 3 or fewer good days resets the streak")
    func shortWeekResets() {
        let w = week([72, 58, 81, 64, 50, 40, 30], today: nil, streak: 6)
        #expect(w.weeklyStreak == 0)
    }

    @Test("Three of four says one more wins it")
    func oneMore() {
        #expect(week([72, 58, 81, 54, 81, nil, nil], today: 4).statusLine == "3 of 4 good days · one more wins the week")
    }
}
