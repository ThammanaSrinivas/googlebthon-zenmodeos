import Foundation
import Testing
import ZenAPI
import ZenMock

@Suite("The admin view: the seeded fake, the decoding, the display helpers")
struct FakeAdminTests {
    /// Saturday 21 Nov 2026, 10:00 IST.
    let saturday = Date(timeIntervalSince1970: 1_795_239_000)

    @Test("skip sign-in: the demo team, admin, published, includes demo data")
    func seeded() async throws {
        let admin = FakeAdmin(now: { [saturday] in saturday })
        let team = try #require(try await admin.adminTeam())
        #expect(team == AdminTeam(cohortId: FakeAdmin.cohortId, name: "Payments"))
        let d = try await admin.dashboard(cohortId: team.cohortId)
        #expect(d.published && d.includesDemo && d.activeN == 12)
        #expect(d.week == "2026-W47")
        #expect(d.trend.map(\.week) == ["2026-W47", "2026-W46", "2026-W45", "2026-W44"])
        #expect(d.trend.compactMap(\.focusH) == [12.9, 11.7, 10.4, 9.2])
        #expect(d.cards.rupeesPerMonth.now == 230_702)
        #expect(d.gold == AdminGold(claimsThisMonth: 2, sponsoredInr: 500))
    }

    @Test("the fake's report is the fixed one: 4 bullets, 2 suggestions, never Gemini's")
    func report() async throws {
        let r = try await FakeAdmin().peopleReport(cohortId: "demo", month: "2026-11", regenerate: true)
        #expect(r.bullets.count == 4 && r.suggestions.count == 2)
        #expect(r.fallback && r.model == nil && !r.cached)
    }

    @Test("ISO weeks across the year boundary")
    func weeks() {
        // Sun 3 Jan 2027 is still 2026-W53.
        let jan3 = Date(timeIntervalSince1970: 1_798_957_800)
        #expect(FakeAdmin.isoWeeks(endingAt: jan3) == ["2026-W53", "2026-W52", "2026-W51", "2026-W50"])
    }

    @Test("decodes the backend's JSON exactly, under-5 state included")
    func decodes() throws {
        let json = #"""
        {"name":"Payments","week":"2026-W47","membersN":4,"activeN":null,"includesDemo":false,
         "published":false,"hourlyCostInr":0,"goldSponsorInr":0,"orgBrainText":"",
         "cards":{"focusHours":{"now":null,"last":null,"change":null},
                  "keptRate":{"now":null,"last":null,"change":null},
                  "afterHoursShare":{"now":null,"last":null,"change":null},
                  "goodDayRate":{"now":null,"last":null,"change":null},
                  "rupeesPerMonth":{"now":null,"last":null,"change":null}},
         "trend":[{"week":"2026-W47","published":false,"focusH":null,"keptRate":null,
                   "afterHoursShare":null,"goodDayRate":null}],
         "gold":{"claimsThisMonth":null,"sponsoredInr":null},"rupeeFormula":null}
        """#
        let d = try JSONDecoder().decode(AdminDashboard.self, from: Data(json.utf8))
        #expect(!d.published && d.activeN == nil && d.cards.focusHours == .empty && d.rupeeFormula == nil)
    }

    @Test("the round trip keeps every field")
    func roundTrip() throws {
        let d = FakeAdmin.seeded(weeks: ["2026-W47", "2026-W46", "2026-W45", "2026-W44"])
        let back = try JSONDecoder().decode(AdminDashboard.self, from: JSONEncoder().encode(d))
        #expect(back == d)
    }

    @Test("rupees in Indian grouping")
    func rupees() {
        #expect(AdminFormat.rupees(230_702) == "₹2,30,702")
        #expect(AdminFormat.rupees(12_345_678) == "₹1,23,45,678")
        #expect(AdminFormat.rupees(999) == "₹999")
        #expect(AdminFormat.rupees(-62_352) == "−₹62,352")
        #expect(AdminFormat.rupees(0) == "₹0")
    }

    @Test("each card's value and change, in its own unit")
    func cards() {
        #expect(AdminFormat.value(12.9, of: .focusHours) == "12.9 h")
        #expect(AdminFormat.value(0.83, of: .keptRate) == "83%")
        #expect(AdminFormat.value(nil, of: .goodDayRate) == "–")
        #expect(AdminFormat.change(1.2, of: .focusHours) == "+1.2 h")
        #expect(AdminFormat.change(-0.05, of: .afterHoursShare) == "−5 pts")
        #expect(AdminFormat.change(0, of: .keptRate) == "no change")
        #expect(AdminFormat.change(74_822, of: .rupeesPerMonth) == "+₹74,822")
        #expect(AdminFormat.change(nil, of: .focusHours) == nil)
    }

    @Test("after-hours going down is the good direction")
    func direction() {
        #expect(AdminFormat.isImprovement(-0.05, of: .afterHoursShare) == true)
        #expect(AdminFormat.isImprovement(0.1, of: .goodDayRate) == true)
        #expect(AdminFormat.isImprovement(-1, of: .focusHours) == false)
        #expect(AdminFormat.isImprovement(0, of: .keptRate) == nil)
    }

    @Test("five cards, in order, with titles")
    func kinds() {
        #expect(AdminCardKind.allCases.count == 5)
        let cards = FakeAdmin.seeded(weeks: ["2026-W47"]).cards
        #expect(AdminCardKind.rupeesPerMonth.card(in: cards).now == 230_702)
        #expect(AdminCardKind.focusHours.title == "Focus hours per person")
    }
}
