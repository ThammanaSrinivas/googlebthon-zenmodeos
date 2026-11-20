import SwiftUI
import Albeit
import ZenAPI

/// Words on the Week section, named once.
enum WeekCopy {
    static let eyebrow = "The weekly streak"
    static let titleTop = "Four good days"
    static let titleBottom = "wins the week."
    static let lede = "A good day is a Zen Score above 6.0. Win four, Monday to Sunday, and the week is yours."
    static let weekStreak = "week streak"
    static func best(_ best: Int, canMake: Int?) -> String {
        canMake.map { "Best \(best) · this week can make it \($0)" } ?? "Best \(best) · this week is won"
    }
    static let twelveWeeks = "12 weeks"
    static let legendGood = "Good day"
    static let legendUnder = "Under 6.0"
    static let legendWon = "Won week"
    static let share = "Share streak"
    static let shareHint = "Shares a picture of your streak. Scores only, never minutes or apps."
    static let demoHistory = "Demo history"
    static let screens = "Across your screens"
    static let iPhoneLine = "Score only"

    static let exploreTitle = "Explore your week"
    static let exploreLede = "Gemini reads your scores, never your apps."
    static let reviewEyebrow = "Weekly review"
    static let reviewSourceGemini = "GEMINI"
    static let reviewSourceHere = "WRITTEN HERE"
    static let reviewLoading = "Zeno's reading your week…"
    static let tryThis = "Try this week"
    static let askAgain = "Write it again"
    static let askEyebrow = "Ask about your week"
    static let askHint = "Gemini answers from your scores"
    static let askThinking = "Zeno's thinking…"
    static let askEmpty = "Pick a question. Answers come from your scores and this Mac's minutes, never from your apps or your iPhone's time."
    static let askFromGemini = "Gemini · from your scores only"
    static let askFromHere = "Written here: Gemini didn't answer in time"
    static let askFallback = "I can't read the week right now. Your scores are safe; ask again in a moment."
    static let fromGemini = "Written by Gemini from your scores alone"
    static let fromHere = "Written here from your scores: Gemini didn't answer in time"

    static let recapsTitle = "Past recaps"
    static let recapsLede = "Your week in Zen, every Monday."
    static let viewAll = "View all"
    static let viewAllHint = "Opens every week on record"
    static let noRecaps = "Your first recap arrives on Monday."
    static let noScores = "No scores that week."
    static let recapsPageTitle = "Recaps"
    static let recapsPageLede = "Every week on record, newest first. Pick one to read it."
    static let backToWeek = "Week"
    static let backHint = "Back to Week"
    static let coverTitle = "Your week in Zen"
    static let latest = "Latest"
    static let won = "Won"
    static let avg = "AVG"
    static let average = "Average"
    static let tryNext = "Try next week"
    static let shareWeek = "Share this week"
    static let toastAction = "Read it"
}

/// Week: the hero (this week and the streak), Explore (Gemini's review and set questions), and the
/// recaps of past weeks, with every week on record a page away.
struct WeekView: View {
    enum Page: Equatable { case week, recaps }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .week
    @State private var selectedRecap: Date?
    @State private var ask = WeekAskModel()

    var body: some View {
        let entries = model.streak.map(RecapBook.entries(from:)) ?? []
        ZStack {
            switch page {
            case .week:
                WeekPage(ask: ask, entries: entries) { entry in
                    selectedRecap = entry?.id
                    page = .recaps
                }
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            case .recaps:
                RecapsPage(entries: entries, selected: $selectedRecap) { page = .week }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(ZenMotion.container, value: page)
        #if DEBUG
        // Debug renders: ZEN_WEEK_PAGE=recaps opens the Recaps page; ZEN_WEEK_ASK=0…3 asks a question.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["ZEN_WEEK_PAGE"] == "recaps" { page = .recaps }
            if let i = env["ZEN_WEEK_ASK"].flatMap(Int.init), WeekPrompt.all.indices.contains(i) {
                ask.ask(WeekPrompt.all[i], recap: WeekDemo.recap, reduceMotion: true)
            }
        }
        #endif
    }
}

/// The Week page itself, top to bottom.
private struct WeekPage: View {
    @Environment(AppModel.self) private var model
    let ask: WeekAskModel
    let entries: [RecapEntry]
    let openRecaps: (RecapEntry?) -> Void

    var body: some View {
        let snapshot = model.snapshot ?? FakeSnapshot.value
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s8) {
                VStack(alignment: .leading, spacing: ZenSpace.s3) {
                    if let streak = model.streak {
                        WeekHero(week: snapshot.week, streak: streak)
                    }
                    ScreensStrip(devices: snapshot.devices)
                }
                ExploreSection(ask: ask)
                PastRecapsFooter(entries: entries, open: openRecaps)
                    .id(Self.footerID)
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // Debug renders: ZEN_WEEK_SCROLL=recaps lands on the footer.
        .onAppear {
            if ProcessInfo.processInfo.environment["ZEN_WEEK_SCROLL"] == "recaps" {
                Task { try? await Task.sleep(for: .milliseconds(400)); proxy.scrollTo(Self.footerID, anchor: .bottom) }
            }
        }
        #endif
        }
    }

    private static let footerID = "past-recaps"
}

/// Each screen's part this week, on one quiet line.
private struct ScreensStrip: View {
    let devices: [DeviceLine]

    var body: some View {
        HStack(spacing: ZenSpace.s5) {
            Eyebrow(WeekCopy.screens)
            ForEach(devices) { d in
                HStack(spacing: ZenSpace.s2) {
                    Image(systemName: d.kind == .iPhone ? "iphone" : "laptopcomputer")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.zen.textHeading)
                    Text(d.name).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(d.detail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ZenSpace.s5)
        .frame(height: 44)
        .background(Capsule().fill(Color.zen.surfaceCard.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Color.zen.borderHairline, lineWidth: 1))
    }
}

/// One day: the score in Departure on a tile. Good days on the green tint, the winning day ringed
/// in amber, a day with no data an outline, days to come quiet.
struct DayTile: View {
    let name: String
    let score: ZenScore?
    var isToday = false
    var isWinning = false
    var isFuture = false

    var body: some View {
        let good = score?.isGoodDay == true
        VStack(spacing: 4) {
            Text(name.uppercased()).font(ZenFont.number(9.5)).tracking(0.6)
                .foregroundStyle(isWinning ? Color.zen.accentRewardText : (isToday ? Color.zen.textHeading : Color.zen.textCaption))
            Text(score?.text ?? (isFuture ? "" : "–"))
                .font(ZenFont.number(17)).foregroundStyle(Color.zen.textHeading)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 62)
        .background {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .fill(isWinning ? Color.zen.accentRewardTint : (good ? Color.zen.surfaceTint : Color.zen.surfaceSunk.opacity(isFuture ? 0.25 : 0.6)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .strokeBorder(isWinning ? Color.zen.accentReward : (isToday ? Color.zen.textBrand.opacity(0.6) : (score == nil && !isFuture ? Color.zen.borderOutline : .clear)),
                              lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(score.map { "\($0.text)\($0.isGoodDay ? ", a good day" : "")" } ?? (isFuture ? "not yet" : "no data"))")
    }
}

/// A four-point spark for Gemini's lines: Zeno's own sparkle, in a cool gradient.
struct GeminiSpark: View {
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0x4F8DF7), Color(hex: 0xA77BF3)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityHidden(true)
    }
}

/// Cells that fill one after another while something loads (never a spinner).
struct LoadingCells: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion)) { tl in
            let step = Int(tl.date.timeIntervalSinceReferenceDate / 0.12) % 9
            CellRow((0..<8).map { $0 < step ? .on : .empty }, size: 8)
        }
    }
}

// MARK: - The sidebar notice

/// "Your week, reviewed": a notice at the foot of the sidebar when a new review lands, until it's
/// read or closed. Amber, because a review is something earned, not something to fix.
struct WeeklyReviewToast: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        if let (review, _) = model.review, !model.reviewSeen {
            HStack(alignment: .top, spacing: ZenSpace.s3) {
                GeminiSpark(size: 13).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(WeekCopy.reviewEyebrow)
                    Text(review.headline).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(WeekCopy.toastAction) {
                        model.reviewSeen = true
                        open()
                    }
                    .buttonStyle(ZenLinkButtonStyle())
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(ZenMotion.exit) { model.reviewSeen = true }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.zen.textCaption)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(ZenSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.accentReward.opacity(0.5), lineWidth: 1))
            .transition(.move(edge: .leading).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Your weekly review is ready")
        }
    }
}
