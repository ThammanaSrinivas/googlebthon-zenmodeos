import SwiftUI
import Testing
@testable import Albeit

@Suite("Zeno and the Albeit tokens")
struct ZenoTests {
    @Test("Zeno's head sits in its 150 × 100 box")
    func headBox() {
        let box = ZenoGeometry.head.boundingRect
        #expect(abs(box.minX) < 0.01 && abs(box.minY) < 0.01)
        #expect(abs(box.maxX - 150) < 0.01 && abs(box.maxY - 100) < 0.01)
    }

    @Test("The ears are mirror images")
    func ears() {
        let l = ZenoGeometry.earLeft.boundingRect, r = ZenoGeometry.earRight.boundingRect
        #expect(abs(l.width - r.width) < 0.01)
        #expect(abs(l.minX - (150 - r.maxX)) < 0.01)
    }

    @Test("Each feeling wears its skin: gold is earned, dusk is quiet, ember asks")
    func skins() {
        #expect(ZenoFeeling.proud.skin == .gold)
        #expect(ZenoFeeling.sleepy.skin == .dusk)
        #expect(ZenoFeeling.sad.skin == .dusk)
        #expect(ZenoFeeling.alert.skin == .ember)
        #expect(ZenoFeeling.happy.skin == .zen)
    }

    @Test("Only happy and proud hop")
    func onlyJoyHops() {
        for f in ZenoFeeling.allCases {
            #expect(f.style.hop == (f == .happy || f == .proud))
        }
    }

    @Test("Ears go up for joy and down for sadness")
    func earDroop() {
        #expect(ZenoFeeling.happy.expression.droop < 0)
        #expect(ZenoFeeling.sad.expression.droop > ZenoFeeling.calm.expression.droop)
    }

    @Test("A spring settles on its target")
    func springSettles() {
        var s = ZenSpring(0, 0.42, 0.82)
        s.target = 1
        for _ in 0..<(240 * 3) { s.step(1.0 / 240) }
        #expect(abs(s.x - 1) < 0.001)
    }

    @Test("A critically damped container spring never overshoots")
    func containerSettles() {
        var s = ZenSpring(0, 0.44, 1)
        s.target = 1
        var peak = 0.0
        for _ in 0..<(240 * 3) { s.step(1.0 / 240); peak = max(peak, s.x) }
        #expect(peak <= 1.0001)
    }

    @Test("Skin blending lands exactly on each end")
    func blend() {
        let a = ZenoSkin.blend(.zen, .gold, 0).rgb[0], b = ZenoSkin.blend(.zen, .gold, 1).rgb[0]
        #expect(abs(a.x - Double(0x86) / 255) < 0.001)
        #expect(abs(b.x - Double(0xFF) / 255) < 0.001)
    }

    @Test("The mark parses into one closed shape inside its square")
    func mark() {
        let box = ZenMark.base.boundingRect
        #expect(box.minX >= -0.01 && box.minY >= -0.01 && box.maxX <= 32.2 && box.maxY <= 32.2)
    }
}
