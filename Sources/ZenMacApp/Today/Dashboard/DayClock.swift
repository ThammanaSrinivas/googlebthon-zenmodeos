import SwiftUI
import Albeit

/// The day as a clock: midnight at the top, one turn a day. The outer ring is this Mac, a session per
/// arc; the inner ring is the iPhone, drawn sealed, because its minutes never leave it.
struct DayClockCard: View {
    let day: DayInsight
    @State private var hovered: UsageSession?

    var body: some View {
        DashCard("The day as a clock", eyebrow: "Midnight at the top") {
            VStack(spacing: ZenSpace.s3) {
                DayDial(day: day, hovered: $hovered)
                    .id(day.id)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ringKey
                detailLine
            }
        }
    }

    private var ringKey: some View {
        HStack(spacing: ZenSpace.s4) {
            if let mac = day.mac {
                HStack(spacing: 6) {
                    Circle().strokeBorder(Color.zen.textHeading.opacity(0.55), lineWidth: 3).frame(width: 11, height: 11)
                    Text("Mac").font(ZenFont.text(12, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(durationText(mac.minutes)).font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                }
            }
            if let phone = day.screens.first(where: \.isSealed) {
                HStack(spacing: 6) {
                    Circle().strokeBorder(Color.zen.textCaption.opacity(0.7), style: StrokeStyle(lineWidth: 1.4, dash: [1.5, 2.5])).frame(width: 11, height: 11)
                    Text("iPhone").font(ZenFont.text(12, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(phone.score.text).font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                    Image(systemName: "lock.fill").font(.system(size: 8.5)).foregroundStyle(Color.zen.textCaption)
                }
                .help("Only the Zen Score leaves your iPhone. Its minutes stay on it.")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What's under the pointer, or the day's longest focus.
    private var detailLine: some View {
        let s = hovered ?? day.longestFocus
        return HStack(spacing: 6) {
            if let s {
                RoundedRectangle(cornerRadius: ZenRadius.cell).fill(s.feel.color).frame(width: 8, height: 8)
                if hovered == nil { Text("Longest focus").font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption) }
                Text("\(clockText(s.start))–\(clockText(s.end))").font(ZenFont.number(11.5)).foregroundStyle(Color.zen.textHeading)
                Text("· \(s.app) · \(durationText(s.minutes))").font(ZenFont.text(12, .medium)).foregroundStyle(Color.zen.textBody)
                    .lineLimit(1)
            } else {
                Text("Nothing measured yet. The day counts itself.").font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
            }
        }
        .frame(height: 16)
        .animation(ZenMotion.calm(ZenMotion.t1), value: hovered)
    }
}

/// Where everything sits on the dial.
private struct DialGeometry {
    let center: CGPoint
    let radius: CGFloat

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = min(size.width, size.height) / 2 - 2
    }

    var tickR: CGFloat { radius - 15 }
    var macR: CGFloat { radius - 30 }
    var macWidth: CGFloat { max(9, radius * 0.085) }
    var phoneR: CGFloat { radius - 47 }

    /// Midnight at the top, clockwise.
    func angle(_ minute: Double) -> Angle { .radians(minute / 1440 * 2 * .pi - .pi / 2) }

    func point(_ minute: Double, _ r: CGFloat) -> CGPoint {
        let a = angle(minute).radians
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }

    /// The session on the Mac's ring under `p`, if any.
    func session(at p: CGPoint, in day: DayInsight) -> UsageSession? {
        let dx = p.x - center.x, dy = p.y - center.y
        guard abs(hypot(dx, dy) - macR) <= macWidth / 2 + 6 else { return nil }
        var a = atan2(dy, dx) + .pi / 2
        if a < 0 { a += 2 * .pi }
        let minute = Double(a) / (2 * .pi) * 1440
        return day.sessions.first { Double($0.start) - 3 <= minute && minute <= Double($0.end) + 3 }
    }
}

private struct DayDial: View {
    let day: DayInsight
    @Binding var hovered: UsageSession?

    var body: some View {
        GeometryReader { geo in
            let g = DialGeometry(size: geo.size)
            ZStack {
                Canvas { ctx, _ in draw(&ctx, g) }
                VStack(spacing: 3) {
                    Text(durationText(day.minutes)).font(ZenFont.number(max(18, g.radius * 0.17))).foregroundStyle(Color.zen.textHeading)
                    // The Zen Score lives in Today's hero; the dial keeps to this Mac's time.
                    Text("on this Mac").font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                }
                .position(g.center)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): if g.session(at: p, in: day) != hovered { hovered = g.session(at: p, in: day) }
                case .ended: hovered = nil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(day))
    }

    private func draw(_ ctx: inout GraphicsContext, _ g: DialGeometry) {
        let ink = Color.zen.textHeading
        let now = Double(day.now)

        // A cell every quarter hour, larger on the hour and at 00, 06, 12, 18. Hours to come are faint.
        for q in 0..<96 {
            let m = Double(q * 15)
            let size: CGFloat = q % 24 == 0 ? 0 : (q % 4 == 0 ? 2.6 : 1.3)
            guard size > 0 else { continue }
            let p = g.point(m, g.tickR)
            ctx.fill(Path(roundedRect: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), cornerRadius: 0.5),
                     with: .color(ink.opacity(m <= now ? 0.4 : 0.14)))
        }
        for (m, label) in [(0.0, "00"), (360.0, "06"), (720.0, "12"), (1080.0, "18")] {
            ctx.draw(Text(label).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption), at: g.point(m, g.tickR), anchor: .center)
        }

        // The Mac's ring: a sunk track, the hours gone a shade deeper, then one arc per session.
        var track = Path()
        track.addArc(center: g.center, radius: g.macR, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        ctx.stroke(track, with: .color(ink.opacity(0.05)), lineWidth: g.macWidth)
        var gone = Path()
        gone.addArc(center: g.center, radius: g.macR, startAngle: g.angle(0), endAngle: g.angle(now), clockwise: false)
        ctx.stroke(gone, with: .color(ink.opacity(0.06)), lineWidth: g.macWidth)

        for s in day.sessions {
            let lit = hovered == nil || hovered == s
            var arc = Path()
            arc.addArc(center: g.center, radius: g.macR, startAngle: g.angle(Double(s.start)),
                       endAngle: g.angle(Double(s.end) - 0.8), clockwise: false)
            ctx.stroke(arc, with: .color(s.feel.color.opacity(lit ? 1 : 0.35)),
                       lineWidth: hovered == s ? g.macWidth + 5 : g.macWidth)
        }

        // The iPhone's ring: sealed. Its minutes stay on the phone.
        var phone = Path()
        phone.addArc(center: g.center, radius: g.phoneR, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        ctx.stroke(phone, with: .color(Color.zen.textCaption.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 5]))

        // Now: a hand from inside the iPhone's ring to the ticks.
        if day.isToday {
            var hand = Path()
            hand.move(to: g.point(now, g.phoneR + 6))
            hand.addLine(to: g.point(now, g.tickR + 4))
            ctx.stroke(hand, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            let tip = g.point(now, g.tickR + 4)
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(ink))
        }
    }

    static func summary(_ day: DayInsight) -> String {
        let feels = Feel.allCases.map { "\($0.rawValue) \(durationText(day.minutes($0)))" }.joined(separator: ", ")
        return "The day as a clock. This Mac: \(durationText(day.minutes)), \(feels). iPhone: Zen Score \(day.screens.first(where: \.isSealed)?.score.text ?? "none"), minutes stay on the phone."
    }
}
