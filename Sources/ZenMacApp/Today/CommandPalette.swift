import SwiftUI
import Albeit
import ZenAPI

/// ⌘K: one centred place to find anything and go there. Sections, your pattern cards, kinds of app,
/// Zeno's lines and a few actions, narrowed by a row of tags. ↑ ↓ move, ↩ opens, esc closes.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var tag: Tag = .all
    @State private var selection = 0
    @FocusState private var focused: Bool

    enum Tag: String, CaseIterable, Identifiable {
        case all = "All", sections = "Sections", patterns = "Patterns", apps = "Apps", zeno = "Zeno", actions = "Actions"
        var id: String { rawValue }
    }

    struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let tag: Tag
        let run: @MainActor () -> Void
    }

    var body: some View {
        let items = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                field
                tags.padding(.horizontal, ZenSpace.s4).padding(.bottom, ZenSpace.s3)
                Divider().overlay(Color.zen.borderHairline)
                list(items)
                footer
            }
            .frame(width: 640)
            .background(RoundedRectangle(cornerRadius: ZenRadius.xxl, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.92)))
            .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.xxl))
            .shadow(color: .black.opacity(0.25), radius: 40, y: 24)
            .padding(.top, 120)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Search")
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: tag) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(items.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onKeyPress(.return) { if items.indices.contains(selection) { pick(items[selection]) }; return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.tab) {
            let all = Tag.allCases
            tag = all[(all.firstIndex(of: tag)! + 1) % all.count]
            return .handled
        }
    }

    private var field: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.zen.textCaption)
            TextField("Search or jump to…", text: $query)
                .textFieldStyle(.plain)
                .font(ZenFont.text(19))
                .foregroundStyle(Color.zen.textHeading)
                .focused($focused)
                .accessibilityLabel("Search")
            Text("esc").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.zen.borderOutline, lineWidth: 1))
        }
        .padding(.horizontal, ZenSpace.s5)
        .frame(height: 64)
    }

    private var tags: some View {
        HStack(spacing: 4) {
            ForEach(Tag.allCases) { t in
                let on = t == tag
                Button { tag = t } label: {
                    Text(t.rawValue).font(ZenFont.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textBody)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 28)
                        .background(Capsule().fill(on ? Color.zen.actionPrimary : Color.zen.textHeading.opacity(0.05)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
            Spacer()
        }
    }

    private func list(_ items: [Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        Text("Nothing by that name yet.").zenType(.body).foregroundStyle(Color.zen.textCaption)
                            .padding(ZenSpace.s5)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if tag == .all, i == 0 || items[i - 1].tag != item.tag {
                            Eyebrow(item.tag.rawValue).padding(.horizontal, ZenSpace.s3).padding(.top, i == 0 ? 0 : ZenSpace.s3).padding(.bottom, 2)
                        }
                        row(item, selected: i == selection)
                            .id(i)
                            .onTapGesture { pick(item) }
                            .onHover { if $0 { selection = i } }
                    }
                }
                .padding(ZenSpace.s3)
            }
            .frame(maxHeight: 380)
            .onChange(of: selection) { _, i in withAnimation(ZenMotion.calm(ZenMotion.t1)) { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.9)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
                Text(item.detail).zenType(.caption).foregroundStyle(Color.zen.textCaption).lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected { Text("↩").font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption) }
        }
        .padding(.horizontal, ZenSpace.s3).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(selected ? Color.zen.textHeading.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var footer: some View {
        HStack(spacing: ZenSpace.s4) {
            Text("↑ ↓ move").font(ZenFont.number(10.5))
            Text("↩ open").font(ZenFont.number(10.5))
            Text("tab next tag").font(ZenFont.number(10.5))
            Spacer()
            Text("⌘K").font(ZenFont.number(10.5))
        }
        .foregroundStyle(Color.zen.textCaption)
        .padding(.horizontal, ZenSpace.s5)
        .frame(height: 36)
        .overlay(alignment: .top) { Rectangle().fill(Color.zen.borderHairline).frame(height: 1) }
    }

    // MARK: What there is to find

    private var results: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return everything.filter { item in
            (tag == .all || item.tag == tag)
                && (q.isEmpty || item.title.lowercased().contains(q) || item.detail.lowercased().contains(q))
        }
    }

    private var everything: [Item] {
        let dash = model.dashboard
        let day = dash.day
        var items: [Item] = TodayView.Section.allCases.map { s in
            Item(id: "section-\(s.rawValue)", symbol: s.symbol, title: s.rawValue, detail: "Go to \(s.rawValue)", tag: .sections) {
                model.navigate = s
            }
        }
        items += dash.cards.map { card in
            Item(id: "card-\(card.id)", symbol: card.suit.symbol, title: card.title, detail: card.face, tag: .patterns) {
                model.navigate = .today
                dash.open(card)
            }
        }
        items += day.kinds.map { kind in
            let apps = Array(Set(day.sessions.filter { $0.kind == kind }.map(\.app))).sorted().prefix(3).joined(separator: ", ")
            return Item(id: "kind-\(kind.rawValue)", symbol: kind.symbol, title: kind.rawValue,
                        detail: "\(apps) · \(durationText(day.minutes(kind)))", tag: .apps) {
                model.navigate = .today
                dash.litKind = kind
            }
        }
        items += day.nudges.map { n in
            Item(id: "zeno-\(n.id)", symbol: "bubble.left", title: "“\(n.line)”", detail: "Zeno at \(clockText(n.minute))", tag: .zeno) {
                model.navigate = .today
            }
        }
        let dark = model.preferences.values.appearance == .dark
        items += [
            Item(id: "act-ask", symbol: "sparkle", title: "Ask Zeno", detail: "A fresh line in the notch", tag: .actions) {
                Task { await model.refreshNudge(trigger: .checkIn) }
            },
            Item(id: "act-test", symbol: "rectangle.topthird.inset.filled", title: "Test Zeno in the notch", detail: "Ignores quiet hours", tag: .actions) {
                model.testZeno(.happy)
            },
            Item(id: "act-theme", symbol: dark ? "sun.max" : "moon", title: dark ? "Switch to paper" : "Switch to ink", detail: "Appearance", tag: .actions) {
                model.preferences.values.appearance = dark ? .light : .dark
            },
            Item(id: "act-calendar", symbol: "calendar.badge.plus", title: "Connect your calendar", detail: "Zeno goes quiet in meetings", tag: .actions) {
                model.connectCalendar()
            },
            Item(id: "act-review", symbol: "text.book.closed", title: "Read your weekly review", detail: "Week", tag: .actions) {
                model.reviewSeen = true
                model.navigate = .week
            },
        ]
        return items
    }

    private func pick(_ item: Item) {
        item.run()
        close()
    }

    private func close() {
        model.paletteOpen = false
    }
}
