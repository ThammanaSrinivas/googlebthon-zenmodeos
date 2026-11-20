import SwiftUI
import Albeit
import ZenAPI

/// The usual stats: four numbers to skim, for the day picked on the left.
struct UsualStatsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var dash = model.dashboard
        let day = dash.day
        let week = model.snapshot?.week ?? FakeSnapshot.value.week

        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s5) {
                DayPicker(days: dash.days, selection: $dash.dayIndex)
                FeelLegend()
                Spacer(minLength: 0)
                if model.isDemo { DemoTag() }
            }
            HStack(alignment: .top, spacing: ZenSpace.s3) {
                scoreTile(day, dash: dash)
                screensTile(day)
                purposeTile(day)
                weekTile(week)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s4)
        .glassCard(radius: ZenRadius.widget)
    }

    private func scoreTile(_ day: DayInsight, dash: DashboardModel) -> some View {
        StatTile(eyebrow: "Zen Score · every screen") {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                ScoreText(day.score.text, size: 38)
                DeltaText(tenths: day.delta)
            }
            Sparkline(scores: dash.lastSeven, highlight: dash.lastSeven.count - 1 - dash.dayIndex)
                .frame(height: 24)
            Text("Last 7 days · a good day is above 6.0").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    private func screensTile(_ day: DayInsight) -> some View {
        StatTile(eyebrow: "By screen") {
            VStack(spacing: ZenSpace.s2) {
                ForEach(day.screens) { ScreenLine(screen: $0) }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            Text("Your score is the lower of the two").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    private func purposeTile(_ day: DayInsight) -> some View {
        let percent = Int((day.onPurpose * 100).rounded())
        return StatTile(eyebrow: "On purpose · this Mac") {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(percent)").font(ZenFont.number(38)).foregroundStyle(Color.zen.textHeading)
                Text("%").font(ZenFont.number(16)).foregroundStyle(Color.zen.textCaption)
            }
            FeelBar(day: day).frame(height: 8).padding(.vertical, 8)
            Text("\(durationText(day.minutes(.unintentional))) unintentional, of \(durationText(day.minutes))")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    private func weekTile(_ week: WeekProgress) -> some View {
        StatTile(eyebrow: "This week") {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                Text("\(week.goodDays)").font(ZenFont.number(38)).foregroundStyle(Color.zen.textHeading)
                Text("of \(WeekProgress.goodDaysToWin) good days").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            WeekDots(week: week).padding(.vertical, 6)
            Text(Self.streakLine(week)).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    /// "9-week streak · one more wins it". Never a daily streak.
    static func streakLine(_ week: WeekProgress) -> String {
        if week.isWon { return "Week won · \(week.weeklyStreak)-week streak" }
        let left = WeekProgress.goodDaysToWin - week.goodDays
        return "\(week.streakBefore)-week streak · " + (left == 1 ? "one more wins it" : "\(left) more win it")
    }
}

/// One screen's row: a Mac shows its minutes, an iPhone its score only (its minutes stay on it).
private struct ScreenLine: View {
    let screen: ScreenDay

    var body: some View {
        HStack(spacing: ZenSpace.s2) {
            Image(systemName: screen.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.zen.textHeading)
                .frame(width: 18)
            Text(screen.name).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
            Spacer(minLength: ZenSpace.s1)
            if screen.isSealed {
                Label("score only", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon).font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                    .imageScale(.small)
                    .help("Only the Zen Score leaves your iPhone. Its minutes and apps stay on it.")
            } else {
                Text(durationText(screen.minutes)).font(ZenFont.number(12.5)).foregroundStyle(Color.zen.textBody)
            }
            Text(screen.score.text)
                .font(ZenFont.number(12.5))
                .foregroundStyle(screen.score.isGoodDay ? Color.zen.textBrand : Color.zen.textHeading)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(screen.score.isGoodDay ? Color.zen.surfaceTint : Color.zen.surfaceSunk))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Mac's minutes as one bar, split by how they felt.
struct FeelBar: View {
    let day: DayInsight

    var body: some View {
        GeometryReader { geo in
            let total = max(day.minutes, 1)
            let parts = Feel.allCases.map { ($0, day.minutes($0)) }.filter { $0.1 > 0 }
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(parts, id: \.0) { feel, m in
                    RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous).fill(feel.color)
                        .frame(width: max(2, usable * CGFloat(m) / CGFloat(total)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Seven days as cells: green for a good day, grey for a day under 6.0, an outline for no data yet.
struct WeekDots: View {
    let week: WeekProgress
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { d in
                let day = week.days[d]
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                        .fill(day.map { $0.isGoodDay ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.16) } ?? Color.zen.textHeading.opacity(0.03))
                        .overlay {
                            if day == nil {
                                RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous).strokeBorder(Color.zen.borderOutline, lineWidth: 1)
                            }
                        }
                        .overlay {
                            if d == week.todayIndex {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.zen.textHeading.opacity(0.7), lineWidth: 1.2)
                                    .padding(-3)
                            }
                        }
                        .frame(width: 14, height: 14)
                    Text(letters[d]).font(ZenFont.number(8.5))
                        .foregroundStyle(d == week.todayIndex ? Color.zen.textHeading : Color.zen.textCaption)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Seven scores as a line, with the good-day line at 6.0 and the picked day ringed.
struct Sparkline: View {
    let scores: [ZenScore]
    let highlight: Int

    var body: some View {
        Canvas { ctx, size in
            guard scores.count > 1 else { return }
            let lo = 3.0, hi = 10.0
            func y(_ tenths: Int) -> CGFloat { size.height - 3 - (CGFloat(Double(tenths) / 10 - lo) / CGFloat(hi - lo)) * (size.height - 6) }
            func x(_ i: Int) -> CGFloat { 4 + CGFloat(i) / CGFloat(scores.count - 1) * (size.width - 8) }

            var bar = Path()
            bar.move(to: CGPoint(x: 0, y: y(60)))
            bar.addLine(to: CGPoint(x: size.width, y: y(60)))
            ctx.stroke(bar, with: .color(Color.zen.textBrand.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            var line = Path()
            for (i, s) in scores.enumerated() {
                let p = CGPoint(x: x(i), y: y(s.tenths))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(Color.zen.textHeading.opacity(0.4)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

            for (i, s) in scores.enumerated() {
                let p = CGPoint(x: x(i), y: y(s.tenths))
                let r: CGFloat = i == highlight ? 3.6 : 2.2
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(s.isGoodDay ? Color.zen.brandFill : Color.zen.textCaption))
                if i == highlight {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
                               with: .color(Color.zen.textHeading.opacity(0.5)), lineWidth: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
