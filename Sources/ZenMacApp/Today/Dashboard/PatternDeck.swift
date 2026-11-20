import SwiftUI
import Albeit

/// The pattern cards, fanned like a hand on a dark table. The strongest pattern in the person's own
/// use is dealt in the middle and on top; the rest fan out from it in order, right then left.
/// Tap one to open it.
struct PatternDeckCard: View {
    @Environment(AppModel.self) private var model
    @State private var hovered: PatternCard.ID?

    /// Cards are drawn at this width and scaled as a whole to fit.
    static let cardWidth: CGFloat = 150

    var body: some View {
        let dash = model.dashboard
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text("Your pattern cards").font(ZenFont.brand(20)).tracking(-0.4).foregroundStyle(Color.zen.islandText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Eyebrow("Last 14 days · tap a card", color: Color.zen.islandDetail)
            }
            .padding(.horizontal, ZenSpace.s5)
            .padding(.top, ZenSpace.s5)

            GeometryReader { geo in
                fan(dash.cards, openID: dash.openCard?.id, in: geo.size, dash: dash)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckStage())
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color(hex: 0x12160F, alpha: 0.22), radius: 22, y: 14)
    }

    private func fan(_ cards: [PatternCard], openID: PatternCard.ID?, in size: CGSize, dash: DashboardModel) -> some View {
        let n = cards.count
        let w = Self.cardWidth, h = w * PlayingCard.aspect
        let scale = min(0.92, size.width / 660, (size.height + 40) / 320)
        let step = n > 1 ? min(12.5, 75 / Double(n - 1)) : 0
        let reach = w * 2.55 * scale
        let topY = h * scale / 2 + 16

        return ZStack {
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                // 0, +1, −1, +2, −2 …: the strongest in the middle.
                let slot = i == 0 ? 0 : (i % 2 == 1 ? (i + 1) / 2 : -(i / 2))
                let theta = Double(slot) * step * .pi / 180
                let isHovered = hovered == card.id
                let lift: CGFloat = (isHovered ? 26 : (slot == 0 ? 12 : 0)) * scale
                let x = size.width / 2 + reach * CGFloat(sin(theta)) + lift * CGFloat(sin(theta))
                let y = topY + reach * CGFloat(1 - cos(theta)) - lift * CGFloat(cos(theta))

                Button { dash.open(card) } label: {
                    PlayingCard(rank: dash.rank(of: card), suit: card.suit, skin: card.skin, feeling: card.feeling,
                                title: card.title, line: card.face, width: w)
                        // Leans toward the pointer and throws a shadow in the card's own colour.
                        .modifier(HoverTilt(glow: card.feeling.skin.glow, maxAngle: 14))
                }
                .buttonStyle(CardPressStyle())
                .scaleEffect(scale * (isHovered ? 1.06 : 1))
                .rotationEffect(.radians(theta))
                .position(x: x, y: y)
                .zIndex(isHovered ? 100 : Double(n - abs(slot)))
                .opacity(openID == card.id ? 0 : 1)
                .onHover { inside in
                    if inside { hovered = card.id } else if hovered == card.id { hovered = nil }
                }
                .pointerStyle(.link)
                .help("\(card.title): \(card.face)")
                .accessibilityHint("Opens the card")
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: hovered)
        .animation(ZenMotion.container, value: openID)
    }
}

/// A press sinks the card a touch.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
    }
}

/// The table the deck is dealt on: ink, a green light under the hand, a faint amber one, the cell
/// grid, and a few sparkles that breathe.
private struct DeckStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var twinkle = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x172019), Color(hex: 0x070907)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x5BDF62, alpha: 0.26), .clear], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Color(hex: 0xFFC800, alpha: 0.13), .clear], center: UnitPoint(x: 0.82, y: 0.1), startRadius: 0, endRadius: 220)
            Canvas { ctx, size in
                let step = ZenGrid.cell + ZenGrid.gap
                for r in 0..<Int(size.height / step) + 1 {
                    for c in 0..<Int(size.width / step) + 1 {
                        let x = CGFloat(c) * step + 4, y = CGFloat(r) * step + 4
                        let dx = (x - size.width / 2) / size.width, dy = (y - size.height * 0.6) / size.height
                        let a = 0.045 * exp(-(dx * dx + dy * dy) * 5)
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: ZenGrid.cell, height: ZenGrid.cell), cornerRadius: ZenRadius.cell),
                                 with: .color(.white.opacity(a)))
                    }
                }
            }
            GeometryReader { geo in
                ForEach(Array(Self.sparkles.enumerated()), id: \.offset) { i, s in
                    Image(systemName: "sparkle")
                        .font(.system(size: s.size, weight: .bold))
                        .foregroundStyle(i % 2 == 0 ? Color.zen.accentReward : .white)
                        .opacity(reduceMotion ? 0.7 : (twinkle ? 0.95 : 0.25))
                        .scaleEffect(reduceMotion ? 1 : (twinkle ? 1 : 0.7))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.8 + Double(i) * 0.35).repeatForever().delay(Double(i) * 0.4), value: twinkle)
                        .position(x: geo.size.width * s.x, y: geo.size.height * s.y)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { twinkle = true }
    }

    private static let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.08, 0.62, 16), (0.93, 0.5, 11), (0.16, 0.24, 8), (0.86, 0.86, 9), (0.5, 0.95, 7),
    ]
}
