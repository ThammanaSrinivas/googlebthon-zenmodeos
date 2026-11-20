import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenMacApp

/// An admin service that can be a member (no team), refuse, be offline, or be under the 5+ gate.
final class StubAdmin: AdminService, @unchecked Sendable {
    enum Mode { case admin, member, notAdmin, offline, unpublished }
    var mode: Mode
    var reportFails = false
    /// Pauses before answering, so a test can see the in-between state.
    var pause: Duration?
    private(set) var regenerated = 0
    init(_ mode: Mode) { self.mode = mode }

    func adminTeam() async throws(AdminError) -> AdminTeam? {
        switch mode {
        case .member: return nil
        case .offline: throw .offline
        default: return AdminTeam(cohortId: "c1", name: "Payments")
        }
    }

    func dashboard(cohortId: String) async throws(AdminError) -> AdminDashboard {
        if let pause { try? await Task.sleep(for: pause) }
        switch mode {
        case .notAdmin: throw .notAdmin
        case .offline: throw .offline
        case .unpublished:
            return AdminDashboard(name: "Payments", week: "2026-W47", membersN: 4, activeN: nil, includesDemo: false, published: false,
                                  hourlyCostInr: 1200, goldSponsorInr: 0, orgBrainText: "",
                                  cards: AdminCards(focusHours: .empty, keptRate: .empty, afterHoursShare: .empty, goodDayRate: .empty,
                                                    rupeesPerMonth: .empty),
                                  trend: [], gold: AdminGold(claimsThisMonth: nil, sponsoredInr: nil), rupeeFormula: nil)
        default: return try await FakeAdmin().dashboard(cohortId: cohortId)
        }
    }

    func peopleReport(cohortId: String, month: String, regenerate: Bool) async throws(AdminError) -> PeopleReport {
        if regenerate { regenerated += 1 }
        if regenerate, let pause { try? await Task.sleep(for: pause) }
        if reportFails { throw .offline }
        return try await FakeAdmin().peopleReport(cohortId: cohortId, month: month, regenerate: regenerate)
    }
}

@MainActor
@Suite("Team admin on the Mac")
struct AdminTests {
    @Test("The section shows only for the team's admin")
    func visibility() async {
        #expect(!TodayView.Section.visible(isAdmin: false).contains(.admin))
        #expect(TodayView.Section.visible(isAdmin: true).contains(.admin))
        let a = AdminModel()
        await a.refreshTeam(StubAdmin(.member))
        #expect(a.team == nil)
        await a.refreshTeam(StubAdmin(.offline))
        #expect(a.team == nil)
        await a.refreshTeam(FakeAdmin())
        #expect(a.team?.name == "Payments")
    }

    @Test("The demo team loads: five cards, the trend, gold, and the report from the numbers")
    func loads() async throws {
        let a = AdminModel()
        await a.refreshTeam(FakeAdmin())
        await a.refresh(FakeAdmin())
        let d = try #require(a.dashboard)
        #expect(d.published && d.activeN == 12 && d.includesDemo)
        #expect(AdminCardKind.allCases.map { AdminFormat.value($0.card(in: d.cards).now, of: $0) }.count == 5)
        #expect(d.trend.count == 4)
        guard case .loaded(let r) = a.report else { Issue.record("no report"); return }
        #expect(r.fallback && r.bullets.count == 4 && r.suggestions.count == 2)
    }

    @Test("Refused by the server: the section goes away")
    func notAdmin() async {
        let a = AdminModel()
        let s = StubAdmin(.notAdmin)
        await a.refreshTeam(s)
        await a.refresh(s)
        #expect(a.team == nil && a.load == .idle)
    }

    @Test("Offline: a retryable state, then the numbers once back")
    func offline() async {
        let a = AdminModel()
        let s = StubAdmin(.admin)
        await a.refreshTeam(s)
        s.mode = .offline
        await a.refresh(s)
        #expect(a.load == .offline)
        s.mode = .admin
        await a.refresh(s)
        #expect(a.dashboard != nil)
    }

    @Test("Under 5 people: published is false and no number is there to show")
    func unpublished() async throws {
        let a = AdminModel()
        let s = StubAdmin(.unpublished)
        await a.refreshTeam(s)
        await a.refresh(s)
        let d = try #require(a.dashboard)
        #expect(!d.published && d.activeN == nil)
        #expect(AdminCardKind.allCases.allSatisfy { $0.card(in: d.cards).now == nil })
        // The report is written from the numbers, so it isn't asked for either.
        #expect(a.report == .idle)
        // Nothing the page draws can carry a number.
        #expect(AdminStory.explanation(d) == nil && AdminStory.heroChange(d) == nil)
        #expect(AdminStory.baseline(d) == nil && AdminStory.perPerson(d) == nil && AdminStory.yearly(d) == nil)
        #expect(AdminStory.weeks(d).isEmpty && AdminStory.goodDayCells(d).isEmpty && AdminStory.trendLabels(d).isEmpty)
        #expect(AdminCardKind.metrics.allSatisfy { AdminStory.series(d, $0).isEmpty })
        #expect(AdminStory.shareText(d, report: nil) == nil)
    }

    @Test("Loading: the numbers show as loading until the server answers")
    func loading() async throws {
        let a = AdminModel()
        let s = StubAdmin(.admin)
        await a.refreshTeam(s)
        s.pause = .milliseconds(300)
        let task = Task { await a.refresh(s) }
        #expect(await eventually { a.load == .loading })
        await task.value
        #expect(a.dashboard != nil)
    }

    @Test("Regenerating: the old report stays (dimmed) while the new one is written")
    func regenerating() async throws {
        let a = AdminModel()
        let s = StubAdmin(.admin)
        await a.refreshTeam(s)
        await a.refresh(s)
        guard case .loaded(let old) = a.report else { Issue.record("no report"); return }
        s.pause = .milliseconds(300)
        let task = Task { await a.loadReport(s, regenerate: true) }
        #expect(await eventually { a.report == .regenerating(old) })
        await task.value
        guard case .loaded(let new) = a.report else { Issue.record("no new report"); return }
        #expect(!new.cached && s.regenerated == 1)
    }

    @Test("Regenerate asks again; if that fails the old report stays")
    func regenerate() async {
        let a = AdminModel()
        let s = StubAdmin(.admin)
        await a.refreshTeam(s)
        await a.refresh(s)
        s.reportFails = true
        await a.loadReport(s, regenerate: true)
        #expect(s.regenerated == 1)
        guard case .loaded = a.report else { Issue.record("the old report should stay"); return }
    }

    @Test("The report's month is India's month")
    func month() {
        // 2026-11-30 19:00 UTC is 1 Dec 00:30 in India.
        #expect(AdminModel.month(Date(timeIntervalSince1970: 1_796_065_200)) == "2026-12")
        #expect(AdminModel.month(Date(timeIntervalSince1970: 1_795_156_200)) == "2026-11")
    }
}

@MainActor
@Suite("Team admin: opening the section before the team is known")
struct AdminOrderTests {
    @Test("refresh asks for the team first, then loads the numbers")
    func refreshFindsTheTeam() async {
        let a = AdminModel()
        await a.refresh(FakeAdmin())
        #expect(a.team != nil && a.dashboard != nil)
    }
}

@Suite("Team admin: the ROI story, from the dashboard's own numbers")
struct AdminStoryTests {
    let d = FakeAdmin.seeded(weeks: ["2026-W47", "2026-W46", "2026-W45", "2026-W44"])

    @Test("The hero: the baseline, the gain, the change and one plain sentence")
    func hero() throws {
        #expect(AdminStory.baseline(d) == 9.2)
        let gain = try #require(AdminStory.gain(d))
        #expect(abs(gain - 3.7) < 0.001)
        #expect(AdminStory.heroChange(d) == "Up ₹74,822 on last week")
        #expect(AdminStory.explanation(d) == "Each person now gets 3.7 more focus hours a week than at the baseline. "
            + "At ₹1,200 an hour, that's ₹2,30,702 of work time back every month.")
        #expect(AdminStory.perPerson(d).map { AdminFormat.rupees($0) } == "₹19,225")
        #expect(AdminStory.yearly(d).map { AdminFormat.rupees($0) } == "₹27,68,424")
    }

    @Test("Without the formula the baseline is the oldest published week")
    func baselineFallback() {
        let noFormula = AdminDashboard(name: d.name, week: d.week, membersN: d.membersN, activeN: d.activeN,
                                       includesDemo: d.includesDemo, published: true, hourlyCostInr: d.hourlyCostInr,
                                       goldSponsorInr: d.goldSponsorInr, orgBrainText: "", cards: d.cards, trend: d.trend,
                                       gold: d.gold, rupeeFormula: nil)
        #expect(AdminStory.baseline(noFormula) == 9.2)
    }

    @Test("The chart reads left to right: oldest week first, this week last")
    func chartWeeks() {
        let weeks = AdminStory.weeks(d)
        #expect(weeks.map(\.label) == ["W44", "W45", "W46", AdminCopy.thisWeek])
        #expect(weeks.map(\.hours) == [9.2, 10.4, 11.7, 12.9])
        #expect(AdminStory.trendLabels(d) == ["W44", "W45", "W46", "W47"])
        #expect(AdminStory.goodDayCells(d) == [3, 5, 6, 7])
        #expect(AdminStory.series(d, .afterHoursShare) == [0.2, 0.15, 0.1, 0.05])
    }

    @Test("A change says its direction in words: after-hours going down is better")
    func verdicts() {
        #expect(AdminStory.verdict(d.cards.focusHours.change, of: .focusHours) == "better")
        #expect(AdminStory.verdict(d.cards.afterHoursShare.change, of: .afterHoursShare) == "better")
        #expect(AdminStory.verdict(0.05, of: .afterHoursShare) == "worse")
        #expect(AdminStory.verdict(d.cards.keptRate.change, of: .keptRate) == "steady")
        #expect(AdminStory.verdict(nil, of: .keptRate) == nil)
    }

    @Test("The report: a lead sentence, rows with their figures pulled out, suggestions without the team's name")
    func report() {
        let (lead, rest) = AdminStory.lead("Payments averaged 11.7 hours. Focus time rose.")
        #expect(lead == "Payments averaged 11.7 hours." && rest == "Focus time rose.")
        #expect(AdminStory.lead("One sentence only.").rest == nil)

        let kept = AdminStory.row("Focus blocks kept rose from 58% to 83%.")
        #expect(kept.text == "Focus blocks kept rose" && kept.figure == "58% → 83%" && kept.symbol == "checkmark.seal")
        let good = AdminStory.row("Good days rose from 70% to every day counted.")
        #expect(good.text == "Good days rose from 70% to every day counted." && good.figure == nil)
        let gold = AdminStory.row("Zen Gold weeks this month: 2.")
        #expect(gold.text == "Zen Gold weeks this month" && gold.figure == "2" && gold.isReward)
        #expect(AdminStory.row("Days with after-hours work fell from 15% to 5%.").symbol == "moon.stars")

        #expect(AdminStory.suggestion("Payments: try meeting-free mornings twice a week.", team: "Payments")
            == "Try meeting-free mornings twice a week.")
        #expect(AdminStory.suggestion("Protect the evenings.", team: "Payments") == "Protect the evenings.")
        #expect(AdminStory.monthName("2026-11") == "November 2026")
    }

    @Test("The fixed report is never credited to Gemini")
    func credit() {
        let fixed = PeopleReport(month: "2026-11", text: "", bullets: [], suggestions: [], fallback: true, model: nil, cached: true)
        let written = PeopleReport(month: "2026-11", text: "", bullets: [], suggestions: [], fallback: false, model: "gemini", cached: false)
        #expect(AdminStory.credit(fixed) == AdminCopy.fromNumbers && !AdminStory.credit(fixed).contains("Gemini"))
        #expect(AdminStory.credit(written).contains("Gemini"))
    }

    @Test("Share the report: team averages, the formula, the report, who it's based on; never anyone's own")
    func share() async throws {
        let r = try await FakeAdmin().peopleReport(cohortId: "demo", month: "2026-11", regenerate: false)
        let text = try #require(AdminStory.shareText(d, report: r))
        #expect(text.hasPrefix("Payments · ZenMode OS team report, W47"))
        #expect(text.contains("₹2,30,702 reclaimed a month (up ₹74,822 on last week)"))
        #expect(text.contains("How we count: (12.9 h now − 9.2 h baseline)"))
        #expect(text.contains("Days with after-hours work: 5% (−5 pts vs last week)"))
        #expect(text.contains("Zen Gold: 2 weeks this month, ₹500 sponsored"))
        #expect(text.contains("Monthly people report, November 2026 (written from the numbers)") && !text.contains("Gemini"))
        #expect(text.contains("Based on 12 people. Includes demo data. " + AdminCopy.privacy))
    }
}
