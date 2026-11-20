import SwiftUI
import Albeit
import ZenAPI
import ZenMock

/// Words on Today, named once.
enum HomeCopy {
    static func greeting(_ name: String?, at date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let part = h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return name.map { "\(part), \($0)" } ?? part
    }
    static let scoreEyebrow = "Zen Score · every screen"
    static let scoreLine = "Your iPhone and this Mac, as one day"
    static let weekEyebrow = "Weekly streak"
    static let zenoEyebrow = "Zeno"
    static let askAgain = "Ask Zeno"
    static let screensTitle = "Across your screens"
    static let screensLine = "This Mac's minutes. Your iPhone sends its Zen Score only."
    static let goldLine = "Won weeks open Zen Gold"
    static let goldDetail = "4 good days win the week. A good day is a Zen Score above 6.0."
    static let openGold = "See Zen Gold"
    static let circleTitle = "Zen Circle"
    static let openCircle = "Open Zen Circle"
    static let search = "Search or jump to…"
}

// MARK: - Hover tilt

/// A card that leans toward the pointer: it tips on both axes, lifts, and casts a shadow away from
/// the light in its own hue, so playing with the deck feels physical. Still under Reduce Motion.
struct HoverTilt: ViewModifier {
    let glow: Color
    var maxAngle: Double = 12
    @State private var lean: CGSize = .zero
    @State private var size: CGSize = .zero
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -lean.height * maxAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : lean.width * maxAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            // A contact shadow, then a long one in the card's own colour, thrown away from the pointer.
            .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: hovering ? 6 : 4, y: hovering ? 4 : 3)
            .shadow(color: glow.opacity(hovering ? (dark ? 0.55 : 0.45) : 0.18),
                    radius: hovering ? 26 : 14,
                    x: reduceMotion ? 0 : -lean.width * 18,
                    y: (hovering ? 18 : 8) - (reduceMotion ? 0 : lean.height * 12))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    guard size.width > 0, size.height > 0 else { return }
                    hovering = true
                    lean = CGSize(width: min(max((p.x / size.width - 0.5) * 2, -1), 1),
                                  height: min(max((p.y / size.height - 0.5) * 2, -1), 1))
                case .ended:
                    hovering = false
                    lean = .zero
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: lean)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hovering)
    }
}

// MARK: - The hero

/// The one place the Zen Score lives on Today: the number, each screen's part, the weekly streak,
/// and Zeno's latest line.
struct HeroCard: View {
    @Environment(AppModel.self) private var model
    let day: DayInsight

    var body: some View {
        let week = (model.snapshot ?? FakeSnapshot.value).week
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ZenSpace.s8) {
                    score
                    divider
                    streak(week)
                    divider
                    zeno.frame(maxWidth: 280)
                }
                VStack(alignment: .leading, spacing: ZenSpace.s6) {
                    HStack(alignment: .top, spacing: ZenSpace.s8) { score; streak(week) }
                    zeno
                }
            }
            Rectangle().fill(Color.zen.borderHairline).frame(height: 1).accessibilityHidden(true)
            goldFooter(week)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxl)
    }

    /// The card's icon, bottom left: the Zen Gold coin, and what a won week opens.
    private func goldFooter(_ week: WeekProgress) -> some View {
        HStack(spacing: ZenSpace.s3) {
            GoldCoin()
                .frame(width: 44, height: 44)
                .shadow(color: Color(hex: 0x8A5A00, alpha: 0.28), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeCopy.goldLine).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(HomeCopy.goldDetail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: ZenSpace.s3)
            Button(HomeCopy.openGold) { model.navigate = .gold }
                .buttonStyle(ZenLinkButtonStyle())
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.zen.borderHairline).frame(width: 1).frame(maxHeight: 150)
    }

    private var score: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(HomeCopy.scoreEyebrow)
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                ScoreText(day.score.text, size: 84)
                DeltaText(tenths: day.delta)
            }
            .accessibilityElement(children: .combine)
            Text(HomeCopy.scoreLine).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            HStack(spacing: ZenSpace.s2) {
                ForEach(day.screens) { s in
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol).font(.system(size: 11, weight: .semibold))
                        Text(s.score.text).font(ZenFont.number(12))
                        if s.isSealed { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    }
                    .foregroundStyle(Color.zen.textHeading)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(Color.zen.surfaceRaised.opacity(0.7)))
                    .help(s.isSealed ? "\(s.name): score only. Its minutes stay on it." : "\(s.name): measured here")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.name), \(s.score.text)\(s.isSealed ? ", score only" : "")")
                }
            }
        }
    }

    private func streak(_ week: WeekProgress) -> some View {
        let names = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(HomeCopy.weekEyebrow)
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                Text("\(week.weeklyStreak)").font(ZenFont.number(44)).foregroundStyle(GoldInk.gradient)
                Text("weeks in a row").font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = week.days[i]
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(d.map { $0.isGoodDay ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.14) } ?? Color.zen.textHeading.opacity(0.04))
                            .overlay {
                                if i == week.todayIndex {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.zen.textHeading.opacity(0.6), lineWidth: 1.5)
                                }
                            }
                            .frame(width: 22, height: 22)
                        Text(names[i]).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption)
                    }
                }
            }
            Text(week.statusLine).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly streak \(week.weeklyStreak). \(week.statusLine)")
    }

    private var zeno: some View {
        let line = model.lastNudge?.0.line ?? day.nudges.last?.line ?? "Nothing to say. Just here."
        let feeling: ZenoFeeling = day.score.isGoodDay ? .happy : .pleasant
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                ZenoView(feeling).frame(width: 56)
                Eyebrow(HomeCopy.zenoEyebrow)
            }
            Text("“\(line)”").font(ZenFont.text(16, .semibold)).foregroundStyle(Color.zen.textHeading)
                .fixedSize(horizontal: false, vertical: true)
            Button(HomeCopy.askAgain) { Task { await model.refreshNudge(trigger: .checkIn) } }
                .buttonStyle(ZenLinkButtonStyle())
        }
    }
}

// MARK: - Across your screens

/// Device analytics, side by side: the day as a clock on the left, where the minutes went on the
/// right (stacked when the window is narrow). The day picker in "Your day"'s header drives both.
struct ScreensSection: View {
    @Environment(AppModel.self) private var model
    let wide: Bool

    var body: some View {
        @Bindable var dash = model.dashboard
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text(HomeCopy.screensTitle).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text(HomeCopy.screensLine).font(ZenFont.text(12.5)).lineLimit(1)
                }
                .foregroundStyle(Color.zen.textCaption)
                Spacer(minLength: 0)
            }
            if wide {
                HStack(alignment: .top, spacing: ZenSpace.s5) {
                    DayClockCard(day: dash.day).frame(maxWidth: 440)
                    MinutesFlowCard(day: dash.day, lit: $dash.litKind)
                }
                .frame(height: 420)
            } else {
                VStack(spacing: ZenSpace.s5) {
                    DayClockCard(day: dash.day).frame(height: 400)
                    MinutesFlowCard(day: dash.day, lit: $dash.litKind).frame(height: 360)
                }
            }
        }
    }
}

// MARK: - Zen Circle at a glance

/// Your month in the pattern you chose, the type it makes you, and the circle as one number.
struct CircleGlanceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let month = PersonalMonth.demo
        let kind = model.preferences.values.pattern
        let cohort = model.cohort ?? CohortSummary(preview: FakeCohorts.demo, score: ZenScore(tenths: 74), goodDayRate: 0.62)
        HStack(alignment: .top, spacing: ZenSpace.s5) {
            PatternTile(month: month.hours, kind: kind)
                .frame(width: 168, height: 168)
                .modifier(HoverTilt(glow: Color.zen.brandSoft, maxAngle: 8))
                .accessibilityLabel("Your month as a \(kind.rawValue)")
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack {
                    Text(HomeCopy.circleTitle).font(ZenFont.brand(22)).foregroundStyle(Color.zen.textHeading)
                    Spacer()
                    DemoTag("Demo history")
                }
                Text("You're a \(month.closest.name.lowercased()), calmest \(month.calmestPart.lowercased()).")
                    .font(ZenFont.text(14)).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    Text(cohort.score?.text ?? "–").font(ZenFont.number(34)).foregroundStyle(Color.zen.textHeading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cohort.preview.name).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                        Text("\(cohort.preview.memberCount) people · \(Int((cohort.goodDayRate ?? 0) * 100))% good days")
                            .zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                }
                HStack(spacing: -8) {
                    ForEach(Array([ZenoFeeling.happy, .pleasant, .proud, .curious, .calm].enumerated()), id: \.offset) { _, f in
                        ZenoStill(f)
                            .frame(width: 30)
                            .padding(4)
                            .background(Circle().fill(Color.zen.surfaceRaised))
                            .overlay(Circle().strokeBorder(Color.zen.borderHairline, lineWidth: 1))
                    }
                    Text("+\(max(cohort.preview.memberCount - 5, 0))").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                        .padding(.leading, 14)
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button(HomeCopy.openCircle) { model.navigate = .cohort }.buttonStyle(ZenLinkButtonStyle())
            }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.xxl)
    }
}
