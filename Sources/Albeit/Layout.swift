import SwiftUI

// MARK: - Section header

/// The head of a section: an eyebrow, a title in the brand voice, an optional line under it and an
/// optional trailing action (usually a `.zenLink` or `.zenSecondary` button). The title is a VoiceOver
/// heading. Use one per compartment so look-alike groups read as one system on every screen.
///
///     ZenSectionHeader("Your team", eyebrow: "Team admin", subtitle: "12 people, 3 invites waiting") {
///         Button("Invite") { … }.buttonStyle(.zenSecondary)
///     }
public struct ZenSectionHeader<Trailing: View>: View {
    public enum Level: Sendable { case page, section, group }

    let title: String
    let eyebrow: String?
    let subtitle: String?
    let level: Level
    let trailing: Trailing

    /// - Parameters:
    ///   - title: the heading (Clash Display: 30 pt for a page, 22 for a section; Geist 15 semibold for a group).
    ///   - eyebrow: a short label above, in Departure caps.
    ///   - subtitle: one line of context below, in the caption voice.
    ///   - level: how high in the page it sits.
    ///   - trailing: an action aligned to the title's baseline.
    public init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil, level: Level = .section,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.level = level
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: level == .group ? ZenSpace.s1 : ZenSpace.s2) {
                if let eyebrow { Eyebrow(eyebrow) }
                titleText
                    .foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: ZenSpace.s4)
            trailing
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var titleText: some View {
        switch level {
        case .page: Text(title).zenType(.headline)
        case .section: Text(title).zenType(.title)
        case .group: Text(title).font(ZenFont.text(15, .semibold))
        }
    }
}

extension ZenSectionHeader where Trailing == EmptyView {
    /// A header with no trailing action.
    public init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil, level: Level = .section) {
        self.init(title, eyebrow: eyebrow, subtitle: subtitle, level: level) { EmptyView() }
    }
}

// MARK: - Card

/// How a `ZenCard` sits on the page.
public enum ZenCardEmphasis: Sendable {
    /// Glass over the ground, with a hairline: the default compartment.
    case standard
    /// A sunk well inside another card, for rows and look-alike items grouped within it.
    case inset
    /// Glass in the brand tint: the one compartment that's about doing well or acting now.
    case brand
    /// Glass in the reward tint: gold, wins. At most one per screen.
    case reward
}

/// A compartment: padded content on glass (or a sunk well), with Albeit's radius, hairline and lift.
/// Use it for every group of look-alike things so screens share one rhythm.
///
///     ZenCard { ZenSectionHeader("Integrations", level: .group); … }
///     ZenCard(.inset, padding: ZenSpace.s3) { row }
public struct ZenCard<Content: View>: View {
    let emphasis: ZenCardEmphasis
    let padding: CGFloat
    let radius: CGFloat
    let content: Content

    /// - Parameters:
    ///   - emphasis: standard glass, an inset well, brand or reward tint.
    ///   - padding: inner padding (default 20 pt; 12 for inset).
    ///   - radius: corner radius (default 24 pt; 16 for inset).
    public init(_ emphasis: ZenCardEmphasis = .standard, padding: CGFloat? = nil, radius: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.emphasis = emphasis
        self.padding = padding ?? (emphasis == .inset ? ZenSpace.s3 : ZenSpace.s5)
        self.radius = radius ?? (emphasis == .inset ? ZenRadius.lg : ZenRadius.xxl)
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ZenCardSurface(emphasis: emphasis, radius: radius))
    }
}

extension View {
    /// Wraps the view as a `ZenCard` compartment (padding included).
    public func zenCard(_ emphasis: ZenCardEmphasis = .standard, padding: CGFloat? = nil, radius: CGFloat? = nil) -> some View {
        ZenCard(emphasis, padding: padding, radius: radius) { self }
    }
}

private struct ZenCardSurface: ViewModifier {
    let emphasis: ZenCardEmphasis
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch emphasis {
        case .inset:
            content
                .background(shape.fill(Color.zen.surfaceSunk.opacity(scheme == .dark ? 0.7 : 0.6)))
                .overlay(shape.strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        case .standard:
            content
                .glassCard(radius: radius)
                .overlay(shape.strokeBorder(Color.zen.borderHairline.opacity(0.8), lineWidth: 1))
        case .brand:
            content
                .glassCard(radius: radius, tint: Color.zen.surfaceTint)
                .overlay(shape.strokeBorder(Color.zen.brandFill.opacity(0.22), lineWidth: 1))
        case .reward:
            content
                .glassCard(radius: radius, tint: Color.zen.accentReward.opacity(0.10))
                .overlay(shape.strokeBorder(Color.zen.accentReward.opacity(0.35), lineWidth: 1))
        }
    }
}
