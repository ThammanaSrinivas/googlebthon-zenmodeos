import SwiftUI

/// The lights of the room (Albeit pattern tones). Never the OS gradient.
public enum BackdropTone: String, CaseIterable, Sendable {
    case zen, mint, amber, dusk, twilight, night

    /// Sky: the wall's colour at the top, and the floor's.
    var sky: (UInt32, UInt32) {
        switch self {
        case .zen: (0xD8ECD3, 0xFFF4D3)
        case .mint: (0xE3F2E0, 0xFBFBF1)
        case .amber: (0xFFEBB5, 0xFFF7E2)
        case .dusk: (0xD5DDDB, 0xF0EDE7)
        case .twilight: (0xD9D6E4, 0xF9E6D6)
        case .night: (0x060D08, 0x122219)
        }
    }

    /// The glow in the moment's hue, behind the hero.
    var glow: UInt32 {
        switch self {
        case .zen, .mint: 0x5BDF62
        case .amber: 0xFFC800
        case .dusk: 0xB9CDB5
        case .twilight: 0xB7A8E0
        case .night: 0x5BDF62
        }
    }

    var isDark: Bool { self == .night }

    public static func `for`(_ feeling: ZenoFeeling) -> BackdropTone {
        switch feeling {
        case .proud: .amber
        case .sleepy: .twilight
        case .sad: .dusk
        case .pleasant: .mint
        default: .zen
        }
    }
}

/// A seamless studio sweep lit in the tone's sky: a wall curves through a cove into a lighter floor,
/// a soft key light falls from the upper left, the corners fall away, paper grain lies over all of
/// it, and a faint 12 pt cell grid sits on the wall. Quiet in the top middle, where titles sit.
public struct ZenBackdrop: View {
    var tone: BackdropTone
    @Environment(\.colorScheme) private var scheme
    /// Where the hero's glow sits, in unit coordinates (nil for none).
    var glowAt: UnitPoint?
    var showsGrid: Bool

    public init(tone: BackdropTone = .zen, glowAt: UnitPoint? = nil, showsGrid: Bool = true) {
        self.tone = tone
        self.glowAt = glowAt
        self.showsGrid = showsGrid
    }

    /// Dark mode is the night tone, whatever the moment's light.
    private var lit: BackdropTone { scheme == .dark ? .night : tone }

    public var body: some View {
        let tone = lit
        ZStack {
            ForEach(BackdropTone.allCases, id: \.self) { t in
                StudioRoom(tone: t, showsGrid: showsGrid)
                    .opacity(t == tone ? 1 : 0)
            }
            if let glowAt {
                GeometryReader { geo in
                    let r = max(geo.size.width, geo.size.height) * 0.42
                    RadialGradient(colors: [Color(hex: tone.glow, alpha: tone.isDark ? 0.22 : 0.34), Color(hex: tone.glow, alpha: 0)],
                                   center: glowAt, startRadius: 0, endRadius: r)
                        .blendMode(tone.isDark ? .screen : .plusLighter)
                        .opacity(tone.isDark ? 1 : 0.7)
                }
            }
            Grain().opacity(tone.isDark ? 0.07 : 0.05).blendMode(.overlay)
        }
        .animation(ZenMotion.calm(1.5), value: tone)
        .animation(ZenMotion.calm(ZenMotion.t3), value: glowAt.map { [$0.x, $0.y] })
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StudioRoom: View {
    let tone: BackdropTone
    let showsGrid: Bool

    var body: some View {
        Canvas(opaque: true) { ctx, size in
            let (s0, s1) = (rgb(tone.sky.0), rgb(tone.sky.1))
            let deep = tone.isDark ? s0 : mix(s0, rgb(0x2F5A33), 0.07)
            let w = size.width, h = size.height
            let coveY = h * 0.64, lift = h * 0.022

            // Wall into floor.
            let wall = Gradient(stops: [
                .init(color: color(deep), location: 0),
                .init(color: color(mix(s0, s1, 0.18)), location: 0.4),
                .init(color: color(mix(s0, s1, 0.5)), location: 0.64),
                .init(color: color(s1), location: 0.8),
                .init(color: color(mix(s1, s0, tone.isDark ? 0.5 : 0.28)), location: 1),
            ])
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(wall, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // The cell grid on the wall, fading before the cove, calm in the top middle.
            if showsGrid {
                let cell = ZenGrid.cell, step = ZenGrid.cell + ZenGrid.gap
                let cols = Int(w / step) + 1, rows = Int((coveY - lift * 2) * 0.9 / step)
                let ink = tone.isDark ? Color.white : Color(hex: 0x2F5A33)
                for r in 0..<max(rows, 0) {
                    let y = CGFloat(r) * step + 6
                    let fade = pow(1 - min(max(y / (coveY - lift * 2), 0), 1), 1.6)
                    for c in 0..<cols {
                        let x = CGFloat(c) * step + 6
                        let dx = (x - w * 0.5) / (w * 0.42), dy = (y - h * 0.36) / (h * 0.2)
                        let calm = 1 - 0.55 * exp(-(dx * dx + dy * dy))
                        let a = fade * calm * (tone.isDark ? 0.05 : 0.055)
                        if a < 0.004 { continue }
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: cell, height: cell), cornerRadius: ZenRadius.cell),
                                 with: .color(ink.opacity(a)))
                    }
                }
            }

            // The cove catches the light.
            var cove = Path()
            cove.move(to: CGPoint(x: -2, y: coveY - lift))
            cove.addQuadCurve(to: CGPoint(x: w + 2, y: coveY - lift), control: CGPoint(x: w / 2, y: coveY + lift))
            var band = ctx
            band.addFilter(.blur(radius: h * 0.05))
            band.stroke(cove, with: .color(.white.opacity(tone.isDark ? 0.05 : 0.55)), lineWidth: h * 0.06)

            // Key light from the upper left.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [.white.opacity(tone.isDark ? 0.05 : 0.5), .white.opacity(0)]),
                center: CGPoint(x: w * 0.16, y: -h * 0.05), startRadius: 0, endRadius: max(w, h) * 0.75))

            // The corners fall away.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [.black.opacity(0), .black.opacity(tone.isDark ? 0.45 : 0.1)]),
                center: CGPoint(x: w / 2, y: h * 0.45), startRadius: min(w, h) * 0.45, endRadius: max(w, h) * 0.85))
        }
    }

    private func rgb(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
    }
    private func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * t }
    private func color(_ c: SIMD3<Double>) -> Color { Color(.sRGB, red: c.x, green: c.y, blue: c.z) }
}

/// Paper grain: a fixed noise tile, generated once.
private struct Grain: View {
    var body: some View {
        Image(decorative: Self.tile, scale: 2)
            .resizable(resizingMode: .tile)
    }

    nonisolated(unsafe) static let tile: CGImage = {
        let n = 160
        var bytes = [UInt8](repeating: 0, count: n * n)
        var seed: UInt32 = 0x1234567
        for i in 0..<(n * n) {
            seed = seed &* 1664525 &+ 1013904223
            bytes[i] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()
}
