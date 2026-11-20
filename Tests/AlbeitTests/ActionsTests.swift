import SwiftUI
import Testing
@testable import Albeit

@Suite("Albeit: the three levels of action")
@MainActor
struct ActionsTests {
    @Test("Primary, secondary, tertiary and destructive styles exist, by name and by shorthand")
    func styles() {
        let primary: ZenPrimaryButtonStyle = .zenPrimary
        let secondary: ZenSecondaryButtonStyle = .zenSecondary
        let link: ZenLinkButtonStyle = .zenLink
        let destructive: ZenDestructiveButtonStyle = .zenDestructive
        _ = (primary, secondary, link, destructive, ZenPrimaryButtonStyle(), ZenSecondaryButtonStyle(), ZenLinkButtonStyle())
    }

    @Test("Every size is at least 28 pt high and grows in order")
    func sizes() {
        let sizes: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
        let heights = sizes.map { ZenButtonMetrics($0).height }
        #expect(heights.allSatisfy { $0 >= 28 })
        #expect(heights == heights.sorted())
        #expect(ZenButtonMetrics(.regular).height == 40)
        #expect(sizes.allSatisfy { ZenButtonMetrics.linkHeight($0) >= 28 })
        // Words stay readable: never below 12 pt.
        #expect(sizes.allSatisfy { ZenButtonMetrics($0).font >= 12 })
    }

    @Test("A disabled control never lights up on hover or press")
    func disabled() {
        #expect(!ZenControlState(enabled: false, hovering: true, pressed: true).hot)
        #expect(ZenControlState(enabled: true, hovering: true, pressed: false).hot)
        #expect(ZenControlState(enabled: true, hovering: false, pressed: true).hot)
        #expect(!ZenControlState(enabled: true, hovering: false, pressed: false).hot)
    }

    @Test("Buttons render in every style, size and scheme, at least 28 pt high")
    func renders() {
        for scheme in [ColorScheme.light, .dark] {
            for size in [ControlSize.mini, .regular, .large] {
                for enabled in [true, false] {
                    let row = HStack {
                        Button("Invite") {}.buttonStyle(.zenPrimary)
                        Button("Export") {}.buttonStyle(.zenSecondary)
                        Button("Remove", role: .destructive) {}.buttonStyle(.zenSecondary)
                        Button("See all") {}.buttonStyle(.zenLink)
                    }
                    .controlSize(size)
                    .disabled(!enabled)
                    .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: row)
                    renderer.scale = 1
                    let image = renderer.cgImage
                    #expect(image != nil)
                    #expect(CGFloat(image?.height ?? 0) >= 28)
                }
            }
        }
    }
}

@Suite("Albeit: the bloom ornament")
@MainActor
struct OrnamentTests {
    @Test("Seeds follow the size, stay inside the bloom and grow toward the rim", arguments: [24.0, 60, 180, 260])
    func seeds(_ radius: Double) {
        let r = CGFloat(radius)
        let seeds = ZenBloomOrnament.bloomSeeds(radius: r)
        #expect((34...700).contains(seeds.count))
        for s in seeds {
            #expect(hypot(s.offset.x, s.offset.y) + s.size / 2 <= r)
            #expect(s.size > 0 && (0...1).contains(s.t))
        }
        #expect(seeds.first!.size < seeds.last!.size)
    }

    @Test("A bigger bloom has more seeds, never more than 700")
    func scaling() {
        let counts = [24.0, 60, 120, 180, 260, 400].map { ZenBloomOrnament.bloomSeeds(radius: CGFloat($0)).count }
        #expect(counts == counts.sorted())
        #expect(counts.last! <= 700)
        #expect(ZenBloomOrnament.bloomSeeds(radius: 1).isEmpty)
    }

    @Test("The kolam lattice stays inside its circle", arguments: [96.0, 260, 480])
    func kolam(_ side: Double) {
        let s = CGFloat(side)
        let dots = ZenBloomOrnament.kolamDots(side: s)
        #expect(dots.count >= 9)
        for p in dots { #expect(hypot(p.x - s / 2, p.y - s / 2) <= s / 2) }
    }
}
