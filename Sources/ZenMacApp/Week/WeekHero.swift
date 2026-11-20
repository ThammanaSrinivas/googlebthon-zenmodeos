import SwiftUI
import Albeit
import ZenAPI

/// The ink palette for the dark cards (the hero, the recap story, the share images). They're dark
/// by design in both appearances, so they name their colours here instead of reading the theme.
enum Ink {
    static let ground = Color(hex: 0x12160F)
    static let text = Color(hex: 0xF2F3EE)
    static let body = Color(hex: 0xC9CCC4)
    static let caption = Color(hex: 0xA4A9A0)
    static let mono = Color(hex: 0x858A81)
    static let line = Color(hex: 0x343A34)
    static let well = Color(hex: 0x1F251F)
    static let green = Color(hex: 0x5BDF62)
    static let fill = Color(hex: 0x2AA136)
    static let onGreen = Color(hex: 0x0B2A0E)
    static let gold = Color(hex: 0xFFC800)
    static let goldSoft = Color(hex: 0xFFD86B)
    static let goldWell = Color(hex: 0x2A2208)
    static let onGold = Color(hex: 0x1A1003)
    static let marigold = Color(hex: 0xFF9A1F)
}

// MARK: - Where the week stands

/// The week's state, word for word the same on every surface (the retention board): a kicker,
/// one line, and the feeling Zeno wears for it.
struct WeekState: Equatable {
    enum Kind: Equatable { case fresh, building, close, lastChance, won, endedShort }

    let kind: Kind
    let kicker: String
    let line: String
    let feeling: ZenoFeeling

    init(_ week: WeekProgress) {
        let good = week.goodDays
        let daysLeft = week.todayIndex.map { 6 - $0 } ?? 0
        let needed = max(0, WeekProgress.goodDaysToWin - good)
        if week.isWon {
            kind = .won
            kicker = WeekCopy.stateWon
            line = "Week won · \(week.weeklyStreak)-week streak"
            feeling = .proud
        } else if week.todayIndex == nil {
            kind = .endedShort
            kicker = WeekCopy.stateEnded
            line = "The week ended at \(good) of 4. Tomorrow starts fresh."
            feeling = .sleepy
        } else if needed > 0 && needed == daysLeft + 1 {
            kind = .lastChance
            kicker = WeekCopy.stateLastChance
            line = "Keep today above 6 to win the week."
            feeling = .curious
        } else if good == 3 {
            kind = .close
            kicker = WeekCopy.stateClose
            line = "3 of 4 good days. One more wins the week."
            feeling = .happy
        } else if good == 0 {
            kind = .fresh
            kicker = WeekCopy.stateFresh
            line = "0 of 4 good days. A fresh week."
            feeling = .calm
        } else {
            kind = .building
            kicker = WeekCopy.stateBuilding
            line = "\(good) of 4 good days."
            feeling = .pleasant
        }
    }
}

/// The streak milestones that get a full moment (Flow 07).
enum Milestone {
    static let all = [1, 4, 10, 25, 52]
    /// The next milestone above `streak`, or nil past a year.
    static func next(after streak: Int) -> Int? { all.first { $0 > streak } }
}

// MARK: - The hero

/// This week, as the iPad tells it: ink, the brand line, Zeno wearing the week's state, the seven
/// days, and the streak as a garland growing toward its next milestone. One primary action.
struct WeekHero: View {
    let week: WeekProgress
    let streak: StreakCalendar

    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let state = WeekState(week)
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        HStack(alignment: .top, spacing: ZenSpace.s10) {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack(spacing: ZenSpace.s3) {
                    Text(state.kicker.uppercased()).font(ZenFont.number(10.5)).tracking(1.05)
                        .foregroundStyle(state.kind == .won ? Ink.gold : Ink.green)
                    Text(weekLabel).font(ZenFont.number(10.5)).tracking(1.05).foregroundStyle(Ink.mono)
                    DemoTag(WeekCopy.demoHistory)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(WeekCopy.titleTop).foregroundStyle(Ink.text)
                    Text(WeekCopy.titleBottom)
                        .foregroundStyle(LinearGradient(colors: [Ink.goldSoft, Ink.gold], startPoint: .leading, endPoint: .trailing))
                }
                .font(ZenFont.brand(44)).tracking(-1.4)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                HStack(spacing: ZenSpace.s2) {
                    ForEach(0..<7, id: \.self) { i in
                        InkDayTile(name: names[i], score: week.days[i], goodIndex: goodIndex(i),
                                   isToday: i == week.todayIndex, isWinning: week.winningDayIndex == i,
                                   isFuture: week.todayIndex.map { i > $0 } ?? false)
                    }
                }
                Text(state.line).font(ZenFont.text(16, .semibold))
                    .foregroundStyle(state.kind == .won ? Ink.goldSoft : Ink.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StreakColumn(streak: streak, weeklyStreak: week.weeklyStreak, feeling: state.feeling)
                .frame(width: 260)
        }
        .padding(ZenSpace.s8)
        .background(InkTable())
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
    }

    private var weekLabel: String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let week = calendar.component(.weekOfYear, from: Date())
        return "· WEEK \(week)"
    }

    /// "Good day 2 of 4" under each good day, counted up to the fourth.
    private func goodIndex(_ i: Int) -> Int? {
        guard week.days[i]?.isGoodDay == true else { return nil }
        let n = week.days.prefix(i + 1).compactMap { $0 }.filter(\.isGoodDay).count
        return n <= WeekProgress.goodDaysToWin ? n : nil
    }
}

/// Zeno, the streak, its garland and the one primary action.
private struct StreakColumn: View {
    let streak: StreakCalendar
    let weeklyStreak: Int
    let feeling: ZenoFeeling

    var body: some View {
        let next = Milestone.next(after: weeklyStreak)
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            ZenoView(feeling).frame(width: 118)
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    Text("\(weeklyStreak)").font(ZenFont.number(54)).foregroundStyle(Ink.text)
                    Text(WeekCopy.weeksInARow).font(ZenFont.text(15, .semibold)).foregroundStyle(Ink.text)
                }
                Text(next.map { WeekCopy.nextMilestone($0 - weeklyStreak, $0) } ?? WeekCopy.pastAYear)
                    .font(ZenFont.text(12.5)).foregroundStyle(Ink.caption)
            }
            .accessibilityElement(children: .combine)
            MilestoneGarland(streak: weeklyStreak, target: next ?? weeklyStreak)
            Spacer(minLength: 0)
            ShareImageButton(fileName: "ZenMode OS weekly streak.png", make: { ImageExport.png(StreakShareImage(streak: streak)) }) {
                Label(WeekCopy.share, systemImage: "square.and.arrow.up")
                    .font(ZenFont.text(14, .semibold)).foregroundStyle(Ink.onGreen)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Capsule().fill(Ink.green))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(WeekCopy.shareHint)
        }
    }
}

/// The streak as marigold beads toward the next milestone: one bead a won week, the last won bead
/// deeper, the beads still to come as seeds.
struct MilestoneGarland: View {
    let streak: Int
    let target: Int
    var size: CGFloat = 13

    var body: some View {
        let total = max(target, streak)
        let shown = min(total, 13)
        let lit = min(streak, shown)
        HStack(spacing: size * 0.35) {
            ForEach(0..<shown, id: \.self) { i in
                Capsule()
                    .fill(i < lit
                          ? AnyShapeStyle(LinearGradient(colors: i == lit - 1 ? [Ink.marigold, Color(hex: 0xE2550F)] : [Ink.goldSoft, Ink.gold],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(width: size * 0.78, height: size * 1.12)
            }
            if total > shown {
                Text("+\(total - shown)").font(ZenFont.number(10)).foregroundStyle(Ink.mono)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) of \(target) weeks toward the next milestone")
    }
}

/// One day on ink: green for a good day (with its count toward four), the winning day ringed in
/// gold, today ringed in green, a day with no data an outline, days to come waiting.
struct InkDayTile: View {
    let name: String
    let score: ZenScore?
    var goodIndex: Int? = nil
    var isToday = false
    var isWinning = false
    var isFuture = false

    var body: some View {
        let good = score?.isGoodDay == true
        let shape = RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
        VStack(spacing: 5) {
            Text(name.uppercased()).font(ZenFont.number(9.5)).tracking(0.7)
                .foregroundStyle(good ? Ink.onGreen.opacity(0.75) : (isToday ? Ink.green : Ink.mono))
            Text(score?.text ?? (isFuture ? "·" : "–"))
                .font(ZenFont.number(21))
                .foregroundStyle(good ? Ink.onGreen : (isFuture ? Ink.mono : Ink.body))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(ZenFont.text(9.5, .medium))
                .foregroundStyle(good ? Ink.onGreen.opacity(0.7) : Ink.mono)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).frame(height: 84)
        .background(shape.fill(isWinning ? Ink.gold : (good ? Ink.fill : (isFuture ? Color.white.opacity(0.03) : (score == nil ? .clear : Ink.well)))))
        .overlay {
            shape.strokeBorder(isWinning ? Ink.goldSoft : (isToday ? Ink.green : (score == nil && !isFuture ? Ink.line : .clear)),
                               lineWidth: isWinning || isToday ? 2 : 1)
        }
        .shadow(color: isToday ? Ink.green.opacity(0.3) : (isWinning ? Ink.gold.opacity(0.3) : .clear), radius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(score.map { "\($0.text)\($0.isGoodDay ? ", a good day" : "")" } ?? (isFuture ? "not yet" : "no data"))\(isToday ? ", today" : "")\(isWinning ? ", won the week" : "")")
    }

    private var caption: String {
        if isWinning { return WeekCopy.wonIt }
        if let goodIndex { return "\(goodIndex) of 4" }
        if isFuture { return " " }
        if score == nil { return WeekCopy.noData }
        return WeekCopy.under6
    }
}

/// The weekly streak as a calendar of weeks: a row a week, Monday to Sunday, each day a cell. Good
/// days glow green, today brightest; a won week gets a gold mark at the end of its row.
struct StreakGrid: View {
    let streak: StreakCalendar
    var cell: CGFloat = 22
    var gap: CGFloat = 4

    var body: some View {
        let initials = ["M", "T", "W", "T", "F", "S", "S"]
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                Text("").frame(width: 30)
                ForEach(0..<7, id: \.self) { i in
                    Text(initials[i]).font(ZenFont.number(9)).foregroundStyle(Ink.mono).frame(width: cell)
                }
            }
            ForEach(Array(streak.weeks.enumerated()), id: \.element.id) { index, week in
                HStack(spacing: gap) {
                    Text(monthLabel(for: week, previous: index > 0 ? streak.weeks[index - 1] : nil))
                        .font(ZenFont.number(8.5)).foregroundStyle(Ink.mono).frame(width: 30, alignment: .leading)
                    ForEach(0..<7, id: \.self) { d in
                        cellView(week.days[d], isToday: week.isCurrent && d == week.days.lastIndex { $0 != nil })
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(week.isWon ? Ink.gold : .clear)
                        .frame(width: 4, height: cell - 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(week.id.formatted(.dateTime.month(.wide).day())): \(week.goodDays) good days\(week.isWon ? ", won" : "")")
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: DayRecord?, isToday: Bool) -> some View {
        let good = day?.score?.isGoodDay == true
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            if let day {
                shape
                    .fill(isToday ? Ink.green : (good ? Ink.fill.opacity(0.8) : (day.score == nil ? .clear : Ink.well)))
                    .overlay { if day.score == nil { shape.strokeBorder(Ink.line, lineWidth: 1) } }
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(ZenFont.number(8))
                    .foregroundStyle(isToday || good ? Ink.onGreen : Ink.mono)
            }
        }
        .frame(width: cell, height: cell)
    }

    private func monthLabel(for week: StreakCalendar.Week, previous: StreakCalendar.Week?) -> String {
        let month = Calendar.current.component(.month, from: week.id)
        if let previous, Calendar.current.component(.month, from: previous.id) == month { return "" }
        return week.id.formatted(.dateTime.month(.abbreviated)).uppercased()
    }
}

/// Ink with a green light low on the right and a faint gold one at the top left, as on the
/// shared streak card.
struct InkTable: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x141A12), Color(hex: 0x070907)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x2AA136, alpha: 0.24), .clear], center: UnitPoint(x: 0.78, y: 0.95), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0xFFC800, alpha: 0.09), .clear], center: UnitPoint(x: 0.04, y: 0.02), startRadius: 0, endRadius: 300)
        }
    }
}

/// The streak as a picture to share, as Flow 07's moment: proud Zeno, the number, the garland.
/// Scores only, never minutes or apps.
struct StreakShareImage: View {
    let streak: StreakCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("ZENMODE OS · THE WEEKLY STREAK").font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Ink.caption)
            ZenoStill(.proud).frame(width: 120)
            Text("\(streak.currentStreak)").font(ZenFont.number(120)).foregroundStyle(Ink.gold)
            Text("weeks in a row").font(ZenFont.brand(34)).foregroundStyle(Ink.text)
            MilestoneGarland(streak: streak.currentStreak, target: Milestone.next(after: streak.currentStreak) ?? streak.currentStreak, size: 22)
            Text("Four good days, every week.").font(ZenFont.text(16)).foregroundStyle(Ink.body)
            Spacer()
            Text("zenmodeos.com").font(ZenFont.number(12)).foregroundStyle(Ink.mono)
        }
        .padding(48)
        .frame(width: 540, height: 675, alignment: .topLeading)
        .background(InkTable())
    }
}
