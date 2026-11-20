// The team admin's view, inside the app (the same numbers as the web admin page): five cards with
// this week, last week and the change, a 4-week trend, Zen Gold counts, the rupee formula, and the
// monthly people report. Every number is a server-side aggregate of 5 or more people with data;
// under that, `published` is false and every number is nil. Never a name next to a number.
import Foundation

/// One card: this week, last week, the change (nil when a week isn't published).
public struct AdminCard: Codable, Equatable, Sendable {
    public let now: Double?
    public let last: Double?
    public let change: Double?

    public init(now: Double?, last: Double?, change: Double?) {
        self.now = now
        self.last = last
        self.change = change
    }

    public static let empty = AdminCard(now: nil, last: nil, change: nil)
}

/// The five cards. Rates are 0...1; focus hours per person per week; rupees per month.
public struct AdminCards: Codable, Equatable, Sendable {
    public let focusHours: AdminCard
    public let keptRate: AdminCard
    public let afterHoursShare: AdminCard
    public let goodDayRate: AdminCard
    public let rupeesPerMonth: AdminCard

    public init(focusHours: AdminCard, keptRate: AdminCard, afterHoursShare: AdminCard, goodDayRate: AdminCard,
                rupeesPerMonth: AdminCard) {
        self.focusHours = focusHours
        self.keptRate = keptRate
        self.afterHoursShare = afterHoursShare
        self.goodDayRate = goodDayRate
        self.rupeesPerMonth = rupeesPerMonth
    }
}

/// One week of the trend, newest first.
public struct AdminTrendWeek: Codable, Equatable, Sendable {
    /// ISO week, "2026-W47".
    public let week: String
    public let published: Bool
    public let focusH: Double?
    public let keptRate: Double?
    public let afterHoursShare: Double?
    public let goodDayRate: Double?

    public init(week: String, published: Bool, focusH: Double?, keptRate: Double?, afterHoursShare: Double?,
                goodDayRate: Double?) {
        self.week = week
        self.published = published
        self.focusH = focusH
        self.keptRate = keptRate
        self.afterHoursShare = afterHoursShare
        self.goodDayRate = goodDayRate
    }
}

/// Zen Gold this month: counts only.
public struct AdminGold: Codable, Equatable, Sendable {
    public let claimsThisMonth: Int?
    public let sponsoredInr: Int?

    public init(claimsThisMonth: Int?, sponsoredInr: Int?) {
        self.claimsThisMonth = claimsThisMonth
        self.sponsoredInr = sponsoredInr
    }
}

/// What the admin view shows (the adminDashboard callable's answer, decoded as it is).
public struct AdminDashboard: Codable, Equatable, Sendable {
    public let name: String
    /// This ISO week.
    public let week: String
    public let membersN: Int
    /// People with data this week ("Based on N people"); nil under the gate.
    public let activeN: Int?
    /// Show "includes demo data".
    public let includesDemo: Bool
    /// False: "Team numbers appear at 5 people", and no number anywhere.
    public let published: Bool
    public let hourlyCostInr: Int
    public let goldSponsorInr: Int
    public let orgBrainText: String
    public let cards: AdminCards
    public let trend: [AdminTrendWeek]
    public let gold: AdminGold
    /// "(12.9 h now − 9.2 h baseline) × 12 people × 4.33 weeks × ₹1,200/h = ₹2,30,702 a month".
    public let rupeeFormula: String?

    public init(name: String, week: String, membersN: Int, activeN: Int?, includesDemo: Bool, published: Bool,
                hourlyCostInr: Int, goldSponsorInr: Int, orgBrainText: String, cards: AdminCards,
                trend: [AdminTrendWeek], gold: AdminGold, rupeeFormula: String?) {
        self.name = name
        self.week = week
        self.membersN = membersN
        self.activeN = activeN
        self.includesDemo = includesDemo
        self.published = published
        self.hourlyCostInr = hourlyCostInr
        self.goldSponsorInr = goldSponsorInr
        self.orgBrainText = orgBrainText
        self.cards = cards
        self.trend = trend
        self.gold = gold
        self.rupeeFormula = rupeeFormula
    }
}

/// The monthly people report (Gemini, from team aggregates only; `fallback` when it's the fixed
/// text from the numbers).
public struct PeopleReport: Codable, Equatable, Sendable {
    /// "2026-11".
    public let month: String
    public let text: String
    public let bullets: [String]
    public let suggestions: [String]
    public let fallback: Bool
    public let model: String?
    public let cached: Bool

    public init(month: String, text: String, bullets: [String], suggestions: [String], fallback: Bool,
                model: String?, cached: Bool) {
        self.month = month
        self.text = text
        self.bullets = bullets
        self.suggestions = suggestions
        self.fallback = fallback
        self.model = model
        self.cached = cached
    }
}

/// The team the signed-in person administers.
public struct AdminTeam: Equatable, Sendable {
    public let cohortId: String
    public let name: String

    public init(cohortId: String, name: String) {
        self.cohortId = cohortId
        self.name = name
    }
}

public enum AdminError: Error, Equatable, Sendable {
    /// Not signed in.
    case signedOut
    /// Signed in, but not this team's admin (the server refuses everyone else).
    case notAdmin
    case invalid
    case offline
}

/// The admin's side of the app. Show the admin view only when `adminTeam()` answers a team.
public protocol AdminService: Sendable {
    /// The team the signed-in person administers, or nil (a member, or no team).
    func adminTeam() async throws(AdminError) -> AdminTeam?
    /// adminDashboard: refreshes this week and last week on the server, then answers.
    func dashboard(cohortId: String) async throws(AdminError) -> AdminDashboard
    /// cohortReport: the cached report for the month, or a new one with `regenerate` (can take ~20 s).
    func peopleReport(cohortId: String, month: String, regenerate: Bool) async throws(AdminError) -> PeopleReport
}

// MARK: - Display helpers (pure, so the screen stays thin and the tests run on Linux)

public enum AdminFormat {
    /// "₹2,30,702" (Indian grouping); negative "−₹62,352".
    public static func rupees(_ value: Double) -> String {
        let n = Int(value.rounded())
        let digits = String(abs(n))
        var grouped = digits
        if digits.count > 3 {
            let last3 = digits.suffix(3)
            var rest = String(digits.dropLast(3))
            var parts: [String] = []
            while rest.count > 2 {
                parts.insert(String(rest.suffix(2)), at: 0)
                rest = String(rest.dropLast(2))
            }
            if !rest.isEmpty { parts.insert(rest, at: 0) }
            grouped = parts.joined(separator: ",") + "," + last3
        }
        return (n < 0 ? "−₹" : "₹") + grouped
    }

    /// "83%" from 0.83.
    public static func percent(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }

    /// "12.9 h".
    public static func hours(_ value: Double) -> String { String(format: "%.1f h", value) }

    /// The value as its card shows it, or "–" when nil.
    public static func value(_ value: Double?, of kind: AdminCardKind) -> String {
        guard let value else { return "–" }
        switch kind {
        case .focusHours: return hours(value)
        case .keptRate, .afterHoursShare, .goodDayRate: return percent(value)
        case .rupeesPerMonth: return rupees(value)
        }
    }

    /// "+1.2 h", "−5 pts", "+₹74,822", "no change", or nil when a week is missing.
    public static func change(_ change: Double?, of kind: AdminCardKind) -> String? {
        guard let change else { return nil }
        let sign = change > 0 ? "+" : change < 0 ? "−" : ""
        switch kind {
        case .focusHours:
            let tenths = (abs(change) * 10).rounded() / 10
            return tenths == 0 ? "no change" : "\(sign)\(String(format: "%.1f", tenths)) h"
        case .keptRate, .afterHoursShare, .goodDayRate:
            let points = Int((abs(change) * 100).rounded())
            return points == 0 ? "no change" : "\(sign)\(points) pts"
        case .rupeesPerMonth:
            let r = abs(change).rounded()
            return r == 0 ? "no change" : sign + rupees(r)
        }
    }

    /// Whether the change is good news (after-hours going down is good).
    public static func isImprovement(_ change: Double?, of kind: AdminCardKind) -> Bool? {
        guard let change, change != 0 else { return nil }
        return kind == .afterHoursShare ? change < 0 : change > 0
    }
}

/// The five cards, in the order the admin view shows them, with their titles.
public enum AdminCardKind: String, CaseIterable, Sendable {
    case focusHours, keptRate, afterHoursShare, goodDayRate, rupeesPerMonth

    public var title: String {
        switch self {
        case .focusHours: "Focus hours per person"
        case .keptRate: "Focus blocks kept"
        case .afterHoursShare: "After-hours days"
        case .goodDayRate: "Good-day rate"
        case .rupeesPerMonth: "Reclaimed per month"
        }
    }

    public func card(in cards: AdminCards) -> AdminCard {
        switch self {
        case .focusHours: cards.focusHours
        case .keptRate: cards.keptRate
        case .afterHoursShare: cards.afterHoursShare
        case .goodDayRate: cards.goodDayRate
        case .rupeesPerMonth: cards.rupeesPerMonth
        }
    }
}
