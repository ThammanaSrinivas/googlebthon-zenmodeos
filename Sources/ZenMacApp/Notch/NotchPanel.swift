import AppKit
import SwiftUI

/// A borderless, click-through panel pinned to the top centre of the built-in screen, so the black
/// shape grows out of the real notch. On a screen without a notch it hangs from the top edge.
@MainActor
final class NotchPanelController {
    private let panel: NotchPanel
    static let size = CGSize(width: 560, height: 220)

    init(model: NotchModel) {
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.size))
        let screen = Self.notchedScreen()
        let notch = Self.notchSize(on: screen)
        let host = NSHostingView(rootView: NotchView(model: model, notch: notch))
        host.sizingOptions = []
        panel.contentView = host
        place(on: screen)
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(on: Self.notchedScreen()) }
        }
    }

    private func place(on screen: NSScreen?) {
        guard let screen else { return }
        let f = screen.frame
        panel.setFrame(CGRect(x: f.midX - Self.size.width / 2, y: f.maxY - Self.size.height,
                              width: Self.size.width, height: Self.size.height), display: true)
    }

    /// The built-in display if it has a notch, otherwise the main screen.
    static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// The camera housing's size, so the resting shape sits exactly on it.
    static func notchSize(on screen: NSScreen?) -> CGSize {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
}

final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        setAccessibilityRole(.popover)
        setAccessibilityLabel("Zeno")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// The menu bar is allowed: the shape lives in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
