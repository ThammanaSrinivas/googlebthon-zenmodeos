import Foundation
import ZenAPI

/// The admin view without a backend (skip sign-in, the open-source build, the tests): the demo team
/// "Payments" of 12 people, 4 weeks of focus data, the same numbers the backend computes for its demo
/// seed (the private contract test checks they agree), labelled with this week and the 3 before it.
/// Always "includes demo data"; the report is the fixed one (fallback), never credited to Gemini.
public struct FakeAdmin: AdminService {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public static let cohortId = "demo"

    public func adminTeam() async throws(AdminError) -> AdminTeam? {
        AdminTeam(cohortId: Self.cohortId, name: "Payments")
    }

    public func dashboard(cohortId: String) async throws(AdminError) -> AdminDashboard {
        Self.seeded(weeks: Self.isoWeeks(endingAt: now()))
    }

    public func peopleReport(cohortId: String, month: String, regenerate: Bool) async throws(AdminError) -> PeopleReport {
        PeopleReport(
            month: month,
            text: "Payments averaged 11.7 focus hours per person a week this month, across 3 counted weeks. "
                + "Focus time rose from 10.4 to 12.9 hours, and evenings got quieter.",
            bullets: [
                "Focus blocks kept rose from 58% to 83%.",
                "Days with after-hours work fell from 15% to 5%.",
                "Good days rose from 70% to every day counted.",
                "Zen Gold weeks this month: 2.",
            ],
            suggestions: [
                "Payments: try meeting-free mornings twice a week.",
                "Protect the evenings: end the day with a shared wrap-up time.",
            ],
            fallback: true, model: nil, cached: !regenerate)
    }

    /// The demo team's dashboard. `weeks` is newest first (this week, then the 3 before it).
    public static func seeded(weeks: [String]) -> AdminDashboard {
        let focus: [Double] = [12.9, 11.7, 10.4, 9.2]
        let kept: [Double] = [0.83, 0.83, 0.58, 0.58]
        let after: [Double] = [0.05, 0.1, 0.15, 0.2]
        let good: [Double] = [1, 0.9, 0.7, 0.4]
        let trend = weeks.prefix(4).enumerated().map { i, week in
            AdminTrendWeek(week: week, published: true, focusH: focus[i], keptRate: kept[i],
                           afterHoursShare: after[i], goodDayRate: good[i])
        }
        return AdminDashboard(
            name: "Payments", week: weeks.first ?? "", membersN: 12, activeN: 12, includesDemo: true, published: true,
            hourlyCostInr: 1200, goldSponsorInr: 250,
            orgBrainText: "Q4 goal: ship UPI autopay by 15 Dec. Meeting-free mornings on Tuesday and Thursday.",
            cards: AdminCards(
                focusHours: AdminCard(now: 12.9, last: 11.7, change: 1.2),
                keptRate: AdminCard(now: 0.83, last: 0.83, change: 0),
                afterHoursShare: AdminCard(now: 0.05, last: 0.1, change: -0.05),
                goodDayRate: AdminCard(now: 1, last: 0.9, change: 0.1),
                rupeesPerMonth: AdminCard(now: 230_702, last: 155_880, change: 74_822)),
            trend: Array(trend),
            gold: AdminGold(claimsThisMonth: 2, sponsoredInr: 500),
            rupeeFormula: "(12.9 h now − 9.2 h baseline) × 12 people × 4.33 weeks × ₹1,200/h = ₹2,30,702 a month")
    }

    /// The ISO week of `date` in India (the teams' time zone) and the 3 before it, newest first.
    public static func isoWeeks(endingAt date: Date) -> [String] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return (0..<4).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -7 * back, to: date) else { return nil }
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            guard let year = c.yearForWeekOfYear, let week = c.weekOfYear else { return nil }
            return String(format: "%04d-W%02d", year, week)
        }
    }
}
