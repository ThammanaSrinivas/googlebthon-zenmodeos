import SwiftUI

// MARK: - Actions: three levels, never two primaries
//
// Every screen has one primary (solid green), any number of secondaries (outlined, quiet) and
// tertiary links (words in the brand green, underlined on hover). Each style reads the environment:
// `isEnabled`, `isFocused` (the keyboard focus ring), `controlSize` (mini 28 pt, small 32, regular 40,
// large 48) and Reduce Motion (no press scale, no state animation). Hover leans the green further from
// the ground: deeper by day, brighter at night. Disabled controls lose their fill, take a dashed outline
// in `controlDisabled` (still ≥ 3:1) and ignore hover.
//
//     Button("Invite the team") { … }.buttonStyle(.zenPrimary)
//     Button("Export") { … }.buttonStyle(.zenSecondary)
//     Button("See all") { … }.buttonStyle(.zenLink)
//     Button("Remove", role: .destructive) { … }.buttonStyle(.zenSecondary)   // or .zenDestructive

/// The size of a Zen button, from the environment's `controlSize`. Never under 28 pt high.
struct ZenButtonMetrics: Equatable {
    let height: CGFloat
    let padding: CGFloat
    let font: CGFloat
    let radius: CGFloat

    init(_ size: ControlSize) {
        switch size {
        case .mini: (height, padding, font, radius) = (28, ZenSpace.s3, 12, ZenRadius.sm)
        case .small: (height, padding, font, radius) = (32, 14, 13, 10)
        case .large, .extraLarge: (height, padding, font, radius) = (48, ZenSpace.s6, 15, 14)
        default: (height, padding, font, radius) = (40, ZenSpace.s5, 14, ZenRadius.md)
        }
    }

    /// A link carries no fill, so it only needs the hit target: 28 pt when small, 32 otherwise.
    static func linkHeight(_ size: ControlSize) -> CGFloat {
        switch size {
        case .mini, .small: 28
        default: 32
        }
    }
}

/// What a control is doing right now. Hover never counts when the control is disabled.
struct ZenControlState: Equatable {
    var enabled: Bool
    var hovering: Bool
    var pressed: Bool

    var hot: Bool { enabled && (hovering || pressed) }
}

enum ZenButtonKind { case primary, secondary, destructive }

/// Primary: the one solid call to action on a screen. Deep brand green with white words by day,
/// bright brand green with ink words at night, lit from above with a soft green lift beneath.
public struct ZenPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        ZenButtonBody(configuration: configuration, kind: configuration.role == .destructive ? .destructive : .primary)
    }
}

/// Secondary: outlined and quiet, raised paper with a ≥ 3:1 edge. On hover it takes the brand tint
/// and a green edge. A `role: .destructive` button in this style is drawn as `ZenDestructiveButtonStyle`.
public struct ZenSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        ZenButtonBody(configuration: configuration, kind: configuration.role == .destructive ? .destructive : .secondary)
    }
}

/// Destructive: a secondary weight in the deduction hue (remove, leave, disconnect). It never shouts
/// in a solid fill; the confirmation step asks again.
public struct ZenDestructiveButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        ZenButtonBody(configuration: configuration, kind: .destructive)
    }
}

/// Tertiary: words in the brand green, underlined on hover and press. For "See all", "Learn more",
/// "Not now": actions that should never compete with the primary.
public struct ZenLinkButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        ZenLinkBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == ZenPrimaryButtonStyle {
    /// The one primary action on a screen.
    public static var zenPrimary: ZenPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ZenSecondaryButtonStyle {
    /// A secondary action: outlined, quiet.
    public static var zenSecondary: ZenSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == ZenDestructiveButtonStyle {
    /// A destructive action at secondary weight.
    public static var zenDestructive: ZenDestructiveButtonStyle { .init() }
}

extension ButtonStyle where Self == ZenLinkButtonStyle {
    /// A tertiary, text-only action.
    public static var zenLink: ZenLinkButtonStyle { .init() }
}

// MARK: - Bodies

private struct ZenButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ZenButtonKind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let m = ZenButtonMetrics(controlSize)
        let state = ZenControlState(enabled: isEnabled, hovering: hovering, pressed: configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: m.radius, style: .continuous)
        configuration.label
            .font(ZenFont.text(m.font, .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground(state))
            .padding(.horizontal, m.padding)
            .frame(minHeight: m.height)
            .background { fill(shape, state) }
            .overlay { edge(shape, state) }
            .contentShape(shape)
            .background { ZenFocusRing(radius: m.radius, visible: isFocused && isEnabled) }
            .scaleEffect(state.enabled && state.pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: state)
            .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: isFocused)
            .onHover { hovering = $0 }
    }

    private var dark: Bool { scheme == .dark }

    private func foreground(_ s: ZenControlState) -> Color {
        guard s.enabled else { return Color.zen.controlDisabled }
        switch kind {
        case .primary: return Color.zen.onActionBrand
        case .secondary: return Color.zen.textHeading
        case .destructive: return Color.zen.scoreDeduct
        }
    }

    @ViewBuilder
    private func fill(_ shape: RoundedRectangle, _ s: ZenControlState) -> some View {
        if !s.enabled {
            shape.fill(Color.zen.textHeading.opacity(dark ? 0.04 : 0.03))
        } else {
            switch kind {
            case .primary:
                let base = s.pressed ? Color.zen.actionBrandPressed : s.hovering ? Color.zen.actionBrandHover : Color.zen.actionBrand
                shape.fill(base)
                    // Lit from above: a faint sheen in the top half, never enough to cost contrast.
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(s.pressed ? 0 : (dark ? 0.16 : 0.10)), .white.opacity(0)],
                                                       startPoint: .top, endPoint: .center)))
                    .shadow(color: Color.zen.actionBrand.opacity(s.pressed ? 0 : (dark ? 0.22 : 0.26)),
                            radius: s.hovering ? 10 : 6, y: s.hovering ? 4 : 3)
            case .secondary:
                shape.fill(s.hot ? Color.zen.surfaceTint : Color.zen.surfaceRaised)
                    .overlay(shape.fill(Color.zen.actionBrand.opacity(s.pressed ? 0.10 : 0)))
                    .shadow(color: Color(hex: 0x12160F, alpha: s.pressed || dark ? 0 : 0.05), radius: 1.5, y: 1)
            case .destructive:
                shape.fill(s.hot ? Color.zen.scoreDeductTint : Color.zen.surfaceRaised)
                    .overlay(shape.fill(Color.zen.scoreDeduct.opacity(s.pressed ? 0.10 : 0)))
                    .shadow(color: Color(hex: 0x12160F, alpha: s.pressed || dark ? 0 : 0.05), radius: 1.5, y: 1)
            }
        }
    }

    @ViewBuilder
    private func edge(_ shape: RoundedRectangle, _ s: ZenControlState) -> some View {
        if !s.enabled {
            shape.strokeBorder(Color.zen.controlDisabled, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else {
            switch kind {
            case .primary:
                // A hairline bevel: light on the top edge, the fill's own deeper green below.
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.35 : 0.22), .white.opacity(0)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            case .secondary:
                shape.strokeBorder(s.hot ? Color.zen.actionBrand : Color.zen.controlBorder, lineWidth: 1)
            case .destructive:
                shape.strokeBorder(Color.zen.scoreDeduct.opacity(s.hot ? 1 : 0.85), lineWidth: 1)
            }
        }
    }
}

private struct ZenLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let state = ZenControlState(enabled: isEnabled, hovering: hovering, pressed: configuration.isPressed)
        configuration.label
            .font(ZenFont.text(controlSize == .mini || controlSize == .small ? 12.5 : 13.5, .semibold))
            .foregroundStyle(color(state))
            .underline(state.hot, color: color(state))
            .frame(minHeight: ZenButtonMetrics.linkHeight(controlSize))
            .contentShape(Rectangle())
            .background { ZenFocusRing(radius: ZenRadius.xs, visible: isFocused && isEnabled, outset: CGSize(width: ZenSpace.s2, height: 0)) }
            .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: state)
            .onHover { hovering = $0 }
            #if os(macOS)
            .pointerStyle(isEnabled ? .link : nil)
            #endif
    }

    private func color(_ s: ZenControlState) -> Color {
        guard s.enabled else { return Color.zen.controlDisabled }
        if s.pressed { return Color.zen.actionBrandPressed }
        return s.hovering ? Color.zen.actionBrandHover : Color.zen.textBrand
    }
}

/// The keyboard focus ring: 2 pt in `focusRing`, drawn `outset` outside the control's own corners.
struct ZenFocusRing: View {
    let radius: CGFloat
    let visible: Bool
    var outset: CGSize = CGSize(width: 3, height: 3)

    var body: some View {
        RoundedRectangle(cornerRadius: radius + min(outset.width, outset.height), style: .continuous)
            .strokeBorder(Color.zen.focusRing, lineWidth: 2)
            .padding(.horizontal, -outset.width)
            .padding(.vertical, -outset.height)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
    }
}
