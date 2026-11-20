import SwiftUI
import Albeit
import ZenAPI

/// The month as a marigold toran: a rope across the top, one string a week hanging from it, one
/// bead a day from Monday down. Good days are marigolds, today is lit, a won week ends in a tassel.
/// Never more than one month: at most five strings.
struct Toran: View {
    let weeks: [StreakCalendar.Week]

    var body: some View {
        let strings = Array(weeks.suffix(5))
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = w / CGFloat(max(strings.count, 1))
            let bead = min(step * 0.34, (h - 64) / 8.6)
            ZStack(alignment: .topLeading) {
                // The rope, sagging gently, with leaves where the strings tie on.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 14))
                    p.addQuadCurve(to: CGPoint(x: w, y: 14), control: CGPoint(x: w / 2, y: 34))
                }
                .stroke(Color(hex: 0x7A5A00).opacity(0.65), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ForEach(Array(strings.enumerated()), id: \.element.id) { i, week in
                    let x = step * (CGFloat(i) + 0.5)
                    let t = x / w
                    let top = 14 + 4 * 20 * t * (1 - t)
                    ToranString(week: week, bead: bead)
                        .frame(width: bead * 1.6)
                        .position(x: x, y: top + (bead * 8.6) / 2 + 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(strings: Array(weeks.suffix(5))))
    }

    static func summary(strings: [StreakCalendar.Week]) -> String {
        let won = strings.filter(\.isWon).count
        let good = strings.reduce(0) { $0 + $1.goodDays }
        return "This month as a garland: \(good) good days, \(won) won weeks."
    }
}

/// One week's string: a leaf at the knot, seven beads, and a tassel if the week was won.
private struct ToranString: View {
    let week: StreakCalendar.Week
    let bead: CGFloat

    var body: some View {
        VStack(spacing: bead * 0.18) {
            Leaf().fill(Color(hex: 0x2AA136)).frame(width: bead * 0.9, height: bead * 0.55)
            ForEach(0..<7, id: \.self) { d in
                let day = week.days[d]
                let isToday = week.isCurrent && d == week.days.lastIndex { $0 != nil }
                Marigold(state: state(day), lit: isToday)
                    .frame(width: bead, height: bead)
            }
            if week.isWon {
                Tassel().fill(LinearGradient(colors: [Color(hex: 0xFFC800), Color(hex: 0xFF8A00)], startPoint: .top, endPoint: .bottom))
                    .frame(width: bead * 0.8, height: bead * 1.1)
            }
        }
    }

    private func state(_ day: DayRecord?) -> Marigold.State {
        guard let day else { return .future }
        guard let score = day.score else { return .noData }
        return score.isGoodDay ? .good : .under
    }
}

/// A bead: a marigold for a good day, a plain seed for a day under 6.0, a ring for no data.
struct Marigold: View {
    enum State { case good, under, noData, future }
    let state: State
    var lit = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            switch state {
            case .good:
                // Two rings of petals, the outer a shade deeper, then the seed head.
                for (count, length, width, color) in [(10, r * 0.98, r * 0.42, Color(hex: 0xFF9A1F)), (8, r * 0.7, r * 0.38, Color(hex: 0xFFC83D))] {
                    for k in 0..<count {
                        var petal = ctx
                        petal.translateBy(x: c.x, y: c.y)
                        petal.rotate(by: .degrees(Double(k) * 360 / Double(count) + (count == 8 ? 22.5 : 0)))
                        petal.fill(Path(ellipseIn: CGRect(x: -width / 2, y: -length, width: width, height: length)), with: .color(color))
                    }
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)), with: .color(Color(hex: 0xB45A00)))
            case .under:
                let k = r * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - k, y: c.y - k, width: k * 2, height: k * 2)),
                         with: .color(scheme == .dark ? Color.white.opacity(0.22) : Color(hex: 0x12160F, alpha: 0.18)))
            case .noData:
                let k = r * 0.55
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - k, y: c.y - k, width: k * 2, height: k * 2)),
                           with: .color(scheme == .dark ? Color.white.opacity(0.3) : Color(hex: 0xC9C7BD)), lineWidth: 1.2)
            case .future:
                let k = r * 0.3
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - k, y: c.y - k, width: k * 2, height: k * 2)),
                         with: .color(scheme == .dark ? Color.white.opacity(0.08) : Color(hex: 0x12160F, alpha: 0.06)))
            }
        }
        // Today glows softly, past the bead's own bounds.
        .background {
            if lit { Circle().fill(Color(hex: 0xFFC800, alpha: 0.5)).blur(radius: 7).scaleEffect(1.7) }
        }
    }
}

private struct Leaf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.4))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.4))
        return p
    }
}

private struct Tassel: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.18, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.18, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.midX, y: r.maxY - r.height * 0.18))
        p.closeSubpath()
        return p
    }
}
