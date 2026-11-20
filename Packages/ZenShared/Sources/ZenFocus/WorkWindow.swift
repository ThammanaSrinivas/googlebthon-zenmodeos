import Foundation
import ZenAPI

/// Work hours as a rule: is it work time, when does work end today, when does it start next.
/// Handles a window that crosses midnight (a night shift, 22:00–06:00): the shift belongs to the
/// day it started on. Days are 1 = Monday … 7 = Sunday, in the hours' own time zone.
public struct WorkWindow: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public let days: Set<Int>
    public let timeZone: TimeZone

    public init?(_ hours: WorkHours) {
        guard let s = DayPlanner.minutes(hours.start), let e = DayPlanner.minutes(hours.end), s != e, s < 1440, e < 1440,
              let tz = TimeZone(identifier: hours.tz) else { return nil }
        start = s
        end = e
        days = Set(hours.days.filter { (1...7).contains($0) })
        timeZone = tz
    }

    public var crossesMidnight: Bool { end < start }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// 1 = Monday … 7 = Sunday.
    public func isoWeekday(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public func isWorkTime(_ date: Date) -> Bool {
        let m = minuteOfDay(date)
        if !crossesMidnight { return days.contains(isoWeekday(date)) && m >= start && m < end }
        if m >= start { return days.contains(isoWeekday(date)) }
        if m < end { return days.contains(isoWeekday(date.addingTimeInterval(-86_400))) }
        return false
    }

    /// The start of work on the day of `date` (00:00 + start), whether or not it's a workday.
    private func at(_ minutes: Int, on date: Date) -> Date {
        calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// The next moment work starts after `date` (within two weeks), or nil with no workdays.
    public func nextStart(after date: Date) -> Date? {
        for offset in 0..<15 {
            let day = calendar.date(byAdding: .day, value: offset, to: date)!
            let s = at(start, on: day)
            if s > date, days.contains(isoWeekday(s)) { return s }
        }
        return nil
    }

    /// The end of the shift `date` is in, or nil when it isn't work time.
    public func currentEnd(at date: Date) -> Date? {
        guard isWorkTime(date) else { return nil }
        if !crossesMidnight { return at(end, on: date) }
        return minuteOfDay(date) >= start ? at(end, on: date.addingTimeInterval(86_400)) : at(end, on: date)
    }

    /// Minutes of [from, to) that fall outside work hours, counted minute by minute.
    public func afterHoursMinutes(from: Date, to: Date) -> Int {
        guard to > from else { return 0 }
        var n = 0
        var t = from
        while t < to {
            if !isWorkTime(t) { n += 1 }
            t = t.addingTimeInterval(60)
        }
        return n
    }
}

/// The after-hours guard's words and moments.
public enum AfterHours {
    /// What the guard does on a tick, given whether the last tick and this one were work time.
    public enum Step: Equatable, Sendable { case none, workEnded, workStarted }

    public static func step(wasWork: Bool?, isWork: Bool) -> Step {
        switch (wasWork, isWork) {
        case (true?, false): .workEnded
        case (false?, true): .workStarted
        default: .none
        }
    }

    /// Slack's status for the evening: "Offline, back 9:30 AM" (tomorrow) or "Offline, back Monday
    /// 9:30 AM" (a later day).
    public static func statusText(back: Date, now: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h:mm a"
        let time = f.string(from: back)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: back)).day ?? 0
        if days <= 1 { return "Offline, back \(time)" }
        f.dateFormat = "EEEE"
        return "Offline, back \(f.string(from: back)) \(time)"
    }
}
