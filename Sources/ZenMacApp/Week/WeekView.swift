import SwiftUI
import Albeit
import ZenAPI

/// Words on the Week section, named once.
enum WeekCopy {
    static let titleTop = "Four good days"
    static let titleBottom = "wins the week."
    static let stateFresh = "Fresh week"
    static let stateBuilding = "Building"
    static let stateClose = "Close"
    static let stateLastChance = "Last chance"
    static let stateWon = "Won"
    static let stateEnded = "Ended short"
    static let weeksInARow = "weeks in a row"
    static func nextMilestone(_ left: Int, _ target: Int) -> String {
        left == 1 ? "One more won week makes \(target)." : "\(left) more won weeks make \(target)."
    }
    static let pastAYear = "A year and counting."
    static let wonIt = "Won it"
    static let noData = "No data"
    static let under6 = "Under 6.0"
    static let share = "Share streak"
    static let shareHint = "Shares a picture of your streak. Scores only, never minutes or apps."
    static let demoHistory = "Demo history"

    static let exploreTitle = "Zeno's read of your week"
    static let reviewEyebrow = "Weekly review"
    /// Gemini is credited only when Gemini wrote the words.
    static let fromGemini = "Zeno · Gemini"
    static let fromNumbers = "Written from your numbers"
    static let reviewLoading = "Zeno's reading your week…"
    static let tryThis = "Try this week"
    static let regenerate = "Regenerate"
    static let regenerateHint = "Writes this week's review again from your scores"
    static let askEyebrow = "Ask about your week"
    static let askLede = "Answers come from your scores and this Mac's minutes, never from your apps or your iPhone's time."
    static let askHint = "Zeno answers from your scores"
    static let askThinking = "Zeno's thinking…"
    static let askEmpty = "Pick a question and the answer lands here."
    static let youAsked = "You asked"
    static let askFallback = "I can't read the week right now. Your scores are safe; ask again in a moment."

    static let recapsTitle = "Past recaps"
    static let recapsLede = "Your week in Zen, every Monday."
    static let viewAll = "View all"
    static let viewAllHint = "Opens every week on record"
    static let noRecaps = "Your first recap arrives on Monday."
    static let noScores = "No scores that week."
    static let noMatches = "No weeks to show here yet."
    static let recapsPageTitle = "Recaps"
    static let recapsPageLede = "Every week on record. Open one to play its story."
    static let scoreLabel = "Zen Score"
    static let scoreSublabel = "week average"
    static let openRecapHint = "Opens this week's recap over the page"
    static let closeRecap = "Close recap"
    static let olderWeek = "Older week"
    static let newerWeek = "Newer week"
    static let backToWeek = "Week"
    static let backHint = "Back to Week"
    static let coverTitle = "Your week in Zen"
    static let won = "Won"
    static let average = "Average"
    static let tryNext = "Try next week"
    static let shareWeek = "Share this week"
    static let toastAction = "Read it"

    static let statGood = "Good days"
    static let statPullBacks = "Pull-backs"
    static let statMac = "This Mac"
    static let screens = "Across your screens"
    static let lowerOfTwo = "Each day's score is the lower of the two"
    static let thisMac = "This Mac"
    static let mac = "Mac"
    static let iPhone = "iPhone"
    static let iPhoneScoreOnly = "The iPhone shares its score only. Its minutes stay on the phone."
    static let twoScreens = "Two screens, one score."
    static let patternLine = "Drawn in the pattern you chose in Zen Circle. Every seed is an hour."
    static let highlight = "The highlight"
    static let inTheWay = "What got in the way"
    static let highlightLine = "The fourth good day landed here, and the week was yours."
    static let inTheWayLine = "Most of the dip landed after 9 pm on this Mac. One evening, not the whole week."
    static let nextWeekKicker = "Next week"
    static let goldOpens = "Zen Gold is open all next week."
    static let winNext = "Let's win the next one."
    static let streakSoFar = "The streak so far"
    static let weeksWon = "weeks won"
    static let bestStreak = "best streak"
    static let goodDayRate = "good days"
    static let milestones = "Milestones"
}

/// Week: this week and the streak, Zeno's read of it, and the recaps of past weeks, with every
/// week on record a page away. A recap opens over whichever page it was picked on.
struct WeekView: View {
    enum Page: Equatable { case week, recaps }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .week
    /// The recap open over the page, by its Monday.
    @State private var openRecap: Date?
    @State private var ask = WeekAskModel()

    var body: some View {
        let entries = model.streak.map(RecapBook.entries(from:)) ?? []
        let overlaid = openRecap != nil
        ZStack {
            Group {
                switch page {
                case .week:
                    WeekPage(ask: ask, entries: entries) { entry in
                        if let entry { openRecap = entry.id } else { page = .recaps }
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                case .recaps:
                    RecapsPage(entries: entries, streak: model.streak, open: { openRecap = $0.id }) {
                        if overlaid { openRecap = nil } else { page = .week }
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            // Under an open recap the page steps back: blurred, out of reach of the pointer, the
            // keyboard and VoiceOver.
            .blur(radius: overlaid ? 6 : 0)
            .disabled(overlaid)
            .accessibilityHidden(overlaid)
            if overlaid {
                RecapOverlay(entries: entries, openID: $openRecap)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(1)
            }
        }
        .animation(ZenMotion.container, value: page)
        .animation(ZenMotion.container, value: overlaid)
        #if DEBUG
        // Debug renders: ZEN_WEEK_PAGE=recaps opens Recaps; ZEN_WEEK_RECAP=n opens the nth newest
        // recap over the page; ZEN_WEEK_ASK=0…3 asks a question.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["ZEN_WEEK_PAGE"] == "recaps" { page = .recaps }
            if let n = env["ZEN_WEEK_RECAP"].flatMap(Int.init), entries.indices.contains(n) { openRecap = entries[n].id }
            if let i = env["ZEN_WEEK_ASK"].flatMap(Int.init), WeekPrompt.all.indices.contains(i) {
                ask.ask(WeekPrompt.all[i], recap: WeekDemo.recap, reduceMotion: true)
            }
        }
        #endif
    }
}

/// The Week page itself: three bands, each with one job.
private struct WeekPage: View {
    @Environment(AppModel.self) private var model
    let ask: WeekAskModel
    let entries: [RecapEntry]
    let openRecaps: (RecapEntry?) -> Void

    var body: some View {
        let snapshot = model.snapshot ?? FakeSnapshot.value
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ZenSpace.s10) {
                    if let streak = model.streak {
                        WeekHero(week: snapshot.week, streak: streak)
                    }
                    ExploreSection(ask: ask)
                    PastRecapsFooter(entries: entries, open: openRecaps)
                        .id(Self.footerID)
                }
                .padding(ZenSpace.s6)
                .padding(.bottom, ZenSpace.s6)
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
