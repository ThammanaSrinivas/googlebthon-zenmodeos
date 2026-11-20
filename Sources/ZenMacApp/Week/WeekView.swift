import SwiftUI
import Albeit
import ZenAPI

/// Words on the Week and Calendar sections, named once.
enum WeekCopy {
    static let eyebrow = "The weekly streak"
    static let titleTop = "Four good days"
    static let titleBottom = "wins the week."
    static let lede = "A good day is a Zen Score above 6.0. Win four, Monday to Sunday, and the week is yours."
    static let reviewEyebrow = "Weekly review · Gemini"
    static let reviewLoading = "Zeno's reading your week…"
    static let tryThis = "Try this week"
    static let fromGemini = "Written by Gemini from your scores alone"
    static let fromHere = "Written here from your scores: Gemini didn't answer in time"
    static let askAgain = "Write it again"
    static let acrossDevices = "Across your screens"
    static let iPhoneLine = "Score only"
    static let share = "Share streak"
    static let toastAction = "Read it"
}

/// Week: the streak as a calendar of weeks, this week's days, Gemini's review, and each screen's part.
struct WeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                header
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    if let streak = model.streak {
                        StreakGridCard(streak: streak)
                            .frame(width: 470)
                    }
                    VStack(spacing: ZenSpace.s4) {
                        ThisWeekCard(snapshot: model.snapshot ?? FakeSnapshot.value)
                        ReviewCard()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        let streak = model.streak
        let good = streak?.thisWeek?.goodDays ?? 0
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(spacing: ZenSpace.s3) {
                    CellRow((0..<4).map { $0 < good ? .on : .empty }, size: 8)
                    Eyebrow(WeekCopy.eyebrow)
                    // The weeks before this one come from day history, which isn't wired yet.
                    DemoTag("Demo history")
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(WeekCopy.titleTop).foregroundStyle(Color.zen.textHeading)
                    Text(WeekCopy.titleBottom)
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xD9A400), Color(hex: 0x7A5A00)], startPoint: .leading, endPoint: .trailing))
                }
                .zenType(.display)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text(WeekCopy.lede).zenType(.body).foregroundStyle(Color.zen.textBody)
            }
            Spacer()
            if let streak {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(streak.currentStreak)").font(ZenFont.number(64)).foregroundStyle(Color.zen.textHeading)
                    Text("week streak").font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text("Best \(streak.bestStreak) · this week can make it \(streak.streakBeforeThisWeek + 1)")
                        .zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - This week

struct ThisWeekCard: View {
    let snapshot: ScoreSnapshot
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let week = snapshot.week
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Eyebrow("This week")
                Spacer()
                Text(week.statusLine).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            HStack(spacing: ZenSpace.s2) {
                ForEach(0..<7, id: \.self) { i in
                    DayTile(name: names[i], score: week.days[i], isToday: i == week.todayIndex,
                            isWinning: week.winningDayIndex == i, isFuture: week.todayIndex.map { i > $0 } ?? false)
                }
            }
            Divider().overlay(Color.zen.borderHairline)
            Eyebrow(WeekCopy.acrossDevices)
            VStack(spacing: ZenSpace.s2) {
                ForEach(snapshot.devices) { d in
                    DeviceRow(symbol: d.kind == .iPhone ? "iphone" : "laptopcomputer", name: d.name, detail: d.detail)
                }
            }
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
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

// MARK: - Gemini's review

struct ReviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(WeekCopy.reviewEyebrow)
                Spacer()
                DemoTag()
            }
            if let (review, source) = model.review, !model.reviewLoading {
                Text(review.headline).zenType(.title).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(review.body).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(WeekCopy.tryThis, color: Color.zen.textBrand)
                    Text(review.experiment).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.8)))
                HStack {
                    Text(source == .gemini ? WeekCopy.fromGemini : WeekCopy.fromHere).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    Button(WeekCopy.askAgain) { Task { await model.loadReview() } }.buttonStyle(ZenLinkButtonStyle())
                }
            } else {
                HStack(spacing: ZenSpace.s3) {
                    ZenoView(.curious).frame(width: 56)
                    VStack(alignment: .leading, spacing: ZenSpace.s2) {
                        Text(WeekCopy.reviewLoading).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        LoadingCells()
                    }
                }
                .padding(.vertical, ZenSpace.s4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WeekCopy.reviewLoading)
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
        .animation(ZenMotion.container, value: model.reviewLoading)
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

// MARK: - The dashboard toast

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
                    Eyebrow("Weekly review")
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
