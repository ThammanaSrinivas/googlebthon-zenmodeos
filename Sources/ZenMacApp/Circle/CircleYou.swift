import SwiftUI
import Albeit
import ZenAPI

/// You: your month as a gallery. The hero says what it shows and what it says about you; then the
/// same month drawn four ways (the pick carries to Today); then the four lives it's compared with;
/// then the cards it makes. Every pattern here is your own hours. Nobody else's are ever drawn.
struct YouGalleryTab: View {
    @Environment(AppModel.self) private var model

    private let mine = PersonalMonth.demo
    private static let lives: [Archetype: MonthHours] = Dictionary(uniqueKeysWithValues: Archetype.allCases.map { ($0, $0.month(seed: 2026)) })

    var body: some View {
        let kind = model.preferences.values.pattern
        VStack(alignment: .leading, spacing: ZenSpace.s6) {
            hero(kind)
            fourWays(kind)
            fourLives(kind).id("lives")
            cards.id("cards")
        }
        .animation(ZenMotion.calm(ZenMotion.t2), value: kind)
    }

    // MARK: The hero

    private func hero(_ kind: PatternKind) -> some View {
        HStack(alignment: .center, spacing: ZenSpace.s8) {
            PatternTile(month: mine.hours, kind: kind)
                .frame(width: 320, height: 320)
                .id(kind)
                .transition(.opacity)
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
                    .frame(maxWidth: 460, alignment: .leading)
                HStack(spacing: ZenSpace.s5) {
                    fact("\(mine.focusHours)", CircleCopy.focus, Color(hex: 0xE2B000))
                    fact("\(mine.unplannedHours)", CircleCopy.unplanned, Color(hex: 0xD9541E))
                    fact(CircleSection.clock(mine.calmestHour), CircleCopy.calmest, Color.zen.brandFill)
                }
                .padding(.vertical, ZenSpace.s1)
                ShareImageButton(fileName: "ZenMode OS month.png", make: { ImageExport.png(MonthShareImage(month: mine, kind: kind)) }) {
                    Label(CircleCopy.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ZenPrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxxl)
    }

    private func fact(_ value: String, _ label: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(ZenFont.number(26)).foregroundStyle(Color.zen.textHeading)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(hue).frame(width: 8, height: 8)
                Text(label).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Your month, four ways (the picker, made of the pictures themselves)

    private func fourWays(_ selected: PatternKind) -> some View {
        CirclePanel(title: CircleCopy.fourWaysTitle, caption: CircleCopy.fourWaysCaption) {
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                ForEach(PatternKind.allCases) { k in
                    WayThumb(month: mine.hours, kind: k, selected: k == selected) {
                        model.preferences.values.pattern = k
                    }
                }
            }
        }
    }

    // MARK: Same pattern, four different lives

    private func fourLives(_ kind: PatternKind) -> some View {
        let closest = mine.closest
        return CirclePanel(title: CircleCopy.livesTitle, caption: CircleCopy.livesCaption) {
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                ForEach(Archetype.allCases) { a in
                    lifeCard(a, kind: kind, isYou: a == closest)
                }
            }
        }
    }

    private func lifeCard(_ a: Archetype, kind: PatternKind, isYou: Bool) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            PatternTile(month: Self.lives[a]!, kind: kind)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isYou {
                        RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous)
                            .strokeBorder(Color.zen.accentReward, lineWidth: 2)
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
            Text(a.name).font(ZenFont.brand(18)).foregroundStyle(Color.zen.textHeading)
            Text(a.line).zenType(.caption).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(CircleCopy.calmestAt) \(CircleSection.clock(a.mindfulHour))".uppercased())
                .font(ZenFont.number(9.5)).tracking(0.8).foregroundStyle(Color.zen.textBrand)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.name). \(a.line)\(isYou ? " Closest to your month." : "")")
    }

    // MARK: Cards from your month

    private var cards: some View {
        let streak = model.streak?.currentStreak ?? 9
        return CirclePanel(title: CircleCopy.cardsTitle, caption: CircleCopy.cardsCaption) {
            HStack(alignment: .top, spacing: ZenSpace.s6) {
                ZenTag(tone: .zen, question: "When are you calmest?", answer: mine.calmestPart,
                       detail: "\(CircleSection.clock(mine.calmestHour)) was your most focused hour across the last 30 days.", seed: 0xA11CE)
                ZenTag(tone: .zen, question: "What does your month look like?", answer: mine.closest.name,
                       detail: "\(Int(mine.onPurposeShare * 100))% of your screen hours went to something on purpose.", seed: 0xB0B)
                ZenTag(tone: .amber, question: "How many weeks have you won?", answer: "\(streak) in a row",
                       detail: "Four good days a week, \(streak) weeks running. This week can make it \(streak + 1).", seed: 0xC0FFEE)
                Spacer(minLength: 0)
            }
            .padding(.vertical, ZenSpace.s1)
        }
    }
}

/// One way of drawing your month, as a pickable thumbnail: ringed in green when it's the one
/// Today uses.
private struct WayThumb: View {
    let month: MonthHours
    let kind: PatternKind
    let selected: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                PatternTile(month: month, kind: kind)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous)
                            .strokeBorder(selected ? Color.zen.brandSoft : .clear, lineWidth: 2.5)
                    }
                    .scaleEffect(hovering && !selected ? 1.02 : 1)
                HStack(spacing: 6) {
                    Text(kind.rawValue).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color.zen.textBrand)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Text("On Today").font(ZenFont.number(9.5)).tracking(0.6).foregroundStyle(Color.zen.textBrand)
                    }
                }
                Text(Self.question(kind)).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(ZenMotion.calm(ZenMotion.t1), value: hovering)
        .accessibilityLabel("Draw your month as a \(kind.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// The question each pattern answers.
    static func question(_ kind: PatternKind) -> String {
        switch kind {
        case .bloom: "How did each hour feel?"
        case .kolam: "How whole were my days?"
        case .garland: "Which days were on screen?"
        case .horizon: "When in the day was I on?"
        }
    }
}
