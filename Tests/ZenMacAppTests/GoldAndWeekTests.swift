import Foundation
import Testing
@testable import ZenMacApp
import ZenAPI

@Suite("Zen Gold: the gate and the money")
struct GoldTests {
    private func week(_ tenths: [Int?]) -> WeekProgress {
        WeekProgress(days: tenths.map { $0.map(ZenScore.init(tenths:)) }, todayIndex: 4, streakBefore: 0)
    }

    @Test("A won week opens gold until Sunday")
    func wonThisWeek() {
        let gate = GoldGate(thisWeek: week([72, 81, 66, 70, nil, nil, nil]), lastWeekWon: false)
        #expect(gate.state == .openThisWeek)
        #expect(gate.isOpen)
    }

    @Test("A won last week keeps gold open all this week")
    func wonLastWeek() {
        let gate = GoldGate(thisWeek: week([72, 58, 81, 54, 81, nil, nil]), lastWeekWon: true)
        #expect(gate.state == .openFromLastWeek)
        #expect(gate.isOpen)
    }

    @Test("Otherwise it says how many good days are left")
    func locked() {
        #expect(GoldGate(thisWeek: week([72, 58, 81, 54, 81, nil, nil]), lastWeekWon: false).state == .locked(daysToGo: 1))
        #expect(GoldGate(thisWeek: week([50, nil, nil, nil, nil, nil, nil]), lastWeekWon: false).state == .locked(daysToGo: 4))
        #expect(GoldGate(thisWeek: week([50, nil, nil, nil, nil, nil, nil]), lastWeekWon: false).line == "4 more good days open gold.")
    }

    @Test("Rupees use Indian grouping", arguments: [
        (5_00, "₹5"), (1_234_50, "₹1,234.50"), (12_34_567_00, "₹12,34,567"), (1_00_00_000_00, "₹1,00,00,000"),
    ])
    func rupees(paise: Int, text: String) {
        #expect(Rupees.text(paise: paise) == text)
    }
}

@Suite("The streak calendar: weeks Monday to Sunday")
struct StreakCalendarTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d))! }

    /// Weeks of 2–8, 9–15 and 16–22 November 2026 (Mondays 2, 9, 16).
    private func records(_ scores: [Int: Int?]) -> [DayRecord] {
        scores.map { DayRecord(date: day($0.key), score: $0.value.map(ZenScore.init(tenths:))) }
    }

    @Test("Won weeks in a row count; the week in progress never breaks it")
    func streak() {
        var s: [Int: Int?] = [:]
        for d in 2...8 { s[d] = 70 }          // won
        for d in 9...15 { s[d] = d < 13 ? 70 : 50 } // 4 good: won
        s[16] = 50; s[17] = 50                // this week, short so far
        let cal = StreakCalendar(records: records(s), today: day(17), calendar: calendar)
        #expect(cal.weeks.count == 3)
        #expect(cal.streakBeforeThisWeek == 2)
        #expect(cal.currentStreak == 2)
        #expect(cal.thisWeek?.days.compactMap { $0 }.count == 2)
    }

    @Test("A finished short week resets it")
    func reset() {
        var s: [Int: Int?] = [:]
        for d in 2...8 { s[d] = 70 }
        for d in 9...15 { s[d] = d < 12 ? 70 : 50 } // 3 good: lost
        let cal = StreakCalendar(records: records(s), today: day(16), calendar: calendar)
        #expect(cal.streakBeforeThisWeek == 0)
        #expect(cal.bestStreak == 1)
    }

    @Test("A gap is a day with no data, not a zero")
    func gaps() {
        let cal = StreakCalendar(records: records([2: 70, 4: 70]), today: day(4), calendar: calendar)
        #expect(cal.weeks.first?.days[1]?.score == nil)
        #expect(cal.weeks.first?.days[1] != nil)
        #expect(cal.weeks.first?.days[3] == nil) // after today: not lived yet
    }
}

@Suite("The weekly review: guardrails and the fallback")
struct ReviewTests {
    @Test("Clinical words are refused")
    func clinical() {
        #expect(throws: ReviewRejection.clinical) {
            try WeeklyReview(headline: "A calmer week", body: "Less phone addiction than before.", experiment: "Keep it up.").validated()
        }
    }

    @Test("Over-long parts are refused")
    func long() {
        #expect(throws: ReviewRejection.tooLong) {
            try WeeklyReview(headline: String(repeating: "a", count: 61), body: "b", experiment: "c").validated()
        }
    }

    @Test("The fallback is written from the numbers alone")
    func fallback() throws {
        let recap = WeekRecap(dayScores: [72, 58, 81, 54, 81, nil, nil], weeklyStreak: 9, devices: [])
        let review = WeeklyReview.fallback(for: recap)
        #expect(review.headline == "3 of 4 good days this week")
        #expect(review.body.contains("Wednesday") && review.body.contains("Thursday"))
        #expect(try review.validated() == review)
    }

    @Test("An iPhone in the recap never carries minutes")
    func iPhoneScoreOnly() {
        let d = WeekRecap.Device(kind: .iPhone, daysCounted: 5, distractingMinutes: 300, pullBacks: 4)
        #expect(d.distractingMinutes == nil && d.pullBacks == nil)
    }
}

@Suite("Preferences")
struct PreferenceTests {
    @Test("A saved file missing newer fields keeps what it has")
    func tolerantDecoding() throws {
        let json = #"{"zenoInNotch":false,"frequency":"chatty"}"#
        let values = try JSONDecoder().decode(PreferenceValues.self, from: Data(json.utf8))
        #expect(values.zenoInNotch == false)
        #expect(values.frequency == .chatty)
        #expect(values.appearance == .system)
        #expect(values.pattern == .bloom)
    }

    @Test("Values survive a round trip")
    func roundTrip() throws {
        var v = PreferenceValues()
        v.appearance = .dark
        v.pattern = .kolam
        v.quiet = .classHours
        let back = try JSONDecoder().decode(PreferenceValues.self, from: JSONEncoder().encode(v))
        #expect(back == v)
    }
}
