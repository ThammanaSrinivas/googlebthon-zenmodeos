import SwiftUI
import Testing
@testable import Albeit

@Suite("Zeno: the drawing")
struct ZenoGeometryTests {
    private let head = CGRect(x: 0, y: 0, width: 150, height: 100)

    private func inside(_ r: CGRect, _ box: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        r.minX >= box.minX - tolerance && r.minY >= box.minY - tolerance
            && r.maxX <= box.maxX + tolerance && r.maxY <= box.maxY + tolerance
    }

    @Test("Every corner of the head has its own radius")
    func radii() {
        #expect(ZenoGeometry.headPoints.count == ZenoGeometry.headRadii.count)
        #expect(ZenoGeometry.headRadii.allSatisfy { $0 > 0 })
    }

    @Test("A polygon with no rounding is exactly its points")
    func sharpPolygon() {
        let square = ZenoGeometry.roundedPolygon([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)],
                                                 radii: [0, 0, 0, 0])
        let box = square.boundingRect
        #expect(abs(box.minX) < 1e-6 && abs(box.minY) < 1e-6 && abs(box.maxX - 10) < 1e-6 && abs(box.maxY - 10) < 1e-6)
    }

    @Test("Rounding never pokes outside the polygon's own box")
    func roundedStaysInside() {
        let tri = ZenoGeometry.roundedPolygon([CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 0, y: 40)], radii: [30, 30, 30])
        #expect(inside(tri.boundingRect, CGRect(x: 0, y: 0, width: 40, height: 40)))
        #expect(!tri.isEmpty)
    }

    @Test("Ears, nose and eyes sit on the head, mirrored about its middle")
    func layout() {
        #expect(inside(ZenoGeometry.earLeft.boundingRect, head) && inside(ZenoGeometry.earRight.boundingRect, head))
        let nose = ZenoGeometry.nose.boundingRect
        #expect(inside(nose, head) && abs(nose.midX - 75) < 0.01)
        #expect(ZenoGeometry.eyeLeft.x + ZenoGeometry.eyeRight.x == 150 && ZenoGeometry.eyeLeft.y == ZenoGeometry.eyeRight.y)
        #expect(ZenoGeometry.earLeftPivot.x + ZenoGeometry.earRightPivot.x == 150)
        #expect(head.contains(ZenoGeometry.eyeLeft) && head.contains(ZenoGeometry.eyeRight))
    }

    @Test("The drawing space holds the head and every sparkle")
    func viewBox() {
        let vb = ZenoGeometry.viewBox
        #expect(vb.contains(head))
        for s in ZenoGeometry.sparkles {
            let box = ZenoGeometry.sparkle.boundingRect.offsetBy(dx: s.x, dy: s.y)
            #expect(inside(box, vb), "sparkle at \(s.x), \(s.y)")
        }
    }

    @Test("Lids come down as they close")
    func lids() {
        let c = ZenoGeometry.eyeLeft
        let open = ZenoGeometry.upperLid(c, 0).boundingRect, shut = ZenoGeometry.upperLid(c, 1).boundingRect
        #expect(shut.maxY > open.maxY)
        #expect(abs(open.minY - (c.y - 18)) < 0.01 && abs(shut.minY - open.minY) < 0.01)
    }

    @Test("Every mouth stays centred under the nose and on the face", arguments: [-1.0, -0.5, 0, 0.5, 1])
    func mouths(_ m: Double) {
        let closed = ZenoGeometry.mouthClosed(m).boundingRect
        #expect(abs(closed.midX - 75) < 0.01)
        #expect(inside(closed, head))
        let open = ZenoGeometry.mouthOpen(0.6, m).boundingRect
        #expect(abs(open.midX - 75) < 0.01)
        #expect(inside(open, head))
    }

    @Test("An open mouth gets deeper as it opens")
    func depth() {
        #expect(ZenoGeometry.mouthOpen(1, 0).boundingRect.maxY > ZenoGeometry.mouthOpen(0, 0).boundingRect.maxY)
    }

    @Test("Closed eyes: joy and contentment curve opposite ways")
    func eyeArcs() {
        let joy = ZenoGeometry.eyeArc(.zero, 1).boundingRect, content = ZenoGeometry.eyeArc(.zero, -1).boundingRect
        #expect(joy.minY < 0 && content.maxY > 0)
        #expect(abs(joy.width - content.width) < 0.01)
    }
}
