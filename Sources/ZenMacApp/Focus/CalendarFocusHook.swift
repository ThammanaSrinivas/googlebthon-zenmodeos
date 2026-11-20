import EventKit
import Foundation
import ZenAPI
import ZenFocus

/// A busy "Focus" event in the person's calendar for the block, through macOS Calendar (EventKit).
/// When their Google account is added to Calendar, the block lands in Google Calendar too. An early
/// stop shortens the event to the real end. Nothing about the event leaves the Mac from us.
final class CalendarFocusHook: FocusHook, @unchecked Sendable {
    let id = "calendar"
    let displayName = "Calendar"
    static let title = "Focus · ZenMode OS"
    private static let eventKeyPrefix = "zen.focus.calendarEvent."

    private let store = EKEventStore()
    private let enabled: @Sendable () -> Bool
    private let calendarId: @Sendable () -> String?

    init(enabled: @escaping @Sendable () -> Bool, calendarId: @escaping @Sendable () -> String? = { nil }) {
        self.enabled = enabled
        self.calendarId = calendarId
    }

    func status() async -> HookStatus {
        guard enabled() else { return .off }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly: return target() == nil ? .needsSetup("No calendar to write to") : .ready
        default: return .needsSetup("Connect your calendar")
        }
    }

    /// The calendar picked in Integrations, else the default one.
    private func target() -> EKCalendar? {
        if let id = calendarId(), let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
        return store.defaultCalendarForNewEvents
    }

    func onFocusStart(_ session: FocusBlock) async throws {
        guard let calendar = target() else { throw HookFailure("No calendar to write to") }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = Self.title
        event.notes = "Notifications are paused until \(FocusClock.text(session.until))."
        event.startDate = session.startAt
        event.endDate = session.until
        event.availability = .busy
        do { try store.save(event, span: .thisEvent, commit: true) } catch { throw HookFailure("Calendar didn't save it") }
        UserDefaults.standard.set(event.eventIdentifier, forKey: Self.eventKeyPrefix + session.id)
    }

    func onFocusEnd(_ session: FocusBlock, kept: Bool) async throws {
        let key = Self.eventKeyPrefix + session.id
        defer { UserDefaults.standard.removeObject(forKey: key) }
        guard !kept, let id = UserDefaults.standard.string(forKey: key), let event = store.event(withIdentifier: id) else { return }
        let end = max(Date(), session.startAt.addingTimeInterval(60))
        guard end < event.endDate else { return }
        event.endDate = end
        do { try store.save(event, span: .thisEvent, commit: true) } catch { throw HookFailure("Calendar didn't update") }
    }

    /// Calendars that can take the block, for the picker.
    static func writableCalendars() -> [(id: String, title: String, source: String)] {
        EKEventStore().calendars(for: .event).filter(\.allowsContentModifications)
            .map { ($0.calendarIdentifier, $0.title, $0.source.title) }
    }
}
