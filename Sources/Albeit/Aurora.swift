import SwiftUI

/// The app's ground: paper by day, ink by night, nearly solid, so content is the only colour on the
/// page. One very soft brand-green light falls from the upper right (a good day lets in a little more),
/// a gentle key light lifts the top edge, and a fine grain lies over all of it so it reads as a surface,
/// not a screen. No other hues, no shift with the hour, no motion: calm by design (and so nothing to
/// pause under Reduce Motion).
public struct ZenAurora: View {
    @Environment(\.colorScheme) private var scheme
    /// 0…1: how much of the brand light to let in (a good day glows a little greener).
    var glow: Double

    public init(glow: Double = 0.6) {
        self.glow = glow
    }

    public var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                Color.zen.surfaceBase
                // The key light: the top edge a breath lighter, gone by the middle of the page.
                LinearGradient(colors: [Color.white.opacity(dark ? 0.025 : 0.32), Color.white.opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
                // The one brand light, upper right, wide and faint.
                RadialGradient(colors: [Color.zen.brandSoft.opacity(Self.lightAlpha(glow: glow, dark: dark)),
                                        Color.zen.brandSoft.opacity(0)],
                               center: UnitPoint(x: 0.86, y: -0.08), startRadius: 0, endRadius: reach * 0.62)
            }
        }
        .overlay(AuroraGrain().opacity(dark ? 0.05 : 0.04).blendMode(.overlay))
        .animation(ZenMotion.calm(ZenMotion.t4), value: glow)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The brand light's strongest point: at most 0.12 by day and 0.10 at night, so text on the
    /// ground keeps its contrast wherever it sits.
    static func lightAlpha(glow: Double, dark: Bool) -> Double {
        let k = min(max(glow, 0), 1)
        return dark ? 0.03 + 0.07 * k : 0.05 + 0.07 * k
    }
}

/// A fine, fixed grain so the light reads as a surface, not a screen.
private struct AuroraGrain: View {
    var body: some View {
        Image(decorative: Self.tile, scale: 2).resizable(resizingMode: .tile)
    }

    nonisolated(unsafe) static let tile: CGImage = {
        let n = 128
        var bytes = [UInt8](repeating: 0, count: n * n)
        var seed: UInt32 = 0x2026_1120
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
