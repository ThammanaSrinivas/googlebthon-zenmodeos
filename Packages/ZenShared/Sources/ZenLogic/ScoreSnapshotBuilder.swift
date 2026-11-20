// Turns the account's combined day and its recent history into the `ScoreSnapshot` every device
// shows: today's score, the Monday–Sunday week and one line per device that counted.
import Foundation
import ZenAPI

public enum ScoreSnapshotBuilder {
    /// The phone's `DeviceLine.id`. A computer's line id is its device id.
    public static let phoneLineId = "phone"

    /// - Parameters:
    ///   - combined: the account's combined day, if any device has published.
    ///   - history: combined scores (tenths) of recent days, at least this week's; `combined` wins
    ///     for its own day.
    ///   - streakBefore: won weeks in a row before this one.
    ///   - today: today in the home time zone.
    ///   - thisDeviceId: the line to mark as this device: a computer's device id, or `phoneLineId`.
    ///   - now: when nothing has published, the snapshot's time.
    ///
    /// A day with no data stays empty in the week (not a good day, not a zero). Until something
    /// counts today the score reads as an untouched day (10.0) and no device is listed.
    public static func make(combined: CombinedDay?, history: [DayKey: Int], streakBefore: Int,
                            today: DayKey, thisDeviceId: String?, now: Date) -> ScoreSnapshot {
        var byDay = history
        if let combined { byDay[combined.day] = combined.score.tenths }
        let todays = combined.flatMap { $0.day == today ? $0 : nil }

        return ScoreSnapshot(
            score: todays?.score ?? ZenScoreRule.untouchedDay,
            week: week(byDay: byDay, today: today, streakBefore: streakBefore),
            devices: todays.map { lines(for: $0, thisDeviceId: thisDeviceId) } ?? [],
            updatedAt: todays?.updatedAt ?? now)
    }

    /// Monday to Sunday around `today`; days after today are always empty.
    public static func week(byDay: [DayKey: Int], today: DayKey, streakBefore: Int) -> WeekProgress {
        guard let date = LocalDate.parse(today) else {
            return WeekProgress(days: Array(repeating: nil, count: 7), todayIndex: nil, streakBefore: streakBefore)
        }
        let monday = date.weekStart
        let todayIndex = monday.daysUntil(date)
        let days: [ZenScore?] = (0..<7).map { i in
            guard i <= todayIndex else { return nil }
            return byDay[monday.plusDays(i).description].map(ZenScore.init(tenths:))
        }
        return WeekProgress(days: days, todayIndex: todayIndex, streakBefore: streakBefore)
    }

    /// One line per device that counted, in the combine's order (the phone first).
    public static func lines(for day: CombinedDay, thisDeviceId: String?) -> [DeviceLine] {
        var seen: [DeviceLine.Kind: Int] = [:]
        return day.countedDevices.map { device in
            let id = device.kind == .phone ? phoneLineId : (device.deviceId ?? "")
            let kind = lineKind(device.platform)
            let isThis = id == thisDeviceId
            var ordinal = 1
            if !isThis {
                seen[kind, default: 0] += 1
                ordinal = seen[kind, default: 1]
            }
            return DeviceLine(id: id, kind: kind, name: name(device.platform, isThisDevice: isThis, ordinal: ordinal),
                              detail: detail(device), isThisDevice: isThis)
        }
    }

    /// What a device contributed, in words. A phone never shows minutes here; a computer shows its
    /// own distracting minutes and pull-backs ("38 m distracting · 4 pull-backs").
    public static func detail(_ device: DeviceContribution) -> String {
        guard device.kind == .computer else { return "Counted on the phone" }
        let pullBacks = device.pullBacks ?? 0
        return "\(duration(minutes: device.minutes ?? 0)) distracting · \(pullBacks) pull-back\(pullBacks == 1 ? "" : "s")"
    }

    /// "38 m", "1 h", "2 h 5 m". ASCII digits whatever the locale.
    public static func duration(minutes: Int) -> String {
        let m = max(minutes, 0)
        if m < 60 { return "\(m) m" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m"
    }

    static func lineKind(_ platform: DevicePlatform) -> DeviceLine.Kind {
        switch platform {
        case .ios, .ipados: return .iPhone
        case .android: return .android
        case .macos: return .mac
        case .windows: return .windows
        case .linux: return .linux
        }
    }

    /// "This Mac", "Mac", "Mac 2", "iPhone".
    static func name(_ platform: DevicePlatform, isThisDevice: Bool, ordinal: Int) -> String {
        let base: String
        switch platform {
        case .ios: base = "iPhone"
        case .ipados: base = "iPad"
        case .android: base = "Android phone"
        case .macos: base = "Mac"
        case .windows: base = "Windows PC"
        case .linux: base = "Linux PC"
        }
        if isThisDevice { return "This \(base)" }
        return ordinal > 1 ? "\(base) \(ordinal)" : base
    }
}
