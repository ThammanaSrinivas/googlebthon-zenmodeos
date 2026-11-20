import AppKit
import EventKit
import SwiftUI
import Albeit

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
    /// Events by the start of the day they fall on, for the ranges the Calendar section has shown.
    /// A multi-day event sits on every day it touches.
    private(set) var byDay: [Date: [Event]] = [:]
    /// Bumps whenever the calendar changes, so views showing a range know to load it again.
    private(set) var revision = 0

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    @ObservationIgnored private var loadedRanges: Set<DateInterval> = []

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
        events = fetch(DateInterval(start: start, end: end))
    }

    /// Loads every event in `range` (a month grid, a week), once per range until the calendar changes.
    func load(_ range: DateInterval) {
        guard state == .connected, !loadedRanges.contains(range) else { return }
        loadedRanges.insert(range)
        let calendar = Calendar.current
        var next = byDay
        for event in fetch(range) {
            var day = calendar.startOfDay(for: event.start)
            // An event ending at midnight doesn't touch the next day.
            let last = event.end.addingTimeInterval(-1)
            var guardDays = 0
            while day <= last && guardDays < 42 {
                if range.contains(day) || day == calendar.startOfDay(for: event.start) {
                    var list = next[day] ?? []
                    if !list.contains(where: { $0.id == event.id }) { list.append(event) }
                    next[day] = list.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                guardDays += 1
            }
        }
        byDay = next
    }

    /// The events touching `day`, all-day ones first, then by start time.
    func events(on day: Date) -> [Event] {
        byDay[Calendar.current.startOfDay(for: day)] ?? []
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

    #if DEBUG
    /// Debug renders only (ZEN_CAL_SAMPLE=1): a believable week of plans, so the chips and the
    /// agenda can be checked without anyone's real calendar. Never compiled into a release.
    func debugSamples(around now: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let plans: [(Int, Int, Int, String, Bool, UInt32)] = [
            (0, 10, 60, "Design review", true, 0x2F6FDB), (0, 14, 90, "Algorithms lecture", true, 0x2AA136), (0, 19, 45, "Gym", false, 0xE2B000),
            (-1, 9, 30, "Standup", true, 0x2F6FDB), (-1, 16, 60, "Office hours", true, 0x7A4BC2),
            (-2, 11, 120, "Lab: networks", true, 0x2AA136), (1, 10, 60, "1:1 with Asha", true, 0x2F6FDB), (1, 15, 30, "Dentist", true, 0xD9541E),
            (3, 9, 600, "Hackathon judging", true, 0x2AA136), (-3, 18, 60, "Running club", false, 0xE2B000), (-8, 10, 60, "Mid-sem exam", true, 0xD9541E),
            (0, 21, 30, "Call home", false, 0x7A4BC2),
        ]
        var next = byDay
        for (offset, hour, minutes, title, busy, hue) in plans {
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            let event = Event(id: "sample-\(title)-\(offset)", title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                              isAllDay: false, isBusy: busy, color: Color(hex: hue))
            next[day, default: []].append(event)
        }
        byDay = next
    }
    #endif

    private func fetch(_ range: DateInterval) -> [Event] {
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                Event(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                      title: e.title ?? "Busy", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      isBusy: !e.isAllDay && e.availability != .free,
                      color: Color(nsColor: e.calendar.color ?? .systemGreen))
            }
    }

    private func startWatching() {
        refresh()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.loadedRanges = []
                self.byDay = [:]
                self.revision += 1
            }
        }
    }
}
