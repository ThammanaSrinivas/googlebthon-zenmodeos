import SwiftUI
import Albeit
import ZenAPI
import ZenMock

enum CircleCopy {
    static let eyebrow = "Zen Circle"
    static let title = "Your people, and you."
    static let tabYou = "You"
    static let tabBros = "Zen Bros"
    static let subtitleYou = "Your month as a picture, and how to read it."
    static let subtitleBros = "Friends keeping one promise a week. Scores only."
    static let subtitleCohort = "Your campus as one. Group numbers, 5 or more, never a name."
    static let navPeople = "people"
    static let navFriends = "friends"
    static let navDays = "days"
    static let navCohortDetail = "the group"
    static let navBrosDetail = "scores only"
    static let navYouDetail = "your month"
    static let onLastWeek = "on last week"
    static let seatsLine = "seats, no names. The amber one is you."
    static let goodDayLine = "6.0, a good day"

    // You
    static let yourMonth = "Your month"
    static let lastThirty = "Your month · the last 30 days"
    static func youAre(_ a: Archetype) -> String { "You're a \(a.name.lowercased())." }
    static let howToRead = "Gold is focus, green on purpose, rust unplanned, dark the phone at rest. The lit seed is your calmest hour."
    static let focus = "focus hours"
    static let unplanned = "unplanned"
    static let calmest = "calmest hour"
    static let calmestAt = "Calmest at"
    static let share = "Share your month"
    static let changePattern = "Change pattern"
    static let demoHistory = "Demo history"
    static let fourWaysTitle = "Your month, four ways"
    static let fourWaysCaption = "The same 720 hours, drawn four ways. Pick one and Today draws it that way too."
    static let livesTitle = "Same pattern, four different lives"
    static let livesCaption = "Four shapes a month tends to take. Yours sits closest to one of them."
    static let mostLike = "Closest to you"
    static let cardsTitle = "Cards from your month"
    static let cardsCaption = "One insight each. Tap Share to send one; nothing goes out on its own."
    static let tagSignature = "ZENMODE OS · YOUR MONTH"

    // Zen Bros
    static let brosName = "Zen Bros"
    static let brosCode = "ZENBRO7"
    static let inviteCode = "Invite code"
    static let scoresOnly = "Scores only"
    static let invite = "Invite a friend"
    static let inviteCopied = "Invite link copied"
    static let daily = "Today"
    static let weekly = "This week"
    static let ranksReset = "Ranks reset Monday"
    static let reactionsLeft = "reactions left today"
    static let iPhoneSeat = "Only the score leaves their iPhone."
    static let youSeat = "Only your Zen Score leaves your devices."
    static let feedTitle = "This week in Zen Bros"
    static let brosPrivacy = "Your circle sees one number from you: your Zen Score. Never apps, minutes or when you were on."

    // Cohort
    static let you = "You"
    static let goodDaySoFar = "A good day so far"
    static let underSix = "Under 6.0 so far"
    static let privacy = "One group score, only for 5 or more. Never a name, an app or a minute next to it."
    static let trendTitle = "Group score, last 7 days"
    static let mixTitle = "How the hostel's months look"
    static let mixCaption = "Each shape is a blend of 5 or more people. Smaller groups stay hidden."
    static let digestEyebrow = "This week · a sample digest"
    static let digestTitle = "Evenings got calmer"
    static let digest = "62% good days, up from 54% last week. Evenings got calmer after Tuesday, and most pull-backs now land between 9 and 11 pm. Thursday is still the group's hard day."
    static let digestCaption = "Each week Gemini writes the group's digest from group scores only, and never names anyone. This one is a sample."
    static let joinTitle = "Join your campus or team"
    static let joinBody = "They share a six-character code. You'll see one group score, and the group sees yours only inside it."
    static let preview = "Preview · demo circle"
}

/// Zen Circle, as three places instead of one long page, the group first:
/// - **The cohort**: the campus or team as one. Aggregates for 5 or more, never a name.
/// - **Zen Bros**: friends, ranked by Zen Score, with streaks and reactions. Scores only.
/// - **You**: your month as a gallery (the pattern, the same month four ways, the four lives it's
///   compared with, the cards it makes). The only place anyone's hours are drawn, and they're yours.
struct CircleSection: View {
    @Environment(AppModel.self) private var model
    @State private var tab: CircleTab = .cohort

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s6) {
                header
                CircleNav(tab: $tab, places: places)
                Group {
                    switch tab {
                    case .cohort: CohortTab()
                    case .bros: BuddiesTab()
                    case .you: YouGalleryTab()
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .padding(.horizontal, ZenSpace.s8)
            .padding(.vertical, ZenSpace.s6)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .animation(ZenMotion.container, value: tab)
        #if DEBUG
        // Debug renders: ZEN_CIRCLE_TAB=cohort|bros|you, ZEN_CIRCLE_SCROLL=lives|cards|feed|mix.
        .task {
            let env = ProcessInfo.processInfo.environment
            if let raw = env["ZEN_CIRCLE_TAB"], let t = CircleTab(rawValue: raw) { tab = t }
            if let anchor = env["ZEN_CIRCLE_SCROLL"] {
                try? await Task.sleep(for: .milliseconds(500))
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        #endif
        }
    }

    private var cohortName: String { model.cohort?.preview.name ?? FakeCohorts.demo.name }
    private var cohortSize: Int { model.cohort?.preview.memberCount ?? FakeCohorts.demo.memberCount }

    /// The three places, each with what's inside it: a count, never a name beside a number.
    private var places: [CirclePlace] {
        [CirclePlace(tab: .cohort, title: cohortName, symbol: "building.columns.fill",
                     count: cohortSize, unit: CircleCopy.navPeople, detail: CircleCopy.navCohortDetail),
         CirclePlace(tab: .bros, title: CircleCopy.tabBros, symbol: "person.2.fill",
                     count: BuddyDemo.circle.count, unit: CircleCopy.navFriends, detail: CircleCopy.navBrosDetail),
         CirclePlace(tab: .you, title: CircleCopy.tabYou, symbol: "sparkles",
                     count: 30, unit: CircleCopy.navDays, detail: CircleCopy.navYouDetail)]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Eyebrow(CircleCopy.eyebrow, color: Color.zen.textBrand)
            Text(CircleCopy.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).zenType(.body).foregroundStyle(Color.zen.textBody)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        switch tab {
        case .cohort: CircleCopy.subtitleCohort
        case .bros: CircleCopy.subtitleBros
        case .you: CircleCopy.subtitleYou
        }
    }

    static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}

/// The group first, then friends, then you.
enum CircleTab: String, CaseIterable, Identifiable {
    case cohort, bros, you
    var id: String { rawValue }
}

/// One place in Zen Circle, as the navigation shows it.
struct CirclePlace: Identifiable {
    let tab: CircleTab
    let title: String
    let symbol: String
    let count: Int
    let unit: String
    let detail: String
    var id: CircleTab { tab }

    /// What VoiceOver reads: the place, then what's in it.
    var spoken: String { "\(title), \(count) \(unit), \(detail)" }
}

/// The three places as big tabs: an icon, the name, and what's inside, with a green bar under the
/// one that's open. Hard to miss, unlike a small segmented pill. ⌘1 ⌘2 ⌘3 jump between them.
private struct CircleNav: View {
    @Binding var tab: CircleTab
    let places: [CirclePlace]

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            ForEach(Array(places.enumerated()), id: \.element.id) { i, place in
                Button { tab = place.tab } label: {
                    CircleNavLabel(place: place, selected: place.tab == tab)
                }
                .buttonStyle(CircleNavStyle(selected: place.tab == tab))
                .focusEffectDisabled()
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .help("\(place.title) (⌘\(i + 1))")
                .accessibilityLabel(place.spoken)
                .accessibilityAddTraits(place.tab == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zen Circle places")
    }
}

private struct CircleNavLabel: View {
    let place: CirclePlace
    let selected: Bool

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: place.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.zen.textBrand : Color.zen.textBody)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                    .fill(selected ? Color.zen.surfaceTint : Color.zen.surfaceSunk.opacity(0.7)))
            VStack(alignment: .leading, spacing: 3) {
                Text(place.title).font(ZenFont.text(15.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(place.count)").font(ZenFont.number(12)).foregroundStyle(Color.zen.textHeading)
                    Text(place.unit).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textCaption)
                    Text("·").font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textCaption)
                    Text(place.detail).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textCaption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ZenSpace.s4)
        .frame(height: 72)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The tab's surface: raised with a green underline when open, a quiet wash on hover, a visible
/// ring for the keyboard, a small press.
private struct CircleNavStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        NavBody(configuration: configuration, selected: selected)
    }

    private struct NavBody: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovering = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
            configuration.label
                .background {
                    shape.fill(selected ? Color.zen.surfaceRaised : Color.zen.surfaceCard.opacity(hovering ? 0.95 : 0.55))
                }
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule().fill(Color.zen.brandFill).frame(height: 3).padding(.horizontal, ZenSpace.s5)
                            .transition(.opacity)
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(selected ? Color.zen.brandFill.opacity(0.55) : Color.zen.borderOutline.opacity(hovering ? 1 : 0.6),
                                       lineWidth: selected ? 1.5 : 1)
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: ZenRadius.xl + 3, style: .continuous)
                            .strokeBorder(Color.zen.textBrand, lineWidth: 2).padding(-3)
                    }
                }
                .modifier(SelectedLift(on: selected))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: hovering)
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
        }
    }
}

private struct SelectedLift: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.modifier(ZenLift()) } else { content }
    }
}

/// One idea per panel: a title, an optional caption and trailing accessory, then the content.
struct CirclePanel<Trailing: View, Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).zenType(.title).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    if let caption {
                        Text(caption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: ZenSpace.s3)
                trailing
            }
            content
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.xxxl)
    }
}

extension CirclePanel where Trailing == EmptyView {
    init(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// Primary (ink pill) or secondary (glass), by whether it's the tab's main action.
struct CircleActionStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        if primary {
            ZenPrimaryButtonStyle().makeBody(configuration: configuration)
        } else {
            ZenSecondaryButtonStyle().makeBody(configuration: configuration)
        }
    }
}

/// Bloom · Kolam · Garland · Horizon, as a quiet segmented pill.
struct PatternPicker: View {
    @Binding var selection: PatternKind

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PatternKind.allCases) { k in
                Button { selection = k } label: {
                    Text(k.rawValue)
                        .font(ZenFont.text(13, k == selection ? .semibold : .medium))
                        .foregroundStyle(k == selection ? Color.zen.textHeading : Color.zen.textBody)
                        .padding(.horizontal, ZenSpace.s4).frame(height: 32)
                        .background { if k == selection { Capsule().fill(Color.zen.surfaceRaised).modifier(ZenLift()) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(k == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.zen.surfaceSunk))
    }
}

/// Your month as a picture to share: the pattern, its name, the lockup. Hours as a shape, never
/// minutes or apps.
struct MonthShareImage: View {
    let month: PersonalMonth
    let kind: PatternKind

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("ZENMODE OS · MY MONTH AS A \(kind.rawValue.uppercased())").font(ZenFont.number(11)).tracking(1.1).foregroundStyle(Color(hex: 0xA4A9A0))
            PatternTile(month: month.hours, kind: kind).frame(width: 444, height: 444)
            Text(month.closest.name).font(ZenFont.brand(34)).foregroundStyle(Color(hex: 0xF2F3EE))
            Text("Calmest at \(CircleSection.clock(month.calmestHour)) · zenmodeos.com").font(ZenFont.text(15)).foregroundStyle(Color(hex: 0xC9CCC4))
        }
        .padding(48)
        .frame(width: 540, height: 675 + 120, alignment: .topLeading)
        .background(InkTable())
    }
}
