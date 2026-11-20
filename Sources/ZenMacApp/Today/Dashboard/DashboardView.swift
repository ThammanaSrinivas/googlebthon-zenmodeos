import SwiftUI
import Albeit
import ZenAPI

/// Today: one look at the day, never the same number twice. A greeting and the one primary action
/// (Share today); the hero (the Zen Score, the weekly streak, Zeno's line); device analytics; Zen
/// Circle beside Zen Gold; then the pattern cards to play with. Search lives in ⌘K.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    enum Anchor: Hashable { case hero, screens, circle, gold, deck }

    /// The readable column: wide enough for the analytics, narrow enough to keep the eye still.
    static let column: CGFloat = 1180

    var body: some View {
        let dash = model.dashboard
        GeometryReader { geo in
            let wide = geo.size.width >= 940
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ZenSpace.s8) {
                        topBar
                        HeroCard(day: dash.day).id(Anchor.hero)
                        ScreensSection().id(Anchor.screens)
                        Group {
                            if wide {
                                HStack(alignment: .top, spacing: ZenSpace.s6) {
                                    CircleGlanceCard().id(Anchor.circle)
                                    GoldGlanceCard { model.navigate = .gold }.id(Anchor.gold)
                                        .frame(width: min(420, geo.size.width * 0.36))
                                }
                                .frame(height: 300)
                            } else {
                                VStack(spacing: ZenSpace.s6) {
                                    CircleGlanceCard().frame(height: 300).id(Anchor.circle)
                                    GoldGlanceCard { model.navigate = .gold }.frame(height: 300).id(Anchor.gold)
                                }
                            }
                        }
                        PatternDeckCard().frame(height: 440).id(Anchor.deck)
                    }
                    .padding(.horizontal, ZenSpace.s6)
                    .padding(.top, ZenSpace.s5)
                    .padding(.bottom, ZenSpace.s16)
                    .frame(maxWidth: Self.column)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                #if DEBUG
                // Debug renders: ZEN_DASH_ANCHOR=screens scrolls to that part of Today.
                .task {
                    let anchors: [String: Anchor] = ["hero": .hero, "screens": .screens, "circle": .circle, "gold": .gold, "deck": .deck, "month": .circle]
                    if let raw = ProcessInfo.processInfo.environment["ZEN_DASH_ANCHOR"], let a = anchors[raw] {
                        try? await Task.sleep(for: .milliseconds(400))
                        proxy.scrollTo(a, anchor: .center)
                    }
                }
                #endif
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
}
