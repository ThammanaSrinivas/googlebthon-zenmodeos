import SwiftUI
import Albeit
import ZenAPI

/// Two portrait cards with a bolt between them, after the Android Home stats cards: you, and your
/// circle as one. A mood gradient carries the state, Zeno's face fills the top, the score sits
/// below. Scores only: your minutes stay yours, and the circle is never a person.
struct FaceCardPair: View {
    let you: ZenScore
    let circleName: String
    let circle: ZenScore
    let goodDayRate: Double

    var body: some View {
        HStack(spacing: 0) {
            FaceCard(label: CircleCopy.you, score: you, line: you.isGoodDay ? CircleCopy.goodDaySoFar : CircleCopy.underSix,
                     feeling: you.isGoodDay ? .happy : .pleasant)
            ZStack {
                Circle().fill(Color.zen.surfaceRaised).frame(width: 34, height: 34).modifier(ZenLift())
                Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0xFFC800))
            }
            .frame(width: 44)
            .zIndex(1)
            .accessibilityHidden(true)
            FaceCard(label: circleName, score: circle, line: "\(Int(goodDayRate * 100))% good days", feeling: circle.isGoodDay ? .pleasant : .calm)
        }
    }
}

private struct FaceCard: View {
    let label: String
    let score: ZenScore
    let line: String
    let feeling: ZenoFeeling

    var body: some View {
        let good = score.isGoodDay
        let colors: [Color] = good ? [Color(hex: 0xE9F8E6), Color(hex: 0x9EDF9A)] : [Color(hex: 0xEFF2EC), Color(hex: 0xC3D2BF)]
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(label).font(ZenFont.brand(15)).foregroundStyle(Color(hex: 0x12160F)).lineLimit(1)
            Text(score.text).font(ZenFont.number(36)).foregroundStyle(Color(hex: 0x12160F))
            Text(line).font(ZenFont.text(12)).foregroundStyle(Color(hex: 0x4A4F46)).lineLimit(1)
        }
        .padding(14)
        .frame(width: 168, height: 208, alignment: .bottomLeading)
        .background {
            // The face fills the top, as on Android: Zeno's whole head, cropped below the chin.
            ZStack(alignment: .top) {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                ZenoStill(feeling).frame(width: 150).offset(y: -14)
            }
            .frame(width: 168, height: 208)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .modifier(ZenLift())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): Zen Score \(score.text), \(line)")
    }
}

/// Your month, small, for Today: the person's own hours in the pattern they picked in Zen Circle.
/// `open` takes them to Zen Circle to change it.
struct YourMonthCard: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        let kind = model.preferences.values.pattern
        let month = PersonalMonth.demo
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Eyebrow("\(CircleCopy.yourMonth) · \(kind.rawValue)")
                Spacer()
                DemoTag(CircleCopy.demoHistory)
            }
            PatternTile(month: month.hours, kind: kind)
                .aspectRatio(1, contentMode: .fit)
                .id(kind)
                .transition(.opacity)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.closest.name).font(ZenFont.brand(20)).foregroundStyle(Color.zen.textHeading)
                    Text("\(CircleCopy.calmestAt) \(CircleSection.clock(month.calmestHour))").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer()
                Button(CircleCopy.changePattern, action: open).buttonStyle(ZenLinkButtonStyle())
            }
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
        .animation(ZenMotion.calm(ZenMotion.t2), value: kind)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your month as a \(kind.rawValue): \(month.closest.name), calmest at \(CircleSection.clock(month.calmestHour))")
    }
}
