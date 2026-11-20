import SwiftUI
import Albeit
import ZenAPI

/// The weekly streak as a calendar of weeks on ink: a row a week, Monday to Sunday, each day a cell.
/// Good days glow green, today brightest; a won week gets an amber mark at the end of its row.
struct StreakGridCard: View {
    let streak: StreakCalendar
    static let cell: CGFloat = 28
    static let gap: CGFloat = 5

    var body: some View {
        HStack(alignment: .top, spacing: ZenSpace.s6) {
            summary
            grid
        }
        .padding(ZenSpace.s6)
        .background(InkTable())
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 26, y: 16)
        .environment(\.colorScheme, .dark)
    }

    private var summary: some View {
        let today = Date()
        return VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Text(today.formatted(.dateTime.weekday(.abbreviated)) + " " + today.formatted(.dateTime.month(.abbreviated)))
                .font(ZenFont.brand(20)).foregroundStyle(Color(hex: 0x5BDF62))
            Text(today.formatted(.dateTime.day()))
                .font(ZenFont.number(64)).foregroundStyle(Color(hex: 0x5BDF62))
            Spacer().frame(height: ZenSpace.s4)
            Text("\(streak.currentStreak)-week streak").font(ZenFont.text(15, .semibold)).foregroundStyle(Color(hex: 0xF2F3EE))
            Text("Best \(streak.bestStreak) · \(streak.thisWeek?.goodDays ?? 0) of 4 this week")
                .font(ZenFont.text(12.5)).foregroundStyle(Color(hex: 0xA4A9A0))
            Spacer()
            legend
            ShareImageButton(fileName: "ZenMode OS weekly streak.png", make: { ImageExport.png(StreakShareImage(streak: streak)) }) {
                Text(WeekCopy.share)
                    .font(ZenFont.text(13, .semibold)).foregroundStyle(Color(hex: 0x0B2A0E))
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(Capsule().fill(Color(hex: 0x5BDF62)))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 128, alignment: .leading)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(Color(hex: 0x2AA136), "A good day")
            legendRow(Color(hex: 0x1F251F), "Under 6.0")
            legendRow(Color(hex: 0xFFC800), "A won week")
        }
        .padding(.bottom, ZenSpace.s3)
    }

    private func legendRow(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(text).font(ZenFont.text(11.5)).foregroundStyle(Color(hex: 0xA4A9A0))
        }
    }

    private var grid: some View {
        let initials = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                Text("").frame(width: 30)
                ForEach(0..<7, id: \.self) { i in
                    Text(initials[i]).font(ZenFont.number(9.5)).foregroundStyle(Color(hex: 0x858A81)).frame(width: Self.cell)
                }
            }
            ForEach(Array(streak.weeks.enumerated()), id: \.element.id) { index, week in
                HStack(spacing: Self.gap) {
                    Text(monthLabel(for: week, previous: index > 0 ? streak.weeks[index - 1] : nil))
                        .font(ZenFont.number(9)).foregroundStyle(Color(hex: 0x858A81)).frame(width: 30, alignment: .leading)
                    ForEach(0..<7, id: \.self) { d in cell(week.days[d], isToday: week.isCurrent && d == week.days.lastIndex { $0 != nil }) }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(week.isWon ? Color(hex: 0xFFC800) : .clear)
                        .frame(width: 4, height: Self.cell - 8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(week.id.formatted(.dateTime.month(.wide).day())): \(week.goodDays) good days\(week.isWon ? ", won" : "")")
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: DayRecord?, isToday: Bool) -> some View {
        let number = day.map { Calendar.current.component(.day, from: $0.date) }
        let good = day?.score?.isGoodDay == true
        ZStack {
            if let day {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isToday ? Color(hex: 0x5BDF62) : (good ? Color(hex: 0x2AA136).opacity(0.78) : (day.score == nil ? .clear : Color(hex: 0x1F251F))))
                    .overlay {
                        if day.score == nil {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(hex: 0x343A34), lineWidth: 1)
                        }
                    }
                    .shadow(color: isToday ? Color(hex: 0x5BDF62).opacity(0.6) : .clear, radius: 10)
                Text("\(number ?? 0)")
                    .font(ZenFont.number(9.5))
                    .foregroundStyle(isToday || good ? Color(hex: 0x0B2A0E) : Color(hex: 0x8E948B))
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

/// Ink with a green light under the grid and a faint amber one, like the shared streak card.
struct InkTable: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x12160F), Color(hex: 0x070907)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x2AA136, alpha: 0.22), .clear], center: UnitPoint(x: 0.7, y: 0.95), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(hex: 0xFFC800, alpha: 0.10), .clear], center: UnitPoint(x: 0.05, y: 0.05), startRadius: 0, endRadius: 260)
        }
    }
}

/// The streak as a picture to share: scores only, never minutes or apps.
struct StreakShareImage: View {
    let streak: StreakCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("ZENMODE OS · THE WEEKLY STREAK").font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Color(hex: 0xA4A9A0))
            Text("\(streak.currentStreak)").font(ZenFont.number(120)).foregroundStyle(Color(hex: 0xFFC800))
            Text("weeks in a row").font(ZenFont.brand(34)).foregroundStyle(Color(hex: 0xF2F3EE))
            Text("Four good days win the week.").font(ZenFont.text(16)).foregroundStyle(Color(hex: 0xC9CCC4))
            Spacer()
            HStack(spacing: 6) {
                ForEach(streak.weeks.suffix(12)) { week in
                    RoundedRectangle(cornerRadius: 4).fill(week.isWon ? Color(hex: 0xFFC800) : Color(hex: 0x2A2F26)).frame(width: 22, height: 30)
                }
            }
            Text("zenmodeos.com").font(ZenFont.number(12)).foregroundStyle(Color(hex: 0x858A81))
        }
        .padding(48)
        .frame(width: 540, height: 675, alignment: .topLeading)
        .background(InkTable())
    }
}
