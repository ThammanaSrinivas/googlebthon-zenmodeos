import SwiftUI
import Albeit
import ZenAPI

// MARK: - The recaps on record

/// One finished week, as its Monday recap reads it.
struct RecapEntry: Identifiable, Equatable, Sendable {
    let id: Date
    let days: [ZenScore?]
    let goodDays: Int
    let isWon: Bool
    let average: ZenScore?
    /// The weekly streak once this week closed.
    let streakAfter: Int
    let headline: String
    let body: String
    let experiment: String

    var range: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: id) ?? id
        let sameMonth = Calendar.current.isDate(id, equalTo: end, toGranularity: .month)
        let start = sameMonth ? id.formatted(.dateTime.day()) : id.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var outcome: String { isWon ? WeekCopy.won : "\(goodDays) of 4" }

    /// What VoiceOver reads for a cover.
    var spoken: String {
        "Week of \(range): \(isWon ? "won" : "\(goodDays) of 4 good days")\(average.map { ", average \($0.text)" } ?? ""). \(headline)"
    }
}

/// Recaps from the streak calendar's finished weeks, newest first. Words come from the numbers;
/// the real ones are Gemini's, written each Monday.
enum RecapBook {
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func entries(from streak: StreakCalendar) -> [RecapEntry] {
        var streakCount = 0
        var out: [RecapEntry] = []
        for week in streak.weeks where !week.isCurrent {
            streakCount = week.isWon ? streakCount + 1 : 0
            let scores = week.days.map { $0?.score }
            let scored = scores.enumerated().compactMap { i, s in s.map { (i, $0) } }
            let average = scored.isEmpty ? nil : ZenScore(tenths: scored.map(\.1.tenths).reduce(0, +) / scored.count)
            let best = scored.max { $0.1 < $1.1 }, low = scored.min { $0.1 < $1.1 }
            let bestName = best.map { dayNames[$0.0] } ?? "", lowName = low.map { dayNames[$0.0] } ?? ""
            let headline = week.isWon
                ? "Week won · \(bestName) led at \(best?.1.text ?? "–")"
                : "\(week.goodDays) of 4 · \(lowName) was the hard day"
            let body = best.flatMap { b in low.map { l in
                b.0 == l.0 ? "\(bestName) came in at \(b.1.text)."
                    : "\(bestName) was the calmest at \(b.1.text). \(lowName) dipped to \(l.1.text). \(week.goodDays) good days, an average of \(average?.text ?? "–")."
            } } ?? WeekCopy.noScores
            let experiment = week.isWon
                ? "Keep \(bestName)'s shape: an early close and the phone outside the room."
                : "Give \(lowName) one phone-free hour after 9."
            out.append(RecapEntry(id: week.id, days: scores, goodDays: week.goodDays, isWon: week.isWon, average: average,
                                  streakAfter: streakCount, headline: headline, body: body, experiment: experiment))
        }
        return out.reversed()
    }
}

// MARK: - A recap cover

/// A recap as a story cover, 4:5: night with a green light for a won week, dusk for one that fell
/// short; the week, "Your week in Zen", the week's beads, and the mark leaning in at the corner.
struct RecapCover: View {
    let entry: RecapEntry
    var isLatest = false
    var isSelected = false
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
        ZStack(alignment: .topLeading) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x151B13), Color(hex: 0x080A07)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [(entry.isWon ? Ink.fill : Color(hex: 0x4D654A)).opacity(entry.isWon ? 0.42 : 0.35), .clear],
                               center: UnitPoint(x: 0.25, y: 1.0), startRadius: 0, endRadius: 260)
                if entry.isWon {
                    RadialGradient(colors: [Ink.gold.opacity(0.14), .clear], center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 180)
                }
            }
            ZenMark()
                .fill(LinearGradient(colors: [Color(hex: 0x5BDF62), Color(hex: 0x2AA136)], startPoint: .top, endPoint: .bottom), style: FillStyle(eoFill: true))
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(-8))
                .opacity(entry.isWon ? 0.9 : 0.4)
                .padding(ZenSpace.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Text((isLatest ? WeekCopy.latest : entry.outcome).uppercased())
                    .font(ZenFont.number(9.5)).tracking(0.8)
                    .foregroundStyle(entry.isWon ? Ink.onGold : Ink.text)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(entry.isWon ? Ink.gold : Color.white.opacity(0.14)))
                Spacer(minLength: ZenSpace.s2)
                Text(entry.range.uppercased()).font(ZenFont.number(10)).tracking(0.9)
                    .foregroundStyle(entry.isWon ? Ink.green : Ink.caption)
                Text(WeekCopy.coverTitle).font(ZenFont.brand(20)).tracking(-0.3).foregroundStyle(Ink.text)
                    .lineLimit(2).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.average?.text ?? "–").font(ZenFont.number(26)).foregroundStyle(Ink.text)
                    Text(WeekCopy.avg).font(ZenFont.number(10)).foregroundStyle(Ink.mono)
                }
                RecapBeads(days: entry.days, size: 9)
                Text(entry.headline).font(ZenFont.text(11.5)).foregroundStyle(Ink.body)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenSpace.s4)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Ink.green : .white.opacity(hovering ? 0.16 : 0.07), lineWidth: isSelected ? 2 : 1))
        .modifier(ZenLift())
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
        .onHover { hovering = $0 }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.spoken)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The week's seven days as small cells: a good day filled green, a measured day a ring, no data faint.
struct RecapBeads: View {
    let days: [ZenScore?]
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(0..<7, id: \.self) { i in
                let day = days.indices.contains(i) ? days[i] : nil
                RoundedRectangle(cornerRadius: size / 5, style: .continuous)
                    .fill(day?.isGoodDay == true ? Ink.green : .clear)
                    .overlay {
                        if day?.isGoodDay != true {
                            RoundedRectangle(cornerRadius: size / 5, style: .continuous)
                                .strokeBorder(day == nil ? Color.white.opacity(0.18) : Color(hex: 0xFF8A3D).opacity(0.7), lineWidth: 1)
                        }
                    }
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The footer on Week

/// The latest recaps as covers, with View all.
struct PastRecapsFooter: View {
    let entries: [RecapEntry]
    let open: (RecapEntry?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(WeekCopy.recapsTitle).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text(WeekCopy.recapsLede).zenType(.body).foregroundStyle(Color.zen.textCaption)
                }
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
                    ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { i, entry in
                        Button { open(entry) } label: { RecapCover(entry: entry, isLatest: i == 0) }
                            .buttonStyle(PressScale())
                    }
                }
            }
        }
    }
}

// MARK: - The Recaps page

/// Every week on record, newest first. The one picked opens above the grid.
struct RecapsPage: View {
    let entries: [RecapEntry]
    @Binding var selected: Date?
    let back: () -> Void

    var body: some View {
        let current = entries.first { $0.id == selected } ?? entries.first
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack {
                    Button(action: back) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text(WeekCopy.backToWeek)
                        }
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityLabel(WeekCopy.backHint)
                    Spacer()
                    DemoTag(WeekCopy.demoHistory)
                }
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Text(WeekCopy.recapsPageTitle).zenType(.display).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text(WeekCopy.recapsPageLede).zenType(.body).foregroundStyle(Color.zen.textBody)
                }
                if let current {
                    RecapDetail(entry: current)
                        .id(current.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZenSpace.s4), count: 4), alignment: .leading, spacing: ZenSpace.s4) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                        Button { selected = entry.id } label: {
                            RecapCover(entry: entry, isLatest: i == 0, isSelected: entry.id == current?.id)
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .padding(ZenSpace.s6)
            .animation(ZenMotion.container, value: selected)
        }
        .scrollIndicators(.hidden)
        .onExitCommand(perform: back)
    }
}

/// One week, opened: the cover beside its numbers, the read of it, and one thing to try next.
private struct RecapDetail: View {
    let entry: RecapEntry
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        HStack(alignment: .top, spacing: ZenSpace.s6) {
            RecapCover(entry: entry, isSelected: false)
                .frame(width: 230)
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow(entry.range, color: Color.zen.textBrand)
                    Text(entry.isWon ? "\(WeekCopy.won) · \(entry.streakAfter)-week streak" : "\(entry.goodDays) of 4 good days")
                        .font(ZenFont.number(10.5)).tracking(0.6)
                        .foregroundStyle(entry.isWon ? Color.zen.accentRewardText : Color.zen.textCaption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(entry.isWon ? Color.zen.accentRewardTint : Color.zen.surfaceSunk))
                }
                Text(entry.headline).font(ZenFont.brand(28)).tracking(-0.7).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: ZenSpace.s2) {
                    ForEach(0..<7, id: \.self) { i in
                        DayTile(name: names[i], score: entry.days[i])
                    }
                }
                Text(entry.body).font(ZenFont.text(14.5)).lineSpacing(5).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Image(systemName: "leaf").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.zen.surfaceTint))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(WeekCopy.tryNext, color: Color.zen.textBrand)
                        Text(entry.experiment).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Text(entry.average.map { "\(WeekCopy.average) \($0.text)" } ?? "").font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    ShareImageButton(fileName: "ZenMode OS week \(entry.range).png", make: { ImageExport.png(RecapShareImage(entry: entry)) }) {
                        Label(WeekCopy.shareWeek, systemImage: "square.and.arrow.up")
                            .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.onActionPrimary)
                            .padding(.horizontal, ZenSpace.s5).frame(height: 40)
                            .background(Capsule().fill(Color.zen.actionPrimary))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(ZenSpace.s6)
        .glassCard(radius: ZenRadius.xxxl)
    }
}

/// A recap as a picture to share: the week's scores only.
struct RecapShareImage: View {
    let entry: RecapEntry

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("ZENMODE OS · \(entry.range.uppercased())").font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Ink.caption)
            Text(WeekCopy.coverTitle).font(ZenFont.brand(40)).foregroundStyle(Ink.text)
            Text(entry.average?.text ?? "–").font(ZenFont.number(110)).foregroundStyle(entry.isWon ? Ink.gold : Ink.text)
            Text(entry.isWon ? "\(WeekCopy.won) · \(entry.streakAfter)-week streak" : "\(entry.goodDays) of 4 good days")
                .font(ZenFont.text(18, .semibold)).foregroundStyle(Ink.body)
            Spacer()
            RecapBeads(days: entry.days, size: 22)
            Text("zenmodeos.com").font(ZenFont.number(12)).foregroundStyle(Ink.mono)
        }
        .padding(48)
        .frame(width: 540, height: 675, alignment: .topLeading)
        .background(InkTable())
    }
}
