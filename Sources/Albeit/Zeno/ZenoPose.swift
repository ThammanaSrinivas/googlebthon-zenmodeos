import SwiftUI

/// Zeno's eight feelings. The feeling matches the moment; sad is never a punishment.
public enum ZenoFeeling: String, CaseIterable, Sendable, Identifiable {
    case calm, happy, pleasant, curious, proud, sleepy, sad, alert

    public var id: String { rawValue }

    public var skin: ZenoSkin {
        switch self {
        case .calm, .happy, .pleasant, .curious: .zen
        case .proud: .gold
        case .sleepy, .sad: .dusk
        case .alert: .ember
        }
    }

    /// How a feeling arrives (book §15): Zeno's spring, the ear kick, how long it holds.
    struct Style {
        var response: Double, damping: Double
        var earKick: Double, kicks: Int
        var exprResponse: Double, exprDamping: Double
        var look: CGPoint
        var hop = false, sparkle = false, peek = false, flick = false, tear = false, zz = false
    }

    var style: Style {
        switch self {
        case .calm: Style(response: 0.5, damping: 0.8, earKick: 0, kicks: 0, exprResponse: 0.5, exprDamping: 0.9, look: .zero)
        case .happy: Style(response: 0.38, damping: 0.52, earKick: 950, kicks: 2, exprResponse: 0.3, exprDamping: 0.7, look: CGPoint(x: 2.4, y: -0.4), hop: true, sparkle: true)
        case .proud: Style(response: 0.38, damping: 0.52, earKick: 900, kicks: 2, exprResponse: 0.3, exprDamping: 0.7, look: CGPoint(x: 2.2, y: -0.4), hop: true, sparkle: true)
        case .pleasant: Style(response: 0.56, damping: 0.78, earKick: 420, kicks: 1, exprResponse: 0.55, exprDamping: 0.9, look: CGPoint(x: 1.6, y: 0), peek: true)
        case .curious: Style(response: 0.42, damping: 0.6, earKick: 560, kicks: 1, exprResponse: 0.34, exprDamping: 0.76, look: CGPoint(x: 2.6, y: -0.8), flick: true)
        case .sad: Style(response: 0.86, damping: 0.92, earKick: 0, kicks: 0, exprResponse: 0.75, exprDamping: 0.96, look: CGPoint(x: 0.5, y: 2.6), tear: true)
        case .sleepy: Style(response: 0.78, damping: 0.9, earKick: 0, kicks: 0, exprResponse: 0.7, exprDamping: 0.95, look: CGPoint(x: 0.4, y: 1.2), zz: true)
        case .alert: Style(response: 0.32, damping: 0.5, earKick: 1150, kicks: 2, exprResponse: 0.22, exprDamping: 0.62, look: .zero)
        }
    }

    /// The face for this feeling. `droop` + is ears down and out; `arc` +1 is ∩, −1 is ‿.
    var expression: ZenoExpression {
        switch self {
        case .calm: ZenoExpression(shut: 0, arc: 0, lidU: 0, lidTilt: 0, brow: 0, browTilt: 0, browY: 0, eyeS: 1, mouth: 0.32, open: 0, blush: 0.25, droop: 2, tilt: 0, wet: 0, earLo: 0, earRo: 0)
        case .happy: ZenoExpression(shut: 1, arc: 1, lidU: 0, lidTilt: 0, brow: 0.55, browTilt: -6, browY: -3, eyeS: 1, mouth: 1, open: 0.62, blush: 1, droop: -10, tilt: 0, wet: 0, earLo: 0, earRo: 0)
        case .pleasant: ZenoExpression(shut: 1, arc: -1, lidU: 0, lidTilt: 0, brow: 0, browTilt: 0, browY: 0, eyeS: 1, mouth: 0.78, open: 0, blush: 0.75, droop: 9, tilt: 3, wet: 0, earLo: 0, earRo: 0)
        case .sad: ZenoExpression(shut: 0, arc: 0, lidU: 0.34, lidTilt: 17, brow: 0.95, browTilt: 22, browY: 1, eyeS: 1.06, mouth: -0.92, open: 0, blush: 0, droop: 36, tilt: -2, wet: 1, earLo: 0, earRo: 0)
        case .curious: ZenoExpression(shut: 0, arc: 0, lidU: 0, lidTilt: 0, brow: 0.8, browTilt: -4, browY: -2, eyeS: 1.1, mouth: 0, open: 0.26, blush: 0.2, droop: 4, tilt: 4, wet: 0, earLo: 17, earRo: -4)
        case .sleepy: ZenoExpression(shut: 0.86, arc: -0.3, lidU: 0, lidTilt: 0, brow: 0, browTilt: 0, browY: 0, eyeS: 1, mouth: 0.15, open: 0, blush: 0.35, droop: 24, tilt: -3, wet: 0, earLo: 0, earRo: 0)
        case .alert: ZenoExpression(shut: 0, arc: 0, lidU: 0, lidTilt: 0, brow: 0.9, browTilt: -3, browY: -4.5, eyeS: 1.18, mouth: -0.12, open: 0.36, blush: 0, droop: -16, tilt: 0, wet: 0, earLo: 0, earRo: 0)
        case .proud: ZenoExpression(shut: 1, arc: 1, lidU: 0, lidTilt: 0, brow: 0.5, browTilt: -6, browY: -3, eyeS: 1, mouth: 1, open: 0.36, blush: 0.9, droop: -12, tilt: 0, wet: 0, earLo: 0, earRo: 0)
        }
    }
}

struct ZenoExpression {
    var shut, arc, lidU, lidTilt, brow, browTilt, browY, eyeS, mouth, open, blush, droop, tilt, wet, earLo, earRo: Double

    /// The face values the animator springs between, by name.
    var faceValues: [ZenoPose.Key: Double] {
        [.shut: shut, .arc: arc, .lidU: lidU, .lidTilt: lidTilt, .brow: brow, .browTilt: browTilt, .browY: browY,
         .eyeS: eyeS, .mouth: mouth, .open: open, .blush: blush, .tilt: tilt, .wet: wet]
    }
}

/// Green does the work, gold is earned, ember asks for attention, dusk is quiet, os celebrates.
public enum ZenoSkin: String, CaseIterable, Sendable {
    case zen, gold, ember, dusk, os

    struct Colors: Sendable {
        var light, mid, deep, rim, blush, glow, ink: Color
        var rgb: [SIMD3<Double>]
    }

    var hexes: [UInt32] {
        switch self {
        case .zen: [0x86E486, 0x34AE41, 0x0F5F1A, 0xEDFFEA, 0xFF8F6B, 0x5BDF62, 0x0A140B]
        case .gold: [0xFFE59A, 0xFFBE2E, 0xC96E00, 0xFFFAE6, 0xFF6F45, 0xFFC800, 0x1A1003]
        case .ember: [0xFFC197, 0xFF7C30, 0xB43F00, 0xFFF1E6, 0xFF4D4D, 0xFF8A3D, 0x1C0A02]
        case .dusk: [0xD3DDCF, 0x93A88F, 0x4D654A, 0xF7FAF5, 0xE59F96, 0xB9CDB5, 0x0F160F]
        case .os: [0xFFD86B, 0x9ACF3C, 0x1C8A34, 0xFFFCEE, 0xFF8550, 0xFFC800, 0x0A140B]
        }
    }

    /// The glow colour, for light behind Zeno and the kicker inside the black notch.
    public var glow: Color { Color(hex: hexes[5]) }

    /// Kicker colour on a light ground.
    public var kickerOnLight: Color {
        switch self {
        case .zen, .os: Color(hex: 0x0F7A18)
        case .gold: Color(hex: 0x7A5A00)
        case .ember: Color(hex: 0xB34700)
        case .dusk: Color(hex: 0x4D654A)
        }
    }

    static func blend(_ a: ZenoSkin, _ b: ZenoSkin, _ t: Double) -> Colors {
        let t = min(max(t, 0), 1)
        let rgb = zip(a.hexes, b.hexes).map { x, y in
            let p = SIMD3<Double>(Double((x >> 16) & 0xFF), Double((x >> 8) & 0xFF), Double(x & 0xFF))
            let q = SIMD3<Double>(Double((y >> 16) & 0xFF), Double((y >> 8) & 0xFF), Double(y & 0xFF))
            return (p + (q - p) * t) / 255
        }
        let c = rgb.map { Color(.sRGB, red: $0.x, green: $0.y, blue: $0.z) }
        return Colors(light: c[0], mid: c[1], deep: c[2], rim: c[3], blush: c[4], glow: c[5], ink: c[6], rgb: rgb)
    }
}

/// Every value that moves on Zeno, in the 150 × 100 box's units.
public struct ZenoPose: Sendable {
    enum Key: CaseIterable {
        case shut, arc, lidU, lidTilt, brow, browTilt, browY, eyeS, mouth, open, blush, tilt, wet
        case droop, earLo, earRo, earWL, earWR, lookX, lookY, hopY, squash, sparkle, tear, tearA, zz, skinT
    }

    var values: [Key: Double]
    var time: Double

    subscript(_ k: Key) -> CGFloat { CGFloat(values[k] ?? 0) }
}
