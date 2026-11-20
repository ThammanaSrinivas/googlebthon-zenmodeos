import SwiftUI
import Testing
@testable import Albeit

@Suite("Albeit: contrast (WCAG 2.2 AA)")
@MainActor
struct ContrastTests {
    private let zen = Color.zen

    /// Every background text can sit on: the surfaces, the ground at its greenest, and glass over both.
    private func backgrounds(_ scheme: ColorScheme) -> [(String, Color)] {
        var all: [(String, Color)] = [("card", zen.surfaceCard), ("base", zen.surfaceBase), ("raised", zen.surfaceRaised),
                                      ("sunk", zen.surfaceSunk), ("tint", zen.surfaceTint)]
        for (i, g) in ZenContrast.grounds(in: scheme).enumerated() {
            all.append(("ground \(i)", g))
            for (j, glass) in ZenContrast.glass(over: g, in: scheme).enumerated() { all.append(("glass \(j) on ground \(i)", glass)) }
        }
        return all
    }

    @Test("The ratio matches WCAG's reference points")
    func reference() {
        let white = ZenContrast.resolve(.white, in: .light), black = ZenContrast.resolve(.black, in: .light)
        #expect(abs(ZenContrast.ratio(white, black) - 21) < 0.01)
        #expect(abs(ZenContrast.ratio(white, white) - 1) < 0.0001)
        #expect(ZenContrast.ratio(white, black) == ZenContrast.ratio(black, white))
        // #767676 on white is the classic just-passing grey: 4.54.
        let grey = ZenContrast.resolve(Color(hex: 0x767676), in: .light)
        #expect(abs(ZenContrast.ratio(grey, white) - 4.54) < 0.02)
    }

    @Test("Compositing lands between its two colours")
    func compositing() {
        let half = ZenContrast.resolve(ZenContrast.composite(.white, opacity: 0.5, over: .black, in: .light), in: .light)
        #expect(abs(half.red - 0.5) < 0.01 && abs(half.green - 0.5) < 0.01)
        let none = ZenContrast.resolve(ZenContrast.composite(.white, opacity: 0, over: Color(hex: 0x0E110E), in: .dark), in: .dark)
        #expect(abs(ZenContrast.ratio(none, ZenContrast.resolve(Color(hex: 0x0E110E), in: .dark)) - 1) < 0.001)
    }

    @Test("Reading text clears 4.5:1 on every surface, the ground and glass", arguments: [ColorScheme.light, .dark])
    func text(_ scheme: ColorScheme) {
        let texts: [(String, Color)] = [("heading", zen.textHeading), ("body", zen.textBody), ("caption", zen.textCaption),
                                         ("brand", zen.textBrand), ("reward", zen.accentRewardText),
                                         ("gain", zen.scoreGain), ("deduct", zen.scoreDeduct)]
        for (t, text) in texts {
            for (b, bg) in backgrounds(scheme) {
                let r = ZenContrast.ratio(text, bg, in: scheme)
                #expect(r >= ZenContrast.text, "\(t) on \(b) in \(scheme): \(r)")
            }
        }
    }

    @Test("Primary words clear 4.5:1 at rest, hover and press, sheen included", arguments: [ColorScheme.light, .dark])
    func primary(_ scheme: ColorScheme) {
        for fill in [zen.actionBrand, zen.actionBrandHover, zen.actionBrandPressed] {
            #expect(ZenContrast.ratio(zen.onActionBrand, fill, in: scheme) >= ZenContrast.text)
            // The words sit in the middle, where the top sheen has faded to about half.
            let lit = ZenContrast.composite(.white, opacity: 0.08, over: fill, in: scheme)
            #expect(ZenContrast.ratio(zen.onActionBrand, lit, in: scheme) >= ZenContrast.text)
        }
        // Hover leans away from the ground: deeper by day, brighter at night.
        let ground = zen.surfaceBase
        #expect(ZenContrast.ratio(zen.actionBrandHover, ground, in: scheme) > ZenContrast.ratio(zen.actionBrand, ground, in: scheme))
    }

    @Test("Secondary, destructive and link words clear 4.5:1 in every state", arguments: [ColorScheme.light, .dark])
    func quieter(_ scheme: ColorScheme) {
        for bg in [zen.surfaceRaised, zen.surfaceTint] {
            #expect(ZenContrast.ratio(zen.textHeading, bg, in: scheme) >= ZenContrast.text)
        }
        for bg in [zen.surfaceRaised, zen.scoreDeductTint] {
            #expect(ZenContrast.ratio(zen.scoreDeduct, bg, in: scheme) >= ZenContrast.text)
        }
        for link in [zen.textBrand, zen.actionBrandHover, zen.actionBrandPressed] {
            for (b, bg) in backgrounds(scheme) {
                #expect(ZenContrast.ratio(link, bg, in: scheme) >= ZenContrast.text, "link on \(b) in \(scheme)")
            }
        }
    }

    @Test("Outlines, the disabled state and the focus ring clear 3:1", arguments: [ColorScheme.light, .dark])
    func nonText(_ scheme: ColorScheme) {
        for (name, line) in [("border", zen.controlBorder), ("disabled", zen.controlDisabled), ("focus", zen.focusRing)] {
            for (b, bg) in backgrounds(scheme) {
                let r = ZenContrast.ratio(line, bg, in: scheme)
                #expect(r >= ZenContrast.nonText, "\(name) on \(b) in \(scheme): \(r)")
            }
        }
        // A disabled control reads quieter than an enabled one.
        #expect(ZenContrast.ratio(zen.controlDisabled, zen.surfaceBase, in: scheme)
                < ZenContrast.ratio(zen.textHeading, zen.surfaceBase, in: scheme))
    }

    @Test("The ground is calm: one faint brand light at most")
    func ground() {
        for dark in [false, true] {
            #expect(ZenAurora.lightAlpha(glow: 1, dark: dark) <= 0.12 + 1e-9)
            #expect(ZenAurora.lightAlpha(glow: 0, dark: dark) < ZenAurora.lightAlpha(glow: 1, dark: dark))
            #expect(ZenAurora.lightAlpha(glow: 5, dark: dark) == ZenAurora.lightAlpha(glow: 1, dark: dark))
        }
    }
}
