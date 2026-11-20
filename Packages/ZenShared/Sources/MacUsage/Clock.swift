// The clock MacDaySync reads and schedules on. The app uses `SystemClock`; tests pass a clock they
// move by hand, so throttles and retries run without waiting.
import Foundation

/// Scheduled work that hasn't run yet can be cancelled.
@MainActor
public protocol ScheduledWork: AnyObject {
    func cancel()
}

@MainActor
public protocol SchedulingClock: AnyObject {
    var now: Date { get }
    /// Runs `work` on the main actor `seconds` from now (or at once for 0 or less).
    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork
}

/// The wall clock, scheduling with `Task.sleep`.
@MainActor
public final class SystemClock: SchedulingClock {
    public init() {}

    public var now: Date { Date() }

    @discardableResult
    public func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let task = Task { @MainActor in
            if seconds > 0 { try? await Task.sleep(for: .milliseconds(Int64(seconds * 1_000))) }
            guard !Task.isCancelled else { return }
            work()
        }
        return TaskWork(task: task)
    }

    private final class TaskWork: ScheduledWork {
        let task: Task<Void, Never>
        init(task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }
}
