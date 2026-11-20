import SwiftUI
import Albeit
import ZenAPI

/// The main window: a sidebar that folds to a rail, the section picked, and two overlays (a pattern
/// card opened from Today, and the ⌘K command palette). The ground is ZenAurora's living light.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .today
    /// The person folded the sidebar; narrow windows fold it on their own.
    @AppStorage("zen.sidebar.collapsed") private var collapsedByChoice = false
    /// Debug renders fold the sidebar without touching the person's own setting.
    @State private var debugRail = false

    enum Section: String, CaseIterable, Identifiable {
        case today = "Today", week = "Week", calendar = "Calendar", cohort = "Zen Circle", gold = "Zen Gold", integrations = "Integrations", settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .week: "chart.bar"
            case .calendar: "calendar"
            case .cohort: "circle.hexagongrid"
            case .gold: "sparkles"
            case .integrations: "square.grid.2x2"
            case .settings: "gearshape"
            }
        }
    }

    /// Below this width the sidebar folds to a rail whatever the setting.
    static let railBelow: CGFloat = 1120

    var body: some View {
        GeometryReader { geo in
            let rail = collapsedByChoice || debugRail || geo.size.width < Self.railBelow
            ZStack {
                ZenAurora(glow: (model.snapshot?.score.isGoodDay ?? true) ? 0.75 : 0.35)
                HStack(spacing: ZenSpace.s4) {
                    Sidebar(section: $section, rail: rail, canExpand: geo.size.width >= Self.railBelow,
                            toggle: { withAnimation(ZenMotion.container) { collapsedByChoice.toggle() } })
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(ZenSpace.s3)
                .padding(.top, 28)
                if let card = model.dashboard.openCard {
                    CardOverlay(card: card)
                        .transition(.opacity)
                        .zIndex(10)
                }
                if model.paletteOpen {
                    CommandPalette()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(20)
                }
            }
            .animation(ZenMotion.container, value: rail)
        }
        .ignoresSafeArea()
        .animation(ZenMotion.calm(ZenMotion.t2), value: model.paletteOpen)
        // ⌘K opens the palette from any section; ⌃⌘S folds the sidebar.
        .background {
            Button("") { model.paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command).hidden()
            Button("") { withAnimation(ZenMotion.container) { collapsedByChoice.toggle() } }
                .keyboardShortcut("s", modifiers: [.command, .control]).hidden()
        }
        .onChange(of: model.navigate) { _, target in
            guard let target else { return }
            withAnimation(ZenMotion.container) { section = target }
            model.navigate = nil
        }
        #if DEBUG
        // Debug renders: ZEN_SECTION=week opens that section; ZEN_SEAT=team picks the seat;
        // ZEN_PALETTE=1 opens the palette; ZEN_RAIL=1 folds the sidebar.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let raw = env["ZEN_SECTION"],
               let picked = Section.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) { section = picked }
            if let seat = env["ZEN_SEAT"].flatMap(Profile.Seat.init(rawValue:)) { model.profile.seat = seat }
            if env["ZEN_PALETTE"] == "1" { model.paletteOpen = true }
            if env["ZEN_RAIL"] == "1" { debugRail = true }
        }
        #endif
    }

    /// The section picked in the sidebar.
    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .today: DashboardView()
        case .week: WeekView()
        case .calendar: CalendarSection()
        case .cohort: CircleSection()
        case .gold: GoldSection()
        case .integrations: IntegrationsSection()
        case .settings: SettingsSection()
        }
    }
}

/// The sidebar: the full list (224) or a rail of icons (68). Notices fold into small dots on the rail.
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: TodayView.Section
    let rail: Bool
    let canExpand: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: rail ? .center : .leading, spacing: ZenSpace.s1) {
            HStack(spacing: ZenSpace.s2) {
                if rail {
                    ZenMark().fill(Color.zen.textHeading, style: FillStyle(eoFill: true)).frame(width: 20, height: 20)
                        .accessibilityLabel("ZenMode OS")
                } else {
                    ZenLockup(size: 15)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rail ? 0 : ZenSpace.s3)
            .frame(height: 28)
            if canExpand {
                Button(action: toggle) {
                    Image(systemName: rail ? "sidebar.right" : "sidebar.left")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.zen.textCaption)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(rail ? "Show the sidebar (⌃⌘S)" : "Fold the sidebar (⌃⌘S)")
                .accessibilityLabel(rail ? "Show the sidebar" : "Fold the sidebar")
                .frame(maxWidth: .infinity, alignment: rail ? .center : .trailing)
                .padding(.top, rail ? ZenSpace.s2 : -30)
            }
            searchButton.padding(.top, ZenSpace.s3).padding(.bottom, ZenSpace.s3)
            ForEach(TodayView.Section.allCases) { s in
                item(s)
            }
            Spacer()
            if rail {
                notices
            } else {
                // A new weekly review shows here, on every section, until it's read or closed.
                WeeklyReviewToast { withAnimation(ZenMotion.container) { section = .week } }
                    .padding(.bottom, ZenSpace.s2)
                    .animation(ZenMotion.container, value: model.reviewSeen)
                    .animation(ZenMotion.container, value: model.review?.0)
                if section != .calendar {
                    SidebarCalendarCard { section = .calendar }
                        .padding(.bottom, ZenSpace.s2)
                }
                account
            }
        }
        .padding(.vertical, ZenSpace.s5)
        .padding(.horizontal, rail ? ZenSpace.s2 : ZenSpace.s2)
        .frame(width: rail ? 68 : 232)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.xl))
    }

    private var searchButton: some View {
        Button { model.paletteOpen = true } label: {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                if !rail {
                    Text("Search").font(ZenFont.text(13))
                    Spacer(minLength: 0)
                    Text("⌘K").font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
                }
            }
            .foregroundStyle(Color.zen.textBody)
            .padding(.horizontal, rail ? 0 : ZenSpace.s3)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.textHeading.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Search or jump anywhere (⌘K)")
        .accessibilityLabel("Search")
    }

    private func item(_ s: TodayView.Section) -> some View {
        let on = s == section
        return Button { withAnimation(ZenMotion.container) { section = s } } label: {
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: s.symbol).font(.system(size: 14, weight: on ? .semibold : .regular)).frame(width: 20)
                if !rail { Text(s.rawValue).font(ZenFont.text(13.5, on ? .semibold : .medium)) }
                if !rail { Spacer(minLength: 0) }
            }
            .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textBody)
            .padding(.horizontal, rail ? 0 : ZenSpace.s3)
            .frame(maxWidth: .infinity).frame(height: 36)
            .background {
                if on { RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.8)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(rail ? s.rawValue : "")
        .accessibilityLabel(s.rawValue)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    /// On the rail: a dot for an unread review, one for a calendar to connect.
    private var notices: some View {
        VStack(spacing: ZenSpace.s3) {
            if model.review != nil && !model.reviewSeen {
                Button { withAnimation(ZenMotion.container) { section = .week } } label: {
                    Image(systemName: "sparkle").foregroundStyle(Color.zen.accentRewardText)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.zen.accentRewardTint))
                }
                .buttonStyle(.plain).help("Your weekly review is ready")
            }
            if model.calendarLink.state == .notAsked {
                Button { withAnimation(ZenMotion.container) { section = .calendar } } label: {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Color.zen.textBrand)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.zen.surfaceTint))
                }
                .buttonStyle(.plain).help("Connect your calendar")
            }
            Circle().fill(Color.zen.brandFill).frame(width: 8, height: 8)
                .help(model.user == nil ? "This Mac only" : "Synced across your screens")
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.user?.displayName ?? "Exploring").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
            HStack(spacing: 6) {
                Circle().fill(Color.zen.brandFill).frame(width: 7, height: 7)
                Text(model.user == nil ? "This Mac only" : "2 of 2 devices · synced").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            if model.isDemo { DemoTag().padding(.top, 4) }
        }
        .padding(ZenSpace.s3)
    }
}
