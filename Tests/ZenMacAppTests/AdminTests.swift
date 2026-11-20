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
