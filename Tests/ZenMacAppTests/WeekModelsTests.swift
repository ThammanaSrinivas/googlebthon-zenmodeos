import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("Week: the demo history and the streak it makes")
struct WeekDemoTests {
    /// Monday 16 to Sunday 22 November 2026.
    @Test("Nine won weeks before this one, whatever day it is", arguments: 16...22)
    func nineWon(day: Int) {
        let today = nov(day, 15)
        let cal = StreakCalendar(records: WeekDemo.history(today: today, calendar: india), today: today, calendar: india)
        #expect(cal.weeks.count == 12)
        #expect(cal.streakBeforeThisWeek == 9)
        #expect(cal.thisWeek?.isWon == false) // the demo week stops at 3 good days
        #expect(cal.currentStreak == 9)
        #expect(cal.bestStreak >= 9)
        #expect(cal.weeks.filter { !$0.isCurrent }.suffix(9).allSatisfy { $0.isWon })
        #expect(cal.weeks.dropLast().last?.isWon == true)
        #expect(cal.weeks[cal.weeks.count - 11].isWon == false) // the short week before the run
    }

    @Test("This week matches the fakes: 7.2, 5.8, 8.1, 5.4, 8.1")
    func thisWeek() throws {
        let today = nov(20, 15) // Friday
        let records = WeekDemo.history(today: today, calendar: india)
        let cal = StreakCalendar(records: records, today: today, calendar: india)
        let week = try #require(cal.thisWeek)
        #expect(week.days.prefix(5).map { $0?.score?.tenths } == [72, 58, 81, 54, 81])
        #expect(week.days.suffix(2).allSatisfy { $0 == nil }) // Saturday and Sunday: not lived yet
        #expect(week.goodDays == 3)
        #expect(week.progress.statusLine == FakeSnapshotWeek.value.statusLine)
    }

    @Test("No record is after today, and every day up to today is there")
    func noFuture() {
        let today = nov(18, 9)
        let records = WeekDemo.history(today: today, calendar: india)
        #expect(records.allSatisfy { $0.date <= today })
        #expect(Set(records.map(\.date)).count == records.count)
        #expect(records.count == 11 * 7 + 3) // eleven whole weeks, then Monday to Wednesday
    }

    @Test("The same history for the same day")
    func deterministic() {
        let a = WeekDemo.history(today: nov(20), calendar: india), b = WeekDemo.history(today: nov(20), calendar: india)
        #expect(a == b)
    }

    @Test("The review's recap is this week, outcomes only: no minutes from the iPhone")
    func recap() {
        let r = WeekDemo.recap
        #expect(r.dayScores == [72, 58, 81, 54, 81, nil, nil])
        #expect(r.weeklyStreak == 9)
        #expect(r.devices.first { $0.kind == .iPhone }?.distractingMinutes == nil)
        #expect(r.devices.first { $0.kind == .mac }?.distractingMinutes == 252)
        #expect(r.progress.todayIndex == 4 && r.progress.goodDays == 3)
    }
}

@Suite("Week: the streak calendar, more cases")
struct StreakCalendarMoreTests {
    private func records(_ scores: [Int: Int?]) -> [DayRecord] {
        scores.map { DayRecord(date: nov($0.key, 9), score: $0.value.map(ZenScore.init(tenths:))) }
    }

    @Test("No history at all: one empty current week, no streak")
    func empty() {
        let cal = StreakCalendar(records: [], today: nov(18), calendar: india)
        #expect(cal.weeks.count == 1)
        #expect(cal.thisWeek?.days.compactMap { $0 }.count == 3) // Monday to Wednesday, all without data
        #expect(cal.thisWeek?.days.compactMap { $0 }.allSatisfy { $0.score == nil } == true)
        #expect(cal.currentStreak == 0 && cal.bestStreak == 0 && cal.streakBeforeThisWeek == 0)
    }

    @Test("Winning this week adds one to the streak at once")
    func wonNow() {
        var s: [Int: Int?] = [:]
        for d in 9...15 { s[d] = 70 }
        for d in 16...19 { s[d] = 70 }
        let cal = StreakCalendar(records: records(s), today: nov(19), calendar: india)
        #expect(cal.streakBeforeThisWeek == 1)
        #expect(cal.currentStreak == 2 && cal.bestStreak == 2)
    }

    @Test("Records in any order, with duplicates, give the same weeks")
    func order() {
        let base = records([2: 70, 3: 70, 4: 70, 5: 70, 9: 50])
        let a = StreakCalendar(records: base, today: nov(10), calendar: india)
        let b = StreakCalendar(records: base.reversed() + base, today: nov(10), calendar: india)
        #expect(a.weeks.map(\.id) == b.weeks.map(\.id))
        #expect(a.weeks.map(\.goodDays) == b.weeks.map(\.goodDays))
        #expect(a.currentStreak == 1 && b.currentStreak == 1)
    }

    @Test("A week with a whole gap in the middle breaks the streak")
    func gapWeek() {
        var s: [Int: Int?] = [:]
        for d in 2...5 { s[d] = 70 }      // won
        for d in 16...19 { s[d] = 70 }    // won; the week of 9 has no data
        let cal = StreakCalendar(records: records(s), today: nov(23), calendar: india)
        #expect(cal.weeks.count == 4)
        #expect(cal.streakBeforeThisWeek == 1)
        #expect(cal.bestStreak == 1)
    }

    @Test("Weeks start on Monday even when the calendar says Sunday")
    func monday() {
        var us = india
        us.firstWeekday = 1
        let cal = StreakCalendar(records: records([22: 70]), today: nov(22), calendar: us)
        #expect(cal.weeks.first?.id == india.startOfDay(for: nov(16)))
        #expect(cal.thisWeek?.days.last??.score?.tenths == 70) // Sunday is the 7th slot
    }
}

@Suite("Week: the weekly review's guardrails and fallback")
struct WeeklyReviewMoreTests {
    @Test("Blank parts are refused, and whitespace is trimmed")
    func empty() throws {
        #expect(throws: ReviewRejection.empty) { try WeeklyReview(headline: "  ", body: "b", experiment: "c").validated() }
        let r = try WeeklyReview(headline: " Calm week \n", body: " ok ", experiment: " try ").validated()
        #expect(r == WeeklyReview(headline: "Calm week", body: "ok", experiment: "try"))
    }

    @Test("Exactly at each limit is fine; one over is not")
    func limits() throws {
        let h = String(repeating: "a", count: WeeklyReview.headlineLimit)
        let b = String(repeating: "b", count: WeeklyReview.bodyLimit)
        let e = String(repeating: "c", count: WeeklyReview.experimentLimit)
        #expect(try WeeklyReview(headline: h, body: b, experiment: e).validated().headline == h)
        #expect(throws: ReviewRejection.tooLong) { try WeeklyReview(headline: h, body: b + "b", experiment: e).validated() }
        #expect(throws: ReviewRejection.tooLong) { try WeeklyReview(headline: h, body: b, experiment: e + "c").validated() }
    }

    @Test("Clinical words are refused anywhere, any case", arguments: ["ADHD", "Depressed", "anxiety", "diagnosis", "therapy", "a disorder"])
    func clinical(word: String) {
        #expect(throws: ReviewRejection.clinical) {
            try WeeklyReview(headline: "Week", body: "Fine", experiment: "No \(word) talk").validated()
        }
    }

    @Test("A won week's fallback names the streak")
    func wonFallback() throws {
        let recap = WeekRecap(dayScores: [72, 68, 81, 64, nil, nil, nil], weeklyStreak: 9, devices: [])
        let r = WeeklyReview.fallback(for: recap)
        #expect(r.headline == "Week won · 10-week streak")
        #expect(r.experiment.hasPrefix("Keep"))
        #expect(try r.validated() == r)
    }

    @Test("No scores yet, and one score only")
    func sparse() {
        let none = WeeklyReview.fallback(for: WeekRecap(dayScores: [nil, nil, nil, nil, nil, nil, nil], weeklyStreak: 0, devices: []))
        #expect(none.headline == "0 of 4 good days this week" && none.body == "No scores yet this week.")
        let one = WeeklyReview.fallback(for: WeekRecap(dayScores: [nil, 65, nil, nil, nil, nil, nil], weeklyStreak: 0, devices: []))
        #expect(one.body == "Tuesday came in at 6.5.")
    }

    @Test("The offline review in the demo passes its own guardrails")
    func demoReview() async throws {
        // FakeReviews' text, checked without waiting for its pause.
        let r = WeeklyReview(
            headline: "Wednesdays are your calm day",
            body: "Three good days so far, with Wednesday at 8.1 leading. Thursday dipped to 5.4, mostly after 9 pm on the Mac. You pulled back 23 times this week, which is how good days get made.",
            experiment: "This Thursday, close the laptop at 9 and leave the phone outside the room.")
        #expect(try r.validated() == r)
    }
}

/// Review services under the test's control.
private struct InstantReview: WeeklyReviewService {
    let answer: WeeklyReview
    func review(for recap: WeekRecap) async throws -> WeeklyReview { answer }
}

private struct FailingReview: WeeklyReviewService {
    func review(for recap: WeekRecap) async throws -> WeeklyReview { throw URLError(.notConnectedToInternet) }
}

private struct NeverReview: WeeklyReviewService {
    func review(for recap: WeekRecap) async throws -> WeeklyReview {
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
}

@Suite("Week: ResilientReviews")
struct ResilientReviewsTests {
    private let recap = WeekDemo.recap

    @Test("A good review is shown, trimmed, as written by Gemini")
    func good() async {
        let r = WeeklyReview(headline: " Calm ", body: "Body.", experiment: "Try.")
        let (review, source) = await ResilientReviews(service: InstantReview(answer: r)).review(for: recap)
        #expect(review.headline == "Calm" && source == .gemini)
    }

    @Test("A refused, failed or slow review falls back to the numbers")
    func fallbacks() async {
        let clinical = WeeklyReview(headline: "Addicted", body: "b", experiment: "c")
        for service in [InstantReview(answer: clinical), FailingReview(), NeverReview()] as [any WeeklyReviewService] {
            let (review, source) = await ResilientReviews(service: service, timeout: .milliseconds(50)).review(for: recap)
            #expect(source == .fallback)
            #expect(review == WeeklyReview.fallback(for: recap))
        }
    }
}

@Suite("Week: a recap's one-line pattern")
struct WeekPatternTests {
    private func line(_ tenths: [Int?]) -> String {
        let days = tenths.map { $0.map(ZenScore.init(tenths:)) }
        let progress = WeekProgress(days: days, todayIndex: nil, streakBefore: 0)
        return WeekPattern.headline(days: days, wonOn: progress.winningDayIndex)
    }

    @Test("A won week says when it was won")
    func won() {
        #expect(line([70, 72, 68, 75, 50, 40, nil]) == "Won by Thursday")
        #expect(line([70, 50, 68, 75, 66, 40, nil]) == "Won on Friday")
        #expect(line([70, 50, 68, 55, 50, 66, 64]) == "Sealed on Sunday")
        #expect(line([70, 72, 68, 75, 66, 64, 61]) == "Seven good days of seven")
    }

    @Test("A week that wasn't won says the shape it took")
    func shapes() {
        #expect(line([70, 72, 68, 50, 40, 45, 50]) == "One good day short")
        #expect(line([66, 58, 59, 50, 42, 44, 40]) == "Strong start, slow finish")
        #expect(line([40, 44, 42, 50, 58, 59, 66]) == "Slow start, strong finish")
        #expect(line([55, 56, 54, 55, 56, 50, 41]) == "Calm weekdays, busy weekend")
        #expect(line([55, 56, 54, 55, 56, 55, 54]) == "Steady all week")
        #expect(line([55, 58, 40, 57, 55, 59, 57]) == "Wednesday pulled it down")
    }

    @Test("Too few scores is a quiet week, never a zero")
    func quiet() {
        #expect(line([nil, 70, nil, nil, 50, nil, nil]) == "A quiet week on record")
        #expect(line([nil, nil, nil, nil, nil, nil, nil]) == "A quiet week on record")
    }

    @Test("Recaps carry the pattern, the labelled average and the streak in what VoiceOver reads")
    func spoken() throws {
        let today = nov(20, 15)
        let cal = StreakCalendar(records: WeekDemo.history(today: today, calendar: india), today: today, calendar: india)
        let entries = RecapBook.entries(from: cal)
        let latest = try #require(entries.first)
        #expect(latest.isWon && latest.streakAfter == 9)
        #expect(latest.headline == WeekPattern.headline(days: latest.days, wonOn: latest.wonOn))
        #expect(latest.spoken.contains("Zen Score week average"))
        #expect(latest.spoken.contains("9-week streak"))
    }
}
