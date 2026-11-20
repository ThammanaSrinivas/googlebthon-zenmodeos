import Foundation

/// The three answers from onboarding. They stay on this Mac.
public struct Profile: Codable, Equatable, Sendable {
    /// Who this seat is for. Campus and team seats join a cohort with a code.
    public enum Seat: String, Codable, CaseIterable, Sendable { case personal, campus, team }

    /// What the computer is for. Time on these never counts against the score.
    public enum Use: String, Codable, CaseIterable, Sendable { case study, work, build, create, everything }

    public var seat: Seat
    public var uses: Set<Use>
    public var quiet: QuietHours
    public var cohortCode: String?

    public init(seat: Seat = .personal, uses: Set<Use> = [], quiet: QuietHours = .none, cohortCode: String? = nil) {
        self.seat = seat
        self.uses = uses
        self.quiet = quiet
        self.cohortCode = cohortCode
    }
}

/// When Zeno stays quiet: a daytime block the person chose (class or work hours) on some
/// weekdays, plus the night (22:30–07:00), which is always quiet.
public struct QuietHours: Codable, Equatable, Hashable, Sendable {
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    /// Minutes after midnight; the block runs from `start` up to `end`, within one day.
    public var start: Int
    public var end: Int

    public init(weekdays: Set<Int>, start: Int, end: Int) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
    }

    public static let nightStart = 22 * 60 + 30
    public static let nightEnd = 7 * 60
    static let monToFri: Set<Int> = [2, 3, 4, 5, 6]

    public static let none = QuietHours(weekdays: [], start: 0, end: 0)
    public static let classHours = QuietHours(weekdays: monToFri, start: 9 * 60, end: 16 * 60)
    public static let workHours = QuietHours(weekdays: monToFri, start: 10 * 60, end: 18 * 60)

    public func isQuiet(at date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if minute >= Self.nightStart || minute < Self.nightEnd { return true }
        guard let weekday = parts.weekday, weekdays.contains(weekday) else { return false }
        return minute >= start && minute < end
    }

    /// True for the hour cell `hour` (0–23) on a weekday in the block, for the 24-cell strip.
    public func hourIsQuiet(_ hour: Int) -> Bool {
        let a = hour * 60, b = a + 60
        let night = a >= Self.nightStart - 30 || b <= Self.nightEnd
        let block = !weekdays.isEmpty && a < end && b > start
        return night || block
    }

    /// "Weekdays 9–4", "Not in the day".
    public var summary: String {
        if weekdays.isEmpty || start == end { return "Only at night" }
        let days = weekdays == Self.monToFri ? "Weekdays" : "\(weekdays.count) days a week"
        return "\(days) \(Self.clock(start))–\(Self.clock(end))"
    }

    static func clock(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m == 0 ? "\(h12)" : "\(h12):\(String(format: "%02d", m))"
    }
}
