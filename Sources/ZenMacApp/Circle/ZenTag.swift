import SwiftUI
import Albeit

/// A Zen Card (Albeit §17): one insight on a punched tag. A 1 pt frame in the tone's deep colour,
/// a dashed inner rule, three punch holes, a horizon seeded by the account, then the question, the
/// answer in Clash (under 26 letters), one line with the real number, and a signature. White
/// inside, never paper, in either theme: it's an object, like a luggage tag.
struct ZenTag: View {
    enum Tone {
        case zen, amber

        var deep: Color { self == .zen ? Color(hex: 0x0F7A18) : Color(hex: 0xE5B400) }
        var question: Color { self == .zen ? Color(hex: 0x0F7A18) : Color(hex: 0x7A5A00) }
        var sky: (UInt32, UInt32) { self == .zen ? (0xD8ECD3, 0xFFF4D3) : (0xFFEBB5, 0xFFF7E2) }
        var hills: [UInt32] { self == .zen ? [0xB9DDB4, 0x86C784, 0x3E9B47] : [0xFFD98A, 0xF2B640, 0xC98A12] }
        var sun: UInt32 { self == .zen ? 0xFFF7D6 : 0xFFFBEA }
    }

    let tone: Tone
    let question: String
    let answer: String
    let detail: String
    /// The account's seed, so the horizon is the same every time and a rename never changes it.
    let seed: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HorizonStrip(tone: tone, seed: seed)
                .frame(height: 112)
                .overlay(alignment: .top) { punchHoles.padding(.top, 9) }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(question).font(ZenFont.text(12.5, .medium)).foregroundStyle(tone.question)
                Text(answer).font(ZenFont.brand(21)).tracking(-0.3).foregroundStyle(Color(hex: 0x12160F))
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(detail).font(ZenFont.text(13)).foregroundStyle(Color(hex: 0x4A4F46))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ZenSpace.s2)
                Text(CircleCopy.tagSignature).font(ZenFont.number(9)).tracking(0.7).foregroundStyle(Color(hex: 0x8B9086))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12)
        }
        .frame(width: 212, height: 290)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(tone.deep.opacity(0.45))
                .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(tone.deep, lineWidth: 1))
        .modifier(ZenLift())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(question) \(answer). \(detail)")
    }

    private var punchHoles: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Color.zen.surfaceBase)
                    .overlay(Circle().strokeBorder(tone.deep.opacity(0.35), lineWidth: 1))
                    .frame(width: 11, height: 11)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The top half of a Zen Card: a sky in the tone, a low sun, three ridges of hills seeded by the
/// account. Quiet enough to sit above text.
struct HorizonStrip: View {
    let tone: ZenTag.Tone
    let seed: UInt64

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: tone.sky.0), Color(hex: tone.sky.1)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let sunX = w * (0.25 + 0.5 * unit(1)), sunR = h * 0.17
            ctx.fill(Path(ellipseIn: CGRect(x: sunX - sunR, y: h * 0.34 - sunR, width: sunR * 2, height: sunR * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: tone.sun), Color(hex: tone.sun, alpha: 0)]),
                                           center: CGPoint(x: sunX, y: h * 0.34), startRadius: sunR * 0.6, endRadius: sunR * 2.2))
            for (i, hex) in tone.hills.enumerated() {
                let base = h * (0.52 + 0.14 * Double(i))
                let amp = h * (0.12 - 0.025 * Double(i))
                let f1 = 1.2 + 2.2 * unit(10 + i), f2 = 3.1 + 2.6 * unit(20 + i), ph = unit(30 + i) * .pi * 2
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h))
                for step in 0...48 {
                    let x = w * Double(step) / 48, t = Double(step) / 48
                    let y = base - amp * (0.6 * sin(t * f1 * .pi + ph) + 0.4 * sin(t * f2 * .pi + ph * 1.7))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: hex)))
            }
        }
        .accessibilityHidden(true)
    }

    /// A stable number in 0..<1 for slot `i` of this seed.
    private func unit(_ i: Int) -> Double {
        var x = seed &+ UInt64(i) &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }
}
