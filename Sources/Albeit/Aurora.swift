import SwiftUI

/// The app's ground: a slow, living mesh of light in Albeit's hues. Paper with mint, sky and a warm
/// edge by day; ink with a green and amber aurora by night. The light leans with the time of day
/// (warmer in the morning and evening), drifts over half a minute, and lies under a fine grain.
/// No grid, no hard edges: it should feel like light on a desk, not a pattern. Still under Reduce Motion.
public struct ZenAurora: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0…1: how much of the mood colour to let in (a good day glows a little greener).
    var glow: Double

    public init(glow: Double = 0.6) {
        self.glow = glow
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            let hour = Calendar.current.component(.hour, from: tl.date)
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors(hour: hour), smoothsColors: true)
        }
        .overlay(AuroraGrain().opacity(scheme == .dark ? 0.06 : 0.045).blendMode(.overlay))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The inner point wanders on a slow Lissajous path; the edges breathe a little. Corners stay put.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t / 17) * 0.09), b = Float(cos(t / 23) * 0.08)
        let e = Float(sin(t / 29) * 0.05), f = Float(cos(t / 19) * 0.05)
        return [
            [0, 0], [0.5 + e, 0], [1, 0],
            [0, 0.5 + f], [0.52 + a, 0.46 + b], [1, 0.5 - f],
            [0, 1], [0.5 - e, 1], [1, 1],
        ]
    }

    private func colors(hour: Int) -> [Color] {
        let warm = hour < 9 || hour >= 17
        if scheme == .dark {
            let base: UInt32 = 0x0A0D0B
            return [
                hex(0x0F2C2B), hex(base), hex(0x1A1430),
                hex(base), mix(0x123A1E, base, glow), hex(base),
                hex(warm ? 0x3A2A08 : 0x1E2A10), hex(base), hex(0x0C1A10),
            ]
        }
        let paper: UInt32 = 0xF4F3EE
        return [
            hex(0xD6E9F0), hex(paper), hex(warm ? 0xFBDFC2 : 0xF6EACB),
            hex(0xF0F3EA), mix(0xCDEFD0, paper, glow), hex(paper),
            hex(0xE5DFF2), hex(0xF1F2EC), hex(0xD9EFD6),
        ]
    }

    private func hex(_ h: UInt32) -> Color { Color(hex: h) }

    /// `a` at `amount`, the rest `b`.
    private func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> Color {
        let k = min(max(amount, 0), 1)
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) / 255 }
        return Color(.sRGB, red: ch(b, 16) + (ch(a, 16) - ch(b, 16)) * k,
                     green: ch(b, 8) + (ch(a, 8) - ch(b, 8)) * k,
                     blue: ch(b, 0) + (ch(a, 0) - ch(b, 0)) * k)
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
