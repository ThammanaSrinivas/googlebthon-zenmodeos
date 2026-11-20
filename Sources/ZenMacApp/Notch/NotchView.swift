import SwiftUI
import Albeit

/// The black shape at the notch. At rest it is exactly the camera housing, so it can't be seen;
/// when Zeno speaks it grows down and out (352-ish × 126, radius 28), Zeno drops in on the left
/// and the words arrive one by one on the right.
struct NotchView: View {
    let model: NotchModel
    /// The physical notch; zero on a screen without one.
    let notch: CGSize

    static let openWidth: CGFloat = 376
    /// How faint the shape gets while the pointer is over it.
    static let hoverOpacity: Double = 0.14

    /// The open shape's size under a notch of `notch`.
    static func openSize(notch: CGSize, hasDetail: Bool) -> CGSize {
        CGSize(width: openWidth, height: notch.height + (hasDetail ? 108 : 92))
    }

    var body: some View {
        let top = notch.height
        let openHeight = Self.openSize(notch: notch, hasDetail: model.moment.detail != nil).height
        let width = model.isOpen ? Self.openWidth : notch.width
        let height = model.isOpen ? openHeight : notch.height
        let radius: CGFloat = model.isOpen ? 28 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.zen.island)
                content(top: top)
                    .frame(width: Self.openWidth, height: openHeight, alignment: .topLeading)
            }
            .frame(width: width, height: height, alignment: .top)
            .clipShape(shape)
            .shadow(color: .black.opacity(model.isOpen ? 0.32 : 0), radius: 26, y: 14)
            .opacity(model.isOpen && model.pointerOver ? Self.hoverOpacity : 1)
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
            RadialGradient(colors: [skin.glow.opacity(0.32), .clear], center: UnitPoint(x: 0.2, y: 1), startRadius: 0, endRadius: 200)
                .opacity(model.zenoIn ? 1 : 0)
                .animation(ZenMotion.calm(ZenMotion.t3), value: model.zenoIn)

            ZenoView(m.feeling, replay: model.replay)
                .frame(width: 108)
                .position(x: 70, y: top + 42)
                .offset(y: model.zenoIn ? 0 : -(top + 96))
                .opacity(model.zenoIn ? 1 : 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(m.kicker.uppercased())
                    .font(ZenFont.number(10)).tracking(1)
                    .foregroundStyle(skin.glow)
                    .opacity(model.wordsIn ? 1 : 0)
                    .offset(y: model.wordsIn ? 0 : 6)
                    .animation(ZenMotion.words, value: model.wordsIn)
                WordsArriving(line: m.line, shown: model.wordsIn, stagger: m.feeling == .sad || m.feeling == .sleepy ? 0.075 : 0.045)
                if let detail = m.detail {
                    Text(detail)
                        .font(ZenFont.text(12.5))
                        .foregroundStyle(Color.zen.islandDetail)
                        .opacity(model.wordsIn ? 1 : 0)
                        .offset(y: model.wordsIn ? 0 : 8)
                        .animation(ZenMotion.words.delay(0.25), value: model.wordsIn)
                }
            }
            .frame(width: Self.openWidth - 142 - 22, alignment: .leading)
            .offset(x: 142, y: top + 12)
        }
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
