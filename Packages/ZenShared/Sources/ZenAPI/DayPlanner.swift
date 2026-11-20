import Foundation

/// "HH:mm" maths for the day plan, and the plain slotter the app falls back on when zenoPlanDay
/// can't be reached (the server has the same one for its own fallback).
public enum DayPlanner {
    /// Minutes since midnight, or nil for anything that isn't "HH:mm" (00:00…23:59, or 24:00).
    public static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0...24).contains(h), (0...59).contains(m),
              h * 60 + m <= 1440 else { return nil }
        return h * 60 + m
    }

    public static func text(_ minutes: Int) -> String {
        let m = min(max(minutes, 0), 1440)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "HH:mm" of `date` in `timeZone`.
    public static func text(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return text((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Today's `hhmm` as a date (in `timeZone`), on the day of `day`.
    public static func date(_ hhmm: String, on day: Date, timeZone: TimeZone = .current) -> Date? {
        guard let m = minutes(hhmm) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: day).addingTimeInterval(TimeInterval(m * 60))
    }

    /// Up to `count` free blocks of `length` minutes from `now` (rounded up to 5) to `dayEnd`, around
    /// `busy`, with a 10-minute break between them. Titled "Focus block".
    public static func slots(now: String, dayEnd: String, busy: [DayBlock], count: Int, length: Int = 50) -> [DayBlock] {
        guard let start = minutes(now), let end = minutes(dayEnd), count > 0, length > 0 else { return [] }
        let taken = busy.compactMap { b -> (Int, Int)? in
            guard let s = minutes(b.start), let e = minutes(b.end), e > s else { return nil }
            return (s, e)
        }.sorted { $0.0 < $1.0 }
        var cursor = (start + 4) / 5 * 5
        var out: [DayBlock] = []
        while out.count < count, cursor + length <= end {
            if let clash = taken.first(where: { $0.0 < cursor + length && $0.1 > cursor }) {
                cursor = (clash.1 + 4) / 5 * 5
                continue
            }
            out.append(DayBlock(start: text(cursor), end: text(cursor + length), title: "Focus block"))
            cursor += length + 10
        }
        return out
    }
}
