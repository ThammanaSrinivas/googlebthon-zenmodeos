import SwiftUI
import Albeit

/// The Zen Gold coin: a reeded edge, a polished face, an engraved ring and the ZenMode OS mark
/// struck in relief. With `glint`, a band of light crosses it once (never under Reduce Motion).
struct GoldCoin: View {
    var glint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -1.2

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // The edge, turned and reeded.
                Circle().fill(AngularGradient(colors: [Color(hex: 0xC98A00), Color(hex: 0xFFE59A), Color(hex: 0xB87400),
                                                       Color(hex: 0xFFD86B), Color(hex: 0xA86800), Color(hex: 0xC98A00)],
                                              center: .center))
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
                    let ticks = s < 40 ? 0 : 84
                    for k in 0..<ticks {
                        let a = Double(k) / Double(ticks) * 2 * .pi
                        var p = Path()
                        p.move(to: CGPoint(x: c.x + cos(a) * r * 0.93, y: c.y + sin(a) * r * 0.93))
                        p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.995, y: c.y + sin(a) * r * 0.995))
                        ctx.stroke(p, with: .color(Color(hex: 0x6E4500, alpha: 0.35)), lineWidth: max(0.5, r * 0.012))
                    }
                }
                // The face.
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF3C4), Color(hex: 0xFFCF33), Color(hex: 0xE0A000), Color(hex: 0xB97A00)],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: s * 0.62))
                    .padding(s * 0.075)
                    .shadow(color: Color(hex: 0x6E4500, alpha: 0.35), radius: s * 0.01, y: s * 0.008)
                // An engraved ring: a dark cut with a lit lip.
                Circle().strokeBorder(Color(hex: 0x8A5A00, alpha: 0.55), lineWidth: max(0.6, s * 0.014)).padding(s * 0.15)
                Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: max(0.4, s * 0.007)).padding(s * 0.165)
                // The mark in relief: light from the top left, shadow to the bottom right.
                let mark = s * 0.38
                ZenMark().fill(Color.white.opacity(0.65), style: FillStyle(eoFill: true))
                    .frame(width: mark, height: mark).offset(x: -s * 0.007, y: -s * 0.007)
                ZenMark().fill(Color(hex: 0x6E4500, alpha: 0.75), style: FillStyle(eoFill: true))
                    .frame(width: mark, height: mark).offset(x: s * 0.009, y: s * 0.009)
                ZenMark().fill(LinearGradient(colors: [Color(hex: 0xFFE27A), Color(hex: 0xE3A400)], startPoint: .topLeading, endPoint: .bottomTrailing),
                               style: FillStyle(eoFill: true))
                    .frame(width: mark, height: mark)
                // The glint.
                LinearGradient(colors: [.clear, Color.white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: s * 0.3, height: s * 1.5)
                    .rotationEffect(.degrees(24))
                    .offset(x: sweep * s)
                    .blendMode(.plusLighter)
                    .mask(Circle())
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { if glint { shine() } }
        .onChange(of: glint) { _, on in if on { shine() } }
    }

    private func shine() {
        guard !reduceMotion else { return }
        sweep = -1.2
        withAnimation(.easeInOut(duration: 1.1).delay(0.35)) { sweep = 1.2 }
    }
}

/// Today's price as a line: green above the previous close, ember below it, with the previous
/// close dashed across. Drawn from real one-minute closes only.
struct GoldSparkline: View {
    let points: [Int]
    let previousClose: Int

    var body: some View {
        Canvas { ctx, size in
            guard points.count > 1 else { return }
            // Scale to the day itself, so its movement reads; the previous close shows only if it
            // falls inside that range (it's always in the stamp below).
            let lo = points.min()!, hi = points.max()!
            let span = max(hi - lo, 1)
            let baselineInRange = previousClose >= lo && previousClose <= hi
            func y(_ v: Int) -> CGFloat { size.height - CGFloat(v - lo) / CGFloat(span) * (size.height - 4) - 2 }
            let step = size.width / CGFloat(points.count - 1)
            var line = Path()
            for (i, v) in points.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            let up = points.last! >= previousClose
            let hue = up ? Color(hex: 0x5BDF62) : Color(hex: 0xFF8A3D)
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [hue.opacity(0.28), hue.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            if baselineInRange {
                var base = Path()
                base.move(to: CGPoint(x: 0, y: y(previousClose)))
                base.addLine(to: CGPoint(x: size.width, y: y(previousClose)))
                ctx.stroke(base, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ctx.stroke(line, with: .color(hue), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let last = CGPoint(x: size.width, y: y(points.last!))
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(hue))
        }
        .accessibilityHidden(true)
    }
}

/// A terms link: plain words in the link's colour, opening zenmodeos.com. The colour already says
/// "link", so there's no arrow; hover deepens it (lighter on ink) and underlines it, a press dims
/// it, and the keyboard gets a ring. `underlined` keeps a dotted line for a link whose colour
/// alone wouldn't set it apart (grey on the ink card).
struct TermsLink: View {
    let title: String
    let url: URL
    var color: Color = Color.zen.textBrand
    var hoverColor: Color = TermsLink.brandHover
    var underlined = false

    static let brandHover = Color(light: 0x0A5C12, dark: 0x8AF08F)
    static let amberHover = Color(light: 0x5A4200, dark: 0xFFE7A3)

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(title) { openURL(url) }
            .buttonStyle(TermsLinkStyle(color: color, hoverColor: hoverColor, underlined: underlined))
            .focusEffectDisabled()
            .help(url.absoluteString)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAddTraits(.isLink)
            .accessibilityHint("Opens zenmodeos.com in your browser")
    }
}

private struct TermsLinkStyle: ButtonStyle {
    let color: Color
    let hoverColor: Color
    let underlined: Bool

    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration, color: color, hoverColor: hoverColor, underlined: underlined)
    }

    private struct LinkBody: View {
        let configuration: Configuration
        let color: Color
        let hoverColor: Color
        let underlined: Bool
        @State private var hovering = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(ZenFont.text(12, .semibold))
                .underline(hovering || focused || underlined, pattern: hovering || focused ? .solid : .dot, color: hovering ? hoverColor : color)
                .foregroundStyle(hovering ? hoverColor : color)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color, lineWidth: 1.5).padding(-4)
                    }
                }
                .onHover { hovering = $0 }
                .pointerStyle(.link)
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: hovering)
        }
    }
}
