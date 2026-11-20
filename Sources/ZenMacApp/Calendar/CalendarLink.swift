import AppKit
import EventKit
import SwiftUI

/// The person's calendar, read on this Mac with EventKit. Zeno goes quiet during busy events and
/// gives a heads-up before one starts. Events are read here and never leave the Mac.
@MainActor
@Observable
final class CalendarLink {
    enum State: Equatable { case notAsked, connected, denied }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        /// Busy events silence Zeno; free ones (a reminder, a birthday) don't.
        let isBusy: Bool
        let color: Color
    }

    private(set) var state: State
    /// Today's and tomorrow's events, soonest first.
    private(set) var events: [Event] = []
    /// The person chose "Not now" on the sidebar card.
    var dismissedPrompt = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: state = .connected
        case .denied, .restricted, .writeOnly: state = .denied
        default: state = .notAsked
        }
        if state == .connected { startWatching() }
    }

    /// Asks once. If the person said no before, opens the Calendars pane of System Settings instead.
    func connect() async {
        if state == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { state = granted ? .connected : .denied }
        if granted { startWatching() }
    }

    func refresh(now: Date = Date()) {
        guard state == .connected else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                Event(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                      title: e.title ?? "Busy", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      isBusy: !e.isAllDay && e.availability != .free,
                      color: Color(nsColor: e.calendar.color ?? .systemGreen))
            }
    }

    /// True inside a busy event, the minutes Zeno keeps quiet.
    func isBusy(at date: Date) -> Bool {
        events.contains { $0.isBusy && $0.start <= date && date < $0.end }
    }

    /// The next busy event that hasn't started yet.
    func nextBusy(after date: Date) -> Event? {
        events.first { $0.isBusy && $0.start > date }
    }

    var today: [Event] { events.filter { Calendar.current.isDateInToday($0.start) } }

    private func startWatching() {
        refresh()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
