import AppKit
import SwiftUI
import Albeit
import ZenAPI

/// The monthly people report, designed: the month as a pattern of good days on the left (a header
/// band when narrow), the summary as a lead sentence, the bullets as rows with their figures pulled
/// out, and the suggestions as chips. Regenerate is secondary, with progress.
struct AdminReportCard: View {
    let report: AdminModel.Report
    let dashboard: AdminDashboard
    let wide: Bool
    let regenerate: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxl, style: .continuous)
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            MonthPattern(month: month, cells: AdminStory.goodDayCells(dashboard), labels: AdminStory.trendLabels(dashboard), tall: wide)
                .frame(width: wide ? 284 : nil)
                .frame(maxWidth: wide ? nil : .infinity, maxHeight: wide ? .infinity : nil)
            content
                .padding(wide ? ZenSpace.s8 : ZenSpace.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(radius: ZenRadius.xxl)
        .clipShape(shape)
    }

    private var month: String {
        switch report {
        case .loaded(let r), .regenerating(let r?): r.month
        default: AdminModel.month(Date())
        }
    }

    private var busy: Bool {
        switch report {
        case .loading, .regenerating: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            header
            switch report {
            case .idle, .loading:
                progress(AdminCopy.reportLoading)
            case .regenerating(let old):
                progress(AdminCopy.regenerating)
                if let old { reportBody(old).opacity(0.45).allowsHitTesting(false).accessibilityHidden(true) }
            case .failed:
                Text(AdminCopy.reportFailed).zenType(.body).foregroundStyle(Color.zen.textBody)
            case .loaded(let r):
                reportBody(r)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: ZenSpace.s3) {
                Text(AdminCopy.reportTitle).font(ZenFont.brand(22)).tracking(-0.4).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ZenSpace.s2)
                regenerateButton
            }
            if case .loaded(let r) = report {
                HStack(spacing: 6) {
                    Image(systemName: r.fallback ? "function" : "sparkle").font(.system(size: 10, weight: .semibold))
                    Text("\(AdminStory.credit(r)) · \(AdminStory.monthName(r.month))").font(ZenFont.text(12.5))
                }
                .foregroundStyle(Color.zen.textCaption)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var regenerateButton: some View {
        Button(action: regenerate) {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)) }
                    Text(AdminCopy.regenerate)
                }
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .disabled(busy)
            .help(AdminCopy.regenerateHelp)
            .accessibilityHint(AdminCopy.regenerateHelp)
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: ZenSpace.s2) {
            ProgressView().controlSize(.small)
            Text(text).zenType(.body).foregroundStyle(Color.zen.textBody)
        }
        .accessibilityElement(children: .combine)
    }

    private func reportBody(_ r: PeopleReport) -> some View {
        let (lead, rest) = AdminStory.lead(r.text)
        return VStack(alignment: .leading, spacing: ZenSpace.s5) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Text(lead).font(ZenFont.text(19, .semibold)).foregroundStyle(Color.zen.textHeading).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let rest {
                    Text(rest).zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            VStack(spacing: 0) {
                ForEach(Array(r.bullets.enumerated()), id: \.offset) { i, b in
                    ReportRow(row: AdminStory.row(b), spoken: b)
                    if i < r.bullets.count - 1 { Rectangle().fill(Color.zen.borderHairline).frame(height: 1).padding(.leading, 44) }
                }
            }
            if !r.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: ZenSpace.s3) {
                    Eyebrow(AdminCopy.tryThis, color: Color.zen.textCaption)
                    FlowChips(items: r.suggestions.map { AdminStory.suggestion($0, team: dashboard.name) })
                }
            }
        }
    }
}

/// One bullet: an icon, the words, the figure on the right in Departure Mono.
private struct ReportRow: View {
    let row: AdminStory.Row
    let spoken: String

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: row.symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(row.isReward ? Color.zen.accentRewardText : Color.zen.textBrand)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous)
                    .fill(row.isReward ? Color.zen.accentRewardTint : Color.zen.surfaceTint))
            Text(row.text).font(ZenFont.text(14.5, .medium)).foregroundStyle(Color.zen.textHeading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ZenSpace.s3)
            if let figure = row.figure {
                Text(figure).font(ZenFont.number(15)).foregroundStyle(Color.zen.textHeading)
                    .padding(.horizontal, ZenSpace.s2).padding(.vertical, 4)
                    .background(Capsule().fill(Color.zen.surfaceSunk.opacity(0.7)))
                    .fixedSize()
            }
        }
        .padding(.vertical, ZenSpace.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// The suggestions as chips, one per line; each copies its words (to paste into the team channel).
private struct FlowChips: View {
    let items: [String]
    @State private var copied: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item, forType: .string)
                    copied = i
                } label: {
                    HStack(spacing: ZenSpace.s2) {
                        Image(systemName: copied == i ? "checkmark" : "lightbulb").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.zen.textBrand)
                        Text(item).font(ZenFont.text(13.5, .medium)).foregroundStyle(Color.zen.textHeading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if copied == i {
                            Text(AdminCopy.copied).font(ZenFont.text(12, .semibold)).foregroundStyle(Color.zen.textBrand)
                        }
                    }
                }
                .buttonStyle(ChipButtonStyle())
                .help(AdminCopy.copyHelp)
                .accessibilityLabel(item)
                .accessibilityHint(AdminCopy.copyHelp)
                .accessibilityValue(copied == i ? AdminCopy.copied : "")
            }
        }
    }
}

/// A quiet tinted chip: hover lifts it, press settles it, keyboard focus rings it.
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration) }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
            configuration.label
                .padding(.horizontal, ZenSpace.s3).padding(.vertical, ZenSpace.s2)
                .frame(minHeight: 36)
                .background(shape.fill(Color.zen.surfaceTint.opacity(hovering ? 1 : 0.75)))
                .overlay(shape.strokeBorder(Color.zen.brandFill.opacity(hovering ? 0.6 : 0.3), lineWidth: 1))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(shape)
        }
    }
}

// MARK: - The pattern

/// The month as a pattern: four weeks of seven cells, lit by the team's good-day rate (a week of
/// 100% is all seven lit). Deep green, lit from below; VoiceOver reads it as a sentence.
struct MonthPattern: View {
    let month: String
    let cells: [Int]
    let labels: [String]
    let tall: Bool

    var body: some View {
        let layout = tall
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZenSpace.s5))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ZenSpace.s6))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(AdminStory.monthName(month).uppercased()).font(ZenFont.number(10.5)).tracking(1.05)
                    .foregroundStyle(Self.soft)
                Text(AdminCopy.patternTitle).font(ZenFont.brand(22)).foregroundStyle(.white)
                Text(cells.isEmpty ? AdminCopy.patternEmpty : AdminCopy.patternCaption).font(ZenFont.text(12.5))
                    .foregroundStyle(Self.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tall { Spacer(minLength: 0) } else { Spacer(minLength: ZenSpace.s4) }
            grid
            if tall { Spacer(minLength: 0) }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                // Dark at the top where the words sit (white ≥ 9:1), lit at the bottom behind the cells.
                LinearGradient(colors: [Color(hex: 0x0A2E0E), Color(hex: 0x12601A)], startPoint: tall ? .top : .leading,
                               endPoint: tall ? .bottom : .trailing)
                RadialGradient(colors: [Color(hex: 0x5BDF62, alpha: 0.30), .clear],
                               center: tall ? UnitPoint(x: 0.4, y: 0.95) : UnitPoint(x: 0.85, y: 0.6), startRadius: 0, endRadius: 240)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AdminCopy.patternCaption)
        .accessibilityValue(zip(labels, cells).map { "\($0) \($1) of 7" }.joined(separator: ", "))
    }

    private static let soft = Color(hex: 0xD6F5D8)

    private var grid: some View {
        let rows = cells.isEmpty ? [0, 0, 0, 0] : cells
        return Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, lit in
                GridRow {
                    Text(r < labels.count ? labels[r] : "").font(ZenFont.number(10.5)).foregroundStyle(Self.soft)
                        .frame(width: 34, alignment: .leading)
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i < lit ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x9AF59F), Color(hex: 0x5BDF62)],
                                                                         startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white.opacity(i < lit ? 0.4 : 0.18), lineWidth: 1))
                            .shadow(color: i < lit ? Color(hex: 0x5BDF62, alpha: 0.55) : .clear, radius: 6)
                            .frame(width: 22, height: 22)
                    }
                }
            }
        }
    }
}
