import SwiftUI

/// A quiet, generative ornament for an empty corner. Brand green only, lit from its heart, low
/// contrast so it never competes with the content beside it, and hidden from VoiceOver.
///
/// - `.bloom`: rounded seeds on the golden angle (the Bloom's own geometry, a sunflower head) inside
///   faint concentric seed rings. It turns once every ten minutes; under Reduce Motion, or with
///   `drifts: false`, it stands still.
/// - `.kolam`: a diamond lattice of dots joined by soft loops, after the pulli kolam drawn at a
///   threshold. It never moves.
///
/// It fills the square it's given (the caller sizes it) and holds up from about 48 pt to 520 pt: the
/// seed count follows the size, so a small one stays crisp and a large one stays fine. Place it
/// behind content, usually bleeding off a corner:
///
///     .background(alignment: .topTrailing) {
///         ZenBloomOrnament().frame(width: 440, height: 440).offset(x: 140, y: -160)
///     }
public struct ZenBloomOrnament: View {
    public enum Pattern: Sendable, Equatable { case bloom, kolam }

    var pattern: Pattern
    var intensity: Double
    var drifts: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - pattern: the bloom (default) or the kolam lattice.
    ///   - intensity: 0…1.5, how present it is; 1 is the designed default.
    ///   - drifts: whether the bloom turns (always still under Reduce Motion).
    public init(_ pattern: Pattern = .bloom, intensity: Double = 1, drifts: Bool = true) {
        self.pattern = pattern
        self.intensity = min(max(intensity, 0), 1.5)
        self.drifts = drifts
    }

    /// One turn every ten minutes: movement you notice only if you look away and back.
    static let period: Double = 600

    public var body: some View {
        let still = reduceMotion || !drifts || pattern == .kolam
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { tl in
            let turn = still ? 0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            OrnamentCanvas(pattern: pattern, intensity: intensity, dark: scheme == .dark)
                .equatable()
                .rotationEffect(.degrees(turn * 360))
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Geometry (pure, tested)

    /// One seed of the bloom: where it sits from the centre, how big it is, and how far out (0 heart … 1 rim).
    struct Seed: Equatable {
        var offset: CGPoint
        var size: CGFloat
        var angle: Double
        var t: Double
    }

    static let golden = 137.508 * Double.pi / 180

    /// The seeds of a bloom of `radius`: spacing follows the size (3.2 … 12 pt), so there are 34 seeds
    /// at the smallest and at most 700 at the largest, and every seed lies inside the radius.
    static func bloomSeeds(radius: CGFloat) -> [Seed] {
        guard radius > 2 else { return [] }
        let spacing = min(max(radius * 0.052, 3.2), 12)
        let n = min(max(Int((radius / spacing) * (radius / spacing)), 34), 700)
        let reach = radius * 0.9
        let k = reach / sqrt(CGFloat(n))
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let r = k * sqrt(CGFloat(i) + 0.5)
            let a = Double(i) * golden
            let size = k * (0.56 + 0.5 * CGFloat(t))
            return Seed(offset: CGPoint(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a))), size: size, angle: a, t: t)
        }
    }

    /// The dots of the kolam lattice for a square of `side`: a diamond lattice (every other row
    /// offset by half a step) clipped to the inscribed circle, 5 … 15 dots across.
    static func kolamDots(side: CGFloat) -> [CGPoint] {
        guard side > 8 else { return [] }
        let across = min(max(Int(side / 34), 5), 15) | 1
        let step = side / CGFloat(across)
        let r = side / 2
        var dots: [CGPoint] = []
        for row in 0..<(across * 2) {
            let y = step * 0.5 + CGFloat(row) * step * 0.5
            guard y < side else { break }
            let shift = row % 2 == 0 ? 0 : step * 0.5
            for col in 0..<across {
                let p = CGPoint(x: step * 0.5 + CGFloat(col) * step + shift, y: y)
                let dx = p.x - r, dy = p.y - r
                if dx * dx + dy * dy <= (r - step * 0.35) * (r - step * 0.35) { dots.append(p) }
            }
        }
        return dots
    }
}

/// The drawing itself, equatable so the drift only rotates it and never redraws it.
private struct OrnamentCanvas: View, Equatable {
    let pattern: ZenBloomOrnament.Pattern
    let intensity: Double
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            switch pattern {
            case .bloom: drawBloom(&ctx, size)
            case .kolam: drawKolam(&ctx, size)
            }
        }
    }

    /// Light: deep greens, a little stronger; dark: the bright brand green, glowing.
    private var rim: Color { dark ? Color(hex: 0x2AA136) : Color(hex: 0x0F7A18) }
    private var heart: Color { dark ? Color(hex: 0x5BDF62) : Color(hex: 0x2AA136) }
    private var strength: Double { (dark ? 0.34 : 0.24) * intensity }

    private func drawBloom(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let side = min(size.width, size.height)
        let radius = side / 2
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let hair = max(0.6, min(1, side / 360))

        // The light at the heart.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: side, height: side)),
                 with: .radialGradient(Gradient(colors: [heart.opacity(strength * (dark ? 0.55 : 0.45)), heart.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: radius * 0.62))

        // Concentric seed rings, on the golden ratios; the outer one is a ring of dots.
        for (i, f) in [0.236, 0.382, 0.618, 0.82, 1.0].enumerated() {
            let r = radius * f * 0.98
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            if i == 4 {
                let dot = max(1.2, radius * 0.012)
                ctx.stroke(ring, with: .color(rim.opacity(strength * 0.7)),
                           style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0.01, max(dot * 4, radius * 0.045)]))
            } else {
                ctx.stroke(ring, with: .color(rim.opacity(strength * (0.32 - Double(i) * 0.04))), lineWidth: hair)
            }
        }

        // The seeds, brightest just off the heart, fading to the rim.
        var seeds = ctx
        if dark { seeds.blendMode = .plusLighter }
        for s in ZenBloomOrnament.bloomSeeds(radius: radius) {
            // Lit from the heart: brightest a little way out, falling away to a whisper at the rim.
            let fade = pow(1 - s.t, 1.35)
            let lift = s.t < 0.1 ? 0.55 + s.t * 4.5 : 1
            let alpha = strength * (0.12 + 0.88 * fade) * lift
            var cell = seeds
            cell.translateBy(x: c.x + s.offset.x, y: c.y + s.offset.y)
            cell.rotate(by: .radians(s.angle))
            let rect = CGRect(x: -s.size / 2, y: -s.size / 2, width: s.size, height: s.size)
            cell.fill(Path(roundedRect: rect, cornerRadius: s.size * 0.28),
                      with: .color(mix(s.t).opacity(alpha)))
        }
    }

    private func drawKolam(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let dots = ZenBloomOrnament.kolamDots(side: side)
        guard dots.count > 1 else { return }
        let across = CGFloat(min(max(Int(side / 34), 5), 15) | 1)
        let step = side / across
        let c = CGPoint(x: side / 2, y: side / 2)
        func fade(_ p: CGPoint) -> Double {
            let d = hypot(p.x - c.x, p.y - c.y) / (side / 2)
            return max(0, 1 - pow(Double(d), 1.6))
        }

        ctx.fill(Path(ellipseIn: CGRect(origin: origin, size: CGSize(width: side, height: side))),
                 with: .radialGradient(Gradient(colors: [heart.opacity(strength * 0.4), heart.opacity(0)]),
                                       center: CGPoint(x: origin.x + c.x, y: origin.y + c.y), startRadius: 0, endRadius: side * 0.36))

        // Loops between diagonal neighbours, bowing away from the centre like a drawn line.
        let lineWidth = max(0.75, min(1.4, side / 320))
        for a in dots {
            for d in [CGPoint(x: step * 0.5, y: step * 0.5), CGPoint(x: -step * 0.5, y: step * 0.5)] {
                let b = CGPoint(x: a.x + d.x, y: a.y + d.y)
                guard dots.contains(where: { abs($0.x - b.x) < 0.5 && abs($0.y - b.y) < 0.5 }) else { continue }
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let out = CGPoint(x: mid.x - c.x, y: mid.y - c.y)
                let len = max(hypot(out.x, out.y), 0.001)
                let bow = step * 0.22
                let ctrl = CGPoint(x: mid.x + out.x / len * bow, y: mid.y + out.y / len * bow)
                var loop = Path()
                loop.move(to: CGPoint(x: origin.x + a.x, y: origin.y + a.y))
                loop.addQuadCurve(to: CGPoint(x: origin.x + b.x, y: origin.y + b.y), control: CGPoint(x: origin.x + ctrl.x, y: origin.y + ctrl.y))
                ctx.stroke(loop, with: .color(rim.opacity(strength * 0.55 * fade(mid))), lineWidth: lineWidth)
            }
        }
        var lit = ctx
        if dark { lit.blendMode = .plusLighter }
        for p in dots {
            let f = fade(p)
            let d = step * 0.16 * (0.7 + 0.3 * CGFloat(f))
            lit.fill(Path(ellipseIn: CGRect(x: origin.x + p.x - d / 2, y: origin.y + p.y - d / 2, width: d, height: d)),
                     with: .color(heart.opacity(strength * (0.35 + 0.65 * f))))
        }
    }

    /// Heart green to rim green.
    private func mix(_ t: Double) -> Color {
        let a: (Double, Double, Double) = dark ? (0x5B, 0xDF, 0x62) : (0x2A, 0xA1, 0x36)
        let b: (Double, Double, Double) = dark ? (0x2A, 0xA1, 0x36) : (0x0F, 0x7A, 0x18)
        let k = min(max(t, 0), 1)
        return Color(.sRGB, red: (a.0 + (b.0 - a.0) * k) / 255, green: (a.1 + (b.1 - a.1) * k) / 255, blue: (a.2 + (b.2 - a.2) * k) / 255)
    }
}
