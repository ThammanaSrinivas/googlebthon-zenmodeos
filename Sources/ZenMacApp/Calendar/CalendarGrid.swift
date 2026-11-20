import SwiftUI
import Albeit
import ZenAPI

/// Each day cell reports its frame, so the hover card can sit beside the day it describes.
struct DayAnchorKey: PreferenceKey {
    static let defaultValue: [Date: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The Zen Score as a dot: filled in the band's colour, a hollow ring for a day with no data,
/// nothing for a day still to come.
struct ScoreDot: View {
    let band: ScoreBand
    var size: CGFloat = 8

    var body: some View {
        Group {
            if let color = band.color {
                Circle().fill(color)
                    .overlay(Circle().strokeBorder(Color.zen.textHeading.opacity(0.12), lineWidth: 0.5))
            } else if band == .noData {
                Circle().strokeBorder(Color.zen.textCaption.opacity(0.55), lineWidth: max(1, size * 0.16))
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// An event inside a day cell: the calendar's colour as a bar, the time, the title.
struct EventChip: View {
    let event: CalendarLink.Event

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3, height: 11)
            if !event.isAllDay {
                Text(ClockText.time(event.start))
                    .font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textBody)
            }
            Text(event.title).font(ZenFont.text(11.5, .medium)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(event.color.opacity(event.isAllDay ? 0.22 : 0.1)))
    }
}

/// One day in the month: the score dot at the top-left, the date at the top-right (today in a
/// brand pill), and up to a few events.
struct DayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isHovered: Bool
    let maxChips: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 5) {
                ScoreDot(band: day.band)
                if let score = day.score, !day.isFuture {
                    Text(score.text).font(ZenFont.number(11.5)).foregroundStyle(Color.zen.textBody)
                        .accessibilityLabel("Zen Score \(score.text)")
                }
                Spacer(minLength: 0)
                dateNumber
            }
            ForEach(day.events.prefix(day.events.count > maxChips ? maxChips - 1 : maxChips)) { EventChip(event: $0) }
            if day.events.count > maxChips {
                Text(CalendarCopy.more(day.events.count - maxChips + 1))
                    .font(ZenFont.text(11, .medium)).foregroundStyle(Color.zen.textCaption).padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .opacity(day.inMonth ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var dateNumber: some View {
        let first = Calendar.current.component(.day, from: day.date) == 1
        let text = first ? day.date.formatted(.dateTime.day().month(.abbreviated)) : day.number
        if day.isToday {
            Text(text)
                .font(ZenFont.text(12, .semibold))
                .foregroundStyle(Color.zen.surfaceBase)
                .padding(.horizontal, 7)
                .frame(minWidth: 22, minHeight: 22)
                .background(Capsule().fill(Color.zen.textBrand))
        } else {
            Text(text)
                .font(ZenFont.text(12, first ? .semibold : .medium))
                .foregroundStyle(day.inMonth ? Color.zen.textHeading : Color.zen.textCaption)
                .frame(minHeight: 22)
        }
    }

    private var background: some View {
        let weekend = CalendarDays.calendar.isDateInWeekend(day.date)
        return Rectangle().fill(
            isSelected ? Color.zen.surfaceTint.opacity(0.9)
                : isHovered ? Color.zen.textHeading.opacity(0.04)
                : weekend ? Color.zen.textHeading.opacity(0.018) : Color.clear)
    }
}

/// The month as Notion lays it out: whole weeks, hairlines between days, nothing heavier.
struct MonthGrid: View {
    let days: [CalendarDay]
    let selected: Date?
    let hovered: Date?
    let onHover: (Date, Bool) -> Void
    let onSelect: (Date) -> Void

    var body: some View {
        let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        let maxChips = rows.count > 5 ? 2 : 3
        VStack(spacing: 0) {
            WeekdayHeader()
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { c, day in
                        DayCell(day: day, isSelected: selected == day.date, isHovered: hovered == day.date, maxChips: maxChips)
                            .overlay(alignment: .trailing) { if c < 6 { Hairline(vertical: true) } }
                            .overlay(alignment: .bottom) { if r < rows.count - 1 { Hairline(vertical: false) } }
                            .anchorPreference(key: DayAnchorKey.self, value: .bounds) { [day.date: $0] }
                            .onHover { onHover(day.date, $0) }
                            .onTapGesture { onSelect(day.date) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.spoken)
                            .accessibilityAddTraits(selected == day.date ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { onSelect(day.date) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// The week as seven columns, every event listed under its day.
struct WeekBoard: View {
    let days: [CalendarDay]
    let selected: Date?
    let hovered: Date?
    let onHover: (Date, Bool) -> Void
    let onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { c, day in
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    HStack(spacing: 6) {
                        ScoreDot(band: day.band, size: 9)
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(ZenFont.number(10)).tracking(0.8)
                            .foregroundStyle(day.isToday ? Color.zen.textBrand : Color.zen.textCaption)
                        Spacer(minLength: 0)
                        Text(day.number)
                            .font(ZenFont.text(13, .semibold))
                            .foregroundStyle(day.isToday ? Color.zen.surfaceBase : Color.zen.textHeading)
                            .frame(minWidth: 24, minHeight: 24)
                            .background { if day.isToday { Circle().fill(Color.zen.textBrand) } }
                    }
                    Text(day.score?.text ?? (day.isFuture ? " " : "–"))
                        .font(ZenFont.number(28)).foregroundStyle(day.score == nil ? Color.zen.textCaption : Color.zen.textHeading)
                    Text(day.band.label).font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                    Hairline(vertical: false).padding(.vertical, 2)
                    ForEach(day.events) { EventChip(event: $0) }
                    Spacer(minLength: 0)
                }
                .padding(ZenSpace.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Rectangle().fill(selected == day.date ? Color.zen.surfaceTint.opacity(0.9) : hovered == day.date ? Color.zen.textHeading.opacity(0.04) : .clear))
                .overlay(alignment: .trailing) { if c < days.count - 1 { Hairline(vertical: true) } }
                .contentShape(Rectangle())
                .anchorPreference(key: DayAnchorKey.self, value: .bounds) { [day.date: $0] }
                .onHover { onHover(day.date, $0) }
                .onTapGesture { onSelect(day.date) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.spoken)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onSelect(day.date) }
            }
        }
    }
}

/// MON TUE … SUN, today's column in the brand colour.
struct WeekdayHeader: View {
    var body: some View {
        let todayIndex = (CalendarDays.calendar.component(.weekday, from: Date()) + 5) % 7
        HStack(spacing: 0) {
            ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated()), id: \.offset) { i, name in
                Text(name.uppercased())
                    .font(ZenFont.number(10)).tracking(0.8)
                    .foregroundStyle(i == todayIndex ? Color.zen.textBrand : Color.zen.textCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).frame(height: 30)
            }
        }
        .overlay(alignment: .bottom) { Hairline(vertical: false) }
        .accessibilityHidden(true)
    }
}

struct Hairline: View {
    let vertical: Bool

    var body: some View {
        Rectangle().fill(Color.zen.borderHairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// The dot colours, in words.
struct ScoreLegend: View {
    var body: some View {
        HStack(spacing: ZenSpace.s4) {
            ForEach(ScoreBand.legend, id: \.1) { band, text in
                HStack(spacing: 6) {
                    ScoreDot(band: band)
                    Text(text).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dot colours: 8 and up, above 6, 4 to 6, under 4, and no data")
    }
}
