import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

/// The models that keep things on this Mac, each given a scratch store, so a test never touches the
/// real choices of whoever runs it.
@MainActor
struct InjectedStoreTests {
    @Test("Gold orders are kept in the store the ledger was given")
    func gold() {
        let d = scratchDefaults()
        let ledger = GoldLedger(defaults: d)
        #expect(ledger.isDemo)
        ledger.record(units: 2, pricePaise: 10_165, week: Date(timeIntervalSince1970: 1_800_000_000))
        let again = GoldLedger(defaults: d)
        #expect(!again.isDemo)
        #expect(again.units == 2 && again.orders.first?.pricePaise == 10_165)
        #expect(GoldLedger(defaults: scratchDefaults()).isDemo)
    }

    @Test("Connections and requests are kept in the store the model was given")
    func integrations() async throws {
        let d = scratchDefaults()
        let tool = try #require(Integration.all.first { !$0.managedByWorkspace && $0.id != "calendar" })
        let model = IntegrationsModel(defaults: d)
        model.connect(tool)
        #expect(await eventually { model.connected.contains(tool.id) })
        model.request("Linear")
        let again = IntegrationsModel(defaults: d)
        #expect(again.isOn(tool, workspace: nil))
        #expect(again.requested == ["Linear"])
        model.disconnect(tool)
        #expect(!IntegrationsModel(defaults: d).isOn(tool, workspace: nil))
        #expect(IntegrationsModel(defaults: scratchDefaults()).requested.isEmpty)
    }

    @Test("AppModel hands its store to what it keeps")
    func appModel() {
        let d = scratchDefaults()
        let m = AppModel(defaults: d)
        m.preferences.values.appearance = .dark
        m.integrations.request("Notion")
        #expect(ZenPreferences(defaults: d).values.appearance == .dark)
        #expect(IntegrationsModel(defaults: d).requested == ["Notion"])
        #expect(m.goldLedger.isDemo)
    }
}

/// ⌘K's matching, apart from the view.
@MainActor
struct PaletteFilterTests {
    private func item(_ title: String, _ detail: String, _ tag: CommandPalette.Tag) -> CommandPalette.Item {
        .init(id: title, symbol: "circle", title: title, detail: detail, tag: tag, run: {})
    }

    private var items: [CommandPalette.Item] {
        [item("Zen Gold", "Go to Zen Gold", .sections),
         item("The night owl", "Most of it after 9 pm", .patterns),
         item("Video", "YouTube, Netflix · 1h 10m", .apps),
         item("Ask Zeno", "A fresh line in the notch", .actions)]
    }

    @Test("An empty query keeps everything under the tag, in order")
    func empty() {
        #expect(CommandPalette.filter(items, query: "", tag: .all).map(\.title) == ["Zen Gold", "The night owl", "Video", "Ask Zeno"])
        #expect(CommandPalette.filter(items, query: "  ", tag: .apps).map(\.title) == ["Video"])
    }

    @Test("The query matches the title or the detail, in any case")
    func matches() {
        #expect(CommandPalette.filter(items, query: "youtube", tag: .all).map(\.title) == ["Video"])
        #expect(CommandPalette.filter(items, query: "ZENO", tag: .all).map(\.title) == ["Ask Zeno"])
        #expect(CommandPalette.filter(items, query: " zen ", tag: .all).map(\.title) == ["Zen Gold", "Ask Zeno"])
    }

    @Test("The tag narrows, and no match shows nothing")
    func tags() {
        #expect(CommandPalette.filter(items, query: "zen", tag: .sections).map(\.title) == ["Zen Gold"])
        #expect(CommandPalette.filter(items, query: "gold", tag: .apps).isEmpty)
    }
}
