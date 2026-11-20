import Accessibility
import Charts
import SwiftUI
import Albeit
import ZenAPI

/// The ink of the ROI band: dark by design in both appearances (like the Week hero), so it names its
/// colours here instead of reading the theme. Every text pair is ≥ 4.5:1 on `ground` and `well`.
enum AdminInk {
    static let ground = Color(hex: 0x12160F)
    static let well = Color(hex: 0x1A2019)
    static let text = Color(hex: 0xF2F3EE)
    static let body = Color(hex: 0xC9CCC4)
    static let caption = Color(hex: 0xA4A9A0)
    static let line = Color(hex: 0x343A34)
    /// The part of a bar at or under the baseline (≥ 3:1 on `well`).
    static let base = Color(hex: 0x6B7268)
    static let green = Color(hex: 0x5BDF62)
    static let fill = Color(hex: 0x2AA136)
    static let greenWell = Color(hex: 0x173A1B)
}

/// The ROI band, first on the page: what the team's extra focus is worth a month, the change, one
/// plain sentence, the honest formula, and the focus hours rising from the baseline.
struct AdminHero: View {
    let dashboard: AdminDashboard
    let wide: Bool

    var body: some View {
        let d = dashboard
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: ZenSpace.s8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: ZenSpace.s6))
        layout {
            story(d).frame(maxWidth: .infinity, alignment: .leading)
            if let base = AdminStory.baseline(d), !AdminStory.weeks(d).isEmpty {
                FocusRiseCard(points: AdminStory.weeks(d), baseline: base, gain: AdminStory.gain(d))
                    .frame(maxWidth: wide ? 440 : .infinity, maxHeight: wide ? .infinity : nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(wide ? ZenSpace.s10 : ZenSpace.s8)
        .background(HeroLight())
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func story(_ d: AdminDashboard) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            Text(AdminCopy.heroKicker.uppercased()).font(ZenFont.number(11)).tracking(1.1).foregroundStyle(AdminInk.green)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                    Text(AdminFormat.value(d.cards.rupeesPerMonth.now, of: .rupeesPerMonth))
                        .font(ZenFont.number(wide ? 80 : 64)).tracking(-2)
                        .foregroundStyle(AdminInk.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(AdminCopy.aMonth).font(ZenFont.text(22, .medium)).foregroundStyle(AdminInk.body)
                        .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(AdminFormat.value(d.cards.rupeesPerMonth.now, of: .rupeesPerMonth)) reclaimed a month")
                .accessibilityAddTraits(.isHeader)
                if let change = AdminStory.heroChange(d) { changePill(change, d.cards.rupeesPerMonth.change) }
            }
            if let line = AdminStory.explanation(d) {
                Text(line).font(ZenFont.text(17, .medium)).foregroundStyle(AdminInk.text).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            HStack(alignment: .top, spacing: ZenSpace.s8) {
                if let p = AdminStory.perPerson(d) { fact(AdminCopy.perPerson, AdminFormat.rupees(p)) }
                if let y = AdminStory.yearly(d) { fact(AdminCopy.yearly, AdminFormat.rupees(y)) }
            }
            if let formula = d.rupeeFormula {
                VStack(alignment: .leading, spacing: ZenSpace.s1) {
                    Text(AdminCopy.howWeCount.uppercased()).font(ZenFont.number(10)).tracking(1).foregroundStyle(AdminInk.caption)
                    Text(formula).font(ZenFont.number(11.5)).foregroundStyle(AdminInk.body).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.top, ZenSpace.s3)
                .overlay(alignment: .top) { Rectangle().fill(AdminInk.line).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func changePill(_ text: String, _ change: Double?) -> some View {
        let up = (change ?? 0) > 0
        let down = (change ?? 0) < 0
        return HStack(spacing: 6) {
            Image(systemName: up ? "arrow.up.right" : down ? "arrow.down.right" : "equal")
                .font(.system(size: 11, weight: .bold))
            Text(text).font(ZenFont.text(13.5, .semibold))
        }
        .foregroundStyle(up ? AdminInk.green : AdminInk.body)
        .padding(.horizontal, ZenSpace.s3).padding(.vertical, 6)
        .background(Capsule().fill(up ? AdminInk.greenWell : AdminInk.well))
        .overlay(Capsule().strokeBorder(up ? AdminInk.fill.opacity(0.5) : AdminInk.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(ZenFont.number(20)).foregroundStyle(AdminInk.text)
            Text(label).font(ZenFont.text(12.5)).foregroundStyle(AdminInk.caption)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The lit ink ground: a green glow rising from the chart's corner, never a flat fill.
private struct HeroLight: View {
    var body: some View {
        ZStack {
            AdminInk.ground
            RadialGradient(colors: [AdminInk.fill.opacity(0.34), .clear], center: UnitPoint(x: 0.92, y: 1.05),
                           startRadius: 10, endRadius: 560)
            RadialGradient(colors: [Color(hex: 0x5BDF62, alpha: 0.10), .clear], center: UnitPoint(x: 0.05, y: -0.1),
                           startRadius: 0, endRadius: 420)
            LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

// MARK: - The focus chart

/// Focus hours per person by week: each bar is the baseline (grey) plus what was reclaimed above it
/// (green). Zero-based, so the rise is honest.
struct FocusRiseCard: View {
    let points: [AdminStory.WeekPoint]
    let baseline: Double
    let gain: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text(AdminCopy.trend).font(ZenFont.text(14, .semibold)).foregroundStyle(AdminInk.text)
                Spacer(minLength: ZenSpace.s2)
                if let gain, gain > 0.04 {
                    Text("+\(String(format: "%.1f", gain)) h").font(ZenFont.number(14)).foregroundStyle(AdminInk.green)
                }
            }
            chart.frame(minHeight: 220, maxHeight: .infinity)
            HStack(spacing: ZenSpace.s4) {
                legend(AdminInk.base, "\(AdminCopy.legendBaseline) \(AdminFormat.hours(baseline))", dashed: true)
                legend(AdminInk.green, AdminCopy.legendReclaimed, dashed: false)
            }
            .accessibilityHidden(true)
        }
        .padding(ZenSpace.s5)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).fill(AdminInk.well.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(ZenMotion.settle(ZenMotion.t4)) { grown = true } }
        }
    }

    private var top: Double { max(points.map(\.hours).max() ?? 1, baseline) * 1.22 }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                let h = grown ? p.hours : 0
                BarMark(x: .value("Week", p.label), yStart: .value("Start", 0), yEnd: .value("Hours", min(h, baseline)),
                        width: .ratio(0.58))
                    .foregroundStyle(AdminInk.base)
                    .cornerRadius(5)
                    .annotation(position: .top, spacing: 6) {
                        if p.hours <= baseline + 0.04 { value(p.hours, highlight: false) }
                    }
                if p.hours > baseline + 0.04 {
                    BarMark(x: .value("Week", p.label), yStart: .value("Baseline", baseline), yEnd: .value("Hours", max(h, baseline)),
                            width: .ratio(0.58))
                        .foregroundStyle(LinearGradient(colors: [AdminInk.green, AdminInk.fill], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(5)
                        .annotation(position: .top, spacing: 6) { value(p.hours, highlight: p.id == points.last?.id) }
                }
            }
            RuleMark(y: .value("Baseline", baseline))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .foregroundStyle(AdminInk.caption)
        }
        .chartYScale(domain: 0...top)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let s = v.as(String.self) {
                        Text(s).font(ZenFont.number(11)).foregroundStyle(s == AdminCopy.thisWeek ? AdminInk.text : AdminInk.caption)
                    }
                }
            }
        }
        .accessibilityLabel(AdminCopy.trend)
        .accessibilityValue(accessibilitySummary)
        .accessibilityChartDescriptor(FocusChartDescriptor(points: points, baseline: baseline))
    }

    private var accessibilitySummary: String {
        let weeks = points.map { "\($0.label) \(AdminFormat.hours($0.hours))" }.joined(separator: ", ")
        return "Baseline \(AdminFormat.hours(baseline)). \(weeks)."
    }

    private func value(_ hours: Double, highlight: Bool) -> some View {
        Text(String(format: "%.1f", hours)).font(ZenFont.number(highlight ? 13 : 11.5))
            .foregroundStyle(highlight ? AdminInk.green : AdminInk.body)
    }

    private func legend(_ color: Color, _ text: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 10, height: 10)
            if dashed {
                Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 16, y: 1)) }
                    .stroke(AdminInk.caption, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).frame(width: 16, height: 2)
            }
            Text(text).font(ZenFont.text(12)).foregroundStyle(AdminInk.caption)
        }
    }
}

/// The chart for VoiceOver's Audio Graphs: weeks on x, hours on y.
struct FocusChartDescriptor: AXChartDescriptorRepresentable {
    let points: [AdminStory.WeekPoint]
    let baseline: Double

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = max(points.map(\.hours).max() ?? 1, baseline)
        let x = AXCategoricalDataAxisDescriptor(title: "Week", categoryOrder: points.map(\.label))
        let y = AXNumericDataAxisDescriptor(title: "Focus hours per person", range: 0...top, gridlinePositions: [baseline]) {
            String(format: "%.1f hours", $0)
        }
        let series = AXDataSeriesDescriptor(name: "Focus hours", isContinuous: false,
                                            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.hours) })
        return AXChartDescriptor(title: AdminCopy.trend,
                                 summary: "Up from a \(AdminFormat.hours(baseline)) baseline to \(AdminFormat.hours(points.last?.hours ?? baseline)).",
                                 xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
