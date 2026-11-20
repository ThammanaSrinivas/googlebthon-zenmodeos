import SwiftUI
import Albeit
import ZenAPI

/// A week drawn as light, from its own scores: a ribbon through the seven days over the 6.0 line,
/// a pillar of light under every good day (amber under the one that won it), and the glow of the
/// calmest day behind it all. No two weeks look alike, and the picture is the data: the higher a
/// day sits, the better it went. Paper and green by day, a lit night in dark mode.
struct WeekLight: View {
    let days: [ZenScore?]
    var wonOn: Int? = nil
    /// The last day lived in a week still running; days after it aren't drawn. nil for a finished week.
    var lastDay: Int? = nil
    /// Shapes the far glow, so even two weeks with the same scores sit in different light.
    var seed: Int = 0
    /// Letters the days along the foot (M T W …), for the larger panels.
    var showsDays = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = WeekLightInk(dark: scheme == .dark)
        Canvas { ctx, size in
            let plot = WeekLightPlot(size: size, showsDays: showsDays)
            drawSky(&ctx, size: size, ink: ink)
            drawGlows(&ctx, size: size, plot: plot, ink: ink)
            drawThreshold(&ctx, size: size, plot: plot, ink: ink)
            drawPillars(&ctx, size: size, plot: plot, ink: ink)
            drawRibbon(&ctx, size: size, plot: plot, ink: ink)
            drawNodes(&ctx, plot: plot, ink: ink)
            if showsDays { drawDayLetters(&ctx, size: size, plot: plot, ink: ink) }
        }
        .accessibilityHidden(true)
    }

    private var lived: Range<Int> { 0..<min(7, (lastDay ?? 6) + 1) }

    private var points: [(Int, ZenScore)] {
        lived.compactMap { i in days.indices.contains(i) ? days[i].map { (i, $0) } : nil }
    }

    // MARK: Layers

    private func drawSky(_ ctx: inout GraphicsContext, size: CGSize, ink: WeekLightInk) {
        let rect = CGRect(origin: .zero, size: size)
        // A week still running, or won, sits in green light; one that ended short, at dusk.
        let green = wonOn != nil || lastDay != nil
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: green ? ink.skyWon : ink.skyShort),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.35, y: size.height)))
        // A few stars on a night sky, set by the seed.
        if ink.dark {
            var s = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 977)
            for _ in 0..<14 {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(s >> 40 & 0xFFFF) / 65535 * size.width
                let y = CGFloat(s >> 20 & 0xFFFF) / 65535 * size.height * 0.45
                let r = 0.5 + CGFloat(s & 0x3) * 0.35
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.28)))
            }
        }
    }

    private func drawGlows(_ ctx: inout GraphicsContext, size: CGSize, plot: WeekLightPlot, ink: WeekLightInk) {
        let w = size.width, h = size.height
        // The far glow drifts with the seed.
        let drift = CGFloat((seed * 37) % 11) / 11
        radial(&ctx, at: CGPoint(x: w * (0.15 + 0.7 * drift), y: h * 0.05), radius: w * 0.75, color: ink.mint, alpha: ink.dark ? 0.16 : 0.34)
        // The calmest day lights the sky above it.
        if let best = points.max(by: { $0.1 < $1.1 }) {
            radial(&ctx, at: plot.point(best.0, best.1), radius: max(w, h) * 0.62, color: ink.green, alpha: ink.dark ? 0.3 : 0.48)
        }
        if let wonOn, days.indices.contains(wonOn), let s = days[wonOn] {
            radial(&ctx, at: plot.point(wonOn, s), radius: max(w, h) * 0.42, color: ink.amber, alpha: ink.dark ? 0.34 : 0.46)
        }
    }

    private func drawThreshold(_ ctx: inout GraphicsContext, size: CGSize, plot: WeekLightPlot, ink: WeekLightInk) {
        var line = Path()
        let y = plot.y(60)
        line.move(to: CGPoint(x: plot.rect.minX - plot.step * 0.3, y: y))
        line.addLine(to: CGPoint(x: plot.rect.maxX + plot.step * 0.3, y: y))
        ctx.stroke(line, with: .color(ink.line), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }

    private func drawPillars(_ ctx: inout GraphicsContext, size: CGSize, plot: WeekLightPlot, ink: WeekLightInk) {
        for (i, s) in points where s.isGoodDay {
            let p = plot.point(i, s)
            let width = plot.step * 0.62
            let rect = CGRect(x: p.x - width / 2, y: p.y, width: width, height: size.height - p.y)
            let color = i == wonOn ? ink.amber : ink.green
            ctx.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .linearGradient(
                Gradient(colors: [color.opacity(ink.dark ? 0.42 : 0.58), color.opacity(0)]),
                startPoint: CGPoint(x: p.x, y: p.y), endPoint: CGPoint(x: p.x, y: size.height)))
        }
    }

    private func drawRibbon(_ ctx: inout GraphicsContext, size: CGSize, plot: WeekLightPlot, ink: WeekLightInk) {
        let pts = points.map { plot.point($0.0, $0.1) }
        guard pts.count > 1 else { return }
        let curve = Self.smooth(pts)
        // Echoes of the ribbon fall away beneath it, like contour lines: the week's own pattern.
        for k in 1...plot.echoes {
            let fade = 1 - Double(k) / Double(plot.echoes + 1)
            ctx.stroke(curve.offsetBy(dx: 0, dy: plot.echoGap * CGFloat(k)),
                       with: .color(ink.green.opacity((ink.dark ? 0.34 : 0.4) * fade)), lineWidth: 1)
        }
        var area = curve
        area.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
        area.addLine(to: CGPoint(x: pts.first!.x, y: size.height))
        area.closeSubpath()
        let top = pts.map(\.y).min() ?? 0
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [ink.green.opacity(ink.dark ? 0.3 : 0.26), ink.green.opacity(0)]),
            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
        // A wide soft stroke under a crisp one: the ribbon glows.
        ctx.stroke(curve, with: .color(ink.green.opacity(ink.dark ? 0.35 : 0.25)), style: StrokeStyle(lineWidth: plot.stroke * 4, lineCap: .round, lineJoin: .round))
        ctx.stroke(curve, with: .color(ink.ribbon), style: StrokeStyle(lineWidth: plot.stroke, lineCap: .round, lineJoin: .round))
    }

    private func drawNodes(_ ctx: inout GraphicsContext, plot: WeekLightPlot, ink: WeekLightInk) {
        let r = plot.node
        for i in lived {
            guard let s = days.indices.contains(i) ? days[i] : nil else {
                // A day with no data: a faint ring on the 6.0 line, not a zero.
                let c = CGPoint(x: plot.x(i), y: plot.y(60))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.8, width: r * 1.6, height: r * 1.6)),
                           with: .color(ink.line), lineWidth: 1)
                continue
            }
            let c = plot.point(i, s)
            let dot = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if i == wonOn {
                radial(&ctx, at: c, radius: r * 5, color: ink.amber, alpha: 0.7)
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: -r * 0.35, dy: -r * 0.35)), with: .color(ink.amberRing))
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: r * 0.05, dy: r * 0.05)), with: .color(ink.amber))
            } else if s.isGoodDay {
                radial(&ctx, at: c, radius: r * 3.6, color: ink.green, alpha: 0.55)
                ctx.fill(Path(ellipseIn: dot), with: .color(ink.ribbon))
                ctx.fill(Path(ellipseIn: dot.insetBy(dx: r * 0.55, dy: r * 0.55)), with: .color(ink.core))
            } else {
                ctx.fill(Path(ellipseIn: dot), with: .color(ink.hollow))
                ctx.stroke(Path(ellipseIn: dot.insetBy(dx: 0.75, dy: 0.75)), with: .color(ink.under), lineWidth: 1.5)
            }
        }
    }

    private func drawDayLetters(_ ctx: inout GraphicsContext, size: CGSize, plot: WeekLightPlot, ink: WeekLightInk) {
        for i in 0..<7 {
            let letter = String(RecapBook.shortNames[i].prefix(1))
            ctx.draw(Text(letter).font(ZenFont.number(10)).foregroundStyle(i == wonOn ? ink.amberText : ink.caption),
                     at: CGPoint(x: plot.x(i), y: size.height - plot.footer / 2), anchor: .center)
        }
    }

    private func radial(_ ctx: inout GraphicsContext, at c: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(alpha), color.opacity(0)]), center: c, startRadius: 0, endRadius: radius))
    }

    /// A Catmull-Rom curve through the points, as cubic Béziers: smooth, and it passes through every day.
    static func smooth(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

/// Where each day sits: seven even columns, a score from 3.5 (low) to 9.5 (high).
private struct WeekLightPlot {
    let rect: CGRect
    let step: CGFloat
    let footer: CGFloat
    let node: CGFloat
    let stroke: CGFloat
    let echoes: Int
    let echoGap: CGFloat

    init(size: CGSize, showsDays: Bool) {
        footer = showsDays ? 30 : 0
        let side = size.width * 0.06
        let top = size.height * 0.24
        let bottom = size.height * 0.2 + footer
        rect = CGRect(x: side, y: top, width: size.width - side * 2, height: max(1, size.height - top - bottom))
        step = rect.width / 7
        node = max(3.2, min(6, size.width * 0.016))
        stroke = max(1.8, min(3, size.width * 0.008))
        echoes = size.height > 200 ? 7 : 4
        echoGap = max(5, rect.height * (size.height > 200 ? 0.075 : 0.13))
    }

    func x(_ day: Int) -> CGFloat { rect.minX + step * (CGFloat(day) + 0.5) }
    func y(_ tenths: Int) -> CGFloat {
        let t = (CGFloat(min(max(tenths, 35), 95)) - 35) / 60
        return rect.maxY - rect.height * t
    }
    func point(_ day: Int, _ score: ZenScore) -> CGPoint { CGPoint(x: x(day), y: y(score.tenths)) }
}

/// The light's colours, by day and by night. Named here because the art is its own small world;
/// the greens and the amber are Albeit's brand and reward hues.
private struct WeekLightInk {
    let dark: Bool

    var skyWon: [Color] { dark ? [Color(hex: 0x0E2212), Color(hex: 0x0A0F0B)] : [Color(hex: 0xCFEBC6), Color(hex: 0xFBF5E3)] }
    var skyShort: [Color] { dark ? [Color(hex: 0x14131D), Color(hex: 0x0B0D0C)] : [Color(hex: 0xE6E4EE), Color(hex: 0xF6F4EE)] }
    var green: Color { Color(hex: dark ? 0x5BDF62 : 0x2AA136) }
    var mint: Color { Color(hex: dark ? 0x3FBF8C : 0x9BE3A4) }
    var amber: Color { Color(hex: 0xFFC800) }
    var amberRing: Color { Color(hex: dark ? 0xFFE58A : 0xB45A00) }
    var amberText: Color { Color(hex: dark ? 0xFFD86B : 0x7A5A00) }
    var ribbon: Color { Color(hex: dark ? 0x5BDF62 : 0x1E8A2A) }
    var core: Color { Color(hex: dark ? 0x0B2A0E : 0xF2FFF0) }
    var hollow: Color { Color(hex: dark ? 0x0E130F : 0xFBFAF5) }
    var under: Color { Color(hex: dark ? 0xA4A9A0 : 0x5C6158) }
    var line: Color { (dark ? Color.white : Color(hex: 0x12160F)).opacity(dark ? 0.22 : 0.2) }
    var caption: Color { Color(hex: dark ? 0xA4A9A0 : 0x5C6158) }
}
