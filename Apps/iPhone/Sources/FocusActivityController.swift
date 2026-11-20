import ActivityKit
import Foundation
import ZenPhoneApp

/// The Live Activity for the Mac's focus, on ActivityKit. `PhoneModel` decides when to start,
/// update and end it (and is tested for that); this only carries the decisions out. The activity
/// goes stale at its end time, so the Lock Screen reads "Focus done" even if the app is asleep.
@MainActor
final class FocusActivityController: FocusActivityControlling {
    private typealias FocusActivity = Activity<FocusActivityAttributes>

    private var activity: FocusActivity?

    func adopt() -> Date? {
        let left = FocusActivity.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        guard let keep = left.max(by: { $0.content.state.until < $1.content.state.until }) else { return nil }
        let extras = Set(left.map(\.id)).subtracting([keep.id])
        if !extras.isEmpty { Task { await Self.finish(extras) } }
        activity = keep
        return keep.content.state.until
    }

    func start(until: Date) -> Bool {
        if activity != nil {
            update(until: until)
            return true
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            activity = try FocusActivity.request(attributes: FocusActivityAttributes(), content: Self.content(until))
            return true
        } catch {
            return false
        }
    }

    func update(until: Date) {
        guard let activity else {
            _ = start(until: until)
            return
        }
        let id = activity.id, content = Self.content(until)
        Task { await Self.push(content, to: id) }
    }

    func end() {
        activity = nil
        // The ids now, so a start that follows at once isn't ended with them.
        let ids = Set(FocusActivity.activities.map(\.id))
        if !ids.isEmpty { Task { await Self.finish(ids) } }
    }

    // ActivityKit's handles aren't Sendable: these look them up again off the main actor by id.

    private nonisolated static func push(_ content: ActivityContent<FocusActivityAttributes.ContentState>, to id: String) async {
        for activity in FocusActivity.activities where activity.id == id {
            await activity.update(content)
        }
    }

    private nonisolated static func finish(_ ids: Set<String>) async {
        for activity in FocusActivity.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func content(_ until: Date) -> ActivityContent<FocusActivityAttributes.ContentState> {
        ActivityContent(state: FocusActivityAttributes.ContentState(until: until), staleDate: until)
    }
}
