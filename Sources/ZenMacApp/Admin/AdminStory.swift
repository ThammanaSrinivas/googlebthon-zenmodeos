import Foundation
import ZenAPI

/// The admin view's story, told from the dashboard's own numbers: the ROI line, the baseline, the
/// chart's weeks, the report's lead and rows, and the text the admin shares. Pure, so the screen
/// stays thin and every sentence is tested. Every function answers nil for an unpublished team
/// (under 5 people), so nothing here can put a number on screen there.
enum AdminStory {
    /// One week of the focus chart, oldest first.
    struct WeekPoint: Identifiable, Equatable {
        let id: String
        /// "W44", or "This week" for the newest.
        let label: String
        let hours: Double
    }

    /// The published weeks with focus hours, oldest first (the chart reads left to right).
    static func weeks(_ d: AdminDashboard) -> [WeekPoint] {
        guard d.published else { return [] }
        let published = d.trend.filter { $0.published && $0.focusH != nil }
        return published.reversed().map { w in
            WeekPoint(id: w.week, label: w.week == d.week ? AdminCopy.thisWeek : shortWeek(w.week), hours: w.focusH ?? 0)
        }
    }

    /// "2026-W47" → "W47".
    static func shortWeek(_ iso: String) -> String {
        guard let w = iso.split(separator: "-").last, w.hasPrefix("W") else { return iso }
        return String(w)
    }

    /// The baseline focus hours: the server's own figure from the formula, else the oldest
    /// published week of the trend.
    static func baseline(_ d: AdminDashboard) -> Double? {
        guard d.published else { return nil }
        if let formula = d.rupeeFormula,
           let match = formula.firstMatch(of: /([0-9]+(?:\.[0-9]+)?) h baseline/),
           let value = Double(match.1) {
            return value
        }
        return weeks(d).first?.hours
    }

    /// Focus hours per person a week above the baseline.
    static func gain(_ d: AdminDashboard) -> Double? {
        guard let now = d.cards.focusHours.now, let base = baseline(d) else { return nil }
        return now - base
    }

    /// The rupees a month, for one person (an average, never anyone's own).
    static func perPerson(_ d: AdminDashboard) -> Double? {
        guard d.published, let r = d.cards.rupeesPerMonth.now, let n = d.activeN, n > 0 else { return nil }
        return r / Double(n)
    }

    /// The monthly figure, for twelve months at this pace.
    static func yearly(_ d: AdminDashboard) -> Double? {
        guard d.published, let r = d.cards.rupeesPerMonth.now else { return nil }
        return r * 12
    }

    /// The one plain sentence under the big number.
    static func explanation(_ d: AdminDashboard) -> String? {
        guard d.published, let rupees = d.cards.rupeesPerMonth.now else { return nil }
        let worth = AdminFormat.rupees(rupees)
        let cost = AdminFormat.rupees(Double(d.hourlyCostInr))
        guard let gain = gain(d), gain > 0.04 else {
            return "What your team's extra focus time is worth at \(cost) an hour: \(worth) a month."
        }
        let hours = String(format: "%.1f", gain)
        return "Each person now gets \(hours) more focus hours a week than at the baseline. "
            + "At \(cost) an hour, that's \(worth) of work time back every month."
    }

    /// "Up ₹74,822 on last week" (the word says the direction, never colour alone).
    static func heroChange(_ d: AdminDashboard) -> String? {
        guard d.published, let c = d.cards.rupeesPerMonth.change else { return nil }
        let r = abs(c).rounded()
        if r == 0 { return "Same as last week" }
        return (c > 0 ? "Up " : "Down ") + AdminFormat.rupees(r) + " on last week"
    }

    /// The word beside a change: better, worse, or steady (after-hours going down is better).
    static func verdict(_ change: Double?, of kind: AdminCardKind) -> String? {
        guard change != nil else { return nil }
        switch AdminFormat.isImprovement(change, of: kind) {
        case true?: return "better"
        case false?: return "worse"
        case nil: return "steady"
        }
    }

    /// A metric's four weeks, oldest first (the sparkline).
    static func series(_ d: AdminDashboard, _ kind: AdminCardKind) -> [Double] {
        guard d.published else { return [] }
        return d.trend.filter(\.published).reversed().compactMap { w in
            switch kind {
            case .focusHours: w.focusH
            case .keptRate: w.keptRate
            case .afterHoursShare: w.afterHoursShare
            case .goodDayRate: w.goodDayRate
            case .rupeesPerMonth: nil
            }
        }
    }

    /// The published weeks' short labels, oldest first ("W44"…).
    static func trendLabels(_ d: AdminDashboard) -> [String] {
        guard d.published else { return [] }
        return d.trend.filter(\.published).reversed().map { shortWeek($0.week) }
    }

    /// Good days per week as cells out of seven, oldest week first (the report's pattern).
    static func goodDayCells(_ d: AdminDashboard) -> [Int] {
        series(d, .goodDayRate).map { min(7, max(0, Int(($0 * 7).rounded()))) }
    }

    // MARK: The report

    /// The report's first sentence (the lead) and the rest.
    static func lead(_ text: String) -> (lead: String, rest: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = trimmed.range(of: ". ") else { return (trimmed, nil) }
        let rest = trimmed[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return (String(trimmed[..<r.lowerBound]) + ".", rest.isEmpty ? nil : rest)
    }

    /// A bullet as a scannable row: the words, and the figure pulled out to the right.
    struct Row: Equatable {
        let text: String
        let figure: String?
        let symbol: String
        let isReward: Bool
    }

    static func row(_ bullet: String) -> Row {
        let symbol = symbol(for: bullet)
        let isReward = bullet.localizedCaseInsensitiveContains("gold")
        if let m = bullet.firstMatch(of: /^(.+?) from ([^ ]*[0-9][^ ]*) to ([^ ]*[0-9][^ ]*?)\.?$/) {
            return Row(text: String(m.1), figure: "\(m.2) → \(m.3)", symbol: symbol, isReward: isReward)
        }
        if let m = bullet.firstMatch(of: /^(.+?): ([0-9][0-9,]*(?:\.[0-9]+)?%?)\.?$/) {
            return Row(text: String(m.1), figure: String(m.2), symbol: symbol, isReward: isReward)
        }
        return Row(text: bullet, figure: nil, symbol: symbol, isReward: isReward)
    }

    static func symbol(for bullet: String) -> String {
        let b = bullet.lowercased()
        if b.contains("gold") { return "sparkles" }
        if b.contains("after-hours") || b.contains("after hours") || b.contains("evening") { return "moon.stars" }
        if b.contains("kept") || b.contains("block") { return "checkmark.seal" }
        if b.contains("good day") { return "sun.max" }
        if b.contains("focus") { return "scope" }
        return "chart.line.uptrend.xyaxis"
    }

    /// "Payments: try meeting-free mornings…" → "Try meeting-free mornings…".
    static func suggestion(_ text: String, team: String) -> String {
        let prefix = team + ": "
        guard !team.isEmpty, text.hasPrefix(prefix) else { return text }
        let rest = text.dropFirst(prefix.count)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// Who wrote the report. Never Gemini when it's the fixed text from the numbers.
    static func credit(_ r: PeopleReport) -> String {
        r.fallback ? AdminCopy.fromNumbers : AdminCopy.fromGemini
    }

    /// "2026-11" → "November 2026".
    static func monthName(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return month }
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                     "October", "November", "December"]
        return "\(names[m - 1]) \(parts[0])"
    }

    // MARK: Sharing

    /// The plain text the admin shares with leadership: team averages, the formula, the report.
    /// Nil under 5 people (there's nothing to share).
    static func shareText(_ d: AdminDashboard, report: PeopleReport?) -> String? {
        guard d.published, let rupees = d.cards.rupeesPerMonth.now else { return nil }
        var lines = ["\(d.name) · \(Copy.product) team report, \(shortWeek(d.week))", ""]
        lines.append("\(AdminFormat.rupees(rupees)) reclaimed a month" + (heroChange(d).map { " (\($0.lowercased()))" } ?? ""))
        if let f = d.rupeeFormula { lines.append("How we count: \(f)") }
        lines.append("")
        for kind in AdminCardKind.metrics {
            let card = kind.card(in: d.cards)
            let change = AdminFormat.change(card.change, of: kind).map { " (\($0) vs last week)" } ?? ""
            lines.append("\(kind.plainTitle): \(AdminFormat.value(card.now, of: kind))\(change)")
        }
        if let claims = d.gold.claimsThisMonth, let inr = d.gold.sponsoredInr {
            lines.append("Zen Gold: \(claims) \(claims == 1 ? "week" : "weeks") this month, \(AdminFormat.rupees(Double(inr))) sponsored")
        }
        if let report {
            lines.append("")
            lines.append("\(AdminCopy.reportTitle), \(monthName(report.month)) (\(credit(report).lowercased()))")
            lines.append(report.text)
            lines += report.bullets.map { "• \($0)" }
            if !report.suggestions.isEmpty {
                lines.append("Try:")
                lines += report.suggestions.map { "→ \(suggestion($0, team: d.name))" }
            }
        }
        lines.append("")
        var footer = d.activeN.map { AdminCopy.basedOn($0) + "." } ?? ""
        if d.includesDemo { footer += " Includes demo data." }
        lines.append((footer + " " + AdminCopy.privacy).trimmingCharacters(in: .whitespaces))
        return lines.joined(separator: "\n")
    }
}

extension AdminCardKind {
    /// The four that support the rupees, in reading order.
    static let metrics: [AdminCardKind] = [.focusHours, .keptRate, .afterHoursShare, .goodDayRate]

    /// The plain-language label on the Mac.
    var plainTitle: String {
        switch self {
        case .focusHours: "Focus hours per person"
        case .keptRate: "Focus blocks kept"
        case .afterHoursShare: "Days with after-hours work"
        case .goodDayRate: "Good days"
        case .rupeesPerMonth: "Reclaimed a month"
        }
    }

    /// What the number means, in one line.
    var meaning: String {
        switch self {
        case .focusHours: "Deep work a week, team average"
        case .keptRate: "Planned focus blocks people kept"
        case .afterHoursShare: "Lower is better: evenings stay free"
        case .goodDayRate: "Days with a Zen Score above 6.0"
        case .rupeesPerMonth: "Focus time above the baseline, in rupees"
        }
    }

    var symbol: String {
        switch self {
        case .focusHours: "scope"
        case .keptRate: "checkmark.seal"
        case .afterHoursShare: "moon.stars"
        case .goodDayRate: "sun.max"
        case .rupeesPerMonth: "indianrupeesign"
        }
    }
}
