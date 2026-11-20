import SwiftUI
import Albeit
import ZenAPI

/// Today: the sidebar and the dashboard (`DashboardView`). A pattern card opens over the whole window.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .today

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

    var body: some View {
        ZStack {
            ZenBackdrop(tone: .zen, glowAt: UnitPoint(x: 0.42, y: 0.3))
            HStack(spacing: ZenSpace.s4) {
                sidebar
                sectionContent
            }
            .padding(ZenSpace.s3)
            .padding(.top, 28)
            if let card = model.dashboard.openCard {
                CardOverlay(card: card)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .ignoresSafeArea()
        #if DEBUG
        // Debug renders: ZEN_SECTION=week opens that section (see scripts/snapshot-tour.sh).
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["ZEN_SECTION"],
               let picked = Section.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) { section = picked }
            if let seat = ProcessInfo.processInfo.environment["ZEN_SEAT"].flatMap(Profile.Seat.init(rawValue:)) { model.profile.seat = seat }
        }
        #endif
    }

    /// The section picked in the sidebar.
    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .today:
            DashboardView()
        case .week: WeekView()
        case .calendar: CalendarSection()
        case .cohort: CircleSection()
        case .gold: GoldSection()
        case .integrations: IntegrationsSection()
        case .settings: SettingsSection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s1) {
            ZenLockup(size: 15).padding(.horizontal, ZenSpace.s3).padding(.bottom, ZenSpace.s5)
            ForEach(Section.allCases) { s in
                Button { section = s } label: {
                    Label(s.rawValue, systemImage: s.symbol)
                        .font(ZenFont.text(13.5, s == section ? .semibold : .medium))
                        .foregroundStyle(s == section ? Color.zen.textHeading : Color.zen.textBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 34)
                        .background {
                            if s == section { RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.75)) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(s == section ? [.isSelected, .isButton] : .isButton)
            }
            Spacer()
            // A new weekly review shows here, on every section, until it's read or closed.
            WeeklyReviewToast { withAnimation(ZenMotion.container) { section = .week } }
                .padding(.bottom, ZenSpace.s2)
                .animation(ZenMotion.container, value: model.reviewSeen)
                .animation(ZenMotion.container, value: model.review?.0)
            SidebarCalendarCard { section = .calendar }
                .padding(.bottom, ZenSpace.s2)
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
        .padding(.vertical, ZenSpace.s5)
        .padding(.horizontal, ZenSpace.s2)
        .frame(width: 224)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.xl))
    }
}
