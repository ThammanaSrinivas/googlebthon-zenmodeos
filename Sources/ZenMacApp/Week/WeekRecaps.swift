import SwiftUI
import Albeit
import ZenAPI

// MARK: - The recaps on record

/// One finished week, as its Monday recap tells it.
struct RecapEntry: Identifiable, Equatable, Sendable {
    let id: Date
    let index: Int
    let days: [ZenScore?]
    let goodDays: Int
    let isWon: Bool
    let average: ZenScore?
    /// The weekly streak once this week closed.
    let streakAfter: Int
    /// The day the fourth good day landed, if it did.
    let wonOn: Int?
    let bestDay: Int?
    let hardDay: Int?
    /// This Mac's distracting minutes each day (nil where it measured nothing).
    let macMinutes: [Int?]
    let pullBacks: Int
    let headline: String
    let body: String
    let experiment: String

    /// The week's emotion: what Zeno wears on its cover. A strong win is proud, a win sealed by
    /// Thursday happy, a midweek win calm, a weekend finish relieved (pleasant); a week one good
    /// day short is curious about the next, a quieter one resting.
    var feeling: ZenoFeeling {
        if isWon {
            if (average?.tenths ?? 0) >= 72 { return .proud }
            switch wonOn ?? 6 {
            case ...3: return .happy
            case 4: return .calm
            default: return .pleasant
            }
        }
        return goodDays == 3 ? .curious : .sleepy
    }

    /// The light the cover is lit in.
    var tone: RecapTone {
        switch feeling {
        case .proud: .amber
        case .happy: .zen
        case .calm, .pleasant: .mint
        default: .twilight
        }
    }

    var weekNumber: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.component(.weekOfYear, from: id)
    }

    var range: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: id) ?? id
        let sameMonth = Calendar.current.isDate(id, equalTo: end, toGranularity: .month)
        let start = sameMonth ? id.formatted(.dateTime.day()) : id.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// "Won on Thursday" or "3 of 4 good days".
    var outcome: String {
        if let wonOn { return "Won on \(RecapBook.dayNames[wonOn])" }
        return "\(goodDays) of 4 good days"
    }

    var macTotal: Int { macMinutes.compactMap { $0 }.reduce(0, +) }

    /// The badge on a card: "Won · 9-week streak" or "3 of 4 good days".
    var badge: String {
        isWon ? "\(WeekCopy.won) · \(streakAfter)-week streak" : "\(goodDays) of 4 good days"
    }

    /// What VoiceOver reads for a card.
    var spoken: String {
        let score = average.map { "\(WeekCopy.scoreLabel) \(WeekCopy.scoreSublabel) \($0.text)" } ?? WeekCopy.noScores
        return "Week \(weekNumber), \(range). \(headline). \(score). \(isWon ? badge : "Not won, \(badge)")."
    }
}

/// Recaps from the streak calendar's finished weeks, newest first. Words come from the numbers;
/// the real ones are Gemini's, written each Monday. The Mac's minutes here are demo numbers drawn
/// from each day's score, labelled as such wherever they show.
enum RecapBook {
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func entries(from streak: StreakCalendar) -> [RecapEntry] {
        var streakCount = 0
        var out: [RecapEntry] = []
        for (n, week) in streak.weeks.enumerated() where !week.isCurrent {
            streakCount = week.isWon ? streakCount + 1 : 0
            let scores = week.days.map { $0?.score }
            let scored = scores.enumerated().compactMap { i, s in s.map { (i, $0) } }
            let average = scored.isEmpty ? nil : ZenScore(tenths: scored.map(\.1.tenths).reduce(0, +) / scored.count)
            let best = scored.max { $0.1 < $1.1 }, low = scored.min { $0.1 < $1.1 }
            let bestName = best.map { dayNames[$0.0] } ?? "", lowName = low.map { dayNames[$0.0] } ?? ""
            let wonOn = week.progress.winningDayIndex
            // Lower scores come with more distracting minutes on the Mac; weekends, a little less.
            let mac: [Int?] = scores.enumerated().map { i, s in
                s.map { max(6, (100 - $0.tenths) * 2 + (i * 7 + n * 11) % 23 - (i >= 5 ? 20 : 0)) }
            }
            let pulls = scored.reduce(0) { $0 + ($1.1.isGoodDay ? 4 : 2) } + n % 3
            let headline = WeekPattern.headline(days: scores, wonOn: wonOn)
            let body = best.flatMap { b in low.map { l in
                b.0 == l.0 ? "\(bestName) came in at \(b.1.text)."
                    : "\(bestName) was the calmest at \(b.1.text). \(lowName) dipped to \(l.1.text). \(week.goodDays) good days, an average of \(average?.text ?? "–")."
            } } ?? WeekCopy.noScores
            let experiment = week.isWon
                ? "Keep \(bestName)'s shape: an early close and the phone outside the room."
                : "Give \(lowName) one phone-free hour after 9."
            out.append(RecapEntry(id: week.id, index: n, days: scores, goodDays: week.goodDays, isWon: week.isWon,
                                  average: average, streakAfter: streakCount, wonOn: wonOn,
                                  bestDay: best?.0, hardDay: low?.0, macMinutes: mac, pullBacks: pulls,
                                  headline: headline, body: body, experiment: experiment))
        }
        return out.reversed()
    }
}

// MARK: - The light a recap is lit in

/// The glow a recap's story is lit in, from the week's feeling: Albeit's green, mint, amber for a
/// proud week, a dusk for a quiet one.
enum RecapTone {
    case zen, mint, amber, twilight

    var glow: UInt32 {
        switch self {
        case .zen, .mint: 0x5BDF62
        case .amber: 0xFFC800
        case .twilight: 0xB7A8E0
        }
    }
}

// MARK: - A recap card

/// A past week as a card: the week drawn as light from its own scores, how it went in one line,
/// the week's average Zen Score with its name on it, and won or not with the streak. Lifts on
/// hover, rings on keyboard focus, and opens the week over the page.
struct RecapCard: View {
    let entry: RecapEntry
    let open: () -> Void

    var body: some View {
        Button(action: open) { RecapCardFace(entry: entry) }
            .buttonStyle(RecapCardStyle())
            .focusEffectDisabled()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.spoken)
            .accessibilityHint(WeekCopy.openRecapHint)
            .accessibilityAddTraits(.isButton)
    }
}

/// The card's face, drawn the same in every state; the style adds the lift and the ring.
private struct RecapCardFace: View {
    let entry: RecapEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeekLight(days: entry.days, wonOn: entry.wonOn, seed: entry.index)
                .frame(height: 136)
                .overlay(alignment: .topLeading) {
                    Text("WEEK \(entry.weekNumber)")
                        .font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(Color.zen.textHeading)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.zen.surfaceRaised.opacity(0.9)))
                        .padding(ZenSpace.s3)
                }
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.range.uppercased()).font(ZenFont.number(10)).tracking(0.8).foregroundStyle(Color.zen.textCaption)
                    Text(entry.headline).font(ZenFont.text(16, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Color.zen.borderHairline).frame(height: 1)
                HStack(alignment: .bottom, spacing: ZenSpace.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeekCopy.scoreLabel).font(ZenFont.text(11.5, .semibold)).foregroundStyle(Color.zen.textBody)
                        Text(WeekCopy.scoreSublabel).font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                    }
                    Spacer(minLength: 0)
                    Text(entry.average?.text ?? "–").font(ZenFont.number(30)).foregroundStyle(Color.zen.textHeading)
                        .lineLimit(1).fixedSize()
                }
                RecapOutcomeBadge(entry: entry)
            }
            .padding(ZenSpace.s4)
        }
    }
}

/// Won (amber, a seal, the streak) or not (quiet, the good days it reached). Words carry it; the
/// colour only agrees.
struct RecapOutcomeBadge: View {
    let entry: RecapEntry

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.isWon ? "checkmark.seal.fill" : "circle.dashed").font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(entry.badge).font(ZenFont.text(12, .semibold)).lineLimit(1)
        }
        .foregroundStyle(entry.isWon ? Color.zen.accentRewardText : Color.zen.textBody)
        .padding(.horizontal, 9).frame(height: 24)
        .background(Capsule().fill(entry.isWon ? Color.zen.accentRewardTint : Color.zen.surfaceSunk))
        .overlay(Capsule().strokeBorder(entry.isWon ? Color.zen.accentReward.opacity(0.55) : Color.zen.borderOutline, lineWidth: 1))
    }
}

/// The card's states: a lift and a deeper shadow on hover, a sink on press, a brand ring on
/// keyboard focus. Reduce Motion keeps the shadow and drops the movement.
private struct RecapCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        @Environment(\.colorScheme) private var scheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
            let dark = scheme == .dark
            let lifted = hovering || focused
            configuration.label
                .background(shape.fill(Color.zen.surfaceRaised))
                .clipShape(shape)
                .overlay(shape.strokeBorder(lifted ? Color.zen.borderOutline : Color.zen.borderHairline, lineWidth: 1))
                .shadow(color: Color(hex: 0x12160F, alpha: dark ? 0.3 : 0.06), radius: 1.5, y: 1)
                .shadow(color: Color(hex: 0x12160F, alpha: lifted ? (dark ? 0.55 : 0.16) : (dark ? 0.22 : 0.06)),
                        radius: lifted ? 26 : 18, y: lifted ? 16 : 10)
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: ZenRadius.xl + 4, style: .continuous)
                            .strokeBorder(Color.zen.textBrand, lineWidth: 2.5)
                            .padding(-5)
                    }
                }
                .offset(y: lifted && !reduceMotion ? -4 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(ZenMotion.calm(ZenMotion.t2), value: lifted)
                .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(shape)
        }
    }
}

// MARK: - The footer on Week

/// The latest recaps as cards, with View all. A card opens its week over the page.
struct PastRecapsFooter: View {
    let entries: [RecapEntry]
    let open: (RecapEntry?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text(WeekCopy.recapsTitle).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text(WeekCopy.recapsLede).zenType(.body).foregroundStyle(Color.zen.textCaption)
                Spacer()
                Button { open(nil) } label: {
                    HStack(spacing: 4) {
                        Text(WeekCopy.viewAll)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(ZenLinkButtonStyle())
                .accessibilityHint(WeekCopy.viewAllHint)
            }
            if entries.isEmpty {
                Text(WeekCopy.noRecaps).zenType(.body).foregroundStyle(Color.zen.textBody)
            } else {
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    ForEach(entries.prefix(4)) { entry in
                        RecapCard(entry: entry) { open(entry) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Sharing

/// A recap as a picture to share, Flow 07's story card: the week as light, Zeno in its feeling,
/// the average and how the week went. Scores only.
struct RecapShareImage: View {
    let entry: RecapEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeekLight(days: entry.days, wonOn: entry.wonOn, seed: entry.index, showsDays: true)
                .frame(height: 330)
                .overlay(alignment: .topTrailing) {
                    ZenoStill(entry.feeling).frame(width: 96).padding(ZenSpace.s6)
                }
                .environment(\.colorScheme, .dark)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text("ZENMODE OS · WEEK \(entry.weekNumber) · \(entry.range.uppercased())")
                    .font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Ink.caption)
                Text(WeekCopy.coverTitle).font(ZenFont.brand(36)).foregroundStyle(Ink.text)
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                    Text(entry.average?.text ?? "–").font(ZenFont.number(72)).foregroundStyle(entry.isWon ? Ink.gold : Ink.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.headline).font(ZenFont.text(17, .semibold)).foregroundStyle(Ink.text)
                        Text("\(WeekCopy.scoreLabel) · \(WeekCopy.scoreSublabel) · \(entry.badge)")
                            .font(ZenFont.text(13)).foregroundStyle(Ink.body)
                    }
                }
                Spacer()
                Text("zenmodeos.com").font(ZenFont.number(12)).foregroundStyle(Ink.mono)
            }
            .padding(40)
        }
        .frame(width: 540, height: 675, alignment: .topLeading)
        .background(InkTable())
    }
}
