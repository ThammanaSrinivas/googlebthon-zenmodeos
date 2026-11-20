import SwiftUI
import Albeit

/// Every sentence on the Calendar section and its sidebar card, named once.
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
    static let next = "Next"
    static let headsUp = "A heads-up 10 minutes before each busy event, then quiet till it ends."
    static let bannerBody = "See your plans beside your scores. Zeno goes quiet in busy events. Events never leave this Mac."
    static let today = "Today"
    static let month = "Month"
    static let week = "Week"
    static let previous = "Previous"
    static let following = "Next"
    static let demoHistory = "Demo history"
    static let agenda = "Agenda"
    static let thisWeek = "This week"
    static let nothingPlanned = "Nothing on the calendar."
    static let connectToSee = "Connect your calendar to see your plans here."
    static let allDay = "All day"
    static let close = "Close"
    static let keys = "← → move · T today · Esc closes"
    static func more(_ n: Int) -> String { "+\(n) more" }
    static func quiet(_ summary: String) -> String {
        "Zeno is quiet: \(summary.lowercased() == "only at night" ? "" : summary + ", and ")every night 10:30 pm to 7 am."
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
                // Primary only where the calendar is the page; in the sidebar it stays secondary,
                // so it never competes with the screen's own primary action.
                Button(CalendarCopy.connect) { model.connectCalendar() }
                    .buttonStyle(large ? AnyButtonStyle(ZenPrimaryButtonStyle()) : AnyButtonStyle(ZenSecondaryButtonStyle()))
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

/// A section still to be built out.
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
