import SwiftUI
import Albeit
import ZenAPI

/// One supporting metric: a plain label, the value, the change as arrow + number + word (never colour
/// alone; after-hours going down is better), and the four weeks as a sparkline.
struct AdminMetricTile: View {
    let kind: AdminCardKind
    let card: AdminCard
    let series: [Double]

    var body: some View {
        let change = AdminFormat.change(card.change, of: kind)
        let good = AdminFormat.isImprovement(card.change, of: kind)
        let verdict = AdminStory.verdict(card.change, of: kind)
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.zen.textBrand)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.zen.surfaceTint))
                Text(kind.plainTitle).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Text(AdminFormat.value(card.now, of: kind)).font(ZenFont.number(34)).tracking(-0.6)
                .foregroundStyle(Color.zen.textHeading)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let change, let verdict { ChangeChip(text: change, verdict: verdict, good: good, change: card.change) }
            if series.count > 1 {
                Sparkline(values: series).frame(height: 30)
                    .accessibilityHidden(true)
            }
            Text(kind.meaning).font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.plainTitle)
        .accessibilityValue(accessibilityValue(change: change, verdict: verdict))
    }

    private func accessibilityValue(change: String?, verdict: String?) -> String {
        var parts = [AdminFormat.value(card.now, of: kind)]
        if let change, let verdict { parts.append("\(change) on last week, \(verdict)") }
        if series.count > 1 {
            parts.append("last 4 weeks: " + series.map { AdminFormat.value($0, of: kind) }.joined(separator: ", "))
        }
        parts.append(kind.meaning)
        return parts.joined(separator: ". ")
    }
}

/// "↑ +1.2 h · better": the arrow is the direction of the number, the word and colour say whether
/// that's good news.
struct ChangeChip: View {
    let text: String
    let verdict: String
    let good: Bool?
    let change: Double?

    var body: some View {
        let arrow = (change ?? 0) > 0 ? "arrow.up" : (change ?? 0) < 0 ? "arrow.down" : "equal"
        let fg = good == true ? Color.zen.scoreGain : good == false ? Color.zen.scoreDeduct : Color.zen.textCaption
        let bg = good == true ? Color.zen.surfaceTint : good == false ? Color.zen.ember.opacity(0.12) : Color.zen.surfaceSunk
        HStack(spacing: 4) {
            Image(systemName: arrow).font(.system(size: 10, weight: .bold))
            Text(good == nil && text == "no change" ? verdict : "\(text) · \(verdict)")
                .font(ZenFont.number(11.5))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, ZenSpace.s2).padding(.vertical, 4)
        .background(Capsule().fill(bg))
        .fixedSize()
    }
}

/// Four weeks as a line, the newest week as a dot. Scaled to its own range, so it shows the shape,
/// never the size (the value above it says that).
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = max(hi - lo, 0.0001)
            let inset: CGFloat = 4
            func point(_ i: Int) -> CGPoint {
                let x = inset + CGFloat(i) / CGFloat(values.count - 1) * (size.width - inset * 2)
                let y = hi == lo ? size.height / 2 : inset + (1 - CGFloat((values[i] - lo) / span)) * (size.height - inset * 2)
                return CGPoint(x: x, y: y)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            var area = line
            area.addLine(to: CGPoint(x: point(values.count - 1).x, y: size.height))
            area.addLine(to: CGPoint(x: point(0).x, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [Color.zen.brandSoft.opacity(0.22), .clear]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(Color.zen.brandFill), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for i in 0..<(values.count - 1) {
                let p = point(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Color.zen.brandFill.opacity(0.6)))
            }
            let last = point(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 4.5, y: last.y - 4.5, width: 9, height: 9)), with: .color(Color.zen.surfaceRaised))
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(Color.zen.brandFill))
        }
    }
}

// MARK: - Zen Gold

/// Zen Gold this month: counts and the sponsored rupees, on the one reward hue. Payout is HR's.
struct AdminGoldTile: View {
    let claims: Int
    let sponsoredInr: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s3) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xFFE27A), Color.zen.accentReward, Color(hex: 0xE0A200)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1)
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0x5A3E00))
                }
                .frame(width: 36, height: 36)
                .shadow(color: Color.zen.accentReward.opacity(0.45), radius: 8, y: 2)
                .accessibilityHidden(true)
                Text(AdminCopy.goldKicker.uppercased()).font(ZenFont.number(10.5)).tracking(1.05)
                    .foregroundStyle(Color.zen.accentRewardText)
            }
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                stat("\(claims)", claims == 1 ? AdminCopy.goldWeek : AdminCopy.goldWeeks)
                stat(AdminFormat.rupees(Double(sponsoredInr)), AdminCopy.goldSponsored)
            }
            Text(AdminCopy.gold).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.accentRewardText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Color.zen.accentRewardTint)
                shape.fill(RadialGradient(colors: [Color.zen.accentReward.opacity(0.28), .clear], center: .topTrailing,
                                          startRadius: 0, endRadius: 260))
            }
        }
        .overlay(shape.strokeBorder(Color.zen.accentReward.opacity(0.35), lineWidth: 1))
        .modifier(ZenLift())
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
            Text(value).font(ZenFont.number(28)).foregroundStyle(Color.zen.textHeading)
            Text(label).font(ZenFont.text(13, .medium)).foregroundStyle(Color.zen.accentRewardText)
        }
    }
}

// MARK: - Trust

/// How the numbers are made, beside the report: who they're from, the 5-person gate, no names.
struct AdminTrustTile: View {
    let activeN: Int?
    let includesDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(AdminCopy.trustTitle)
            if let n = activeN { line("person.2.fill", AdminCopy.basedOn(n) + AdminCopy.trustActive) }
            line("lock.shield", AdminCopy.trustGate)
            line("eye.slash", AdminCopy.trustNames)
            if includesDemo { line("testtube.2", AdminCopy.trustDemo) }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                .frame(width: 18)
            Text(text).font(ZenFont.text(13)).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
