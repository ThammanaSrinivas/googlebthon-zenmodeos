import SwiftUI
import Albeit

/// The black shape at the notch. At rest it is exactly the camera housing, so it can't be seen.
/// When Zeno speaks it pours out: it widens and drops (432 × up to ~180, radius 32) with curved shoulders
/// where it meets the menu bar, so it reads as one piece of black flowing out of the notch. Zeno
/// drops in on the left and the words arrive one by one on the right. An important moment also
/// wears a lit rim in the feeling's colour while it's up.
struct NotchView: View {
    let model: NotchModel
    /// The physical notch; zero on a screen without one.
    let notch: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let openWidth: CGFloat = 432
    /// The curve where the open shape meets the menu bar.
    static let shoulder: CGFloat = 12
    /// How faint the shape gets while the pointer is over it.
    static let hoverOpacity: Double = 0.14
    /// Zeno's column, and where the words start.
    static let zenoWidth: CGFloat = 124
    static let textX: CGFloat = 160

    /// The open shape's size under a notch of `notch` (its body, without the shoulders).
    static func openSize(notch: CGSize, hasDetail: Bool) -> CGSize {
        CGSize(width: openWidth, height: notch.height + (hasDetail ? 140 : 104))
    }

    var body: some View {
        let top = notch.height
        let open = model.isOpen
        let openHeight = Self.openSize(notch: notch, hasDetail: model.moment.detail != nil).height
        let shoulder = open && notch.height > 0 ? Self.shoulder : 0
        let width = (open ? Self.openWidth : notch.width) + shoulder * 2
        let height = open ? openHeight : notch.height
        let shape = NotchShape(radius: open ? 32 : 10, shoulder: shoulder)
        let glow = model.moment.feeling.skin.glow

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.zen.island)
                content(top: top)
                    .frame(width: Self.openWidth, height: openHeight, alignment: .topLeading)
                    // The words and Zeno surface out of the black rather than sliding in on a card.
                    .scaleEffect(open || reduceMotion ? 1 : 0.94, anchor: .top)
                    .blur(radius: open || reduceMotion ? 0 : 6)
                    .opacity(open ? 1 : 0)
                // The lit rim of an important moment: brightest along the bottom edge, nothing at the top.
                shape
                    .stroke(LinearGradient(colors: [glow.opacity(0), glow.opacity(0.55)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                    .opacity(model.attention && open ? 1 : 0)
                    .animation(ZenMotion.calm(ZenMotion.t3), value: model.attention)
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .shadow(color: .black.opacity(open ? 0.34 : 0), radius: 28, y: 14)
            .shadow(color: glow.opacity(model.attention && open ? 0.28 : 0), radius: 22, y: 10)
            .zenoHearing(open ? model.hearing : nil, glow: glow)
            .opacity(open && model.pointerOver ? Self.hoverOpacity : 1)
            .animation(ZenMotion.calm(ZenMotion.t2), value: model.pointerOver)
            Spacer(minLength: 0)
        }
        .frame(width: NotchPanelController.size.width, height: NotchPanelController.size.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isOpen ? "Zeno, \(model.moment.feeling.rawValue): \(model.moment.line)" : "Zeno")
    }

    private func content(top: CGFloat) -> some View {
        let m = model.moment
        let skin = m.feeling.skin
        return ZStack(alignment: .topLeading) {
            // A glow in the feeling's colour, low on Zeno's side.
            RadialGradient(colors: [skin.glow.opacity(m.important ? 0.4 : 0.32), .clear], center: UnitPoint(x: 0.18, y: 1),
                           startRadius: 0, endRadius: 230)
                .opacity(model.zenoIn ? 1 : 0)
                .animation(ZenMotion.calm(ZenMotion.t3), value: model.zenoIn)

            ZenoView(m.feeling, replay: model.replay)
                .frame(width: Self.zenoWidth)
                .position(x: 80, y: top + 50)
                .offset(y: model.zenoIn ? 0 : -(top + 110))
                .opacity(model.zenoIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(m.kicker.uppercased())
                    .font(ZenFont.number(11)).tracking(1)
                    .foregroundStyle(skin.glow)
                    .opacity(model.wordsIn ? 1 : 0)
                    .offset(y: model.wordsIn ? 0 : 6)
                    .animation(ZenMotion.words, value: model.wordsIn)
                WordsArriving(line: m.line, shown: model.wordsIn, stagger: m.feeling == .sad || m.feeling == .sleepy ? 0.075 : 0.045,
                              font: ZenFont.text(17, .semibold))
                if let detail = m.detail {
                    Text(detail)
                        .font(ZenFont.text(13.5))
                        .foregroundStyle(Color.zen.islandDetail)
                        .opacity(model.wordsIn ? 1 : 0)
                        .offset(y: model.wordsIn ? 0 : 8)
                        .animation(ZenMotion.words.delay(0.25), value: model.wordsIn)
                }
            }
            .frame(width: Self.openWidth - Self.textX - 26, alignment: .leading)
            .offset(x: Self.textX, y: top + 14)
        }
    }
}

/// The notch's outline: square at the top, rounded at the bottom, and (open) curved shoulders that
/// flare into the menu bar, the way liquid leaves a spout. Both radii animate.
struct NotchShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, shoulder) }
        set { radius = newValue.first; shoulder = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(0, min(shoulder, rect.width / 4, rect.height / 2))
        let r = max(0, min(radius, (rect.width - s * 2) / 2, rect.height - s))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// A line whose words arrive one after another: up 11 pt, out of a 5 pt blur.
struct WordsArriving: View {
    let line: String
    let shown: Bool
    var stagger: Double = 0.045
    var font: Font = ZenFont.text(15.5, .semibold)
    var color: Color = Color.zen.islandText

    var body: some View {
        let words = line.split(separator: " ").map(String.init)
        FlowLayout(spacing: 4.5, lineSpacing: 1) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                Text(word)
                    .font(font)
                    .tracking(-0.2)
                    .foregroundStyle(color)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 11)
                    .blur(radius: shown ? 0 : 5)
                    .animation(shown ? ZenMotion.words.delay(Double(i) * stagger) : ZenMotion.calm(0.18), value: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
    }
}

/// Lays words out left to right and wraps them.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Zeno hearing you, on Zeno's whole card (the notch's black shape, the Talk to Zeno island): a
/// drop shadow in Zeno's colour under the card that swells and deepens with your voice. A calm one
/// at silence, so it still reads as "listening" while you pause; none while Zeno talks or thinks.
/// Reduce Motion keeps the shadow and stops it following every syllable.
struct ZenoHearing: ViewModifier {
    let level: Double?
    let glow: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = level != nil
        let l = reduceMotion ? 0.3 : min(max(level ?? 0, 0), 1)
        return content
            // Two layers: a close drop shadow that grounds the card, and a wider one that blooms as you talk.
            .shadow(color: glow.opacity(on ? 0.55 : 0), radius: on ? 6 + 6 * l : 0, x: 0, y: on ? 8 : 0)
            .shadow(color: glow.opacity(on ? 0.35 + 0.5 * l : 0), radius: on ? 18 + 26 * l : 0, x: 0, y: on ? 14 + 12 * l : 0)
            .animation(.easeOut(duration: 0.14), value: l)
            .animation(ZenMotion.calm(ZenMotion.t2), value: on)
    }
}

extension View {
    func zenoHearing(_ level: Double?, glow: Color) -> some View { modifier(ZenoHearing(level: level, glow: glow)) }
}
