import SwiftUI
import Albeit
import ZenAPI

/// How a day's Zen Score reads at a glance: the colour of the dot at the top-left of its cell.
enum ScoreBand: Equatable {
    case great, good, middling, low, noData, toCome

    init(score: ZenScore?, isFuture: Bool) {
        if isFuture { self = .toCome; return }
        guard let score else { self = .noData; return }
        switch score.tenths {
        case 80...: self = .great
        case 61..<80: self = .good
        case 40...60: self = .middling
        default: self = .low
        }
    }

    /// The dot's fill; nil draws a hollow ring (no data) or nothing (a day still to come).
    var color: Color? {
        switch self {
        case .great: Color.zen.scoreGain
        case .good: Color.zen.brandFill
        case .middling: Color.zen.feelFocus
        case .low: Color.zen.feelUnintentional
        case .noData, .toCome: nil
        }
    }

    /// Plain words, never a verdict: a cost is information.
    var label: String {
        switch self {
        case .great: "A great day"
        case .good: "A good day"
        case .middling: "Under 6.0"
        case .low: "Under 4.0"
        case .noData: "No data"
        case .toCome: "Still to come"
        }
    }

    /// The legend under the grid.
    static let legend: [(ScoreBand, String)] = [(.great, "8 and up"), (.good, "Above 6"), (.middling, "4 to 6"), (.low, "Under 4"), (.noData, "No data")]
}

/// "09:30", "18:00": the 24-hour clock every surface in the app uses, whatever the locale.
enum ClockText {
    static let style = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: .current)

    static func time(_ date: Date) -> String { date.formatted(style) }
    static func span(_ start: Date, _ end: Date) -> String { "\(time(start)) – \(time(end))" }
}

/// One day as the Calendar section shows it.
struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isFuture: Bool
    let score: ZenScore?
    let events: [CalendarLink.Event]

    var id: Date { date }
    var band: ScoreBand { ScoreBand(score: score, isFuture: isFuture) }
    var number: String { date.formatted(.dateTime.day()) }

    /// "Friday 20 November, Zen Score 8.1, a good day, 2 events"
    var spoken: String {
        let when = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let score = self.score.map { "Zen Score \($0.text), \(band.label.lowercased())" } ?? band.label.lowercased()
        let plans = events.isEmpty ? "" : ", \(events.count) event\(events.count == 1 ? "" : "s")"
        return "\(when), \(score)\(plans)"
    }
}

/// Builds the days for a month grid or a week from the streak history, today's live score and the
/// person's calendar. Weeks run Monday to Sunday.
@MainActor
struct CalendarDays {
    let model: AppModel
    let now: Date

    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    /// The scores the app knows, by day: the demo history, with today's live number on top.
    private var scores: [Date: ZenScore] {
        let cal = Self.calendar
        var map: [Date: ZenScore] = [:]
        for week in model.streak?.weeks ?? [] {
            for day in week.days.compactMap({ $0 }) {
                if let s = day.score { map[cal.startOfDay(for: day.date)] = s }
            }
        }
        if let live = model.snapshot?.score { map[cal.startOfDay(for: now)] = live }
        return map
    }

    /// The six weeks that show `month` (Notion's grid always has whole weeks).
    func monthGrid(_ month: Date) -> (range: DateInterval, days: [CalendarDay]) {
        let cal = Self.calendar
        let interval = cal.dateInterval(of: .month, for: month)!
        let first = cal.dateInterval(of: .weekOfYear, for: interval.start)!.start
        let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end)!
        let lastWeekEnd = cal.dateInterval(of: .weekOfYear, for: lastDay)!.end
        let count = cal.dateComponents([.day], from: first, to: lastWeekEnd).day ?? 35
        let range = DateInterval(start: first, end: lastWeekEnd)
        // Half-open: DateInterval.contains includes its end, which is the next month's 1st.
        return (range, days(from: first, count: count, inMonth: { $0 >= interval.start && $0 < interval.end }))
    }

    /// Monday to Sunday around `day`.
    func week(_ day: Date) -> (range: DateInterval, days: [CalendarDay]) {
        let interval = Self.calendar.dateInterval(of: .weekOfYear, for: day)!
        return (interval, days(from: interval.start, count: 7, inMonth: { _ in true }))
    }

    private func days(from first: Date, count: Int, inMonth: (Date) -> Bool) -> [CalendarDay] {
        let cal = Self.calendar
        let today = cal.startOfDay(for: now)
        let scores = self.scores
        return (0..<count).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: first) else { return nil }
            return CalendarDay(date: date, inMonth: inMonth(date), isToday: date == today, isFuture: date > today,
                               score: scores[date], events: model.calendarLink.events(on: date))
        }
    }

    /// The week a day sits in, in the streak's words: "3 of 4 good days", "Week won".
    func weekLine(for day: Date) -> String {
        let cal = Self.calendar
        let monday = cal.dateInterval(of: .weekOfYear, for: day)!.start
        if cal.isDate(monday, inSameDayAs: cal.dateInterval(of: .weekOfYear, for: now)!.start), let live = model.snapshot?.week {
            return live.statusLine
        }
        if monday > now { return "Still to come" }
        guard let week = model.streak?.weeks.first(where: { cal.isDate($0.id, inSameDayAs: monday) }) else { return "Before your history starts" }
        if week.isWon { return "Week won · \(week.goodDays) good days" }
        return "\(week.goodDays) of 4 good days"
    }
}
