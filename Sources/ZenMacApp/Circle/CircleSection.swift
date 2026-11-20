import SwiftUI
import Albeit
import ZenAPI
import ZenMock

enum CircleCopy {
    static let eyebrow = "Zen Circle"
    static let yourMonth = "Your month"
    static let lastThirty = "Your month · the last 30 days"
    static func youAre(_ a: Archetype) -> String { "You're a \(a.name.lowercased())." }
    static let howToRead = "Every seed is one hour of your last 30 days: midnight at the heart, the evening at the rim. Gold is focus, green on purpose, rust unplanned, dark the phone at rest. The lit seed is your calmest hour."
    static let focus = "focus hours"
    static let unplanned = "unplanned hours"
    static let calmest = "your calmest hour"
    static let calmestAt = "Calmest at"
    static let onToday = "Your pick shows on Today, too."
    static let share = "Share your month"
    static let changePattern = "Change pattern"
    static let demoHistory = "Demo history"
    static let circle = "Your circle"
    static let privacy = "One group score, only for 5 or more. Never a name, an app or a minute next to it."
    static let you = "You"
    static let goodDaySoFar = "A good day so far"
    static let underSix = "Under 6.0 so far"
    static let patternsEyebrow = "Your circle's months · each a blend of 5 or more"
    static let patternsTitle = "Same pattern, four different lives."
    static let mostLike = "You're most like this"
    static let patternsPrivacy = "Groups under 5 stay hidden, so nobody can be picked out."
    static let digestEyebrow = "This week in the circle · Gemini"
    static let digestTitle = "Evenings got calmer"
    static let digest = "62% good days, up from 54% last week. Evenings got calmer after Tuesday, and most pull-backs now land between 9 and 11 pm. Thursday is still the group's hard day."
    static let digestCaption = "Written by Gemini from group scores only. It never names anyone."
    static let cardsEyebrow = "Cards from your month"
    static let tagSignature = "ZENMODE OS · YOUR MONTH"
    static let joinTitle = "Join your circle"
    static let joinBody = "Your campus or team shares a six-character code. You'll see one group score, and the group sees yours only inside it."
    static let preview = "Preview · demo circle"
}

/// Zen Circle. You first: your own month as a pattern (the pick carries to Today), then your circle
/// as one (scores only, 5 or more), the shapes of month the circle tends to have, and three cards.
struct CircleSection: View {
    @Environment(AppModel.self) private var model

    private var summary: CohortSummary {
        model.cohort ?? CohortSummary(preview: FakeCohorts.demo, score: ZenScore(tenths: 74), goodDayRate: 0.62)
    }

    private static let groups: [(Archetype, Int)] = [(.morning, 7), (.nightOwl, 5), (.weekender, 6), (.deepWorker, 5)]
    private static let months: [Archetype: MonthHours] = Dictionary(uniqueKeysWithValues: Archetype.allCases.map { ($0, $0.month(seed: 2026)) })
    private let mine = PersonalMonth.demo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s8) {
                if model.cohort == nil { JoinCircleCard() }
                hero
                circle
                archetypes
                cards
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
        .animation(ZenMotion.calm(ZenMotion.t2), value: model.preferences.values.pattern)
    }

    // MARK: Your month

    private var hero: some View {
        @Bindable var prefs = model.preferences
        let kind = prefs.values.pattern
        return HStack(alignment: .top, spacing: ZenSpace.s8) {
            PatternTile(month: mine.hours, kind: kind)
                .frame(width: 380, height: 380)
                .id(kind)
                .transition(.opacity)
                .modifier(ZenLift())
                .accessibilityLabel("Your month as a \(kind.rawValue)")
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow(CircleCopy.lastThirty, color: Color.zen.textBrand)
                    DemoTag(CircleCopy.demoHistory)
                }
                Text(CircleCopy.youAre(mine.closest)).zenType(.display).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(CircleCopy.howToRead).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                PatternPicker(selection: $prefs.values.pattern)
                HStack(spacing: ZenSpace.s3) {
                    fact("\(mine.focusHours)", CircleCopy.focus, Color(hex: 0xE2B000))
                    fact("\(mine.unplannedHours)", CircleCopy.unplanned, Color(hex: 0xD9541E))
                    fact(Self.clock(mine.calmestHour), CircleCopy.calmest, Color.zen.brandFill)
                }
                HStack(spacing: ZenSpace.s4) {
                    ShareImageButton(fileName: "ZenMode OS month.png", make: { ImageExport.png(MonthShareImage(month: mine, kind: kind)) }) {
                        Label(CircleCopy.share, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ShareStyle(primary: model.cohort != nil))
                    Label(CircleCopy.onToday, systemImage: "sun.max").font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textCaption)
                }
                .padding(.top, ZenSpace.s1)
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private func fact(_ value: String, _ label: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(hue).frame(width: 8, height: 8)
                Text(label).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            Text(value).font(ZenFont.number(26)).foregroundStyle(Color.zen.textHeading)
        }
        .padding(ZenSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Your circle

    private var circle: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: ZenSpace.s2) {
                        Eyebrow("\(CircleCopy.circle) · \(s.preview.organisation) · \(s.preview.memberCount) people")
                        if model.cohort == nil { DemoTag(CircleCopy.preview) } else if model.isDemo { DemoTag() }
                    }
                    Text("\(s.preview.name), as one.").zenType(.headline).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Text("▲ 0.3 on last week").font(ZenFont.number(12)).foregroundStyle(Color.zen.scoreGain)
            }
            HStack(alignment: .top, spacing: ZenSpace.s5) {
                VStack(alignment: .leading, spacing: ZenSpace.s3) {
                    if let score = s.score {
                        FaceCardPair(you: model.snapshot?.score ?? ZenScore(tenths: 81), circleName: s.preview.name,
                                     circle: score, goodDayRate: s.goodDayRate ?? 0)
                    }
                    seats(s.preview.memberCount)
                    Text(CircleCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                digestCard
            }
        }
    }

    private func seats(_ n: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<min(n, 24), id: \.self) { i in
                RoundedRectangle(cornerRadius: ZenRadius.cell)
                    .fill(i == 0 ? Color.zen.accentReward : Color.zen.brandFill.opacity([0.9, 0.5, 0.72][i % 3]))
                    .frame(width: 12, height: 12)
            }
            Text("\(n) seats").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption).padding(.leading, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) seats, no names")
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(CircleCopy.digestEyebrow)
                Spacer()
                DemoTag()
            }
            Text(CircleCopy.digestTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(CircleCopy.digest).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(CircleCopy.digestCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
    }

    // MARK: The circle's months

    private var archetypes: some View {
        let kind = model.preferences.values.pattern
        let closest = mine.closest
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(CircleCopy.patternsEyebrow)
                Text(CircleCopy.patternsTitle).zenType(.headline).foregroundStyle(Color.zen.textHeading)
            }
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                ForEach(Self.groups, id: \.0) { archetype, people in
                    archetypeCard(archetype, people: people, kind: kind, isYou: archetype == closest)
                }
            }
            Text(CircleCopy.patternsPrivacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    private func archetypeCard(_ a: Archetype, people: Int, kind: PatternKind, isYou: Bool) -> some View {
        let month = Self.months[a]!
        return VStack(alignment: .leading, spacing: ZenSpace.s2) {
            PatternTile(month: month, kind: kind)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isYou {
                        RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color.zen.accentReward, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isYou {
                        Text(CircleCopy.mostLike).font(ZenFont.text(11, .semibold)).foregroundStyle(Color(hex: 0x1A1003))
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(Color.zen.accentReward))
                            .padding(10)
                    }
                }
                .id(kind)
                .transition(.opacity)
            HStack(alignment: .firstTextBaseline) {
                Text(a.name).font(ZenFont.brand(18)).foregroundStyle(Color.zen.textHeading)
                Spacer()
                Text("\(people) people").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
            }
            Text(a.line).zenType(.caption).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Text("Calmest at \(Self.clock(a.mindfulHour))".uppercased())
                .font(ZenFont.number(9.5)).tracking(0.8).foregroundStyle(Color.zen.textBrand)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.name), a blend of \(people) people. \(a.line)\(isYou ? " You're most like this." : "")")
    }

    // MARK: Cards

    private var cards: some View {
        let streak = model.streak?.currentStreak ?? 9
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Eyebrow(CircleCopy.cardsEyebrow)
            ScrollView(.horizontal) {
                HStack(spacing: ZenSpace.s5) {
                    ZenTag(tone: .zen, question: "When are you calmest?", answer: mine.calmestPart,
                           detail: "\(Self.clock(mine.calmestHour)) was your most focused hour across the last 30 days.", seed: 0xA11CE)
                    ZenTag(tone: .zen, question: "What does your month look like?", answer: mine.closest.name,
                           detail: "\(Int(mine.onPurposeShare * 100))% of your screen hours went to something on purpose.", seed: 0xB0B)
                    ZenTag(tone: .amber, question: "How many weeks have you won?", answer: "\(streak) in a row",
                           detail: "Four good days a week, \(streak) weeks running. This week can make it \(streak + 1).", seed: 0xC0FFEE)
                }
                .padding(.vertical, ZenSpace.s3)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}

/// Primary (ink pill) or secondary (glass) for the share action, by whether it's the screen's main one.
private struct ShareStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        if primary {
            ZenPrimaryButtonStyle().makeBody(configuration: configuration)
        } else {
            ZenSecondaryButtonStyle().makeBody(configuration: configuration)
        }
    }
}

/// Your month as a picture to share: the pattern, its name, the lockup. Hours as a shape, never
/// minutes or apps.
private struct MonthShareImage: View {
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

/// Join by code, for anyone who skipped it in onboarding. The screen's primary action until joined.
private struct JoinCircleCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .center, spacing: ZenSpace.s5) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Text(CircleCopy.joinTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
                Text(CircleCopy.joinBody).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = model.codeState {
                    Text(message).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
                } else if model.isDemo {
                    Text(Copy.Seat.demoCode).zenType(.caption).foregroundStyle(Color.zen.accentRewardText)
                }
            }
            Spacer()
            TextField(Copy.Seat.codeLabel, text: $model.codeText, prompt: Text("ZEN4HS"))
                .textFieldStyle(.plain)
                .font(ZenFont.number(20)).tracking(3)
                .padding(.horizontal, ZenSpace.s4)
                .frame(width: 170, height: 44)
                .background(RoundedRectangle(cornerRadius: ZenRadius.md).fill(Color.zen.surfaceRaised))
                .onSubmit { model.joinCohort() }
                .accessibilityLabel(Copy.Seat.codeLabel)
            Button("Join") { model.joinCohort() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(model.codeText.count < JoinCode.length || model.codeState == .checking)
        }
        .padding(ZenSpace.s5)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color.zen.brandFill.opacity(0.3), lineWidth: 1))
    }
}
