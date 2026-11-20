// Day keys: the "yyyy-MM-dd" (ASCII digits) a day is filed under, in the zone it was lived in.
import Foundation
import ZenAPI

public enum DayKeys {
    /// No time zone runs further ahead of UTC than this (UTC+14, Kiribati), so a day past the UTC
    /// day of now + 14 h comes from a wrong clock.
    public static let furthestZoneAhead: TimeInterval = 14 * 3_600

    /// The day `date` falls on in `timeZone`, in ASCII digits whatever the device's locale.
    public static func key(for date: Date, in timeZone: TimeZone) -> DayKey {
        LocalDate.today(in: timeZone, now: date).description
    }

    /// The latest day any time zone has reached at `now`: the UTC day of now + 14 h.
    public static func latestAllowed(now: Date) -> DayKey {
        key(for: now.addingTimeInterval(furthestZoneAhead), in: utc)
    }

    /// A well-formed key: `yyyy-MM-dd`, ASCII digits, a real date.
    public static func isValid(_ key: DayKey) -> Bool { LocalDate.parse(key) != nil }

    /// The date a key names, nil when it isn't one.
    public static func date(_ key: DayKey) -> LocalDate? { LocalDate.parse(key) }

    /// The key `days` after `key` (before, for a negative count); nil for a malformed key.
    public static func adding(_ days: Int, to key: DayKey) -> DayKey? {
        LocalDate.parse(key)?.plusDays(days).description
    }

    /// The Monday of the Monday–Sunday week `key` falls in.
    public static func weekStart(of key: DayKey) -> DayKey? { LocalDate.parse(key)?.weekStart.description }

    static let utc = TimeZone(secondsFromGMT: 0)!
}
