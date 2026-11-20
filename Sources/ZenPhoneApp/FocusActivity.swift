import Foundation
import ZenAPI

/// The Live Activity that carries the Mac's focus to the Lock Screen and the Dynamic Island:
/// "Focusing until 12:00", an end time, never a countdown. The iPhone app target supplies the
/// ActivityKit one (Apps/iPhone); the tests and the Mac build of this library use stand-ins, so
/// every decision about it lives in `PhoneModel` and `FocusActivityStep`, not in ActivityKit.
@MainActor
public protocol FocusActivityControlling: AnyObject {
    /// Takes over whatever an earlier launch left on the Lock Screen: keeps one activity, ends any
    /// others, and returns the kept one's end time (nil when nothing was left).
    func adopt() -> Date?
    /// Shows a new activity. False when the system refused (Live Activities off, app in the
    /// background); the model tries again on the next change or when the app comes back.
    func start(until: Date) -> Bool
    /// Moves the end time of the activity on show.
    func update(until: Date)
    /// Ends every activity of ours.
    func end()
}

/// No Live Activities: the Mac build of this library, previews, and anywhere the app doesn't set one.
@MainActor
public final class NoFocusActivity: FocusActivityControlling {
    public init() {}
    public func adopt() -> Date? { nil }
    public func start(until: Date) -> Bool { false }
    public func update(until: Date) {}
    public func end() {}
}

/// The one decision: given the end time on show (if any) and what the Mac says now, what to do.
enum FocusActivityStep: Equatable {
    case keep, start(Date), update(Date), end

    static func next(shown: Date?, live: LiveFocus, now: Date) -> FocusActivityStep {
        guard live.isFocusing(at: now), let until = live.until else {
            return shown == nil ? .keep : .end
        }
        guard let shown else { return .start(until) }
        return shown == until ? .keep : .update(until)
    }
}
