import SwiftUI
import Albeit
import ZenAPI
import ZenMock

/// The cohort as one: a campus or team seen only in aggregate, for groups of 5 or more. You beside
/// the group as face cards, the seats without names, the week's trend, Gemini's digest, and how the
/// group's months tend to look (counts of the four shapes, never anyone's pattern).
struct CohortTab: View {
    @Environment(AppModel.self) private var model

    private var summary: CohortSummary {
        model.cohort ?? CohortSummary(preview: FakeCohorts.demo, score: ZenScore(tenths: 74), goodDayRate: 0.62)
    }

    private static let trend: [Int] = [68, 70, 71, 69, 73, 74, 74]
    private static let mix: [(Archetype, Int)] = [(.morning, 7), (.weekender, 6), (.nightOwl, 5), (.deepWorker, 5)]

    var body: some View {
        let s = summary
        VStack(alignment: .leading, spacing: ZenSpace.s6) {
            if model.cohort == nil { JoinCircleCard() }
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                asOne(s)
                digest.frame(width: 360)
            }
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                trendPanel.frame(width: 420)
                mixPanel(s)
            }
            .id("mix")
        }
    }

    // MARK: You beside the group

    private func asOne(_ s: CohortSummary) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: ZenSpace.s2) {
                        Eyebrow("\(s.preview.organisation) · \(s.preview.memberCount) people")
                        if model.cohort == nil { DemoTag(CircleCopy.preview) } else if model.isDemo { DemoTag() }
                    }
                    Text("\(s.preview.name), as one.").zenType(.headline).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Text("▲ 0.3 on last week").font(ZenFont.number(12)).foregroundStyle(Color.zen.scoreGain)
            }
            if let score = s.score {
                FaceCardPair(you: model.snapshot?.score ?? ZenScore(tenths: 81), circleName: s.preview.name,
                             circle: score, goodDayRate: s.goodDayRate ?? 0)
            }
            seats(s.preview.memberCount)
            Text(CircleCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxxl)
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
        .accessibilityLabel("\(n) seats, no names. You are the amber one.")
    }

    private var digest: some View {
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
            Spacer(minLength: ZenSpace.s3)
            Text(CircleCopy.digestCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.xxxl)
    }

    // MARK: The week, as a trend

    private var trendPanel: some View {
        CirclePanel(title: CircleCopy.trendTitle) {
            HStack(alignment: .bottom, spacing: ZenSpace.s2) {
                ForEach(Array(Self.trend.enumerated()), id: \.offset) { i, t in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(t > ZenScore.goodDayThresholdTenths ? Color.zen.brandFill.opacity(i == Self.trend.count - 1 ? 1 : 0.55) : Color.zen.textHeading.opacity(0.2))
                            .frame(height: CGFloat(t - 50) * 4)
                        Text(ZenScore(tenths: t).text).font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
                        Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Group score over the last 7 days, from 6.8 to 7.4")
        }
    }

    // MARK: How the group's months look: counts of the four shapes

    private func mixPanel(_ s: CohortSummary) -> some View {
        let total = Self.mix.reduce(0) { $0 + $1.1 }
        return CirclePanel(title: CircleCopy.mixTitle, caption: CircleCopy.mixCaption) {
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(Self.mix, id: \.0) { a, n in
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Self.hue(a))
                                .frame(width: max(8, (geo.size.width - 9) * CGFloat(n) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 16)
                .accessibilityHidden(true)
                VStack(spacing: ZenSpace.s2) {
                    ForEach(Self.mix, id: \.0) { a, n in
                        HStack(spacing: ZenSpace.s3) {
                            RoundedRectangle(cornerRadius: 3).fill(Self.hue(a)).frame(width: 12, height: 12)
                            Text(a.name).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                            Text("\(CircleCopy.calmestAt.lowercased()) \(CircleSection.clock(a.mindfulHour))").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                            Spacer()
                            Text("\(n) people").font(ZenFont.number(11.5)).foregroundStyle(Color.zen.textHeading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private static func hue(_ a: Archetype) -> Color {
        switch a {
        case .morning: Color(hex: 0xE2B000)
        case .nightOwl: Color(hex: 0x6B7FD7)
        case .weekender: Color(hex: 0xD9541E)
        case .deepWorker: Color(hex: 0x2AA136)
        }
    }
}

/// Join by code, for anyone who skipped it in onboarding. The tab's primary action until joined.
struct JoinCircleCard: View {
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
        .padding(ZenSpace.s6)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).strokeBorder(Color.zen.brandFill.opacity(0.3), lineWidth: 1))
    }
}
