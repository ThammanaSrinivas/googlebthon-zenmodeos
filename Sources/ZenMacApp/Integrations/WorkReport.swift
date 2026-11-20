import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Albeit

enum WorkCopy {
    static let eyebrow = "Work · tracked by itself"
    static let title = "Where your work week went"
    static let lede = "Measured on this Mac from the app in front, your calendar and the tickets in progress. Nothing to start, stop or fill in."
    static let byTicket = "By ticket"
    static let export = "Export timesheet"
    static let shareLead = "Send my lead a weekly summary"
    static let shareLeadDetail = "Hours by kind of work and ticket only. You see it before it goes. Off unless you turn it on."
    static let teamTitle = "Your team, as one"
    static let teamCaption = "12 people · group numbers only, never a name next to one"
}

/// The person's own work week, by kind of work and by ticket: automatic time tracking that stays
/// theirs. Their timesheet exports as a CSV; a summary to their lead goes only if they switch it on.
struct WorkReportCard: View {
    @State private var shareWithLead = false

    struct Slice: Identifiable {
        let id: String
        let label: String
        let minutes: Int
        let color: Color
    }

    static let slices: [Slice] = [
        Slice(id: "deep", label: "Deep work", minutes: 1120, color: Color(hex: 0xE2B000)),
        Slice(id: "meetings", label: "Meetings", minutes: 375, color: Color(hex: 0x93A88F)),
        Slice(id: "messages", label: "Messages", minutes: 185, color: Color(hex: 0x5BDF62)),
        Slice(id: "admin", label: "Admin", minutes: 140, color: Color(hex: 0x8E948B)),
        Slice(id: "distracting", label: "Distracting", minutes: 110, color: Color(hex: 0xD9541E)),
    ]

    static let tickets: [(key: String, minutes: Int)] = [("ZEN-142", 430), ("ZEN-150", 330), ("ZEN-133", 245), ("ZEN-151", 115)]

    var body: some View {
        let total = Self.slices.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Eyebrow(WorkCopy.eyebrow, color: Color.zen.textBrand)
                DemoTag()
                Spacer()
                Text(Self.hours(total)).font(ZenFont.number(13)).foregroundStyle(Color.zen.textCaption)
            }
            Text(WorkCopy.title).zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(WorkCopy.lede).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)

            // One bar, split by kind of work.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Self.slices) { s in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(s.color)
                            .frame(width: max(4, (geo.size.width - 8) * CGFloat(s.minutes) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: ZenSpace.s3)], alignment: .leading, spacing: ZenSpace.s2) {
                ForEach(Self.slices) { s in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 10, height: 10)
                        Text(s.label).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                        Text(Self.hours(s.minutes)).font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Divider().overlay(Color.zen.borderHairline)
            Eyebrow(WorkCopy.byTicket)
            VStack(spacing: ZenSpace.s2) {
                let longest = Self.tickets.map(\.minutes).max() ?? 1
                ForEach(Self.tickets, id: \.key) { t in
                    HStack(spacing: ZenSpace.s3) {
                        Text(t.key).font(ZenFont.number(12)).foregroundStyle(Color.zen.textHeading).frame(width: 74, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xE2B000).opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(t.minutes) / CGFloat(longest))
                        }
                        .frame(height: 8)
                        Text(Self.hours(t.minutes)).font(ZenFont.number(11.5)).foregroundStyle(Color.zen.textCaption).frame(width: 64, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(t.key): \(Self.hours(t.minutes))")
                }
            }

            Divider().overlay(Color.zen.borderHairline)
            HStack(alignment: .center, spacing: ZenSpace.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkCopy.shareLead).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(WorkCopy.shareLeadDetail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle(WorkCopy.shareLead, isOn: $shareWithLead).labelsHidden().toggleStyle(.switch).tint(Color.zen.brandFill)
            }
            HStack {
                Spacer()
                Button(WorkCopy.export) { Self.exportTimesheet() }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .help("A CSV of this week's hours by kind of work and by ticket. Yours to keep.")
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    static func hours(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m" }

    /// The timesheet as CSV, saved where the person chooses.
    static func exportTimesheet() {
        var csv = "section,item,minutes,hours\n"
        for s in slices { csv += "kind,\(s.label),\(s.minutes),\(String(format: "%.2f", Double(s.minutes) / 60))\n" }
        for t in tickets { csv += "ticket,\(t.key),\(t.minutes),\(String(format: "%.2f", Double(t.minutes) / 60))\n" }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "ZenMode OS timesheet \(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

/// The team as one: focus share, meeting load and after-hours messages, for 5 or more.
struct TeamInsightsCard: View {
    private let rows: [(label: String, value: String, delta: String, good: Bool)] = [
        ("Time in deep work", "61%", "▲ 4 pts", true),
        ("Time in meetings", "22%", "▼ 3 pts", true),
        ("Messages after 9 pm", "−18%", "on last week", true),
        ("Good days, as a team", "64%", "▲ 6 pts", true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Eyebrow("Team insights")
                DemoTag()
            }
            Text(WorkCopy.teamTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(WorkCopy.teamCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            VStack(spacing: 0) {
                ForEach(rows, id: \.label) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.label).font(ZenFont.text(13)).foregroundStyle(Color.zen.textBody)
                        Spacer()
                        Text(r.value).font(ZenFont.number(17)).foregroundStyle(Color.zen.textHeading)
                        Text(r.delta).font(ZenFont.number(10.5)).foregroundStyle(r.good ? Color.zen.scoreGain : Color.zen.scoreDeduct)
                            .frame(width: 84, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.zen.borderHairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
    }
}
