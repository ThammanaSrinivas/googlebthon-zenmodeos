import SwiftUI
import Albeit

/// The quiet ornament in Today's top-right corner: a bloom of seeds (137.5° apart, as the month's
/// Bloom pattern lays its hours) inside a few kolam rings of dots. Brand green, low contrast, still,
/// and only decoration: VoiceOver skips it and it never takes a click.
struct TodayOrnament: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            let dark = scheme == .dark
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rMax = min(size.width, size.height) / 2
            let green = dark ? Color(hex: 0x5BDF62) : Color(hex: 0x2AA136)
            let strength: Double = dark ? 0.75 : 1

            // Kolam rings: dots on four circles, every other ring offset by half a step.
            for (i, ring) in [0.56, 0.7, 0.84, 0.98].enumerated() {
                let r = rMax * ring
                let count = Int(r / 7)
                for k in 0..<count {
                    let a = (Double(k) + (i % 2 == 0 ? 0 : 0.5)) / Double(count) * 2 * .pi
                    let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    let s: CGFloat = k % 4 == 0 ? 2.4 : 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                             with: .color(green.opacity((0.16 - Double(i) * 0.028) * strength)))
                }
            }

            // The bloom: seeds grow and fade toward the rim.
            let seeds = 420
            let reach = rMax * 0.5
            let k = reach / sqrt(Double(seeds))
            let golden = 137.508 * Double.pi / 180
            for n in 1..<seeds {
                let t = Double(n) / Double(seeds)
                let r = k * sqrt(Double(n)), a = Double(n) * golden
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                let s = 2.0 + 3.2 * t
                var seed = ctx
                seed.translateBy(x: p.x, y: p.y)
                seed.rotate(by: .radians(a))
                seed.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: s * 0.22),
                          with: .color(green.opacity((0.22 - 0.12 * t) * strength)))
            }
            // A warm heart, the one lit seed every Bloom has.
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)),
                     with: .radialGradient(Gradient(colors: [green.opacity(0.22 * strength), .clear]), center: c, startRadius: 0, endRadius: 18))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
