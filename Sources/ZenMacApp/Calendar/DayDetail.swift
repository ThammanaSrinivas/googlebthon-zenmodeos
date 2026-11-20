import SwiftUI
import Albeit
import ZenAPI

/// A day, in full: the Zen Score and what it means, the week it belongs to, the agenda with the
/// busy events Zeno will keep quiet in, and the quiet hours. The hover preview and the pinned
/// panel are the same card; the preview lists fewer events and has no close button.
struct DayDetailCard: View {
    let day: CalendarDay
    let weekLine: String
    let quietLine: String
    let connected: Bool
    var onClose: (() -> Void)?

    private var isPreview: Bool { onClose == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.wide)))
                        .font(ZenFont.brand(20)).foregroundStyle(Color.zen.textHeading)
                    Text(day.date.formatted(.dateTime.day().month(.wide).year()))
                        .zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.zen.textCaption)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.zen.textHeading.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(CalendarCopy.close)
                }
            }

            HStack(alignment: .center, spacing: ZenSpace.s3) {
                ScoreDot(band: day.band, size: 12)
                Text(day.score?.text ?? "–")
                    .font(ZenFont.number(40))
                    .foregroundStyle(day.score == nil ? Color.zen.textCaption : Color.zen.textHeading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.band.label).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text("Zen Score").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.score.map { "Zen Score \($0.text), \(day.band.label)" } ?? day.band.label)

            HStack(spacing: ZenSpace.s2) {
                Eyebrow(CalendarCopy.thisWeek)
                Text(weekLine).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
            }

            Hairline(vertical: false)

            Eyebrow(CalendarCopy.agenda)
            agenda

            Hairline(vertical: false)
            Text(quietLine).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var agenda: some View {
        if day.events.isEmpty {
            Text(connected ? CalendarCopy.nothingPlanned : CalendarCopy.connectToSee)
                .zenType(.body).foregroundStyle(Color.zen.textBody)
        } else {
            let limit = isPreview ? 4 : day.events.count
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                ForEach(day.events.prefix(limit)) { AgendaRow(event: $0) }
                if day.events.count > limit {
                    Text(CalendarCopy.more(day.events.count - limit)).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
        }
    }
}

/// One event in the agenda: its time, its title, and whether Zeno keeps quiet in it.
private struct AgendaRow: View {
    let event: CalendarLink.Event

    var body: some View {
        HStack(alignment: .top, spacing: ZenSpace.s2) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(2)
                Text(event.isAllDay ? CalendarCopy.allDay : ClockText.span(event.start, event.end))
                    .font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
            }
            Spacer(minLength: 0)
            if event.isBusy {
                Text(CalendarCopy.quietPill).font(ZenFont.text(10.5, .semibold)).foregroundStyle(Color.zen.textBrand)
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(Color.zen.surfaceTint))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
