import Foundation
import Testing
@testable import Albeit

/// Plays the animator frame by frame (60 fps, as a display would) from `from` to `to`.
@MainActor
private func play(_ a: ZenoAnimator, from: Double, to: Double) -> ZenoRenderState {
    var t = from
    var last = a.sample(at: t)
    while t < to {
        t = min(t + 1.0 / 60, to)
        last = a.sample(at: t)
    }
    return last
}

@Suite("Zeno: the animator")
@MainActor
struct ZenoAnimatorTests {
    @Test("A new animator rests exactly on its feeling's face", arguments: ZenoFeeling.allCases)
    func rests(_ f: ZenoFeeling) {
        let pose = ZenoAnimator(feeling: f).sample(at: 0).pose
        for (key, value) in f.expression.faceValues {
            #expect(abs(Double(pose[key]) - value) < 1e-9, "\(f) \(key)")
        }
        #expect(abs(Double(pose[.droop]) - f.expression.droop) < 1e-9)
        #expect(abs(Double(pose[.lookX]) - f.style.look.x) < 1e-9)
        #expect(Double(pose[.zz]) == (f.style.zz ? 1 : 0))
        #expect(Double(pose[.skinT]) == 1)
    }

    @Test("Every feeling's arrival settles on its face", arguments: ZenoFeeling.allCases)
    func settles(_ f: ZenoFeeling) {
        let a = ZenoAnimator(feeling: .calm)
        a.express(f, at: 0)
        let pose = play(a, from: 0, to: 6).pose
        #expect(a.feeling == f)
        // Blinks can close open eyes at any moment, so the lids are left out.
        for (key, value) in f.expression.faceValues where key != .shut {
            #expect(abs(Double(pose[key]) - value) < 0.02, "\(f) \(key): \(pose[key]) vs \(value)")
        }
        #expect(abs(Double(pose[.droop]) - f.expression.droop) < 0.05, "\(f) droop")
        #expect(abs(Double(pose[.lookY]) - f.style.look.y) < 0.02, "\(f) lookY")
        #expect(abs(Double(pose[.hopY]) - (f.style.tear ? 5 : 0)) < 0.05, "\(f) hopY")
        #expect(abs(Double(pose[.sparkle])) < 0.02, "\(f): sparkles fade out")
    }

    @Test("The same script gives the same frames every time")
    func deterministic() {
        func run() -> [Double] {
            let a = ZenoAnimator(feeling: .calm)
            a.express(.happy, at: 0)
            var frames: [Double] = []
            var t = 0.0
            while t < 2 {
                t += 1.0 / 60
                let p = a.sample(at: t).pose
                frames += [p[.hopY], p[.earWL], p[.mouth], p[.squash]].map(Double.init)
            }
            return frames
        }
        #expect(run() == run())
    }

    @Test("Happy hops: Zeno leaves the ground, then lands")
    func hop() {
        let a = ZenoAnimator(feeling: .calm)
        a.express(.happy, at: 0)
        var lowest = 0.0
        var t = 0.0
        while t < 3 { t += 1.0 / 60; lowest = min(lowest, Double(a.sample(at: t).pose[.hopY])) }
        #expect(lowest < -2)
        #expect(abs(Double(a.sample(at: 3).pose[.hopY])) < 0.5)
    }

    @Test("Calm never hops")
    func noHop() {
        let a = ZenoAnimator(feeling: .sleepy)
        a.express(.calm, at: 0)
        var lowest = 0.0
        var t = 0.0
        while t < 3 { t += 1.0 / 60; lowest = min(lowest, Double(a.sample(at: t).pose[.hopY])) }
        #expect(lowest > -0.5)
    }

    @Test("A new feeling interrupts the last: sad after happy ends sad")
    func interrupt() {
        let a = ZenoAnimator(feeling: .calm)
        a.express(.happy, at: 0)
        _ = play(a, from: 0, to: 0.3)
        a.express(.sad, at: 0.3)
        let pose = play(a, from: 0.3, to: 6).pose
        #expect(abs(Double(pose[.mouth]) - ZenoFeeling.sad.expression.mouth) < 0.02)
        #expect(abs(Double(pose[.droop]) - ZenoFeeling.sad.expression.droop) < 0.05)
    }

    @Test("Reduce Motion: the face snaps at once, no spring")
    func reduceMotion() {
        let a = ZenoAnimator(feeling: .calm)
        a.reduceMotion = true
        _ = a.sample(at: 0)
        a.express(.proud, at: 0)
        let pose = a.sample(at: 0).pose
        #expect(abs(Double(pose[.mouth]) - ZenoFeeling.proud.expression.mouth) < 1e-9)
        #expect(abs(Double(pose[.droop]) - ZenoFeeling.proud.expression.droop) < 1e-9)
        #expect(Double(pose[.hopY]) == 0)
    }

    @Test("The skin crossfades from green to gold for pride")
    func skin() {
        let a = ZenoAnimator(feeling: .calm)
        _ = a.sample(at: 0)
        a.express(.proud, at: 0)
        let start = a.sample(at: 0)
        #expect(Double(start.pose[.skinT]) == 0)
        #expect(abs(start.colors.rgb[1].x - Double(0x34) / 255) < 1e-6) // still zen's mid
        let end = play(a, from: 0, to: 3)
        #expect(abs(Double(end.pose[.skinT]) - 1) < 0.01)
        #expect(abs(end.colors.rgb[1].x - Double(0xFF) / 255) < 0.01) // gold's mid
    }

    @Test("Staying in the same skin doesn't crossfade")
    func sameSkin() {
        let a = ZenoAnimator(feeling: .calm)
        _ = a.sample(at: 0)
        a.express(.happy, at: 0)
        #expect(Double(a.sample(at: 0).pose[.skinT]) == 1)
    }

    @Test("After a long pause it skips ahead instead of replaying every frame")
    func longPause() {
        let a = ZenoAnimator(feeling: .calm)
        a.express(.happy, at: 0)
        let late = a.sample(at: 10_000)
        #expect(late.pose.time == 10_000)
        #expect(late.pose[.mouth].isFinite)
    }
}

@Suite("Zeno: feelings, faces and skins")
struct ZenoFeelingDataTests {
    @Test("Every feeling has a face, a style and a skin; sad and sleepy are quiet")
    func complete() {
        #expect(ZenoFeeling.allCases.count == 8)
        for f in ZenoFeeling.allCases {
            #expect(f.expression.faceValues.count == 13, "\(f)")
            #expect(f.style.response > 0 && f.style.damping > 0 && f.style.damping <= 1, "\(f)")
            #expect(f.style.exprResponse > 0, "\(f)")
            #expect((0...1).contains(f.expression.shut) && (-1...1).contains(f.expression.arc), "\(f)")
        }
        #expect(ZenoFeeling.sad.style.tear && ZenoFeeling.sleepy.style.zz)
        #expect(ZenoFeeling.allCases.filter { $0.style.tear } == [.sad])
    }

    @Test("Every skin has seven colours")
    func skins() {
        for s in ZenoSkin.allCases {
            #expect(s.hexes.count == 7, "\(s)")
            #expect(s.hexes.allSatisfy { $0 <= 0xFFFFFF })
        }
    }

    @Test("Blending is clamped, and halfway is the midpoint")
    func blend() {
        let below = ZenoSkin.blend(.zen, .gold, -1).rgb, above = ZenoSkin.blend(.zen, .gold, 2).rgb
        #expect(below == ZenoSkin.blend(.zen, .gold, 0).rgb)
        #expect(above == ZenoSkin.blend(.zen, .gold, 1).rgb)
        let mid = ZenoSkin.blend(.zen, .gold, 0.5).rgb[0]
        #expect(abs(mid.x - (Double(0x86) + Double(0xFF)) / 2 / 255) < 1e-9)
        #expect(ZenoSkin.blend(.ember, .ember, 0.37).rgb == ZenoSkin.blend(.ember, .ember, 0).rgb)
    }

    @Test("A pose reads 0 for anything it doesn't hold")
    func poseDefault() {
        let p = ZenoPose(values: [.mouth: 0.5], time: 0)
        #expect(p[.mouth] == 0.5 && p[.tear] == 0)
    }

    @Test("Every pose key the animator drives has a spring")
    @MainActor
    func allKeys() {
        let pose = ZenoAnimator().sample(at: 0).pose
        let missing = ZenoPose.Key.allCases.filter { pose.values[$0] == nil }
        #expect(missing.isEmpty, "no spring for \(missing)")
    }
}
