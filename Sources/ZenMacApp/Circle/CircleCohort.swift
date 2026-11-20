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
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            if model.cohort == nil { JoinCircleCard() }
            asOne(s)
            HStack(alignment: .top, spacing: ZenSpace.s5) {
                digest.frame(maxWidth: .infinity, maxHeight: .infinity)
                trendPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            mixPanel(s).id("mix")
        }
    }

    // MARK: You beside the group

    /// The hero: you and the group as two face cards, the words beside them.
    private func asOne(_ s: CohortSummary) -> some View {
        HStack(alignment: .center, spacing: ZenSpace.s8) {
            if let score = s.score {
                FaceCardPair(you: model.snapshot?.score ?? ZenScore(tenths: 81), circleName: s.preview.name,
                             circle: score, goodDayRate: s.goodDayRate ?? 0)
            }
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow("\(s.preview.organisation) · \(s.preview.memberCount) people")
                    if model.cohort == nil { DemoTag(CircleCopy.preview) } else if model.isDemo { DemoTag() }
                }
                Text("\(s.preview.name), as one.").zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                    Text("0.3").font(ZenFont.number(13))
                    Text(CircleCopy.onLastWeek).font(ZenFont.text(13, .medium))
                }
                .foregroundStyle(Color.zen.scoreGain)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Color.zen.surfaceTint))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Up 0.3 on last week")
                seats(s.preview.memberCount).padding(.top, ZenSpace.s2)
                Text(CircleCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxxl)
    }

    private func seats(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<min(n, 24), id: \.self) { i in
                    RoundedRectangle(cornerRadius: ZenRadius.cell)
                        .fill(i == 0 ? Color.zen.accentReward : Color.zen.brandFill.opacity([0.9, 0.5, 0.72][i % 3]))
                        .frame(width: 12, height: 12)
                }
            }
            HStack(spacing: 4) {
                Text("\(n)").font(ZenFont.number(11.5)).foregroundStyle(Color.zen.textHeading)
                Text(CircleCopy.seatsLine).font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) seats, no names. You are the amber one.")
    }

    private var digest: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(alignment: .center, spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(CircleCopy.digestEyebrow).lineLimit(1)
                Spacer(minLength: ZenSpace.s2)
                DemoTag()
            }
            Text(CircleCopy.digestTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
                .accessibilityAddTraits(.isHeader)
            Text(CircleCopy.digest).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ZenSpace.s2)
            Text(CircleCopy.digestCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.xxxl)
    }

    // MARK: The week, as a trend

    private static let chartHeight: CGFloat = 132
    /// Bar height for a score, from 5.5 at the floor to 8.0 near the top.
    private static func barHeight(_ tenths: Int) -> CGFloat { max(6, CGFloat(tenths - 55) / 25 * (chartHeight - 22)) }

    private var trendPanel: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        return CirclePanel(title: CircleCopy.trendTitle) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: ZenSpace.s2) {
                        ForEach(Array(Self.trend.enumerated()), id: \.offset) { i, t in
                            let last = i == Self.trend.count - 1
                            VStack(spacing: 4) {
                                Text(ZenScore(tenths: t).text).font(ZenFont.number(10.5))
                                    .foregroundStyle(last ? Color.zen.textHeading : Color.zen.textCaption)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(t > ZenScore.goodDayThresholdTenths ? Color.zen.brandFill.opacity(last ? 1 : 0.5) : Color.zen.textHeading.opacity(0.2))
                                    .frame(height: Self.barHeight(t))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    // The good-day line, over the bars: a day above 6.0 is a good day.
                    Line().stroke(Color.zen.textHeading.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .frame(height: 2)
                        .padding(.bottom, Self.barHeight(ZenScore.goodDayThresholdTenths) - 1)
                        .accessibilityHidden(true)
                }
                .frame(height: Self.chartHeight, alignment: .bottom)
                HStack(spacing: ZenSpace.s2) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                        Text(d).font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption).frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 6) {
                    Line().stroke(Color.zen.textHeading.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])).frame(width: 18, height: 2)
                    Text(CircleCopy.goodDayLine).font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                }
                .padding(.top, ZenSpace.s1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Group score over the last 7 days, from 6.8 to 7.4, every day a good day")
        }
    }

    // MARK: How the group's months look: counts of the four shapes

    private func mixPanel(_ s: CohortSummary) -> some View {
        let total = Self.mix.reduce(0) { $0 + $1.1 }
        return CirclePanel(title: CircleCopy.mixTitle, caption: CircleCopy.mixCaption) {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: ZenSpace.s8), GridItem(.flexible(), spacing: ZenSpace.s8)],
                          alignment: .leading, spacing: ZenSpace.s3) {
                    ForEach(Self.mix, id: \.0) { a, n in
                        HStack(spacing: ZenSpace.s3) {
                            RoundedRectangle(cornerRadius: 3).fill(Self.hue(a)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                                Text("\(CircleCopy.calmestAt) \(CircleSection.clock(a.mindfulHour))").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                            }
                            Spacer(minLength: ZenSpace.s2)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(n)").font(ZenFont.number(15)).foregroundStyle(Color.zen.textHeading)
                                Text(CircleCopy.navPeople).font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(a.name), calmest at \(CircleSection.clock(a.mindfulHour)): \(n) people")
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
                .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).strokeBorder(Color.zen.borderOutline, lineWidth: 1))
                .onSubmit { model.joinCohort() }
                .accessibilityLabel(Copy.Seat.codeLabel)
            Button("Join") { model.joinCohort() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(model.codeText.count < JoinCode.length || model.codeState == .checking)
        }
        .padding(.horizontal, ZenSpace.s6).padding(.vertical, ZenSpace.s5)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).strokeBorder(Color.zen.brandFill.opacity(0.3), lineWidth: 1))
    }
}

/// A horizontal rule as a shape, so it can be dashed.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
