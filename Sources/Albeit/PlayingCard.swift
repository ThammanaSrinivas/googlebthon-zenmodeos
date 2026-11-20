import SwiftUI

// A ZenMode OS playing card: a lit face in one of Zeno's skins, an arched window with Zeno inside,
// a rank and a suit in the corners. Pattern cards are dealt as these.

/// The faces a card can wear: Zeno's skins and Albeit's surfaces, lit from the top.
public enum CardSkin: String, CaseIterable, Sendable {
    case zen, mint, gold, ember, dusk, paper, night

    private struct Hexes { let top, bottom, deep, rim, window, ink, glow: UInt32 }

    private var hexes: Hexes {
        switch self {
        case .zen: Hexes(top: 0xA6EDA2, bottom: 0x34AE41, deep: 0x0F5F1A, rim: 0xEDFFEA, window: 0xF4FFF1, ink: 0x0A140B, glow: 0x5BDF62)
        case .mint: Hexes(top: 0xF1FAEE, bottom: 0xA9D9A2, deep: 0x2F6B35, rim: 0xFFFFFF, window: 0xF6FCF4, ink: 0x0A140B, glow: 0x5BDF62)
        case .gold: Hexes(top: 0xFFE9A8, bottom: 0xFFBE2E, deep: 0xC96E00, rim: 0xFFFAE6, window: 0xFFFBEA, ink: 0x1A1003, glow: 0xFFC800)
        case .ember: Hexes(top: 0xFFCDA8, bottom: 0xFF7C30, deep: 0xB43F00, rim: 0xFFF1E6, window: 0xFFF6EE, ink: 0x1C0A02, glow: 0xFF8A3D)
        case .dusk: Hexes(top: 0xE2EADE, bottom: 0x93A88F, deep: 0x4D654A, rim: 0xF7FAF5, window: 0xFAFCF8, ink: 0x0F160F, glow: 0xB9CDB5)
        case .paper: Hexes(top: 0xFFFFFF, bottom: 0xE4E1D7, deep: 0xA9A69A, rim: 0xFFFFFF, window: 0xF6F5F0, ink: 0x12160F, glow: 0xFFC800)
        case .night: Hexes(top: 0x26332A, bottom: 0x0B0E0B, deep: 0x000000, rim: 0x5BDF62, window: 0x161A16, ink: 0xF2F3EE, glow: 0x5BDF62)
        }
    }

    public var top: Color { Color(hex: hexes.top) }
    public var bottom: Color { Color(hex: hexes.bottom) }
    /// The card's edge and the plinth under the window.
    public var deep: Color { Color(hex: hexes.deep) }
    public var rim: Color { Color(hex: hexes.rim) }
    public var window: Color { Color(hex: hexes.window) }
    /// Text on the face.
    public var ink: Color { Color(hex: hexes.ink) }
    /// The light behind Zeno, and the card's hue wherever it is quoted (charts, overlays).
    public var glow: Color { Color(hex: hexes.glow) }
    public var isDark: Bool { self == .night }
}

public enum CardSuit: String, CaseIterable, Sendable {
    case spade, heart, diamond, club

    public var symbol: String { "suit.\(rawValue).fill" }
    public var name: String { rawValue + "s" }
}

/// The arched window: a rectangle under a half circle.
public struct ArchShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// One card, drawn whole at `width` (its height is `width × 1.4`). Scale the view, never the parts.
public struct PlayingCard: View {
    let rank: String
    let suit: CardSuit
    let skin: CardSkin
    let feeling: ZenoFeeling
    let title: String
    let line: String
    let width: CGFloat
    /// A live, breathing Zeno (one card on screen) or a still one (a deck, a rendered image).
    let liveZeno: Bool

    public static let aspect: CGFloat = 1.4

    public init(rank: String, suit: CardSuit, skin: CardSkin, feeling: ZenoFeeling, title: String, line: String,
                width: CGFloat, liveZeno: Bool = false) {
        self.rank = rank
        self.suit = suit
        self.skin = skin
        self.feeling = feeling
        self.title = title
        self.line = line
        self.width = width
        self.liveZeno = liveZeno
    }

    public var body: some View {
        let w = width, h = width * Self.aspect
        let face = RoundedRectangle(cornerRadius: w * 0.085, style: .continuous)

        ZStack {
            face.fill(LinearGradient(colors: [skin.top, skin.bottom], startPoint: .top, endPoint: .bottom))
            // The key light, from the upper left.
            face.fill(RadialGradient(colors: [.white.opacity(skin.isDark ? 0.10 : 0.42), .white.opacity(0)],
                                     center: UnitPoint(x: 0.18, y: 0), startRadius: 0, endRadius: w * 0.95))
            RoundedRectangle(cornerRadius: w * 0.055, style: .continuous)
                .strokeBorder(skin.rim.opacity(skin.isDark ? 0.32 : 0.8), lineWidth: max(1, w * 0.008))
                .padding(w * 0.045)

            VStack(spacing: 0) {
                window(w: w, h: h).padding(.top, h * 0.085)
                Capsule().fill(skin.deep.opacity(skin.isDark ? 0.9 : 0.42))
                    .frame(width: w * 0.64, height: max(2, w * 0.022))
                Text(title)
                    .font(ZenFont.brand(max(20, w * 0.128))).tracking(-0.3)
                    .foregroundStyle(skin.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, w * 0.1)
                    .padding(.top, h * 0.035)
                Text(line)
                    .font(ZenFont.text(max(10, w * 0.07), .medium))
                    .foregroundStyle(skin.ink.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, w * 0.13)
                    .padding(.top, h * 0.012)
                Spacer(minLength: 0)
            }

            corner(w).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, w * 0.08).padding(.top, w * 0.075)
            corner(w).rotationEffect(.degrees(180)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, w * 0.08).padding(.bottom, w * 0.075)

            // Gloss: a sheen across the top half, as on a lacquered card.
            face.fill(LinearGradient(stops: [.init(color: .white.opacity(skin.isDark ? 0.08 : 0.24), location: 0),
                                             .init(color: .white.opacity(0), location: 0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .frame(width: w, height: h)
        .clipShape(face)
        .overlay(face.strokeBorder(skin.deep.opacity(skin.isDark ? 1 : 0.5), lineWidth: max(1, w * 0.006)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank) of \(suit.name). \(title). \(line)")
    }

    private func corner(_ w: CGFloat) -> some View {
        VStack(spacing: w * 0.012) {
            Text(rank).font(ZenFont.number(w * 0.13)).tracking(-0.5)
            Image(systemName: suit.symbol).font(.system(size: w * 0.08, weight: .semibold))
        }
        .foregroundStyle(skin.ink.opacity(0.9))
    }

    private func window(w: CGFloat, h: CGFloat) -> some View {
        let aw = w * 0.56, ah = h * 0.4
        let brass = Color(hex: skin.isDark ? 0x5BDF62 : 0xFFD86B)
        return ZStack(alignment: .bottom) {
            ArchShape().fill(LinearGradient(colors: [skin.window, skin.window.opacity(0.94)], startPoint: .top, endPoint: .bottom))
            ArchShape().fill(RadialGradient(colors: [skin.glow.opacity(skin.isDark ? 0.3 : 0.38), skin.glow.opacity(0)],
                                            center: UnitPoint(x: 0.5, y: 0.92), startRadius: 0, endRadius: aw * 0.7))
            Group {
                if liveZeno { ZenoView(feeling) } else { ZenoStill(feeling) }
            }
            .frame(width: aw * 0.72)
            .padding(.bottom, ah * 0.08)
        }
        .frame(width: aw, height: ah)
        .clipShape(ArchShape())
        .overlay(ArchShape().stroke(skin.deep.opacity(skin.isDark ? 0.9 : 0.35), lineWidth: w * 0.03))
        .overlay(ArchShape().stroke(brass, lineWidth: max(1, w * 0.011)))
        .overlay(alignment: .top) {
            Circle().fill(brass)
                .overlay(Circle().stroke(skin.deep.opacity(0.4), lineWidth: 0.8))
                .frame(width: w * 0.055, height: w * 0.055)
                .offset(y: -w * 0.026)
        }
    }
}
