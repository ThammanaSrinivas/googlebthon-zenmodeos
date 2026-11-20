import SwiftUI

// MARK: - The mark and the lockup

/// The ZenMode OS mark: a 100 square with an 8 % cut at 45°, 8 radii and a 12 % dot.
public struct ZenMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 32.18
        return Self.base.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: s, y: s))
    }

    static let base = SVGPath.parse("M29.708 0.13C31.07 0.15 32.17 1.27 32.15 2.63L32.03 11.72C32.02 12.36 31.77 12.97 31.33 13.42L13.76 31.44C13.3 31.91 12.66 32.18 11.99 32.18H2.47C1.11 32.18 0 31.07 0 29.71V20.66C0 20 0.26 19.37 0.72 18.91L18.89 0.74C19.36 0.27 20.01 0.01 20.67 0.01L29.708 0.13ZM27.97 20.3C29.53 18.75 32.18 19.85 32.18 22.04V29.72C32.18 31.08 31.08 32.18 29.72 32.18H22.04C19.85 32.18 18.75 29.53 20.3 27.97L24.14 24.14L27.97 20.3ZM16.04 14.11C14.97 14.11 14.11 14.98 14.11 16.04C14.11 17.1 14.97 17.96 16.04 17.96C17.1 17.96 17.96 17.1 17.96 16.04C17.96 14.98 17.1 14.11 16.04 14.11ZM10.14 0C12.34 0 13.44 2.66 11.88 4.21L4.21 11.88C2.66 13.44 0 12.34 0 10.14V2.46C0 1.1 1.1 0 2.46 0H10.14Z")
}

/// "ZenMode OS", with the OS in the gradient.
public struct ZenLockup: View {
    var size: CGFloat

    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        HStack(spacing: size * 0.4) {
            ZenMark().fill(Color.zen.textHeading, style: FillStyle(eoFill: true))
                .frame(width: size * 1.05, height: size * 1.05)
            HStack(spacing: size * 0.22) {
                Text("ZenMode").foregroundStyle(Color.zen.textHeading)
                Text("OS").foregroundStyle(ZenGradient.os)
            }
            .font(ZenFont.brand(size))
            .tracking(-0.3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ZenMode OS")
    }
}

/// A small parser for the absolute SVG commands the mark uses (M L H V C Z).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var number = ""
        for ch in d {
            if ch.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if ch == "-" && !number.isEmpty && !number.hasSuffix("e") {
                tokens.append(number); number = "-"
            } else {
                number.append(ch)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var i = 0, command = "M", current = CGPoint.zero
        func next() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            switch command {
            case "M": current = CGPoint(x: next(), y: next()); path.move(to: current); command = "L"
            case "L": current = CGPoint(x: next(), y: next()); path.addLine(to: current)
            case "H": current.x = next(); path.addLine(to: current)
            case "V": current.y = next(); path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: next(), y: next()), c2 = CGPoint(x: next(), y: next())
                current = CGPoint(x: next(), y: next())
                path.addCurve(to: current, control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: i += 1
            }
        }
        return path
    }
}

// MARK: - Cells, not circles

/// A row of 12 pt cells: filled, on (amber), or empty. Progress, weeks and promises are drawn this way.
public struct CellRow: View {
    public enum Fill { case empty, on, reward }

    var cells: [Fill]
    var size: CGFloat
    var onColor: Color

    public init(_ cells: [Fill], size: CGFloat = ZenGrid.cell, onColor: Color = Color.zen.brandFill) {
        self.cells = cells
        self.size = size
        self.onColor = onColor
    }

    public init(filled: Int, of total: Int, size: CGFloat = ZenGrid.cell, onColor: Color = Color.zen.brandFill) {
        self.init((0..<total).map { $0 < filled ? .on : .empty }, size: size, onColor: onColor)
    }

    public var body: some View {
        HStack(spacing: size / 4) {
            ForEach(cells.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                    .fill(color(cells[i]))
                    .overlay {
                        if cells[i] == .empty {
                            RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                                .strokeBorder(Color.zen.borderOutline.opacity(0.7), lineWidth: 1)
                        }
                    }
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ f: Fill) -> Color {
        switch f {
        case .empty: Color.zen.textHeading.opacity(0.04)
        case .on: onColor
        case .reward: Color.zen.accentReward
        }
    }
}

// MARK: - The score

/// The score, huge, in the score gradient. One focal point per screen.
public struct ScoreText: View {
    var text: String
    var size: CGFloat

    public init(_ text: String, size: CGFloat = 72) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(ZenFont.number(size))
            .tracking(-size * 0.02)
            .foregroundStyle(ZenGradient.score)
            .monospacedDigit()
    }
}

// MARK: - Glass

extension View {
    /// A card of Liquid Glass over the lit backdrop, with Albeit's hairline and soft shadow.
    public func glassCard(radius: CGFloat = ZenRadius.xxl, tint: Color? = nil) -> some View {
        self
            .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: .rect(cornerRadius: radius))
            .modifier(ZenLift())
    }
}

/// The lift under a card: a thin contact shadow and a wide, faint ambient one. Light enough that
/// a page of cards reads as paper on paper, never a stack of heavy slabs. Dark mode lets the glass
/// edge do the work and keeps only a whisper of shadow.
public struct ZenLift: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .shadow(color: Color(hex: 0x12160F, alpha: dark ? 0.18 : 0.05), radius: 1.5, y: 1)
            .shadow(color: Color(hex: 0x12160F, alpha: dark ? 0.22 : 0.06), radius: 18, y: 10)
    }
}

/// A small honest label on anything that isn't real yet.
public struct DemoTag: View {
    var text: String
    public init(_ text: String = "Demo data") { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(ZenFont.number(9.5)).tracking(0.9)
            .foregroundStyle(Color.zen.accentRewardText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.zen.accentRewardTint))
            .accessibilityLabel(text)
    }
}
