import SwiftUI
import Albeit
import ZenAPI

/// The ink palette for the dark cards (the hero, the recap covers, the share images). They're dark
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
}

/// The week's hero, as on the iPad: ink, "Four good days / wins the week." with the second line in
/// gold, this week's seven days big enough to read across the room, the streak, the one primary
/// action, and the streak itself as a calendar of weeks on the right.
struct WeekHero: View {
    let week: WeekProgress
    let streak: StreakCalendar

    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        HStack(alignment: .top, spacing: ZenSpace.s10) {
            story
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated)) + " " + Date.now.formatted(.dateTime.month(.abbreviated)))
                        .font(ZenFont.brand(20)).foregroundStyle(Ink.green)
                    Text(Date.now.formatted(.dateTime.day())).font(ZenFont.number(20)).foregroundStyle(Ink.green)
                    Spacer()
                    Text(WeekCopy.twelveWeeks.uppercased()).font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(Ink.mono)
                }
                StreakGrid(streak: streak)
                legend
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(ZenSpace.s8)
        .background(InkTable())
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
    }

    private var story: some View {
        let weeklyStreak = week.weeklyStreak
        return VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack(spacing: ZenSpace.s3) {
                CellRow((0..<4).map { $0 < week.goodDays ? (week.isWon ? .reward : .on) : .empty }, size: 8, onColor: Ink.green)
                Text(WeekCopy.eyebrow.uppercased()).font(ZenFont.number(10.5)).tracking(1.05).foregroundStyle(Ink.caption)
                DemoTag(WeekCopy.demoHistory)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(WeekCopy.titleTop).foregroundStyle(Ink.text)
                Text(WeekCopy.titleBottom)
                    .foregroundStyle(LinearGradient(colors: [Ink.goldSoft, Ink.gold], startPoint: .leading, endPoint: .trailing))
            }
            .font(ZenFont.brand(46)).tracking(-1.5)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(WeekCopy.lede).font(ZenFont.text(15)).lineSpacing(5).foregroundStyle(Ink.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ZenSpace.s2) {
                ForEach(0..<7, id: \.self) { i in
                    InkDayTile(name: names[i], score: week.days[i], isToday: i == week.todayIndex,
                               isWinning: week.winningDayIndex == i, isFuture: week.todayIndex.map { i > $0 } ?? false)
                }
            }
            Text(week.statusLine).font(ZenFont.text(15, .semibold)).foregroundStyle(week.isWon ? Ink.goldSoft : Ink.text)
            HStack(alignment: .bottom, spacing: ZenSpace.s4) {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    Text("\(weeklyStreak)").font(ZenFont.number(44)).foregroundStyle(Ink.text)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WeekCopy.weekStreak).font(ZenFont.text(14, .semibold)).foregroundStyle(Ink.text)
                        Text(WeekCopy.best(max(streak.bestStreak, weeklyStreak), canMake: week.isWon ? nil : weeklyStreak + 1))
                            .font(ZenFont.text(12)).foregroundStyle(Ink.caption)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: ZenSpace.s4)
                ShareImageButton(fileName: "ZenMode OS weekly streak.png", make: { ImageExport.png(StreakShareImage(streak: streak)) }) {
                    Label(WeekCopy.share, systemImage: "square.and.arrow.up")
                        .font(ZenFont.text(14, .semibold)).foregroundStyle(Ink.onGreen)
                        .padding(.horizontal, ZenSpace.s5).frame(height: 40)
                        .background(Capsule().fill(Ink.green))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(WeekCopy.shareHint)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: ZenSpace.s4) {
            legendItem(Ink.fill, WeekCopy.legendGood)
            legendItem(Ink.well, WeekCopy.legendUnder)
            legendItem(Ink.gold, WeekCopy.legendWon)
        }
        .padding(.top, ZenSpace.s1)
    }

    private func legendItem(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(c)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Ink.line, lineWidth: 1))
                .frame(width: 9, height: 9)
            Text(text).font(ZenFont.text(11)).foregroundStyle(Ink.caption)
        }
    }
}

/// One day on ink: green for a good day, the winning day ringed in gold, today ringed in green,
/// a day with no data an outline, days to come waiting.
struct InkDayTile: View {
    let name: String
    let score: ZenScore?
    var isToday = false
    var isWinning = false
    var isFuture = false

    var body: some View {
        let good = score?.isGoodDay == true
        let shape = RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
        VStack(spacing: 6) {
            Text(name.uppercased()).font(ZenFont.number(9.5)).tracking(0.7)
                .foregroundStyle(good ? Ink.onGreen.opacity(0.75) : (isToday ? Ink.green : Ink.mono))
            Text(score?.text ?? (isFuture ? "·" : "–"))
                .font(ZenFont.number(21))
                .foregroundStyle(good ? Ink.onGreen : (isFuture ? Ink.mono : Ink.body))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).frame(height: 72)
        .background(shape.fill(good ? Ink.fill : (isFuture ? Color.white.opacity(0.03) : (score == nil ? .clear : Ink.well))))
        .overlay {
            shape.strokeBorder(isWinning ? Ink.gold : (isToday ? Ink.green : (score == nil && !isFuture ? Ink.line : .clear)),
                               lineWidth: isWinning || isToday ? 2 : 1)
        }
        .shadow(color: isToday ? Ink.green.opacity(0.35) : .clear, radius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(score.map { "\($0.text)\($0.isGoodDay ? ", a good day" : "")" } ?? (isFuture ? "not yet" : "no data"))\(isToday ? ", today" : "")")
    }
}

/// The weekly streak as a calendar of weeks: a row a week, Monday to Sunday, each day a cell. Good
/// days glow green, today brightest; a won week gets a gold mark at the end of its row.
struct StreakGrid: View {
    let streak: StreakCalendar
    static let cell: CGFloat = 26
    static let gap: CGFloat = 5

    var body: some View {
        let initials = ["M", "T", "W", "T", "F", "S", "S"]
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                Text("").frame(width: 30)
                ForEach(0..<7, id: \.self) { i in
                    Text(initials[i]).font(ZenFont.number(9.5)).foregroundStyle(Ink.mono).frame(width: Self.cell)
                }
            }
            ForEach(Array(streak.weeks.enumerated()), id: \.element.id) { index, week in
                HStack(spacing: Self.gap) {
                    Text(monthLabel(for: week, previous: index > 0 ? streak.weeks[index - 1] : nil))
                        .font(ZenFont.number(9)).foregroundStyle(Ink.mono).frame(width: 30, alignment: .leading)
                    ForEach(0..<7, id: \.self) { d in
                        cell(week.days[d], isToday: week.isCurrent && d == week.days.lastIndex { $0 != nil })
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(week.isWon ? Ink.gold : .clear)
                        .frame(width: 4, height: Self.cell - 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(week.id.formatted(.dateTime.month(.wide).day())): \(week.goodDays) good days\(week.isWon ? ", won" : "")")
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: DayRecord?, isToday: Bool) -> some View {
        let good = day?.score?.isGoodDay == true
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            if let day {
                shape
                    .fill(isToday ? Ink.green : (good ? Ink.fill.opacity(0.8) : (day.score == nil ? .clear : Ink.well)))
                    .overlay { if day.score == nil { shape.strokeBorder(Ink.line, lineWidth: 1) } }
                    .shadow(color: isToday ? Ink.green.opacity(0.6) : .clear, radius: 10)
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(ZenFont.number(9))
                    .foregroundStyle(isToday || good ? Ink.onGreen : Ink.mono)
            }
        }
        .frame(width: Self.cell, height: Self.cell)
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

/// The streak as a picture to share: scores only, never minutes or apps.
struct StreakShareImage: View {
    let streak: StreakCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("ZENMODE OS · THE WEEKLY STREAK").font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Ink.caption)
            Text("\(streak.currentStreak)").font(ZenFont.number(120)).foregroundStyle(Ink.gold)
            Text("weeks in a row").font(ZenFont.brand(34)).foregroundStyle(Ink.text)
            Text("Four good days win the week.").font(ZenFont.text(16)).foregroundStyle(Ink.body)
            Spacer()
            HStack(spacing: 6) {
                ForEach(streak.weeks.suffix(12)) { week in
                    RoundedRectangle(cornerRadius: 4).fill(week.isWon ? Ink.gold : Color(hex: 0x2A2F26)).frame(width: 22, height: 30)
                }
            }
            Text("zenmodeos.com").font(ZenFont.number(12)).foregroundStyle(Ink.mono)
        }
        .padding(48)
        .frame(width: 540, height: 675, alignment: .topLeading)
        .background(InkTable())
    }
}
