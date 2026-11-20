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

    /// What VoiceOver reads for a cover.
    var spoken: String {
        "Week \(weekNumber), \(range): \(outcome)\(average.map { ", average \($0.text)" } ?? ""). \(headline)"
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
            let headline = week.isWon
                ? "\(bestName)s set the pace"
                : "\(lowName) was the hard day"
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

// MARK: - The cover art

/// The lights a recap cover can be lit in: Albeit's pattern tones, each with a night variant.
enum RecapTone {
    case zen, mint, amber, twilight

    /// Sky top and bottom on paper.
    var day: (UInt32, UInt32) {
        switch self {
        case .zen: (0xD8ECD3, 0xFFF4D3)
        case .mint: (0xE3F2E0, 0xFBFBF1)
        case .amber: (0xFFE3A1, 0xFFF7E2)
        case .twilight: (0xD9D6E4, 0xF9E6D6)
        }
    }

    /// The glow behind Zeno, the same by day and night.
    var glow: UInt32 {
        switch self {
        case .zen, .mint: 0x5BDF62
        case .amber: 0xFFC800
        case .twilight: 0xB7A8E0
        }
    }

    /// The near and far hills.
    var hills: (UInt32, UInt32) {
        switch self {
        case .zen: (0x9FD49A, 0xC6E6BF)
        case .mint: (0xB8DDB4, 0xD6EDD1)
        case .amber: (0xF2C25A, 0xF9DD97)
        case .twilight: (0xB9B2CF, 0xD4CDE2)
        }
    }
}

/// A recap's cover: the week's light, a horizon, Zeno in the week's feeling, and a string of beads
/// across the top, a marigold for every good day. Lit by day, a night sky in dark mode.
struct RecapArt: View {
    let entry: RecapEntry
    var zenoScale: CGFloat = 0.5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = entry.tone
        let dark = scheme == .dark
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: dark ? [Color(hex: 0x0B120C), Color(hex: 0x152218)] : [Color(hex: tone.day.0), Color(hex: tone.day.1)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: tone.glow, alpha: dark ? 0.32 : 0.42), .clear],
                               center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: w * 0.62)
                // The sun sits over the week's calmest day, Monday on the left.
                if let best = entry.bestDay {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: dark ? 0xF2F3EE : 0xFFF8E1), Color(hex: tone.glow, alpha: dark ? 0.5 : 0.75)],
                                             center: .center, startRadius: 0, endRadius: w * 0.07))
                        .frame(width: w * 0.13, height: w * 0.13)
                        .shadow(color: Color(hex: tone.glow, alpha: 0.6), radius: 14)
                        .position(x: w * (0.12 + 0.76 * (CGFloat(best) + 0.5) / 7), y: h * 0.5)
                }
                Hills(seed: entry.index, height: 0.36)
                    .fill(Color(hex: dark ? 0x1C2A1E : tone.hills.1).opacity(dark ? 1 : 0.9))
                Hills(seed: entry.index + 7, height: 0.24)
                    .fill(Color(hex: dark ? 0x233526 : tone.hills.0))
                BeadString(days: entry.days, wonOn: entry.wonOn)
                    .frame(height: h * 0.2)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, w * 0.08)
                    .padding(.top, h * 0.05)
                ZenoStill(entry.feeling)
                    .frame(width: w * zenoScale)
                    .position(x: w / 2, y: h * 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rolling hills, the lower `height` of the frame, shaped by a seed so every week is its own place.
private struct Hills: Shape {
    let seed: Int
    let height: CGFloat

    func path(in r: CGRect) -> Path {
        let top = r.maxY - r.height * height
        let a = CGFloat((seed * 37) % 17) / 17, b = CGFloat((seed * 53) % 13) / 13
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: top + r.height * 0.06 * a))
        p.addCurve(to: CGPoint(x: r.maxX, y: top + r.height * 0.05 * b),
                   control1: CGPoint(x: r.width * (0.25 + 0.15 * b), y: top - r.height * 0.09),
                   control2: CGPoint(x: r.width * (0.65 + 0.1 * a), y: top + r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Seven beads on a sagging string: a marigold for a good day (the winning one deeper), a seed for
/// a day under 6.0, a ring for no data.
private struct BeadString: View {
    let days: [ZenScore?]
    let wonOn: Int?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Seeds and rings sit on the sky: dark ink by day, pale ink at night.
        let seedInk: UInt32 = scheme == .dark ? 0xE8EBE3 : 0x12160F
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            var rope = Path()
            rope.move(to: CGPoint(x: 0, y: h * 0.15))
            rope.addQuadCurve(to: CGPoint(x: w, y: h * 0.15), control: CGPoint(x: w / 2, y: h * 0.55))
            ctx.stroke(rope, with: .color(Color(hex: 0x7A5A00, alpha: 0.45)), lineWidth: 1.2)
            let r = min(w / 22, h * 0.26)
            for i in 0..<7 {
                let t = (CGFloat(i) + 0.5) / 7
                let x = w * t, y = h * 0.15 + (h * 0.4) * 4 * t * (1 - t) * 0.5 + r * 1.2
                let day = days.indices.contains(i) ? days[i] : nil
                if day?.isGoodDay == true {
                    let deep = i == wonOn
                    for k in 0..<8 {
                        var petal = ctx
                        petal.translateBy(x: x, y: y)
                        petal.rotate(by: .degrees(Double(k) * 45))
                        petal.fill(Path(ellipseIn: CGRect(x: -r * 0.4, y: -r, width: r * 0.8, height: r)),
                                   with: .color(deep ? Color(hex: 0xFF7A1A) : Color(hex: 0xFFB524)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.32, y: y - r * 0.32, width: r * 0.64, height: r * 0.64)), with: .color(Color(hex: 0xB45A00)))
                } else if day != nil {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.5, width: r, height: r)), with: .color(Color(hex: seedInk, alpha: 0.22)))
                } else {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.5, width: r, height: r)), with: .color(Color(hex: seedInk, alpha: 0.3)), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - A recap thumbnail

/// A recap as a moment: the art on top, then the week, its outcome and its average. Calm on paper,
/// a quiet lift on hover.
struct RecapThumb: View {
    let entry: RecapEntry
    var isSelected = false
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            RecapArt(entry: entry)
                .aspectRatio(5 / 4, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("WEEK \(entry.weekNumber)").font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    Text(entry.average?.text ?? "–").font(ZenFont.number(15)).foregroundStyle(Color.zen.textHeading)
                }
                Text(entry.outcome).font(ZenFont.text(13.5, .semibold))
                    .foregroundStyle(entry.isWon ? Color.zen.accentRewardText : Color.zen.textHeading)
                    .lineLimit(1)
                Text(entry.range).font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
            }
            .padding(.horizontal, ZenSpace.s3 + 2).padding(.vertical, ZenSpace.s3)
        }
        .background(shape.fill(Color.zen.surfaceCard.opacity(0.85)))
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Color.zen.textBrand : Color.zen.borderHairline, lineWidth: isSelected ? 2 : 1))
        .modifier(ZenLift())
        .offset(y: hovering ? -3 : 0)
        .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spoken)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - The footer on Week

/// The latest recaps as moments, with View all.
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
                        Button { open(entry) } label: { RecapThumb(entry: entry) }
                            .buttonStyle(PressScale())
                    }
                }
            }
        }
    }
}

// MARK: - Sharing

/// A recap as a picture to share, Flow 07's story card: the week's art, the average, the beads.
/// Scores only.
struct RecapShareImage: View {
    let entry: RecapEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecapArt(entry: entry, zenoScale: 0.42)
                .frame(height: 330)
                .environment(\.colorScheme, .light)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text("ZENMODE OS · WEEK \(entry.weekNumber) · \(entry.range.uppercased())")
                    .font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Ink.caption)
                Text(WeekCopy.coverTitle).font(ZenFont.brand(36)).foregroundStyle(Ink.text)
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                    Text(entry.average?.text ?? "–").font(ZenFont.number(72)).foregroundStyle(entry.isWon ? Ink.gold : Ink.text)
                    Text(entry.isWon ? "\(entry.outcome) · \(entry.streakAfter)-week streak" : entry.outcome)
                        .font(ZenFont.text(16, .semibold)).foregroundStyle(Ink.body)
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
