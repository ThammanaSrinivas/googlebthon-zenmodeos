import SwiftUI

/// Zeno, alive: breathes, blinks, and plays a feeling's arrival whenever `feeling` (or `replay`) changes.
/// One Zeno, never redrawn: scale this view, never the parts. Decorative for VoiceOver; the line
/// beside Zeno carries the meaning.
public struct ZenoView: View {
    public var feeling: ZenoFeeling
    public var replay: Int

    @State private var animator: ZenoAnimator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ feeling: ZenoFeeling, replay: Int = 0) {
        self.feeling = feeling
        self.replay = replay
        _animator = State(initialValue: ZenoAnimator(feeling: feeling))
    }

    /// Width / height of Zeno's drawing space.
    public static let aspectRatio: CGFloat = 210 / 160
    /// How much bigger the canvas is than the layout box, so hops and sparkles aren't clipped.
    static let overscan: CGFloat = 1.7

    public var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 120)) { timeline in
                let state = animator.sample(at: timeline.date.timeIntervalSinceReferenceDate)
                Canvas { ctx, size in
                    let inner = CGSize(width: size.width / Self.overscan, height: size.height / Self.overscan)
                    let box = CGRect(x: (size.width - inner.width) / 2, y: (size.height - inner.height) / 2,
                                     width: inner.width, height: inner.height)
                    ZenoRenderer.draw(&ctx, in: box, state: state)
                }
                .frame(width: geo.size.width * Self.overscan, height: geo.size.height * Self.overscan)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            animator.reduceMotion = reduceMotion
            animator.express(feeling, at: Date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: feeling) { _, next in animator.express(next, at: Date.timeIntervalSinceReferenceDate) }
        .onChange(of: replay) { _, _ in animator.express(feeling, at: Date.timeIntervalSinceReferenceDate) }
        .onChange(of: reduceMotion) { _, value in animator.reduceMotion = value }
    }
}

/// Draws one frame of Zeno into `box` (the 210 × 160 drawing space).
enum ZenoRenderer {
    typealias G = ZenoGeometry

    static func draw(_ ctx: inout GraphicsContext, in box: CGRect, state: ZenoRenderState) {
        let p = state.pose, col = state.colors
        let s = box.width / G.viewBox.width
        var base = ctx
        base.translateBy(x: box.minX - G.viewBox.minX * s, y: box.minY - G.viewBox.minY * s)
        base.scaleBy(x: s, y: s)

        // Breathing, squash and the hop.
        let shut = clamp(p[.shut], 0, 1)
        let sleepy = shut > 0.6 && p[.arc] < 0.3 && p[.arc] > -0.6
        let breath = sin(p.time * 2 * .pi / (sleepy ? 5 : 3.6)) * (sleepy ? 0.02 : 0.011)
        let sq = p[.squash] * 0.035
        let sx = (1 + sq * 0.7) * (1 - breath * 0.5), sy = (1 - sq) * (1 + breath)
        let hop = p[.hopY] * 1.78

        var root = base
        root.translateBy(x: 0, y: hop)
        root.translateBy(x: 75, y: 100)
        root.rotate(by: .degrees(p[.tilt]))
        root.scaleBy(x: sx, y: sy)
        root.translateBy(x: -75, y: -100)

        let highlight = Gradient(stops: [.init(color: .white.opacity(0.36), location: 0),
                                         .init(color: .white.opacity(0.06), location: 0.55),
                                         .init(color: .white.opacity(0), location: 1)])
        let rim = Gradient(colors: [col.rim.opacity(0.75), col.rim.opacity(0)])
        let body = Gradient(stops: [.init(color: col.light, location: 0), .init(color: col.mid, location: 0.55),
                                    .init(color: col.deep, location: 1)])

        // Ears
        let earL = -p[.droop] + p[.earLo] + p[.earWL], earR = p[.droop] + p[.earRo] + p[.earWR]
        for (path, pivot, angle) in [(G.earLeft, G.earLeftPivot, earL), (G.earRight, G.earRightPivot, earR)] {
            var e = root
            e.translateBy(x: pivot.x, y: pivot.y)
            e.rotate(by: .degrees(angle))
            e.translateBy(x: -pivot.x, y: -pivot.y)
            e.fill(path, with: .linearGradient(Gradient(colors: [col.light, col.mid]), startPoint: .zero, endPoint: CGPoint(x: 10, y: 44)))
            e.fill(path, with: .radialGradient(highlight, center: CGPoint(x: 60, y: 16), startRadius: 0, endRadius: 70))
            var r = e
            r.clip(to: path)
            r.stroke(path, with: .linearGradient(rim, startPoint: .zero, endPoint: CGPoint(x: 0, y: 30)), lineWidth: 2)
        }

        // Head
        let bodyShading = GraphicsContext.Shading.linearGradient(body, startPoint: CGPoint(x: 20, y: 0), endPoint: CGPoint(x: 34, y: 100))
        root.fill(G.head, with: bodyShading)
        root.fill(G.head, with: .radialGradient(highlight, center: CGPoint(x: 60, y: 16), startRadius: 0, endRadius: 70))
        root.fill(G.head, with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.16)]),
                                                startPoint: CGPoint(x: 0, y: 58), endPoint: CGPoint(x: 0, y: 100)))
        do {
            var r = root
            r.clip(to: G.head)
            r.stroke(G.head, with: .linearGradient(rim, startPoint: .zero, endPoint: CGPoint(x: 0, y: 30)), lineWidth: 2.2)
        }

        // Face
        var face = root
        face.translateBy(x: p[.lookX] * 0.45, y: p[.lookY] * 0.34)
        let blush = clamp(p[.blush], 0, 1)
        if blush > 0.01 {
            var b = face
            b.opacity = blush
            for cx in [33.0, 117.0] {
                let g = Gradient(colors: [col.blush.opacity(0.78), col.blush.opacity(0)])
                b.fill(Path(ellipseIn: CGRect(x: cx - 9, y: 61, width: 18, height: 10)),
                       with: .radialGradient(g, center: CGPoint(x: cx, y: 66), startRadius: 0, endRadius: 9))
            }
        }

        let squash = max(0.06, 1 - shut * 1.05)
        let ballAlpha = 1 - smooth(0.72, 0.92, shut), arcAlpha = smooth(0.55, 0.9, shut)
        let wet = clamp(p[.wet], 0, 1)
        let eyeGradient = Gradient(stops: [.init(color: Color(hex: 0x3A4A3D), location: 0), .init(color: Color(hex: 0x0C140D), location: 0.62),
                                           .init(color: Color(hex: 0x030503), location: 1)])
        for (i, c) in [G.eyeLeft, G.eyeRight].enumerated() {
            var e = face
            e.translateBy(x: p[.lookX] * 0.7 + c.x, y: p[.lookY] * 0.65 + c.y)
            e.scaleBy(x: p[.eyeS], y: p[.eyeS])
            e.translateBy(x: -c.x, y: -c.y)
            if ballAlpha > 0.01 {
                var ball = e
                ball.opacity = ballAlpha
                ball.translateBy(x: 0, y: c.y * (1 - squash))
                ball.scaleBy(x: 1, y: squash)
                let r = G.eyeRadius
                ball.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .radialGradient(eyeGradient, center: CGPoint(x: c.x - 1.44, y: c.y - 2.02), startRadius: 0, endRadius: 10.4))
                let c1 = 2.3 + 0.6 * wet
                ball.fill(Path(ellipseIn: CGRect(x: c.x - 2.3 - c1, y: c.y - 2.6 - c1, width: c1 * 2, height: c1 * 2)), with: .color(.white))
                ball.fill(Path(ellipseIn: CGRect(x: c.x + 2.6 - 1.05, y: c.y + 2.5 - 1.05, width: 2.1, height: 2.1)), with: .color(.white.opacity(0.85)))
                if wet > 0.01 {
                    var tearLine = Path()
                    tearLine.move(to: CGPoint(x: c.x - 4.4, y: c.y + 3.6))
                    tearLine.addQuadCurve(to: CGPoint(x: c.x + 4.4, y: c.y + 3.6), control: CGPoint(x: c.x, y: c.y + 7.2))
                    ball.stroke(tearLine, with: .color(.white.opacity(0.8 * wet)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                var lid = ball
                lid.clip(to: Path(ellipseIn: CGRect(x: c.x - r - 0.45, y: c.y - r - 0.45, width: (r + 0.45) * 2, height: (r + 0.45) * 2)))
                lid.translateBy(x: c.x, y: c.y)
                lid.rotate(by: .degrees(i == 0 ? -p[.lidTilt] : p[.lidTilt]))
                lid.translateBy(x: -c.x, y: -c.y)
                lid.fill(G.upperLid(c, clamp(p[.lidU], 0, 1)), with: bodyShading)
            }
            if arcAlpha > 0.01 {
                var a = e
                a.opacity = arcAlpha
                a.stroke(G.eyeArc(c, clamp(p[.arc], -1, 1)), with: .color(col.ink), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
            }
        }

        let brow = clamp(p[.brow], 0, 1)
        if brow > 0.01 {
            for (c, sign) in [(G.eyeLeft, -1.0), (G.eyeRight, 1.0)] {
                var b = face
                b.opacity = brow
                b.translateBy(x: c.x, y: G.browY + p[.browY] - (p[.eyeS] - 1) * 12)
                b.rotate(by: .degrees(sign * p[.browTilt]))
                b.stroke(G.brow, with: .color(col.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }

        face.fill(G.nose, with: .color(col.ink))
        var glint = Path()
        glint.move(to: CGPoint(x: 73.5, y: 68)); glint.addLine(to: CGPoint(x: 75, y: 66.5)); glint.addLine(to: CGPoint(x: 76.5, y: 68))
        face.stroke(glint, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))

        let open = clamp(p[.open], 0, 1), openAlpha = clamp(open * 5, 0, 1), mouth = clamp(p[.mouth], -1, 1)
        if openAlpha < 0.99 {
            var m = face
            m.opacity = 1 - openAlpha
            m.stroke(G.mouthClosed(mouth), with: .color(col.ink), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        }
        if openAlpha > 0.01 {
            var m = face
            m.opacity = openAlpha
            let shape = G.mouthOpen(open, mouth)
            m.fill(shape, with: .color(col.ink))
            let sm = max(0, mouth), top = 78 - 0.8 * sm, depth = 2 + 7.8 * open
            var tongue = m
            tongue.clip(to: shape)
            let rx = (5.4 + 1.8 * sm) * 0.62, ry = max(0.1, depth * 0.36)
            tongue.fill(Path(ellipseIn: CGRect(x: 75 - rx, y: top + depth - 1.3 - ry, width: rx * 2, height: ry * 2)), with: .color(Color(hex: 0xFF8C78)))
        }

        let tearAlpha = clamp(p[.tearA], 0, 1)
        if tearAlpha > 0.01 {
            let tp = clamp(p[.tear], 0, 1)
            var t = face
            t.opacity = tearAlpha
            t.translateBy(x: lerp(42, 37, tp), y: lerp(59, 84, tp * tp))
            let k = lerp(0.5, 1, clamp(tp * 3, 0, 1))
            t.scaleBy(x: k, y: k)
            t.fill(G.tear, with: .radialGradient(Gradient(colors: [.white, Color(hex: 0xCDE9FF, alpha: 0.8)]),
                                                 center: CGPoint(x: -0.5, y: -0.5), startRadius: 0, endRadius: 4.5))
        }

        // Sparkles and z's float outside the body.
        let spark = p[.sparkle]
        if spark > 0.001 && spark < 0.999 {
            for (i, sp) in G.sparkles.enumerated() {
                let a = sin(.pi * spark)
                var g = base
                g.opacity = a
                g.translateBy(x: sp.x + sp.dx * 26 * spark, y: sp.y + sp.dy * 26 * spark + hop)
                g.scaleBy(x: 0.35 + a * 0.9, y: 0.35 + a * 0.9)
                g.rotate(by: .degrees(spark * 45))
                g.fill(G.sparkle, with: .color(i % 2 == 1 ? .white : col.glow))
            }
        }
        let zz = p[.zz]
        if zz > 0.01 {
            for i in 0..<2 {
                let phase = (p.time / 2.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                var z = base
                z.opacity = zz * sin(.pi * phase)
                let point = CGPoint(x: 146 + CGFloat(i) * 10 + phase * 12, y: 4 - CGFloat(i) * 8 - phase * 24)
                z.draw(Text("z").font(ZenFont.number(i == 0 ? 14 : 10)).foregroundStyle(col.light), at: point, anchor: .bottomLeading)
            }
        }
    }

    private static func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(v, a), b) }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private static func smooth(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }
}

/// Zeno holding one feeling, drawn once: no clock, no blinking. For places where many Zenos sit
/// side by side (the card deck, the nudge list) and for images rendered to share.
public struct ZenoStill: View {
    public var feeling: ZenoFeeling

    public init(_ feeling: ZenoFeeling) { self.feeling = feeling }

    public var body: some View {
        let state = ZenoAnimator(feeling: feeling).sample(at: 0)
        GeometryReader { geo in
            Canvas { ctx, size in
                let inner = CGSize(width: size.width / ZenoView.overscan, height: size.height / ZenoView.overscan)
                let box = CGRect(x: (size.width - inner.width) / 2, y: (size.height - inner.height) / 2,
                                 width: inner.width, height: inner.height)
                ZenoRenderer.draw(&ctx, in: box, state: state)
            }
            .frame(width: geo.size.width * ZenoView.overscan, height: geo.size.height * ZenoView.overscan)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(ZenoView.aspectRatio, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
