import SwiftUI
import Albeit
import ZenAPI
import ZenMock

enum CircleCopy {
    static let eyebrow = "Zen Circle"
    static let privacy = "One group score, only for 5 or more. Never a name, an app or a minute next to it."
    static let patternsEyebrow = "Four kinds of month, one circle"
    static let patternsTitle = "Same pattern, four different lives."
    static let patternsPrivacy = "Each pattern blends 5 or more people from the circle. Smaller groups stay hidden."
    static let feelKey = "Gold is focus, green on purpose, rust unplanned, the darker seeds the phone at rest. The lit seed is the hour the group was most mindful."
    static let digestEyebrow = "This week in the circle · Gemini"
    static let digest = "62% good days, up from 54% last week. Evenings got calmer after Tuesday, and most pull-backs now land between 9 and 11 pm. Thursday is still the group's hard day."
    static let digestCaption = "Written by Gemini from group scores only. It never names anyone."
    static let joinTitle = "Join your circle"
    static let joinBody = "Your campus or team shares a six-character code. You'll see one group score, and the group sees yours only inside it."
    static let preview = "Preview · demo circle"
}

/// Zen Circle: the cohort as one. A group score and trend, seats without names, Gemini's digest,
/// and the circle's months as four patterns, each a blend of 5 or more people.
struct CircleSection: View {
    @Environment(AppModel.self) private var model
    @State private var kind: PatternKind = .bloom

    /// The demo circle until a real one is joined, labelled so.
    private var summary: CohortSummary {
        model.cohort ?? CohortSummary(preview: FakeCohorts.demo, score: ZenScore(tenths: 74), goodDayRate: 0.62)
    }

    private static let groups: [(Archetype, Int)] = [(.morning, 7), (.nightOwl, 5), (.weekender, 6), (.deepWorker, 5)]
    private static let months: [Archetype: MonthHours] = Dictionary(uniqueKeysWithValues: Archetype.allCases.map { ($0, $0.month(seed: 2026)) })
    private static let trend: [Int] = [68, 70, 71, 69, 73, 74, 74]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                if model.cohort == nil { JoinCircleCard() }
                header
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    seatsCard
                    digestCard
                }
                patterns
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        let s = summary
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow("\(CircleCopy.eyebrow) · \(s.preview.organisation)", color: Color.zen.textBrand)
                    if model.cohort == nil { DemoTag(CircleCopy.preview) } else if model.isDemo { DemoTag() }
                }
                Text("\(s.preview.name), as one.").zenType(.display).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text("\(s.preview.memberCount) people · \(CircleCopy.privacy)").zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ZenSpace.s6)
            if let score = s.score {
                VStack(alignment: .trailing, spacing: 2) {
                    ScoreText(score.text, size: 72)
                    Text("▲ 0.3 on last week").font(ZenFont.number(12)).foregroundStyle(Color.zen.scoreGain)
                    Text("\(Int((s.goodDayRate ?? 0) * 100))% good days").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Group score \(score.text), up 0.3 on last week, \(Int((s.goodDayRate ?? 0) * 100)) percent good days")
            }
        }
    }

    private var seatsCard: some View {
        let n = summary.preview.memberCount
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Eyebrow("\(n) seats")
                Spacer()
                Text("You").font(ZenFont.number(10)).foregroundStyle(Color.zen.accentRewardText)
                RoundedRectangle(cornerRadius: 2).fill(Color.zen.accentReward).frame(width: 10, height: 10)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 5), count: 12), alignment: .leading, spacing: 5) {
                ForEach(0..<n, id: \.self) { i in
                    RoundedRectangle(cornerRadius: ZenRadius.cell)
                        .fill(i == 0 ? Color.zen.accentReward : Color.zen.brandFill.opacity([0.9, 0.55, 0.75][i % 3]))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Divider().overlay(Color.zen.borderHairline)
            Eyebrow("Group score, last 7 days")
            HStack(alignment: .bottom, spacing: ZenSpace.s2) {
                ForEach(Array(Self.trend.enumerated()), id: \.offset) { i, t in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(t > 60 ? Color.zen.brandFill.opacity(i == Self.trend.count - 1 ? 1 : 0.6) : Color.zen.textHeading.opacity(0.2))
                            .frame(height: CGFloat(t - 50) * 3)
                        Text(ZenScore(tenths: t).text).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Group score over the last 7 days, from 6.8 to 7.4")
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(CircleCopy.digestEyebrow)
                Spacer()
                DemoTag()
            }
            Text("Evenings got calmer").zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(CircleCopy.digest).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(CircleCopy.digestCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
    }

    private var patterns: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Eyebrow(CircleCopy.patternsEyebrow, color: Color.zen.textBrand)
                    Text(CircleCopy.patternsTitle).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                }
                Spacer()
                PatternPicker(selection: $kind)
            }
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                ForEach(Self.groups, id: \.0) { archetype, people in
                    archetypeCard(archetype, people: people)
                }
            }
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Text("\(kind.legend) \(CircleCopy.feelKey)").zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CircleCopy.patternsPrivacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
        .padding(ZenSpace.s6)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxl, style: .continuous).fill(Color.zen.surfaceBase.opacity(0.85)))
        .animation(ZenMotion.calm(ZenMotion.t2), value: kind)
    }

    private func archetypeCard(_ a: Archetype, people: Int) -> some View {
        let month = Self.months[a]!
        let isYou = a == .deepWorker
        return VStack(alignment: .leading, spacing: ZenSpace.s2) {
            PatternTile(month: month, kind: kind)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if isYou {
                        Text("You're here").font(ZenFont.text(11, .semibold)).foregroundStyle(Color(hex: 0x1A1003))
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(Color.zen.accentReward))
                            .padding(10)
                    }
                }
                .id(kind)
                .transition(.opacity)
            HStack(alignment: .firstTextBaseline) {
                Text(a.name).font(ZenFont.brand(20)).foregroundStyle(Color.zen.textHeading)
                Spacer()
                Text("\(people) people").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
            }
            Text(a.line).zenType(.caption).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(month.focusHours / people) focus hours · \(month.unplannedHours / people) unplanned · most mindful at \(Self.clock(a.mindfulHour))".uppercased())
                .font(ZenFont.number(9.5)).tracking(0.8).foregroundStyle(Color.zen.textBrand)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.name), \(people) people. \(a.line) Most mindful at \(Self.clock(a.mindfulHour)).\(isYou ? " Your month looks like this." : "")")
    }

    static func clock(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
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
                        .background { if k == selection { Capsule().fill(Color.zen.surfaceRaised).shadow(color: .black.opacity(0.08), radius: 3, y: 1) } }
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

/// Join by code, for anyone who skipped it in onboarding.
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
        .glassCard(radius: ZenRadius.widget, tint: Color.zen.brandSoft.opacity(0.12))
    }
}
