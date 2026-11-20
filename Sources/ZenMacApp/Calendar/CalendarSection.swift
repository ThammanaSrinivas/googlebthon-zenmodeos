import SwiftUI
import Albeit
import ZenAPI

enum CalendarCopy {
    static let title = "Calendar"
    static let connectTitle = "Connect your calendar"
    static let connectBody = "Zeno goes quiet in class and meetings, and gives you a heads-up first."
    static let staysHere = "Events are read on this Mac and never leave it."
    static let connect = "Connect"
    static let notNow = "Not now"
    static let deniedTitle = "Calendar access is off"
    static let deniedBody = "Turn it on in System Settings so Zeno can keep quiet in your meetings."
    static let openSettings = "Open System Settings"
    static let quietPill = "Zeno quiet"
    static let nothingToday = "Nothing on today. Zeno's free to speak."
    static let next = "Next"
    static let headsUp = "A heads-up 10 minutes before each busy event, then quiet till it ends."
}

/// Calendar: this month with each day's Zen Score, and the person's own calendar beside it.
struct CalendarSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(CalendarCopy.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now.formatted(.dateTime.month(.wide).year())).zenType(.body).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    // Past days come from day history, which isn't wired yet.
                    DemoTag("Demo history")
                }
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    MonthScoresCard(records: model.streak.map { $0.weeks.flatMap { $0.days.compactMap { $0 } } } ?? [])
                    YourCalendarCard()
                        .frame(width: 380)
                }
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }
}

/// This month as a grid: each day's score on a cell, good days green, today ringed.
private struct MonthScoresCard: View {
    let records: [DayRecord]

    var body: some View {
        let calendar = Self.mondayCalendar
        let today = calendar.startOfDay(for: Date())
        let month = calendar.dateInterval(of: .month, for: today)!
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: month.start)!.start
        let byDay = Dictionary(records.map { (calendar.startOfDay(for: $0.date), $0.score) }, uniquingKeysWith: { a, _ in a })
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeekStart) }
        let rows = stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }.filter { row in row.contains { month.contains($0) } }

        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                    Text(d.uppercased()).font(ZenFont.number(9.5)).tracking(0.6).foregroundStyle(Color.zen.textCaption).frame(maxWidth: .infinity)
                }
            }
            ForEach(rows, id: \.first) { row in
                HStack(spacing: ZenSpace.s2) {
                    ForEach(row, id: \.self) { day in
                        dayCell(day, inMonth: month.contains(day), isToday: day == today, isFuture: day > today, score: byDay[day] ?? nil)
                    }
                }
            }
            HStack(spacing: ZenSpace.s4) {
                legend(Color.zen.brandFill.opacity(0.85), "A good day, above 6.0")
                legend(Color.zen.surfaceSunk, "Under 6.0")
                legend(.clear, "No data", outlined: true)
            }
            .padding(.top, ZenSpace.s2)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity)
        .glassCard(radius: ZenRadius.widget)
    }

    static var mondayCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private func dayCell(_ day: Date, inMonth: Bool, isToday: Bool, isFuture: Bool, score: ZenScore?) -> some View {
        let good = score?.isGoodDay == true
        return VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.day())).font(ZenFont.number(10.5))
                .foregroundStyle(good && !isFuture ? Color(hex: 0x0B2A0E).opacity(0.7) : Color.zen.textCaption)
            Spacer(minLength: 0)
            if let score, !isFuture {
                Text(score.text).font(ZenFont.number(15))
                    .foregroundStyle(good ? Color(hex: 0x0B2A0E) : Color.zen.textHeading)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 62)
        .background {
            RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                .fill(good && !isFuture ? Color.zen.brandSoft.opacity(isToday ? 1 : 0.72) : Color.zen.surfaceSunk.opacity(score == nil || isFuture ? 0.25 : 0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                .strokeBorder(isToday ? Color.zen.textHeading : (score == nil && !isFuture && inMonth ? Color.zen.borderOutline : .clear), lineWidth: isToday ? 2 : 1)
        }
        .opacity(inMonth ? 1 : 0.3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(score.map { "Zen Score \($0.text)" } ?? (isFuture ? "not yet" : "no data"))")
    }

    private func legend(_ color: Color, _ text: String, outlined: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color)
                .overlay { if outlined { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.zen.borderOutline, lineWidth: 1) } }
                .frame(width: 12, height: 12)
            Text(text).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }
}

/// The person's own calendar: connect it, or see today and tomorrow with the quiet times marked.
private struct YourCalendarCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let link = model.calendarLink
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            switch link.state {
            case .notAsked:
                ConnectCalendarPrompt(large: true)
            case .denied:
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Eyebrow("Your calendar")
                    Text(CalendarCopy.deniedTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
                    Text(CalendarCopy.deniedBody).zenType(.body).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(CalendarCopy.openSettings) { Task { await link.connect() } }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
            case .connected:
                Eyebrow("Today · your calendar")
                if link.today.isEmpty {
                    Text(CalendarCopy.nothingToday).zenType(.body).foregroundStyle(Color.zen.textBody)
                } else {
                    VStack(spacing: ZenSpace.s2) {
                        ForEach(link.today) { EventRow(event: $0) }
                    }
                }
                let tomorrow = link.events.filter { Calendar.current.isDateInTomorrow($0.start) }
                if !tomorrow.isEmpty {
                    Eyebrow("Tomorrow").padding(.top, ZenSpace.s2)
                    VStack(spacing: ZenSpace.s2) {
                        ForEach(tomorrow.prefix(4)) { EventRow(event: $0) }
                    }
                }
                Divider().overlay(Color.zen.borderHairline)
                Text(CalendarCopy.headsUp).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Color.zen.borderHairline)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack {
                    Text("Zeno is quiet").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    Text(model.profile.quiet.summary).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                }
                QuietStrip(quiet: model.profile.quiet)
            }
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
        .animation(ZenMotion.container, value: link.state)
    }
}

private struct EventRow: View {
    let event: CalendarLink.Event

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
                Text(event.isAllDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
            }
            Spacer(minLength: 0)
            if event.isBusy {
                Text(CalendarCopy.quietPill).font(ZenFont.text(11, .semibold)).foregroundStyle(Color(hex: 0x4D654A))
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Color(hex: 0x93A88F).opacity(0.25)))
            }
        }
        .padding(.horizontal, ZenSpace.s3).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.55)))
        .accessibilityElement(children: .combine)
    }
}

/// The ask: connect the calendar. Large in the Calendar section, compact at the foot of the sidebar.
struct ConnectCalendarPrompt: View {
    @Environment(AppModel.self) private var model
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? ZenSpace.s3 : ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "calendar").font(.system(size: large ? 16 : 13, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                Text(CalendarCopy.connectTitle).font(ZenFont.text(large ? 17 : 13, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            Text(CalendarCopy.connectBody).font(ZenFont.text(large ? 14 : 12)).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            if large {
                Text(CalendarCopy.staysHere).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            HStack(spacing: ZenSpace.s3) {
                Button(CalendarCopy.connect) { model.connectCalendar() }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .controlSize(large ? .regular : .small)
                if !large {
                    Button(CalendarCopy.notNow) { withAnimation(ZenMotion.exit) { model.calendarLink.dismissedPrompt = true } }
                        .buttonStyle(ZenLinkButtonStyle())
                }
            }
        }
    }
}

/// The foot of the sidebar: the connect prompt until the calendar is connected, then the next
/// busy event and the promise that Zeno will be quiet in it.
struct SidebarCalendarCard: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        let link = model.calendarLink
        Group {
            switch link.state {
            case .notAsked where !link.dismissedPrompt:
                ConnectCalendarPrompt()
                    .padding(ZenSpace.s3)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.7)))
            case .connected:
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(CalendarCopy.next)
                        if let next = link.nextBusy(after: Date()) {
                            Text(next.start.formatted(date: .omitted, time: .shortened)).font(ZenFont.number(15)).foregroundStyle(Color.zen.textHeading)
                            Text(next.title).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
                            Text("\(CalendarCopy.quietPill) then").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        } else {
                            Text("Nothing else today").font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ZenSpace.s3)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.7)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
        }
        .animation(ZenMotion.container, value: link.state)
        .animation(ZenMotion.container, value: link.dismissedPrompt)
    }
}

/// Cohort, Zen Gold and Settings until they're built out.
struct SectionPlaceholder: View {
    let title: String
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Text(title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
            Text(line).zenType(.body).foregroundStyle(Color.zen.textBody)
            Spacer()
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
