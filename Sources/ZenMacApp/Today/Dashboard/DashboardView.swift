import SwiftUI
import Albeit
import ZenAPI

/// Today, as the founder's sketch lays it out: search and one primary action on top, the usual stats,
/// then the day as a clock beside where the minutes went, then the pattern cards beside the nudges.
/// Built for skimming: one number per tile, one idea per card, details on hover or tap.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool

    enum Anchor: Hashable { case stats, clock, flow, deck, nudges }

    var body: some View {
        @Bindable var dash = model.dashboard
        GeometryReader { geo in
            let inner = geo.size.width - ZenSpace.s2 * 2
            let wide = inner >= 860
            ScrollViewReader { proxy in
                VStack(spacing: ZenSpace.s4) {
                    topBar(proxy: proxy)
                        .padding(.horizontal, ZenSpace.s2)
                        .zIndex(2)
                    ScrollView {
                        VStack(spacing: ZenSpace.s4) {
                            UsualStatsCard().id(Anchor.stats)
                            row(wide: wide, width: inner, split: 0.4, height: 344,
                                DayClockCard(day: dash.day).id(Anchor.clock),
                                MinutesFlowCard(day: dash.day, lit: $dash.litKind).id(Anchor.flow))
                            row(wide: wide, width: inner, split: 0.58, height: 404,
                                PatternDeckCard().id(Anchor.deck),
                                NudgesCard(day: dash.day).id(Anchor.nudges))
                        }
                        .padding(.horizontal, ZenSpace.s2)
                        .padding(.top, ZenSpace.s1)
                        .padding(.bottom, ZenSpace.s8)
                        .animation(ZenMotion.container, value: dash.dayIndex)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k", modifiers: .command).opacity(0).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func row<L: View, R: View>(wide: Bool, width: CGFloat, split: CGFloat, height: CGFloat, _ left: L, _ right: R) -> some View {
        if wide {
            HStack(spacing: ZenSpace.s4) {
                left.frame(width: (width - ZenSpace.s4) * split)
                right
            }
            .frame(height: height)
        } else {
            VStack(spacing: ZenSpace.s4) {
                left.frame(height: height)
                right.frame(height: height)
            }
        }
    }

    // MARK: The top bar

    private func topBar(proxy: ScrollViewProxy) -> some View {
        @Bindable var dash = model.dashboard
        let hits = SearchHit.find(dash.query, in: dash)
        return HStack(spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.zen.textCaption)
                TextField("Search your patterns, apps and Zeno's lines", text: $dash.query)
                    .textFieldStyle(.plain)
                    .font(ZenFont.text(14))
                    .foregroundStyle(Color.zen.textHeading)
                    .focused($searchFocused)
                    .onSubmit { if let first = hits.first { pick(first, proxy: proxy) } }
                    .onExitCommand { dash.query = ""; searchFocused = false }
                if dash.query.isEmpty {
                    Text("⌘K").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.zen.borderOutline, lineWidth: 1))
                } else {
                    Button { dash.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.zen.textCaption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, ZenSpace.s4)
            .frame(height: 40)
            .glassEffect(.regular.interactive(), in: .capsule)
            .frame(maxWidth: 640)
            .overlay(alignment: .topLeading) {
                if !dash.query.isEmpty {
                    SearchResults(hits: hits) { pick($0, proxy: proxy) }
                        .offset(y: 48)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(ZenMotion.calm(ZenMotion.t1), value: dash.query.isEmpty)

            Spacer(minLength: ZenSpace.s3)

            // The screen's one primary action.
            ShareImageButton(fileName: "Today · ZenMode OS.png") {
                ImageExport.png(TodayShareImage(score: dash.days[0].score, week: model.snapshot?.week ?? FakeSnapshot.value.week, date: Date()))
            } label: {
                Label("Share today", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ZenPrimaryButtonStyle())
            .help("Share today's Zen Score and week as a picture. Scores only.")
        }
    }

    private func pick(_ hit: SearchHit, proxy: ScrollViewProxy) {
        let dash = model.dashboard
        dash.query = ""
        searchFocused = false
        switch hit.target {
        case .card(let card): dash.open(card)
        case .kind(let kind):
            dash.litKind = kind
            withAnimation(ZenMotion.container) { proxy.scrollTo(Anchor.flow, anchor: .center) }
        case .anchor(let a):
            withAnimation(ZenMotion.container) { proxy.scrollTo(a, anchor: .center) }
        }
    }
}

/// One search result.
struct SearchHit: Identifiable {
    enum Target { case card(PatternCard), kind(AppKind), anchor(DashboardView.Anchor) }

    let id: String
    let symbol: String
    let title: String
    let detail: String
    let target: Target

    /// Patterns first, then kinds of app (an app's name finds its kind), then Zeno's lines, then places.
    @MainActor
    static func find(_ query: String, in dash: DashboardModel) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for card in dash.cards where [card.title, card.face, card.body, card.suitMeaning].contains(where: { $0.lowercased().contains(q) }) {
            hits.append(SearchHit(id: "card-\(card.id)", symbol: card.suit.symbol, title: card.title, detail: "Pattern card · \(card.face)", target: .card(card)))
        }
        let day = dash.day
        for kind in AppKind.allCases {
            let apps = Array(Set(day.sessions.filter { $0.kind == kind }.map(\.app))).sorted()
            guard kind.rawValue.lowercased().contains(q) || apps.contains(where: { $0.lowercased().contains(q) }) else { continue }
            let detail = apps.isEmpty ? "Nothing \(day.isToday ? "today" : "that day")" : "\(apps.joined(separator: ", ")) · \(durationText(day.minutes(kind)))"
            hits.append(SearchHit(id: "kind-\(kind.rawValue)", symbol: kind.symbol, title: kind.rawValue, detail: detail, target: .kind(kind)))
        }
        for n in day.nudges where n.line.lowercased().contains(q) {
            hits.append(SearchHit(id: "nudge-\(n.id)", symbol: "bubble.left", title: "“\(n.line)”", detail: "Zeno at \(clockText(n.minute))", target: .anchor(.nudges)))
        }
        let places: [(String, String, DashboardView.Anchor, [String])] = [
            ("The day as a clock", "clock", .clock, ["clock", "day", "hour", "time"]),
            ("Where the minutes went", "arrow.triangle.branch", .flow, ["minutes", "flow", "where", "focus", "intentional", "unintentional"]),
            ("Zen Score and the week", "chart.bar", .stats, ["score", "week", "streak", "iphone", "mac", "screen"]),
            ("Nudges and pull-backs", "bubble.left.and.bubble.right", .nudges, ["nudge", "zeno", "pull"]),
        ]
        for (title, symbol, anchor, words) in places where words.contains(where: { $0.hasPrefix(q) || q.hasPrefix($0) }) {
            hits.append(SearchHit(id: "place-\(title)", symbol: symbol, title: title, detail: "Jump to it", target: .anchor(anchor)))
        }
        return Array(hits.prefix(6))
    }
}

private struct SearchResults: View {
    let hits: [SearchHit]
    let pick: (SearchHit) -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hits.isEmpty {
                Text("Nothing by that name yet.").zenType(.caption).foregroundStyle(Color.zen.textCaption).padding(ZenSpace.s3)
            }
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                Button { pick(hit) } label: {
                    HStack(spacing: ZenSpace.s3) {
                        Image(systemName: hit.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.zen.textBrand).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.title).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
                            Text(hit.detail).zenType(.caption).foregroundStyle(Color.zen.textCaption).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if i == 0 { Text("↩").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption) }
                    }
                    .padding(.horizontal, ZenSpace.s3).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                        .fill(hovered == hit.id ? Color.zen.surfaceTint : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? hit.id : (hovered == hit.id ? nil : hovered) }
            }
        }
        .padding(ZenSpace.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .shadow(color: Color(hex: 0x12160F, alpha: 0.18), radius: 24, y: 14)
    }
}
