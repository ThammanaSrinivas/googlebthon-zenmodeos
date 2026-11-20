// A calendar date with no time and no zone (java.time.LocalDate's twin, ported from the ZenMode OS
// iOS core logic): epoch-day arithmetic, Monday-first weeks. The places that touch a clock or a
// zone are `LocalDate.today(in:now:)` and `startOfDay(in:)`; everything else is plain maths, so
// the rules built on it test without a clock.
import Foundation

public enum DayOfWeek: Int, Sendable, CaseIterable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// `value` in java.time: Monday = 1 … Sunday = 7.
    public var value: Int { rawValue }

    public static func < (lhs: DayOfWeek, rhs: DayOfWeek) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Days since 1970-01-01 (negative before it). The only stored field.
    public let epochDay: Int

    public init(epochDay: Int) { self.epochDay = epochDay }

    /// `LocalDate.of(2026, 11, 20)`. Traps on an impossible date, like java.time.
    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month), "month out of range: \(month)")
        precondition(day >= 1 && day <= LocalDate.lengthOfMonth(year: year, month: month), "day out of range: \(day)")
        epochDay = LocalDate.daysFromCivil(year: year, month: month, day: day)
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var dayOfMonth: Int { civil.day }

    /// 1970-01-01 was a Thursday (ISO 4).
    public var dayOfWeek: DayOfWeek {
        let shifted = ((epochDay + 3) % 7 + 7) % 7
        return DayOfWeek(rawValue: shifted + 1)!
    }

    public func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }
    public func minusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay - n) }
    public func plusWeeks(_ n: Int) -> LocalDate { plusDays(n * 7) }
    public func minusWeeks(_ n: Int) -> LocalDate { minusDays(n * 7) }

    /// Days from `self` to `other`: positive when `other` is later.
    public func daysUntil(_ other: LocalDate) -> Int { other.epochDay - epochDay }

    /// The Monday of this date's Monday–Sunday week.
    public var weekStart: LocalDate { minusDays(dayOfWeek.value - 1) }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.epochDay < rhs.epochDay }

    /// ISO-8601 `yyyy-MM-dd` in ASCII digits: the `DayKey` spelling.
    public var description: String {
        let c = civil
        return pad(c.year, 4) + "-" + pad(c.month, 2) + "-" + pad(c.day, 2)
    }

    /// The date of a `yyyy-MM-dd` key in ASCII digits; nil for anything else.
    public static func parse(_ text: String) -> LocalDate? {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for i in range {
                let b = bytes[i]
                guard b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(b - UInt8(ascii: "0"))
            }
            return value
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10),
              (1...12).contains(m), d >= 1, d <= lengthOfMonth(year: y, month: m)
        else { return nil }
        return LocalDate(year: y, month: m, day: d)
    }

    // ── Clock and zone ────────────────────────────────────────────

    /// The date it is at `now` in `timeZone`.
    public static func today(in timeZone: TimeZone, now: Date) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Local midnight at the start of this date in `timeZone` (right across a DST change too).
    public func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) {
            return calendar.startOfDay(for: date)
        }
        return Date(timeIntervalSince1970: TimeInterval(epochDay) * 86_400)
    }

    // ── Civil calendar maths (Howard Hinnant's algorithms) ────────

    private var civil: (year: Int, month: Int, day: Int) { LocalDate.civilFromDays(epochDay) }

    static func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func lengthOfMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

private func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(abs(value))
    let padded = String(repeating: "0", count: max(width - digits.count, 0)) + digits
    return value < 0 ? "-" + padded : padded
}
