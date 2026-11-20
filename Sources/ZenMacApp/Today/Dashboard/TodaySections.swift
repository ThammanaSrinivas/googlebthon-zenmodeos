import SwiftUI
import Albeit

/// Today's compartments, in reading order: act, see, plan, earn, play. Each one opens with a
/// numbered header so look-alike cards read as one group.
enum TodaySection: Int, CaseIterable, Identifiable {
    case now = 1, day, work, rewards, play

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .day: "Your day"
        case .work: "Work"
        case .rewards: "Rewards & circle"
        case .play: "Play"
        }
    }

    var line: String {
        switch self {
        case .now: "One switch for quiet, and what came in while you focused."
        case .day: "The Zen Score from every screen, and where this Mac's minutes went."
        case .work: "Plan the day, wrap it up, and your team."
        case .rewards: "Your circle, and the gold a won week opens."
        case .play: "What Zeno noticed, dealt as cards."
        }
    }

    /// "01", "02" … in Departure Mono.
    var number: String { String(format: "%02d", rawValue) }
}

/// A section header: the number, the Clash title, one quiet line, an optional control on the
/// right, and a hairline with a short green lead that closes the compartment's top edge.
struct TodaySectionHeader<Accessory: View>: View {
    let section: TodaySection
    @ViewBuilder var accessory: () -> Accessory

    init(_ section: TodaySection, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.section = section
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(alignment: .center, spacing: ZenSpace.s4) {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                    Text(section.number)
                        .font(ZenFont.number(13))
                        .foregroundStyle(Color.zen.textBrand)
                    Text(section.title)
                        .font(ZenFont.brand(24)).tracking(-0.5)
                        .foregroundStyle(Color.zen.textHeading)
                    ViewThatFits(in: .horizontal) {
                        Text(section.line).font(ZenFont.text(13)).foregroundStyle(Color.zen.textCaption).lineLimit(1)
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(section.title). \(section.line)")
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ZenSpace.s3)
                accessory()
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.zen.borderHairline).frame(height: 1)
                Capsule().fill(Color.zen.brandFill).frame(width: 28, height: 2)
            }
            .accessibilityHidden(true)
        }
    }
}

extension TodaySectionHeader where Accessory == EmptyView {
    init(_ section: TodaySection) {
        self.init(section) { EmptyView() }
    }
}

/// A small icon-only button (close, tick, remove): a soft disc on hover, a press dip, a 28-pt target.
struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietIconBody(configuration: configuration)
    }

    private struct QuietIconBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(minWidth: 28, minHeight: 28)
                .background(Circle().fill(Color.zen.textHeading.opacity(hovering ? 0.08 : 0)))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(ZenMotion.calm(ZenMotion.t1), value: hovering)
                .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
        }
    }
}

/// A card that opens somewhere: a click anywhere on it opens, and pointing at it lifts it a touch and
/// rims it in green. The card's own link stays the keyboard's way in. Still under Reduce Motion.
struct OpensOnClick: ViewModifier {
    let radius: CGFloat
    let label: String
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.zen.brandFill.opacity(hovering ? 0.55 : 0), lineWidth: 1.5)
                .allowsHitTesting(false))
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .shadow(color: Color(hex: 0x12160F, alpha: hovering ? 0.1 : 0), radius: 16, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture(perform: open)
            .onHover { hovering = $0 }
            .pointerStyle(.link)
            .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
            .accessibilityAction(named: label, open)
    }
}

extension View {
    func opensOnClick(radius: CGFloat, label: String, _ open: @escaping () -> Void) -> some View {
        modifier(OpensOnClick(radius: radius, label: label, open: open))
    }
}
