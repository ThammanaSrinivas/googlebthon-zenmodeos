import SwiftUI

/// Zeno is built from the mark's pieces: the two corner triangles are the ears, the band is the
/// face, the dot is the eyes, the cut turned 45° is the nose. Everything lives in a 150 × 100 box;
/// the drawing space is that box with room around it for ears, sparkles and z's (−30, −36, 210 × 160).
enum ZenoGeometry {
    static let viewBox = CGRect(x: -30, y: -36, width: 210, height: 160)

    static let headPoints: [CGPoint] = [
        (50, 0), (100, 0), (100, 10.7), (150, 60.7), (150, 100), (111.3, 100), (100, 88.7), (100, 100),
        (50, 100), (50, 88.7), (38.7, 100), (0, 100), (0, 60.7), (50, 10.7),
    ].map { CGPoint(x: $0.0, y: $0.1) }
    static let headRadii: [CGFloat] = [8, 8, 4, 9, 8, 2.5, 2, 2, 2, 2, 2.5, 8, 9, 4]

    static let head = roundedPolygon(headPoints, radii: headRadii)
    static let earLeft = roundedPolygon([CGPoint(x: 0, y: 0), CGPoint(x: 38, y: 0), CGPoint(x: 0, y: 38)], radii: [8, 7, 7])
    static let earRight = roundedPolygon([CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 38), CGPoint(x: 112, y: 0)], radii: [8, 7, 7])
    static let nose = roundedPolygon(
        [CGPoint(x: 75, y: 65.4), CGPoint(x: 80, y: 70.4), CGPoint(x: 75, y: 75.4), CGPoint(x: 70, y: 70.4)],
        radii: [1.5, 1.5, 1.5, 1.5])

    static let eyeLeft = CGPoint(x: 48, y: 51)
    static let eyeRight = CGPoint(x: 102, y: 51)
    static let eyeRadius: CGFloat = 7.2
    static let browY: CGFloat = 38.5
    static let earLeftPivot = CGPoint(x: 22, y: 24)
    static let earRightPivot = CGPoint(x: 128, y: 24)

    /// A polygon whose corners are rounded with quadratic curves, each corner its own radius.
    static func roundedPolygon(_ points: [CGPoint], radii: [CGFloat]) -> Path {
        var path = Path()
        let n = points.count
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n]
            let a = CGPoint(x: p0.x - p1.x, y: p0.y - p1.y), b = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
            let la = hypot(a.x, a.y), lb = hypot(b.x, b.y)
            let u = CGPoint(x: a.x / la, y: a.y / la), v = CGPoint(x: b.x / lb, y: b.y / lb)
            let angle = acos(min(max(u.x * v.x + u.y * v.y, -1), 1))
            let t = min(radii[i] / tan(angle / 2), la / 2, lb / 2)
            let start = CGPoint(x: p1.x + u.x * t, y: p1.y + u.y * t)
            let end = CGPoint(x: p1.x + v.x * t, y: p1.y + v.y * t)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: p1)
        }
        path.closeSubpath()
        return path
    }

    /// The upper lid: a curtain that comes down over the eye as `u` goes to 1.
    static func upperLid(_ c: CGPoint, _ u: CGFloat) -> Path {
        let yb = c.y - 8 + u * 16.4, bow = 2.8 * (1 - u * 0.6)
        var p = Path()
        p.move(to: CGPoint(x: c.x - 11, y: c.y - 18))
        p.addLine(to: CGPoint(x: c.x + 11, y: c.y - 18))
        p.addLine(to: CGPoint(x: c.x + 11, y: yb))
        p.addQuadCurve(to: CGPoint(x: c.x - 11, y: yb), control: CGPoint(x: c.x, y: yb + bow))
        p.closeSubpath()
        return p
    }

    /// A closed eye: +1 is ∩ (joy), −1 is ‿ (contentment).
    static func eyeArc(_ c: CGPoint, _ a: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x - 6.6, y: c.y + 1.6 * a))
        p.addQuadCurve(to: CGPoint(x: c.x + 6.6, y: c.y + 1.6 * a), control: CGPoint(x: c.x, y: c.y - 6.4 * a))
        return p
    }

    static let brow: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -6.5, y: 1.2))
        p.addQuadCurve(to: CGPoint(x: 6.5, y: 1.2), control: CGPoint(x: 0, y: -2))
        return p
    }()

    static func mouthClosed(_ m: CGFloat) -> Path {
        var p = Path()
        if m >= 0 {
            let e = 79 - 1.8 * m, c = 79 + 2.8 * m, w = 1.4 * m
            p.move(to: CGPoint(x: 69 - w, y: e))
            p.addQuadCurve(to: CGPoint(x: 75, y: 78.7 + 0.2 * m), control: CGPoint(x: 72, y: c))
            p.addQuadCurve(to: CGPoint(x: 81 + w, y: e), control: CGPoint(x: 78, y: c))
        } else {
            let k = -m
            p.move(to: CGPoint(x: 69.6 + 0.4 * k, y: 79 + 0.9 * k))
            p.addQuadCurve(to: CGPoint(x: 80.4 - 0.4 * k, y: 79 + 0.9 * k), control: CGPoint(x: 75, y: 79 - 5.2 * k))
        }
        return p
    }

    static func mouthOpen(_ o: CGFloat, _ m: CGFloat) -> Path {
        let s = max(0, m), w = 5.4 + 1.8 * s, top = 78 - 0.8 * s, depth = 2 + 7.8 * o
        var p = Path()
        p.move(to: CGPoint(x: 75 - w, y: top))
        p.addQuadCurve(to: CGPoint(x: 75 + w, y: top), control: CGPoint(x: 75, y: top + 1.2 + 1.8 * s))
        p.addCurve(to: CGPoint(x: 75, y: top + depth),
                   control1: CGPoint(x: 75 + w * 0.95, y: top + depth * 0.92), control2: CGPoint(x: 75 + w * 0.42, y: top + depth))
        p.addCurve(to: CGPoint(x: 75 - w, y: top),
                   control1: CGPoint(x: 75 - w * 0.42, y: top + depth), control2: CGPoint(x: 75 - w * 0.95, y: top + depth * 0.92))
        p.closeSubpath()
        return p
    }

    static let tear: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -3.6))
        p.addCurve(to: CGPoint(x: 2.7, y: 1.8), control1: CGPoint(x: 1.8, y: -1), control2: CGPoint(x: 2.7, y: 0.6))
        p.addArc(center: CGPoint(x: 0, y: 1.8), radius: 2.7, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: -3.6), control1: CGPoint(x: -2.7, y: 0.6), control2: CGPoint(x: -1.8, y: -1))
        p.closeSubpath()
        return p
    }()

    static let sparkle: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -6))
        p.addCurve(to: CGPoint(x: 6, y: 0), control1: CGPoint(x: 0.7, y: -1.4), control2: CGPoint(x: 1.4, y: -0.7))
        p.addCurve(to: CGPoint(x: 0, y: 6), control1: CGPoint(x: 1.4, y: 0.7), control2: CGPoint(x: 0.7, y: 1.4))
        p.addCurve(to: CGPoint(x: -6, y: 0), control1: CGPoint(x: -0.7, y: 1.4), control2: CGPoint(x: -1.4, y: 0.7))
        p.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: -1.4, y: -0.7), control2: CGPoint(x: -0.7, y: -1.4))
        p.closeSubpath()
        return p
    }()

    /// Where each sparkle starts and which way it flies.
    static let sparkles: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat)] = [
        (-20, -4, -1.2, -1), (164, 6, 1.1, -0.9), (22, -20, -0.5, -1.3), (130, -22, 0.6, -1.25), (75, -30, 0, -1.2),
    ]
}
