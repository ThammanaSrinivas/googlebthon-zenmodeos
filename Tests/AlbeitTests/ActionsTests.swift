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
