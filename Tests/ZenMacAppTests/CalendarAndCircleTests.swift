import Foundation
import Testing
import Albeit
import ZenAPI
@testable import ZenMacApp

@Suite("Calendar: score bands and clock text")
@MainActor
struct ScoreBandTests {
    @Test("Bands by score", arguments: [
        (80, ScoreBand.great), (100, .great), (79, .good), (61, .good), (60, .middling), (40, .middling), (39, .low), (0, .low),
    ])
    func bands(tenths: Int, band: ScoreBand) {
        #expect(ScoreBand(score: ZenScore(tenths: tenths), isFuture: false) == band)
    }

    @Test("No data is its own band; a day still to come beats any score")
    func special() {
        #expect(ScoreBand(score: nil, isFuture: false) == .noData)
        #expect(ScoreBand(score: ZenScore(tenths: 90), isFuture: true) == .toCome)
        #expect(ScoreBand.noData.color == nil && ScoreBand.toCome.color == nil)
        #expect(ScoreBand.great.color != nil && ScoreBand.low.color != nil)
    }

    @Test("A good band is exactly a good day")
    func goodMatchesRule() {
        for t in 0...100 {
            let band = ScoreBand(score: ZenScore(tenths: t), isFuture: false)
            #expect((band == .good || band == .great) == ZenScore(tenths: t).isGoodDay, "\(t)")
        }
    }

    @Test("The legend lists every band a past day can have")
    func legend() {
        #expect(ScoreBand.legend.map(\.0) == [.great, .good, .middling, .low, .noData])
        #expect(Set(ScoreBand.legend.map(\.0.label)).count == 5)
    }

    @Test("The 24-hour clock, whatever the locale")
    func clock() {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 9, minute: 5, second: 0, of: Date())!
        let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        #expect(ClockText.time(morning) == "09:05")
        #expect(ClockText.span(morning, evening) == "09:05 – 18:00")
    }
}

@Suite("Calendar: the month grid and week lines")
@MainActor
struct CalendarDaysTests {
    private var calendar: Calendar { CalendarDays.calendar }

    private func started() async -> AppModel {
        let m = AppModel()
        m.notch.reduceMotion = true
        m.start()
        _ = await eventually { m.snapshot != nil }
        return m
    }

    @Test("A month grid is whole weeks, Monday first, the month's days marked")
    func monthGrid() {
        let m = AppModel()
        let now = Date()
        let grid = CalendarDays(model: m, now: now).monthGrid(now)
        #expect(grid.days.count % 7 == 0 && (28...42).contains(grid.days.count))
        #expect(calendar.component(.weekday, from: grid.days[0].date) == 2)
        let month = calendar.dateInterval(of: .month, for: now)!
        #expect(grid.days.filter { $0.date >= month.start && $0.date < month.end }.allSatisfy { $0.inMonth })
        #expect(grid.days.filter { $0.isToday }.count == 1)
        #expect(grid.days.allSatisfy { $0.isFuture == ($0.date > calendar.startOfDay(for: now)) })
        #expect(grid.range.start == grid.days[0].date)
    }

    private var november: [CalendarDay] {
        let nov15 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        return CalendarDays(model: AppModel(), now: nov15).monthGrid(nov15).days
    }

    @Test("November 2026 spans six weeks: 26 October to 6 December")
    func novemberGrid() {
        let days = november
        #expect(days.count == 42)
        #expect(calendar.component(.month, from: days[0].date) == 10 && calendar.component(.day, from: days[0].date) == 26)
        #expect(calendar.component(.month, from: days[41].date) == 12 && calendar.component(.day, from: days[41].date) == 6)
        #expect(days.filter { calendar.component(.month, from: $0.date) == 11 }.allSatisfy { $0.inMonth })
        #expect(days.prefix(6).allSatisfy { !$0.inMonth }) // 26 to 31 October
    }

    @Test("Only the month's own days are marked in the month")
    func onlyTheMonth() {
        let days = november
        #expect(days.filter { $0.inMonth }.count == 30)
        #expect(days[36].inMonth == false) // 1 December
    }

    @Test("A week is seven days from Monday")
    func week() {
        let now = Date()
        let w = CalendarDays(model: AppModel(), now: now).week(now)
        #expect(w.days.count == 7)
        #expect(calendar.component(.weekday, from: w.days[0].date) == 2)
        #expect(w.days.contains { $0.isToday })
    }

    @Test("Today shows the live score; past days the history's")
    func scores() async {
        let m = await started()
        let now = Date()
        let w = CalendarDays(model: m, now: now).week(now)
        let today = w.days.first { $0.isToday }
        #expect(today?.score == m.snapshot?.score)
        #expect(w.days.filter { $0.isFuture }.allSatisfy { $0.score == nil && $0.band == .toCome })
        let lastMonth = calendar.date(byAdding: .day, value: -21, to: now)!
        let past = CalendarDays(model: m, now: now).week(lastMonth).days
        #expect(past.contains { $0.score != nil })
    }

    @Test("Week lines: this week live, past weeks from history, later weeks still to come")
    func weekLines() async {
        let m = await started()
        let now = Date()
        let days = CalendarDays(model: m, now: now)
        #expect(days.weekLine(for: now) == m.snapshot?.week.statusLine)
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: now)!
        #expect(days.weekLine(for: lastWeek).hasPrefix("Week won · "))
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        #expect(days.weekLine(for: nextWeek) == "Still to come")
        let longAgo = calendar.date(byAdding: .day, value: -7 * 30, to: now)!
        #expect(days.weekLine(for: longAgo) == "Before your history starts")
    }

    @Test("The spoken line names the score and its band")
    func spoken() {
        let day = CalendarDay(date: Date(), inMonth: true, isToday: true, isFuture: false, score: ZenScore(tenths: 81), events: [])
        #expect(day.spoken.hasSuffix(", Zen Score 8.1, a great day"))
        let empty = CalendarDay(date: Date(), inMonth: true, isToday: false, isFuture: false, score: nil, events: [])
        #expect(empty.spoken.hasSuffix(", no data"))
    }
}

@Suite("Zen Circle: tabs, words and patterns")
@MainActor
struct CircleTests {
    @Test("Three tabs: You, Zen Bros, the cohort")
    func tabs() {
        #expect(CircleTab.allCases.map(\.rawValue) == ["you", "bros", "cohort"])
        #expect(CircleCopy.tabYou == "You" && CircleCopy.tabBros == "Zen Bros")
    }

    @Test("Hours on the 12-hour clock", arguments: [(0, "12 AM"), (7, "7 AM"), (12, "12 PM"), (14, "2 PM"), (23, "11 PM")])
    func clock(hour: Int, text: String) {
        #expect(CircleSection.clock(hour) == text)
    }

    @Test("The archetype line reads naturally")
    func youAre() {
        #expect(CircleCopy.youAre(.deepWorker) == "You're a deep worker.")
        #expect(CircleCopy.youAre(PersonalMonth.demo.closest).hasPrefix("You're a "))
    }

    @Test("Every pattern explains itself, starting with its name")
    func patterns() {
        for p in PatternKind.allCases { #expect(p.legend.hasPrefix(p.rawValue + " · ")) }
    }

    @Test("Each hour of the month has a steady shade")
    func variants() {
        for day in 0..<30 {
            for hour in 0..<24 {
                let v = FeelPalette.variant(day, hour)
                #expect((0..<1).contains(v))
                #expect(v == FeelPalette.variant(day, hour))
            }
        }
    }

    @Test("Group privacy: the circle copy promises scores only, and 5 or more")
    func privacy() {
        #expect(CircleCopy.privacy.contains("5 or more"))
        #expect(CircleCopy.brosPrivacy.contains("Never apps, minutes"))
        #expect(CircleCopy.iPhoneSeat.contains("Only the score"))
    }

    @Test("The sidebar's sections each have their own name and symbol")
    func sections() {
        let all = TodayView.Section.allCases
        #expect(all.count == 8)
        // Team admin shows only for the team's admin.
        #expect(TodayView.Section.visible(isAdmin: false).count == 7)
        #expect(Set(all.map(\.rawValue)).count == all.count && Set(all.map(\.symbol)).count == all.count)
        #expect(all.first == .today)
    }
}
