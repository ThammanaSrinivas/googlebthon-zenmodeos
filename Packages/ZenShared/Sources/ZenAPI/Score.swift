import Foundation

/// A Zen Score, kept in tenths so 6.0 compares exactly (60 is not a good day, 61 is).
public struct ZenScore: Codable, Comparable, Hashable, Sendable {
    public let tenths: Int

    public init(tenths: Int) { self.tenths = min(max(tenths, 0), 100) }

    /// A good day is a Zen Score *above* 6.0.
    public static let goodDayThresholdTenths = 60

    public var isGoodDay: Bool { tenths > Self.goodDayThresholdTenths }

    /// "8.1", always one decimal, never localised digits.
    public var text: String { "\(tenths / 10).\(tenths % 10)" }

    public static func < (a: ZenScore, b: ZenScore) -> Bool { a.tenths < b.tenths }
}

/// Monday to Sunday in the home time zone. A day with no data is `nil`: not a good day, and not a zero.
public struct WeekProgress: Equatable, Sendable {
    public let days: [ZenScore?]
    /// Index of today (0 = Monday), or nil for a finished week.
    public let todayIndex: Int?
    /// Won weeks in a row before this one.
    public let streakBefore: Int

    public init(days: [ZenScore?], todayIndex: Int?, streakBefore: Int) {
        precondition(days.count == 7, "A week has seven days")
        self.days = days
        self.todayIndex = todayIndex
        self.streakBefore = streakBefore
    }

    public static let goodDaysToWin = 4

    public var goodDays: Int { days.compactMap { $0 }.filter(\.isGoodDay).count }

    /// A week is won the moment the 4th good day lands.
    public var isWon: Bool { goodDays >= Self.goodDaysToWin }

    /// The day the week was won on, if it was.
    public var winningDayIndex: Int? {
        var count = 0
        for (i, day) in days.enumerated() where day?.isGoodDay == true {
            count += 1
            if count == Self.goodDaysToWin { return i }
        }
        return nil
    }

    /// The week in progress never breaks the streak; a finished week short of 4 resets it.
    public var weeklyStreak: Int {
        if isWon { return streakBefore + 1 }
        return todayIndex == nil ? 0 : streakBefore
    }

    /// The one status line every surface uses.
    public var statusLine: String {
        if isWon { return "Week won · \(weeklyStreak)-week streak" }
        let left = Self.goodDaysToWin - goodDays
        if left == 1 { return "\(goodDays) of \(Self.goodDaysToWin) good days · one more wins the week" }
        return "\(goodDays) of \(Self.goodDaysToWin) good days this week"
    }
}

/// One row per device that counted toward today, without saying what anyone did on a phone.
public struct DeviceLine: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case iPhone, mac, windows, linux, android }

    public let id: String
    public let kind: Kind
    public let name: String
    /// What this device contributed, in words. An iPhone never shows minutes.
    public let detail: String
    public let isThisDevice: Bool

    public init(id: String, kind: Kind, name: String, detail: String, isThisDevice: Bool) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.isThisDevice = isThisDevice
    }
}

/// Today, as every device of one person sees it.
public struct ScoreSnapshot: Equatable, Sendable {
    public let score: ZenScore
    public let week: WeekProgress
    public let devices: [DeviceLine]
    public let updatedAt: Date

    public init(score: ZenScore, week: WeekProgress, devices: [DeviceLine], updatedAt: Date) {
        self.score = score
        self.week = week
        self.devices = devices
        self.updatedAt = updatedAt
    }
}

public protocol ScoreService: Sendable {
    func today() async throws -> ScoreSnapshot
    /// The snapshot now, then every change: within seconds on the real backend (a listener),
    /// every 30 s by default (`pollingUpdates`, Sync.swift).
    func updates() -> AsyncStream<ScoreSnapshot>
}
