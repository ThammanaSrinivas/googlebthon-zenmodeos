import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

// IntegrationsModel's saving is tested in StoresAndPaletteTests, against a scratch store.

@Suite("Integrations: the catalog")
struct IntegrationCatalogTests {
    private let all = Integration.all

    @Test("Ids are unique and every tool has a name, a symbol and both sentences")
    func complete() {
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.name)).count == all.count)
        for i in all {
            #expect(!i.name.isEmpty && !i.symbol.isEmpty, "\(i.id)")
            #expect(!i.does.isEmpty && !i.reads.isEmpty, "\(i.id)")
            #expect(i.does.hasSuffix(".") && i.reads.hasSuffix("."), "\(i.id)")
            #expect(i.hue <= 0xFFFFFF, "\(i.id)")
        }
    }

    @Test("Every category has at least one tool, and the catalog runs category by category")
    func categories() {
        for c in Integration.Category.allCases {
            #expect(all.contains { $0.category == c }, "\(c)")
            #expect(!c.label.isEmpty)
        }
        let order = all.map(\.category)
        var seen: [Integration.Category] = []
        for c in order where seen.last != c { seen.append(c) }
        #expect(seen == Integration.Category.allCases, "tools of one category sit together, in the tab order")
    }

    @Test("Only the Mac's own calendar connects for real today")
    func live() {
        #expect(all.filter { $0.isLive }.map(\.id) == ["calendar"])
    }

    @Test("Each tool says what it never reads, or that it reads nothing")
    func privacy() {
        for i in all {
            let r = i.reads.lowercased()
            #expect(r.contains("never") || r.hasPrefix("nothing") || r.contains("which focus") || r.contains("when a call"),
                    "\(i.id): \(i.reads)")
        }
    }

    @Test("Workspace-managed tools are the team's work tools")
    func managed() {
        #expect(Set(all.filter { $0.managedByWorkspace }.map(\.id)) == ["jira", "slack"])
    }

    @Test("Every seat gets at least one suggestion, at most four", arguments: Profile.Seat.allCases)
    func suggestions(seat: Profile.Seat) {
        let s = Integration.suggested(for: seat) { _ in false }
        #expect(!s.isEmpty && s.count <= 4)
        #expect(s.allSatisfy { $0.suggestedFor.contains(seat) })
    }

    @Test("Suggestions keep the catalog's order and leave out what's on")
    func suggestionsExclude() {
        let personal = Integration.suggested(for: .personal) { _ in false }.map(\.id)
        #expect(personal == ["calendar", "focus", "browser", "spotify"])
        let withoutCalendar = Integration.suggested(for: .personal) { $0.id == "calendar" }.map(\.id)
        #expect(withoutCalendar == ["focus", "browser", "spotify"])
        #expect(Integration.suggested(for: .campus) { _ in true }.isEmpty)
    }

    @Test("Campus suggestions are campus tools first")
    func campus() {
        #expect(Integration.suggested(for: .campus) { _ in false }.map(\.id) == ["calendar", "discord", "browser", "classroom"])
        #expect(Integration.suggested(for: .team) { _ in false }.map(\.id) == ["google", "jira", "slack", "browser"])
    }

    @Test("The two demo workspaces")
    func workspaces() {
        #expect(Workspace.campus.isCampus && !Workspace.team.isCampus)
        #expect(Workspace.team.seats > 0 && Workspace.campus.seats > 0)
        #expect(Workspace.team.monogram == "AL")
    }
}
