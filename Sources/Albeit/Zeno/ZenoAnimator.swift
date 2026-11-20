import SwiftUI

/// A damped spring set by response and damping fraction, the same model as SwiftUI's springs.
struct ZenSpring {
    var x: Double, v: Double = 0, target: Double
    private(set) var k: Double = 0, c: Double = 0

    init(_ x: Double, _ response: Double, _ damping: Double) {
        self.x = x
        self.target = x
        tune(response, damping)
    }

    mutating func tune(_ response: Double, _ damping: Double) {
        k = pow(2 * .pi / response, 2)
        c = 4 * .pi * damping / response
    }

    mutating func step(_ dt: Double) {
        let a = -k * (x - target) - c * v
        v += a * dt
        x += v * dt
    }
}

/// What the renderer needs for one frame.
struct ZenoRenderState: Sendable {
    var pose: ZenoPose
    var colors: ZenoSkin.Colors
}

/// Drives Zeno. A feeling is a short script of spring targets and kicks on one clock at 240 steps
/// a second, so every arrival is deterministic and can be interrupted by the next.
@MainActor
final class ZenoAnimator {
    typealias Key = ZenoPose.Key
    private struct Event { var at: Double; var run: (inout [Key: ZenSpring]) -> Void }

    private var springs: [Key: ZenSpring] = [:]
    private var events: [Event] = []
    private var clock: Double?
    private var simTime: Double = 0
    private var nextBlink: Double = 0
    private var seed: UInt64 = 0x9E3779B97F4A7C15
    private(set) var feeling: ZenoFeeling = .calm
    private var skinFrom: ZenoSkin = .zen
    private var skinTo: ZenoSkin = .zen
    var reduceMotion = false

    init(feeling: ZenoFeeling = .calm) {
        let calm = ZenoFeeling.calm.expression
        for (key, value) in calm.faceValues { springs[key] = ZenSpring(value, 0.35, 0.85) }
        springs[.droop] = ZenSpring(calm.droop, 0.32, 0.62)
        springs[.earLo] = ZenSpring(0, 0.3, 0.7)
        springs[.earRo] = ZenSpring(0, 0.3, 0.7)
        springs[.earWL] = ZenSpring(0, 0.16, 0.2)
        springs[.earWR] = ZenSpring(0, 0.16, 0.2)
        springs[.lookX] = ZenSpring(0, 0.3, 0.9)
        springs[.lookY] = ZenSpring(0, 0.3, 0.9)
        springs[.hopY] = ZenSpring(0, 0.5, 0.7)
        springs[.squash] = ZenSpring(0, 0.2, 0.32)
        springs[.sparkle] = ZenSpring(0, 1.3, 1)
        springs[.tear] = ZenSpring(0, 2.4, 1)
        springs[.tearA] = ZenSpring(0, 0.3, 1)
        springs[.zz] = ZenSpring(0, 0.6, 1)
        springs[.skinT] = ZenSpring(1, 0.5, 1)
        self.feeling = feeling
        skinFrom = feeling.skin
        skinTo = feeling.skin
        snap(to: feeling)
    }

    /// Plays `feeling`'s arrival from now.
    func express(_ next: ZenoFeeling, at now: Double) {
        if clock == nil { clock = now; simTime = now }
        let t0 = simTime
        events.removeAll()
        let previousSkin = springs[.skinT]!.x >= 0.5 ? skinTo : skinFrom
        feeling = next
        if next.skin != skinTo {
            skinFrom = previousSkin
            skinTo = next.skin
            springs[.skinT]!.x = 0
            springs[.skinT]!.target = 1
        }
        if reduceMotion { snap(to: next); return }

        let s = next.style, x = next.expression
        func at(_ dt: Double, _ run: @escaping (inout [Key: ZenSpring]) -> Void) { events.append(Event(at: t0 + dt, run: run)) }
        func to(_ k: Key, _ v: Double, _ r: Double? = nil, _ d: Double? = nil) -> (inout [Key: ZenSpring]) -> Void {
            { sp in if let r { sp[k]!.tune(r, d ?? 0.9) }; sp[k]!.target = v }
        }
        func kick(_ k: Key, _ v: Double) -> (inout [Key: ZenSpring]) -> Void { { sp in sp[k]!.v += v } }

        // Extras from the last feeling let go.
        at(0) { sp in
            sp[.tearA]!.target = 0
            if !s.zz { sp[.zz]!.target = 0 }
            sp[.hopY]!.tune(s.response, s.damping)
            sp[.hopY]!.target = 0
        }
        at(0.13, to(.droop, x.droop, 0.34, 0.62))
        at(0.13, to(.earLo, x.earLo, 0.3, 0.7))
        at(0.13, to(.earRo, x.earRo, 0.3, 0.7))
        let land = s.response * 0.42 + 0.06
        if s.kicks > 0 {
            at(land) { sp in sp[.squash]!.v += 1.6; sp[.earWL]!.v += s.earKick; sp[.earWR]!.v -= s.earKick * 0.9 }
            if s.kicks > 1 {
                at(land + 0.15) { sp in sp[.earWL]!.v -= s.earKick * 0.6; sp[.earWR]!.v += s.earKick * 0.55 }
            }
        }
        at(land + 0.06, to(.shut, 1, 0.055, 1))
        let exprAt = land + 0.19
        at(exprAt - 0.07, to(.shut, x.shut > 0.5 ? x.shut : 0, x.shut > 0.5 ? 0.3 : 0.07, 1))
        at(exprAt) { sp in
            for (k, v) in x.faceValues where k != .shut {
                sp[k]!.tune(s.exprResponse, s.exprDamping)
                sp[k]!.target = v
            }
        }
        at(exprAt + 0.07, to(.lookX, s.look.x, 0.32, 0.88))
        at(exprAt + 0.07, to(.lookY, s.look.y, 0.32, 0.88))
        let lineEnd = exprAt + 0.55
        if s.hop {
            at(lineEnd - 0.04) { sp in sp[.hopY]!.v -= 260; sp[.earWL]!.v += 700; sp[.earWR]!.v -= 640 }
            at(lineEnd + 0.06, kick(.squash, 1.2))
        }
        if s.sparkle {
            at(lineEnd - 0.04) { sp in sp[.sparkle]!.x = 0; sp[.sparkle]!.v = 0; sp[.sparkle]!.target = 1 }
            at(lineEnd + 1.6) { sp in sp[.sparkle]!.x = 0; sp[.sparkle]!.v = 0; sp[.sparkle]!.target = 0 }
        }
        if s.tear {
            at(exprAt + 0.5, to(.hopY, 5, 1.6, 1))
            at(exprAt + 0.7) { sp in sp[.tearA]!.target = 1; sp[.tear]!.x = 0; sp[.tear]!.v = 0; sp[.tear]!.target = 1 }
            at(exprAt + 2.6, to(.tearA, 0, 0.5, 1))
        }
        if s.zz { at(exprAt, to(.zz, 1, 0.8, 1)) }
        if s.peek {
            at(lineEnd + 0.5, to(.shut, 0, 0.2, 1))
            at(lineEnd + 0.5, to(.lookX, 0, 0.4, 0.9))
            at(lineEnd + 1.3, to(.shut, 1, 0.35, 1))
            at(lineEnd + 1.3, to(.lookX, s.look.x, 0.4, 0.9))
        }
        if s.flick {
            at(lineEnd + 0.3, kick(.earWL, -520))
            at(lineEnd + 0.9, kick(.earWL, 380))
        }
        events.sort { $0.at < $1.at }
        nextBlink = t0 + lineEnd + 0.7 + random() * 0.6
    }

    /// Advances the clock to `now` and returns the frame.
    func sample(at now: Double) -> ZenoRenderState {
        if clock == nil { clock = now; simTime = now }
        // After a long pause (window hidden), skip ahead instead of replaying every step.
        if now - simTime > 0.12 { simTime = now - 0.12 }
        let dt = 1.0 / 240
        while simTime + dt <= now {
            for k in springs.keys { springs[k]!.step(dt) }
            simTime += dt
            while let first = events.first, first.at <= simTime {
                events.removeFirst()
                first.run(&springs)
            }
            idleBlink()
        }
        var values: [Key: Double] = [:]
        for (k, s) in springs { values[k] = s.x }
        let t = springs[.skinT]!.x
        return ZenoRenderState(pose: ZenoPose(values: values, time: now), colors: ZenoSkin.blend(skinFrom, skinTo, t))
    }

    /// Blinks while holding open eyes, never on a beat you can predict.
    private func idleBlink() {
        guard !reduceMotion, feeling.expression.shut < 0.5, simTime >= nextBlink, events.isEmpty else { return }
        let rest = feeling.expression.shut
        springs[.shut]!.tune(0.055, 1)
        springs[.shut]!.target = 1
        events.append(Event(at: simTime + 0.12) { sp in sp[.shut]!.tune(0.07, 1); sp[.shut]!.target = rest })
        nextBlink = simTime + 1.6 + random() * 1.7
    }

    private func snap(to f: ZenoFeeling) {
        let x = f.expression
        for (k, v) in x.faceValues { springs[k]!.x = v; springs[k]!.target = v; springs[k]!.v = 0 }
        for (k, v) in [(Key.droop, x.droop), (.earLo, x.earLo), (.earRo, x.earRo), (.lookX, f.style.look.x), (.lookY, f.style.look.y),
                       (.zz, f.style.zz ? 1 : 0), (.skinT, 1), (.earWL, 0), (.earWR, 0), (.hopY, 0), (.squash, 0), (.sparkle, 0), (.tearA, 0)] {
            springs[k]!.x = v; springs[k]!.target = v; springs[k]!.v = 0
        }
        skinFrom = f.skin
        skinTo = f.skin
    }

    private func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
}
