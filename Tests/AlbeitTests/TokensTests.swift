import SwiftUI
import Testing
@testable import Albeit

/// A palette colour resolved in light or dark, as 0…255 sRGB.
@MainActor
private func rgb(_ color: Color, _ scheme: ColorScheme) -> (r: Double, g: Double, b: Double) {
    var env = EnvironmentValues()
    env.colorScheme = scheme
    let c = color.resolve(in: env)
    return (Double(c.red) * 255, Double(c.green) * 255, Double(c.blue) * 255)
}

private func hex(_ v: UInt32) -> (r: Double, g: Double, b: Double) {
    (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
}

private func same(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Bool {
    abs(a.r - b.r) < 1 && abs(a.g - b.g) < 1 && abs(a.b - b.b) < 1
}

/// WCAG contrast between two resolved colours.
@MainActor
private func contrast(_ a: Color, _ b: Color, _ scheme: ColorScheme) -> Double {
    func lum(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func f(_ v: Double) -> Double { let s = v / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
    let x = lum(rgb(a, scheme)), y = lum(rgb(b, scheme))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

@Suite("Albeit: the tokens")
@MainActor
struct TokensTests {
    private let zen = Color.zen

    @Test("Every palette token is a colour, in light and in dark")
    func complete() {
        let tokens = Mirror(reflecting: zen).children.compactMap { $0.value as? Color }
        #expect(tokens.count == Mirror(reflecting: zen).children.count)
        #expect(tokens.count >= 25)
        for t in tokens {
            for scheme in [ColorScheme.light, .dark] {
                let c = rgb(t, scheme)
                #expect((0...255.5).contains(c.r) && (0...255.5).contains(c.g) && (0...255.5).contains(c.b))
            }
        }
    }

    @Test("Paper by day, ink by night")
    func surfaces() {
        #expect(same(rgb(zen.surfaceBase, .light), hex(0xF2F1EC)))
        #expect(same(rgb(zen.surfaceBase, .dark), hex(0x0E110E)))
        #expect(same(rgb(zen.textHeading, .light), hex(0x12160F)))
        #expect(same(rgb(zen.textHeading, .dark), hex(0xF2F3EE)))
    }

    @Test("Brand and reward colours stay the same in both")
    func fixed() {
        for c in [zen.brandFill, zen.accentReward, zen.ember, zen.island] {
            #expect(same(rgb(c, .light), rgb(c, .dark)))
        }
        #expect(same(rgb(zen.brandFill, .light), hex(0x2AA136)))
    }

    @Test("Text is readable on every surface, in both (WCAG AA, 4.5:1)", arguments: [ColorScheme.light, .dark])
    func readable(_ scheme: ColorScheme) {
        for text in [zen.textHeading, zen.textBody, zen.textCaption, zen.textBrand, zen.scoreGain, zen.scoreDeduct] {
            for surface in [zen.surfaceBase, zen.surfaceCard, zen.surfaceRaised] {
                #expect(contrast(text, surface, scheme) >= 4.5)
            }
        }
        #expect(contrast(zen.onActionPrimary, zen.actionPrimary, scheme) >= 4.5)
        #expect(contrast(zen.accentRewardText, zen.accentRewardTint, scheme) >= 4.5)
        #expect(contrast(zen.islandText, zen.island, scheme) >= 4.5 && contrast(zen.islandDetail, zen.island, scheme) >= 4.5)
    }

    @Test("Hex colours land on their bytes")
    func hexInit() {
        #expect(same(rgb(Color(hex: 0xFFC800), .light), (255, 200, 0)))
        #expect(same(rgb(Color(hex: 0x000000), .dark), (0, 0, 0)))
    }

    @Test("Spacing is on the 4 pt grid; radii and durations grow in order")
    func scales() {
        let space: [CGFloat] = [ZenSpace.s1, ZenSpace.s2, ZenSpace.s3, ZenSpace.s4, ZenSpace.s5, ZenSpace.s6, ZenSpace.s8,
                                ZenSpace.s10, ZenSpace.s12, ZenSpace.s16, ZenSpace.s24, ZenSpace.s32]
        #expect(space == [4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 96, 128])
        let radii = [ZenRadius.xs, ZenRadius.sm, ZenRadius.md, ZenRadius.lg, ZenRadius.xl, ZenRadius.xxl, ZenRadius.xxxl]
        #expect(radii == radii.sorted() && Set(radii).count == radii.count)
        let t = [ZenMotion.t1, ZenMotion.t2, ZenMotion.t3, ZenMotion.t4, ZenMotion.t5]
        #expect(t == [0.16, 0.32, 0.64, 1.2, 1.8])
        #expect(ZenGrid.cell + ZenGrid.gap == 16)
    }
}
