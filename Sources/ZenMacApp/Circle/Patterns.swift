import SwiftUI
import Albeit

/// A month as 720 hours (30 days × 24), each hour one of four feels. Every pattern draws from this.
struct MonthHours: Sendable {
    enum Feel: UInt8, Sendable { case rest, focus, intentional, unplanned }

    /// `cells[day * 24 + hour]`
    let cells: [Feel]
    /// The hour of the day the month was most mindful, and the day it shone brightest.
    let mindfulHour: Int
    let mindfulDay: Int

    func feel(day: Int, hour: Int) -> Feel { cells[day * 24 + hour] }

    var focusHours: Int { cells.filter { $0 == .focus }.count }
    var unplannedHours: Int { cells.filter { $0 == .unplanned }.count }
}

/// The four kinds of month a circle tends to have. Aggregates of 5 or more people each.
enum Archetype: String, CaseIterable, Identifiable, Sendable {
    case morning, nightOwl, weekender, deepWorker

    var id: String { rawValue }

    var name: String {
        switch self {
        case .morning: "Morning person"
        case .nightOwl: "Night owl"
        case .weekender: "Weekender"
        case .deepWorker: "Deep worker"
        }
    }

    var line: String {
        switch self {
        case .morning: "Up with the light, phone down by lunch. Calm weekdays."
        case .nightOwl: "The day starts late and so does the screen. Midnight is the hard part."
        case .weekender: "Tight weekdays. Saturdays are where the minutes go."
        case .deepWorker: "Long afternoon sessions, phone face down. The 3 PM block is sacred."
        }
    }

    var mindfulHour: Int {
        switch self {
        case .morning: 7
        case .nightOwl: 22
        case .weekender: 11
        case .deepWorker: 14
        }
    }

    /// A month in this shape, the same every time for the same seed.
    func month(seed: UInt64) -> MonthHours {
        var s = seed &+ UInt64(mindfulHour) &* 7919
        func rand() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 11) / Double(1 << 53)
        }
        var cells: [MonthHours.Feel] = []
        cells.reserveCapacity(720)
        for day in 0..<30 {
            let weekend = day % 7 >= 5
            for hour in 0..<24 {
                let (active, focus, unplanned) = mix(hour: hour, weekend: weekend)
                if rand() > active { cells.append(.rest); continue }
                let r = rand()
                cells.append(r < focus ? .focus : (r < focus + unplanned ? .unplanned : .intentional))
            }
        }
        return MonthHours(cells: cells, mindfulHour: mindfulHour, mindfulDay: 17)
    }

    /// For an hour: how likely a screen is on, and of that, how much is focus and how much unplanned.
    private func mix(hour h: Int, weekend: Bool) -> (Double, Double, Double) {
        switch self {
        case .morning:
            if h < 6 || h >= 22 { return (0.03, 0.1, 0.4) }
            if h < 12 { return (0.85, 0.55, 0.06) }
            if h < 18 { return (0.6, 0.3, 0.2) }
            return (0.35, 0.1, 0.35)
        case .nightOwl:
            if h >= 3 && h < 9 { return (0.03, 0.1, 0.4) }
            if h < 3 { return (0.7, 0.1, 0.55) }
            if h < 14 { return (0.4, 0.25, 0.2) }
            if h < 21 { return (0.7, 0.35, 0.2) }
            return (0.9, 0.2, 0.42)
        case .weekender:
            if h < 7 || h >= 23 { return (0.04, 0.1, 0.4) }
            if weekend { return (0.85, 0.08, 0.6) }
            if h < 18 { return (0.7, 0.4, 0.1) }
            return (0.5, 0.1, 0.3)
        case .deepWorker:
            if h < 7 || h >= 23 { return (0.03, 0.1, 0.4) }
            if h >= 13 && h < 18 { return (0.92, 0.75, 0.04) }
            if h < 13 { return (0.6, 0.35, 0.12) }
            return (0.45, 0.15, 0.3)
        }
    }
}

/// The pattern family (Albeit §16).
enum PatternKind: String, CaseIterable, Identifiable, Sendable {
    case bloom = "Bloom", kolam = "Kolam", garland = "Garland", horizon = "Horizon"

    var id: String { rawValue }

    var legend: String {
        switch self {
        case .bloom: "Bloom · every seed is one hour of the month. Midnight sits at the heart and the evening at the rim, so each ring is one hour of the day across thirty days."
        case .kolam: "Kolam · the month as a dot lattice, a day to a row. Lit dots are hours on a screen; quiet dots are the phone at rest."
        case .garland: "Garland · thirty strands hang from the toran, one a day. Each bead is an hour on a screen, from morning at the top to night at the end."
        case .horizon: "Horizon · the month as a landscape: days run left to right and the hours of the day rise from midnight at the ground."
        }
    }
}

/// The colours of how time felt, the same on every pattern: gold focus, green on purpose,
/// rust unplanned, dark seeds the phone at rest.
enum FeelPalette {
    static func color(_ feel: MonthHours.Feel, variant: Double) -> Color {
        switch feel {
        case .focus: variant < 0.5 ? Color(hex: 0xFFC800) : Color(hex: 0xE2B000)
        case .intentional: variant < 0.33 ? Color(hex: 0x5BDF62) : (variant < 0.66 ? Color(hex: 0x3FBF49) : Color(hex: 0x2AA136))
        case .unplanned: variant < 0.5 ? Color(hex: 0xD9541E) : Color(hex: 0xFF8A3D)
        case .rest: variant < 0.5 ? Color(hex: 0x2A3328) : Color(hex: 0x343E31)
        }
    }

    static func variant(_ day: Int, _ hour: Int) -> Double {
        let x = sin(Double(day * 31 + hour * 17) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}

/// Draws a month in any of the four patterns on an ink tile, with the most mindful hour lit.
struct PatternTile: View {
    let month: MonthHours
    let kind: PatternKind

    var body: some View {
        Canvas { ctx, size in
            switch kind {
            case .bloom: drawBloom(&ctx, size)
            case .kolam: drawKolam(&ctx, size)
            case .garland: drawGarland(&ctx, size)
            case .horizon: drawHorizon(&ctx, size)
            }
        }
        .background {
            ZStack {
                Color(hex: 0x0C130C)
                RadialGradient(colors: [Color(hex: 0x1D3A1F), .clear], center: .center, startRadius: 0, endRadius: 220)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .accessibilityHidden(true)
    }

    private func lit(_ ctx: inout GraphicsContext, at p: CGPoint, size s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 4, y: p.y - s * 4, width: s * 8, height: s * 8)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xE8FFE8, alpha: 0.55), .clear]), center: p, startRadius: 0, endRadius: s * 4))
        ctx.fill(Path(roundedRect: CGRect(x: p.x - s * 0.75, y: p.y - s * 0.75, width: s * 1.5, height: s * 1.5), cornerRadius: s * 0.3),
                 with: .color(Color(hex: 0xF2FFF0)))
    }

    /// A sunflower of 720 seeds, an hour each, laid in hour order: midnight at the heart, the evening
    /// at the rim, so each band is one hour of the day across thirty days. Seeds sit 137.5° apart.
    private func drawBloom(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let rMax = min(size.width, size.height) * 0.46
        let k = rMax / sqrt(720 + 12)
        let seed = k * 1.5
        let golden = 137.508 * Double.pi / 180
        var litPoint = c
        for hour in 0..<24 {
            for day in 0..<30 {
                let n = Double(hour * 30 + day + 12)
                let r = k * sqrt(n), a = n * golden
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                let feel = month.feel(day: day, hour: hour)
                var s = ctx
                s.translateBy(x: p.x, y: p.y)
                s.rotate(by: .radians(a))
                s.opacity = feel == .rest ? 0.8 : 1
                s.fill(Path(roundedRect: CGRect(x: -seed / 2, y: -seed / 2, width: seed, height: seed), cornerRadius: seed * 0.18),
                       with: .color(FeelPalette.color(feel, variant: FeelPalette.variant(day, hour))))
                if hour == month.mindfulHour && day == month.mindfulDay { litPoint = p }
            }
        }
        lit(&ctx, at: litPoint, size: seed)
    }

    /// A diamond lattice: a day to a row, an hour to a dot; neighbouring lit dots join with a loop.
    private func drawKolam(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let inset: CGFloat = 18
        let stepX = (size.width - inset * 2) / 24, stepY = (size.height - inset * 2) / 30
        func point(_ day: Int, _ hour: Int) -> CGPoint {
            CGPoint(x: inset + (CGFloat(hour) + (day % 2 == 0 ? 0.25 : 0.75)) * stepX, y: inset + (CGFloat(day) + 0.5) * stepY)
        }
        for day in 0..<30 {
            for hour in 0..<23 where month.feel(day: day, hour: hour) != .rest && month.feel(day: day, hour: hour + 1) != .rest {
                var line = Path()
                let a = point(day, hour), b = point(day, hour + 1)
                line.move(to: a)
                line.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: a.y - stepY * 0.6))
                ctx.stroke(line, with: .color(Color(hex: 0x5BDF62, alpha: 0.22)), lineWidth: 1)
            }
        }
        for day in 0..<30 {
            for hour in 0..<24 {
                let p = point(day, hour), feel = month.feel(day: day, hour: hour)
                let d = min(stepX, stepY) * (feel == .rest ? 0.32 : 0.62)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                         with: .color(FeelPalette.color(feel, variant: FeelPalette.variant(day, hour)).opacity(feel == .rest ? 0.7 : 1)))
            }
        }
        lit(&ctx, at: point(month.mindfulDay, month.mindfulHour), size: min(stepX, stepY) * 0.7)
    }

    /// Thirty strands from a curved toran; each bead an hour on a screen, morning first.
    private func drawGarland(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let inset: CGFloat = 16
        let stepX = (size.width - inset * 2) / 30
        var rope = Path()
        rope.move(to: CGPoint(x: inset, y: 22))
        rope.addQuadCurve(to: CGPoint(x: size.width - inset, y: 22), control: CGPoint(x: size.width / 2, y: 46))
        ctx.stroke(rope, with: .color(Color(hex: 0xFFC800, alpha: 0.7)), lineWidth: 2)
        let bead = CGSize(width: stepX * 0.62, height: stepX * 0.9)
        var litPoint = CGPoint.zero
        for day in 0..<30 {
            let x = inset + (CGFloat(day) + 0.5) * stepX
            let t = (x - inset) / (size.width - inset * 2)
            var y = 22 + 4 * 24 * t * (1 - t) * 0.5 + 6
            for i in 0..<24 {
                let hour = (i + 6) % 24
                let feel = month.feel(day: day, hour: hour)
                guard feel != .rest else { continue }
                let rect = CGRect(x: x - bead.width / 2, y: y, width: bead.width, height: bead.height)
                ctx.fill(UnevenRoundedRectangle(topLeadingRadius: bead.width / 2, bottomLeadingRadius: bead.width * 0.6,
                                                bottomTrailingRadius: bead.width * 0.6, topTrailingRadius: bead.width / 2).path(in: rect),
                         with: .color(FeelPalette.color(feel, variant: FeelPalette.variant(day, hour))))
                if hour == month.mindfulHour && day == month.mindfulDay { litPoint = CGPoint(x: x, y: y + bead.height / 2) }
                y += bead.height + 2
            }
        }
        if litPoint != .zero { lit(&ctx, at: litPoint, size: bead.width) }
    }

    /// Days left to right, hours rising from midnight at the ground; the sky lightens above the land.
    private func drawHorizon(_ ctx: inout GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0x16301A), Color(hex: 0x0C130C)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        let inset: CGFloat = 14
        let w = (size.width - inset * 2) / 30, h = (size.height - inset * 2) / 24
        for day in 0..<30 {
            for hour in 0..<24 {
                let feel = month.feel(day: day, hour: hour)
                let rect = CGRect(x: inset + CGFloat(day) * w + 1, y: size.height - inset - CGFloat(hour + 1) * h + 1, width: w - 2, height: h - 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                         with: .color(FeelPalette.color(feel, variant: FeelPalette.variant(day, hour)).opacity(feel == .rest ? 0.55 : 1)))
            }
        }
        let p = CGPoint(x: inset + (CGFloat(month.mindfulDay) + 0.5) * w, y: size.height - inset - (CGFloat(month.mindfulHour) + 0.5) * h)
        lit(&ctx, at: p, size: min(w, h))
    }
}
