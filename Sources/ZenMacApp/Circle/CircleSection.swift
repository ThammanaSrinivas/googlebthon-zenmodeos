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
    static let invite = "Invite a friend"
    static let inviteCopied = "Invite link copied"
    static let daily = "Today"
    static let weekly = "This week"
    static let ranksReset = "Ranks reset Monday"
    static let reactionsLeft = "reactions left today"
    static let iPhoneSeat = "Counted on their iPhone. Only the score is shared."
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
    static let digestEyebrow = "This week in the circle · Gemini"
    static let digestTitle = "Evenings got calmer"
    static let digest = "62% good days, up from 54% last week. Evenings got calmer after Tuesday, and most pull-backs now land between 9 and 11 pm. Thursday is still the group's hard day."
    static let digestCaption = "Written by Gemini from group scores only. It never names anyone."
    static let joinTitle = "Join your campus or team"
    static let joinBody = "They share a six-character code. You'll see one group score, and the group sees yours only inside it."
    static let preview = "Preview · demo circle"
}

/// Zen Circle, as three places instead of one long page:
/// - **You**: your month as a gallery (the pattern, the same month four ways, the four lives it's
///   compared with, the cards it makes). The only place anyone's hours are drawn, and they're yours.
/// - **Zen Bros**: friends, ranked by Zen Score, with streaks and reactions. Scores only.
/// - **The cohort**: the campus or team as one. Aggregates for 5 or more, never a name.
struct CircleSection: View {
    @Environment(AppModel.self) private var model
    @State private var tab: CircleTab = .you

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s6) {
                header
                Group {
                    switch tab {
                    case .you: YouGalleryTab()
                    case .bros: BuddiesTab()
                    case .cohort: CohortTab()
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .padding(.horizontal, ZenSpace.s6)
            .padding(.vertical, ZenSpace.s6)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .animation(ZenMotion.container, value: tab)
        #if DEBUG
        // Debug renders: ZEN_CIRCLE_TAB=you|bros|cohort, ZEN_CIRCLE_SCROLL=lives|cards|feed|mix.
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: ZenSpace.s6) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(CircleCopy.eyebrow, color: Color.zen.textBrand)
                Text(CircleCopy.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).zenType(.body).foregroundStyle(Color.zen.textCaption)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: ZenSpace.s4)
            CircleTabSwitch(tab: $tab, cohortName: cohortName)
        }
    }

    private var subtitle: String {
        switch tab {
        case .you: CircleCopy.subtitleYou
        case .bros: CircleCopy.subtitleBros
        case .cohort: CircleCopy.subtitleCohort
        }
    }

    static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}

enum CircleTab: String, CaseIterable, Identifiable {
    case you, bros, cohort
    var id: String { rawValue }
}

/// You · Zen Bros · the cohort: a quiet segmented pill with a glyph per place.
private struct CircleTabSwitch: View {
    @Binding var tab: CircleTab
    let cohortName: String

    var body: some View {
        HStack(spacing: 2) {
            item(.you, CircleCopy.tabYou, "sparkles")
            item(.bros, CircleCopy.tabBros, "person.2.fill")
            item(.cohort, cohortName, "building.columns.fill")
        }
        .padding(4)
        .background(Capsule().fill(Color.zen.surfaceSunk))
    }

    private func item(_ t: CircleTab, _ label: String, _ symbol: String) -> some View {
        let on = t == tab
        return Button { tab = t } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(ZenFont.text(13.5, on ? .semibold : .medium))
            }
            .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textBody)
            .padding(.horizontal, ZenSpace.s4).frame(height: 34)
            .background { if on { Capsule().fill(Color.zen.surfaceRaised).modifier(ZenLift()) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
