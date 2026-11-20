import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// Albeit · the ZenMode OS design system (v5). One name per meaning; screens read these, never hex.
// Values are the book's V5 CSS (paper / ink).

extension Color {
    /// A colour that follows the system appearance.
    init(light: UInt32, dark: UInt32, alpha: Double = 1) {
        #if canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: alpha)
        })
        #else
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: alpha) : UIColor(hex: light, alpha: alpha) })
        #endif
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// The semantic palette: `Color.zen.surfaceBase`.
    public static let zen = ZenPalette()
}

#if canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#else
extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

public struct ZenPalette: Sendable {
    // Surfaces
    public let surfaceBase = Color(light: 0xF2F1EC, dark: 0x0E110E)
    public let surfaceCard = Color(light: 0xFAF9F5, dark: 0x161A16)
    public let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1C211C)
    public let surfaceSunk = Color(light: 0xEAE8E2, dark: 0x090B09)
    public let surfaceTint = Color(light: 0xE6F6E7, dark: 0x142516)
    // Text
    public let textHeading = Color(light: 0x12160F, dark: 0xF2F3EE)
    public let textBody = Color(light: 0x4A4F46, dark: 0xC9CCC4)
    public let textCaption = Color(light: 0x5C6158, dark: 0xA4A9A0)
    public let textBrand = Color(light: 0x0F7A18, dark: 0x5BDF62)
    // Lines
    public let borderHairline = Color(light: 0xDCDAD1, dark: 0x262B26)
    public let borderOutline = Color(light: 0xC9C7BD, dark: 0x343A34)
    // Action and meaning
    public let actionPrimary = Color(light: 0x12160F, dark: 0xF2F3EE)
    public let onActionPrimary = Color(light: 0xF2F3EE, dark: 0x12160F)
    public let brandFill = Color(hex: 0x2AA136)
    public let brandSoft = Color(hex: 0x5BDF62)
    public let accentReward = Color(hex: 0xFFC800)
    public let accentRewardText = Color(light: 0x7A5A00, dark: 0xFFD86B)
    public let accentRewardTint = Color(light: 0xFFF3CC, dark: 0x2A2208)
    public let scoreGain = Color(light: 0x0F7A18, dark: 0x5BDF62)
    public let scoreDeduct = Color(light: 0xB34700, dark: 0xFF8A3D)
    public let ember = Color(hex: 0xFF6600)
    // The black of the notch and the Island
    public let island = Color(hex: 0x000000)
    public let islandText = Color(hex: 0xF5F5F1)
    public let islandDetail = Color(hex: 0xA3A39C)
    public let islandPill = Color(hex: 0x262626)
}

/// The score gradient (`--score`): ember to amber to green. Only on the score itself.
public enum ZenGradient {
    public static let score = LinearGradient(
        stops: [.init(color: Color(hex: 0xFF6600), location: 0),
                .init(color: Color(hex: 0xFFC800), location: 0.46),
                .init(color: Color(hex: 0x5BDF62), location: 1)],
        startPoint: .leading, endPoint: .trailing)
    /// The OS gradient (`--os`), for the "OS" in the wordmark only. Never behind text.
    public static let os = LinearGradient(
        stops: [.init(color: Color(hex: 0xFF6600), location: 0),
                .init(color: Color(hex: 0xFFC800), location: 0.48),
                .init(color: Color(hex: 0x0F7A18), location: 1)],
        startPoint: .leading, endPoint: .trailing)
}

/// 4 pt steps: s1 4 … s32 128.
public enum ZenSpace {
    public static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 20
    public static let s6: CGFloat = 24, s8: CGFloat = 32, s10: CGFloat = 40, s12: CGFloat = 48, s16: CGFloat = 64
    public static let s24: CGFloat = 96, s32: CGFloat = 128
}

public enum ZenRadius {
    public static let xs: CGFloat = 6, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 20
    public static let xxl: CGFloat = 24, xxxl: CGFloat = 34
    public static let widget: CGFloat = 22
    /// A cell in the 12 + 4 grid.
    public static let cell: CGFloat = 2
}

/// The grid: a 12 pt cell with a 4 pt gap.
public enum ZenGrid {
    public static let cell: CGFloat = 12
    public static let gap: CGFloat = 4
}

/// Springs and curves. Only Zeno bounces; containers settle.
public enum ZenMotion {
    public static let container = Animation.spring(response: 0.42, dampingFraction: 0.82)
    public static let exit = Animation.spring(response: 0.44, dampingFraction: 0.94)
    public static let zenoHappy = Animation.spring(response: 0.38, dampingFraction: 0.52)
    public static let zenoSad = Animation.spring(response: 0.86, dampingFraction: 0.92)
    public static let words = Animation.spring(response: 0.44, dampingFraction: 0.78)
    public static func calm(_ seconds: Double) -> Animation { .timingCurve(0.22, 0.61, 0.36, 1, duration: seconds) }
    public static func settle(_ seconds: Double) -> Animation { .timingCurve(0.32, 0.72, 0, 1, duration: seconds) }
    /// 160 / 320 / 640 / 1200 / 1800 ms. 1200 is the hand-off, the one in the system.
    public static let t1 = 0.16, t2 = 0.32, t3 = 0.64, t4 = 1.2, t5 = 1.8
}
