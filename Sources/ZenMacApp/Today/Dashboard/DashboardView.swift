import SwiftUI
import Albeit
import ZenAPI

/// Today: one look at the day, in five compartments read top to bottom: Now (Focus, and the
/// catch-up after it), Your day (the hero and the screens, side by side), Work (plan, wrap up, the
/// team), Rewards & circle, and Play (Zen Cards and the pattern deck). A new person sees "Get set
/// up" first. The greeting carries the one primary action (Share today); search lives in ⌘K.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    enum Anchor: Hashable { case setup, now, hero, screens, work, circle, gold, cards, deck }

    /// The readable column: wide enough for the analytics, narrow enough to keep the eye still.
    static let column: CGFloat = 1180
    /// Below this content width, side-by-side pairs stack.
    static let pairBelow: CGFloat = 940

    var body: some View {
        @Bindable var dash = model.dashboard
        GeometryReader { geo in
            let wide = geo.size.width >= Self.pairBelow
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ZenSpace.s12) {
                        VStack(alignment: .leading, spacing: ZenSpace.s6) {
                            topBar
                            SetupChecklistCard {
                                withAnimation(ZenMotion.container) { proxy.scrollTo(Anchor.work, anchor: .top) }
                            }
                            .id(Anchor.setup)
                        }

                        compartment(.now) {
                            FocusCard()
                            CatchUpCardView()
                        }
                        .id(Anchor.now)

                        compartment(.day, accessory: { DayPicker(days: dash.days, selection: $dash.dayIndex) }) {
                            HeroCard(day: dash.day).id(Anchor.hero)
                            ScreensSection(wide: wide).id(Anchor.screens)
                        }

                        compartment(.work) {
                            pair(wide, equal: true) {
                                DayPlanCard()
                            } trailing: {
                                TeamCard()
                            }
                        }
                        .id(Anchor.work)

                        compartment(.rewards) {
                            pair(wide, height: 300, trailingWidth: min(420, geo.size.width * 0.36)) {
                                CircleGlanceCard()
                                    .opensOnClick(radius: ZenRadius.xxl, label: HomeCopy.openCircle) { model.navigate = .cohort }
                                    .id(Anchor.circle)
                            } trailing: {
                                GoldGlanceCard { model.navigate = .gold }
                                    .opensOnClick(radius: ZenRadius.widget, label: "Open Zen Gold") { model.navigate = .gold }
                                    .id(Anchor.gold)
                            }
                        }

                        compartment(.play) {
                            pair(wide, height: 440, leadingWidth: min(400, geo.size.width * 0.36)) {
                                ZenCardStackCard().id(Anchor.cards)
                            } trailing: {
                                PatternDeckCard().id(Anchor.deck)
                            }
                        }
                    }
                    .padding(.horizontal, ZenSpace.s6)
                    .padding(.top, ZenSpace.s5)
                    .padding(.bottom, ZenSpace.s16)
                    .frame(maxWidth: Self.column)
                    .frame(maxWidth: .infinity)
                    // Albeit's quiet bloom in the page's top-right corner; still, so nothing on Today moves on its own.
                    .background(alignment: .topTrailing) {
                        ZenBloomOrnament(.bloom, intensity: 0.85, drifts: false)
                            .frame(width: 440, height: 440)
                            .offset(x: 170, y: -250)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                #if DEBUG
                // Debug renders: ZEN_DASH_ANCHOR=screens scrolls to that part of Today.
                .task {
                    let anchors: [String: Anchor] = ["setup": .setup, "now": .now, "hero": .hero, "screens": .screens, "work": .work,
                                                     "circle": .circle, "gold": .gold, "cards": .cards, "deck": .deck, "month": .circle]
                    if let raw = ProcessInfo.processInfo.environment["ZEN_DASH_ANCHOR"], let a = anchors[raw] {
                        try? await Task.sleep(for: .milliseconds(1500))
                        proxy.scrollTo(a, anchor: .center)
                    }
                }
                #endif
            }
        }
    }

    /// A numbered compartment: its header, then its cards.
    private func compartment<Content: View>(_ section: TodaySection, @ViewBuilder content: () -> Content) -> some View {
        compartment(section, accessory: { EmptyView() }, content: content)
    }

    private func compartment<Accessory: View, Content: View>(_ section: TodaySection, @ViewBuilder accessory: @escaping () -> Accessory,
                                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            TodaySectionHeader(section, accessory: accessory)
            VStack(alignment: .leading, spacing: ZenSpace.s6) { content() }
        }
    }

    /// Two cards side by side when there's room, one above the other when there isn't. `equal`
    /// stretches both to the taller one's height.
    @ViewBuilder
    private func pair<Leading: View, Trailing: View>(_ wide: Bool, equal: Bool = false, height: CGFloat? = nil,
                                                     leadingWidth: CGFloat? = nil, trailingWidth: CGFloat? = nil,
                                                     @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        if wide {
            HStack(alignment: .top, spacing: ZenSpace.s6) {
                leading().frame(width: leadingWidth).frame(maxHeight: .infinity, alignment: .top)
                trailing().frame(width: trailingWidth).frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: height)
            .fixedSize(horizontal: false, vertical: equal)
        } else {
            VStack(spacing: ZenSpace.s6) {
                leading().frame(height: height)
                trailing().frame(height: height)
            }
        }
    }

    private var topBar: some View {
        let dash = model.dashboard
        return HStack(alignment: .center, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeCopy.greeting(model.user?.firstName, at: Date()))
                    .font(ZenFont.brand(30)).tracking(-0.8).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .zenType(.body).foregroundStyle(Color.zen.textCaption)
            }
            Spacer(minLength: ZenSpace.s4)
            Button { model.paletteOpen = true } label: {
                HStack(spacing: ZenSpace.s2) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                    Text(HomeCopy.search).font(ZenFont.text(13))
                    Text("⌘K").font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
                }
                .foregroundStyle(Color.zen.textBody)
                .padding(.horizontal, ZenSpace.s4).frame(height: 38)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            // Secondary: the screen's one primary is Focus ("Lock in. Log off.").
            ShareImageButton(fileName: "Today · ZenMode OS.png") {
                ImageExport.png(TodayShareImage(score: dash.days[0].score, week: model.snapshot?.week ?? FakeSnapshot.value.week, date: Date()))
            } label: {
                Label("Share today", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .help("Share today's Zen Score and week as a picture. Scores only.")
        }
    }
}
