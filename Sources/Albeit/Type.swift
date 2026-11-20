import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Three voices. Clash Display is the brand (Medium 500, never below 20, never a paragraph);
/// Geist is everything readable; Departure Mono is every number.
/// The fonts load from the system when installed; otherwise the system faces stand in.
public enum ZenFont {
    public static func brand(_ size: CGFloat) -> Font {
        hasClash ? .custom("ClashDisplay-Medium", fixedSize: size) : .system(size: size, weight: .semibold, design: .default)
    }

    public static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasGeist ? .custom("Geist", size: size).weight(weight) : .system(size: size, weight: weight)
    }

    public static func number(_ size: CGFloat) -> Font {
        hasDeparture ? .custom("DepartureMono-Regular", size: size) : .system(size: size, design: .monospaced)
    }

    static let hasClash = installed("ClashDisplay-Medium")
    static let hasGeist = installed("Geist-Regular") || installed("Geist")
    static let hasDeparture = installed("DepartureMono-Regular")

    private static func installed(_ name: String) -> Bool {
        #if canImport(AppKit)
        return NSFont(name: name, size: 12) != nil
        #else
        return UIFont(name: name, size: 12) != nil
        #endif
    }
}

/// The product type scale (points on Apple). Kerning per voice.
public enum ZenType {
    case display, headline, title, lede, body, bodyStrong, caption, label, eyebrow, metricXL, metric, metricSmall

    public var font: Font {
        switch self {
        case .display: ZenFont.brand(44)
        case .headline: ZenFont.brand(30)
        case .title: ZenFont.brand(22)
        case .lede: ZenFont.text(16)
        case .body: ZenFont.text(14)
        case .bodyStrong: ZenFont.text(14, .semibold)
        case .caption: ZenFont.text(12.5)
        case .label: ZenFont.text(13, .medium)
        case .eyebrow: ZenFont.number(10.5)
        case .metricXL: ZenFont.number(72)
        case .metric: ZenFont.number(28)
        case .metricSmall: ZenFont.number(15)
        }
    }

    public var tracking: CGFloat {
        switch self {
        case .display: -1.4
        case .headline: -0.9
        case .title: -0.4
        case .eyebrow: 1.05
        case .metricXL: -1
        default: 0
        }
    }

    public var lineSpacing: CGFloat {
        switch self {
        case .lede: 6
        case .body, .bodyStrong: 5
        case .caption: 3
        default: 0
        }
    }
}

extension View {
    /// `Text("…").zenType(.headline)`
    public func zenType(_ style: ZenType) -> some View {
        font(style.font).tracking(style.tracking).lineSpacing(style.lineSpacing)
    }
}

/// "PROMISE · 4H": Departure, caps, +0.1em.
public struct Eyebrow: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = Color.zen.textCaption) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased()).zenType(.eyebrow).foregroundStyle(color)
    }
}
