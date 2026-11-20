import Foundation

/// "Zeno, focus 40 min", "focus for 90 minutes", "focus until 12", "focus until 18:30": what the
/// person typed (⌘K) or said, as a focus length. Nil for anything else.
public enum FocusCommand: Equatable, Sendable {
    case minutes(Int)
    /// A clock time today (24-hour), or tomorrow if it has passed.
    case until(hour: Int, minute: Int)

    /// Lengths are 5…720 minutes.
    public static func parse(_ text: String) -> FocusCommand? {
        let s = text.lowercased().replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let body = s.hasPrefix("zeno ") ? String(s.dropFirst(5)) : s
        guard body.hasPrefix("focus") else { return nil }
        let rest = body.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("until") {
            let t = rest.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let parts = t.split(separator: ":")
            guard let h = parts.first.flatMap({ Int($0) }), (0...23).contains(h) else { return nil }
            let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? -1 : 0
            guard (0...59).contains(m) else { return nil }
            return .until(hour: h, minute: m)
        }
        let words = rest.split(separator: " ").map(String.init).filter { $0 != "for" }
        guard let first = words.first else { return nil }
        let digits = first.prefix { $0.isNumber }
        guard let n = Int(digits), n > 0 else { return nil }
        let unit = String(first.dropFirst(digits.count)) + (words.count > 1 ? words[1] : "")
        let minutes = unit.hasPrefix("h") ? n * 60 : n
        guard (5...720).contains(minutes) else { return nil }
        return .minutes(minutes)
    }

    /// The end time from `now`.
    public func until(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .minutes(let m): return now.addingTimeInterval(TimeInterval(m * 60))
        case .until(let h, let m):
            let today = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
    }

    public var label: String {
        switch self {
        case .minutes(let m): m % 60 == 0 && m >= 60 ? "Focus \(m / 60) h" : "Focus \(m) min"
        case .until(let h, let m): String(format: "Focus until %02d:%02d", h, m)
        }
    }
}
