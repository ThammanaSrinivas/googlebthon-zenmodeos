import SwiftUI

/// WCAG 2.2 contrast for Albeit colours, resolved in light or dark. Use it in tests (and while
/// designing) to prove a pairing before it ships:
///
///     ZenContrast.ratio(Color.zen.textCaption, Color.zen.surfaceCard, in: .dark) >= ZenContrast.text
///
/// Glass renders flat in snapshots, so `glass(over:in:)` gives the range Liquid Glass's regular
/// variant spans over a ground; check text against every one of them.
public enum ZenContrast {
    /// Body text and captions (AA).
    public static let text = 4.5
    /// Text 18 pt and up, or 14 pt bold and up (AA).
    public static let largeText = 3.0
    /// Outlines, focus rings, icons that carry meaning (AA, 1.4.11).
    public static let nonText = 3.0

    /// `color` resolved in `scheme`.
    @MainActor
    public static func resolve(_ color: Color, in scheme: ColorScheme) -> Color.Resolved {
        var env = EnvironmentValues()
        env.colorScheme = scheme
        return color.resolve(in: env)
    }

    /// Relative luminance, 0 (black) … 1 (white).
    public static func luminance(_ c: Color.Resolved) -> Double {
        func clamp(_ v: Float) -> Double { min(max(Double(v), 0), 1) }
        return 0.2126 * clamp(c.linearRed) + 0.7152 * clamp(c.linearGreen) + 0.0722 * clamp(c.linearBlue)
    }

    /// The contrast ratio between two colours, 1 … 21. Order doesn't matter.
    public static func ratio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The contrast ratio between two palette colours in `scheme`.
    @MainActor
    public static func ratio(_ a: Color, _ b: Color, in scheme: ColorScheme) -> Double {
        ratio(resolve(a, in: scheme), resolve(b, in: scheme))
    }

    /// `top` at `opacity` laid over an opaque `bottom` (source-over, in sRGB), as an opaque colour.
    @MainActor
    public static func composite(_ top: Color, opacity: Double, over bottom: Color, in scheme: ColorScheme) -> Color {
        let t = resolve(top, in: scheme), b = resolve(bottom, in: scheme)
        let k = Float(min(max(opacity, 0), 1)) * t.opacity
        return Color(.sRGB, red: Double(b.red + (t.red - b.red) * k),
                     green: Double(b.green + (t.green - b.green) * k),
                     blue: Double(b.blue + (t.blue - b.blue) * k))
    }

    /// What a card of regular Liquid Glass can look like over `ground`: lifted toward white, dimmed a
    /// touch, and tinted with the brand. Text on glass has to clear all of them.
    @MainActor
    public static func glass(over ground: Color, in scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [composite(.white, opacity: 0.10, over: ground, in: scheme),
                    composite(.white, opacity: 0.14, over: ground, in: scheme),
                    composite(Color.zen.brandFill, opacity: 0.14,
                              over: composite(.white, opacity: 0.10, over: ground, in: scheme), in: scheme)]
        }
        return [composite(.white, opacity: 0.35, over: ground, in: scheme),
                composite(.black, opacity: 0.06, over: ground, in: scheme),
                composite(Color.zen.brandFill, opacity: 0.12,
                          over: composite(.white, opacity: 0.20, over: ground, in: scheme), in: scheme)]
    }

    /// The app's ground (`ZenAurora`) at its plainest and where its brand light is strongest.
    @MainActor
    public static func grounds(in scheme: ColorScheme) -> [Color] {
        let base = Color.zen.surfaceBase
        return [base, composite(Color.zen.brandSoft, opacity: ZenAurora.lightAlpha(glow: 1, dark: scheme == .dark),
                                over: base, in: scheme)]
    }
}
