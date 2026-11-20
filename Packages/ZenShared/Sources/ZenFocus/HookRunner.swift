import Dispatch
import Foundation
import ZenAPI

/// Whether an integration can run.
public enum HookStatus: Equatable, Sendable {
    case ready
    /// Not set up yet; the reason says what's missing ("Paste a Slack token").
    case needsSetup(String)
    /// Set up, but switched off for focus.
    case off
}

/// One integration Focus Mode drives: Mac Do Not Disturb, Slack, the calendar, a webhook. Every hook
/// has the same shape, so the runner treats them alike and adding one touches nothing else.
public protocol FocusHook: Sendable {
    /// Stable id, the key in `focus_sessions.hooks` ("dnd", "slack", "calendar", "webhook").
    var id: String { get }
    var displayName: String { get }
    func status() async -> HookStatus
    func onFocusStart(_ session: FocusBlock) async throws
    /// Runs for every hook that was ready at the start, even one whose start failed (a half-set
    /// status still needs clearing), after an early stop and after a crash.
    func onFocusEnd(_ session: FocusBlock, kept: Bool) async throws
}

/// What a hook did, for its chip.
public struct HookOutcome: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let state: HookState
    /// Why it failed or was skipped, in words people read.
    public let note: String?

    public init(id: String, displayName: String, state: HookState, note: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.note = note
    }
}

/// Fires every hook in parallel, each with its own deadline. A failed or slow hook never stops focus,
/// and the runner itself never throws.
public struct HookRunner: Sendable {
    public static let defaultTimeout: Duration = .seconds(5)

    public let timeout: Duration

    public init(timeout: Duration = HookRunner.defaultTimeout) {
        self.timeout = timeout
    }

    /// Starts every ready hook. Outcomes come back in the hooks' order.
    public func start(_ session: FocusBlock, hooks: [any FocusHook]) async -> [HookOutcome] {
        await run(hooks) { hook in
            switch await withDeadline(timeout, { await hook.status() }) {
            case .finished(.ready):
                break
            case .finished(.needsSetup(let why)):
                return HookOutcome(id: hook.id, displayName: hook.displayName, state: .skipped, note: why)
            case .finished(.off):
                return HookOutcome(id: hook.id, displayName: hook.displayName, state: .skipped, note: "Off")
            case .timedOut, .failed:
                return HookOutcome(id: hook.id, displayName: hook.displayName, state: .failed, note: "Didn't answer")
            }
            return await outcome(of: hook) { try await hook.onFocusStart(session) }
        }
    }

    /// Ends the hooks that started (on or failed); skipped ones are left alone.
    public func end(_ session: FocusBlock, kept: Bool, hooks: [any FocusHook], started: [HookOutcome]) async -> [HookOutcome] {
        let ran = Set(started.filter { $0.state != .skipped }.map(\.id))
        return await run(hooks.filter { ran.contains($0.id) }) { hook in
            await outcome(of: hook) { try await hook.onFocusEnd(session, kept: kept) }
        }
    }

    /// Ends every hook regardless of how it started: recovery after a crash, when the start's
    /// outcomes are gone. Hooks that aren't set up are skipped.
    public func endAll(_ session: FocusBlock, kept: Bool, hooks: [any FocusHook]) async -> [HookOutcome] {
        await run(hooks) { hook in
            guard case .finished(.ready) = await withDeadline(timeout, { await hook.status() }) else {
                return HookOutcome(id: hook.id, displayName: hook.displayName, state: .skipped)
            }
            return await outcome(of: hook) { try await hook.onFocusEnd(session, kept: kept) }
        }
    }

    private func outcome(of hook: any FocusHook, _ body: @escaping @Sendable () async throws -> Void) async -> HookOutcome {
        switch await withDeadline(timeout, body) {
        case .finished:
            return HookOutcome(id: hook.id, displayName: hook.displayName, state: .on)
        case .timedOut:
            return HookOutcome(id: hook.id, displayName: hook.displayName, state: .failed, note: "Took too long")
        case .failed(let error):
            return HookOutcome(id: hook.id, displayName: hook.displayName, state: .failed, note: HookFailure.describe(error))
        }
    }

    private func run(_ hooks: [any FocusHook], _ each: @escaping @Sendable (any FocusHook) async -> HookOutcome) async -> [HookOutcome] {
        await withTaskGroup(of: (Int, HookOutcome).self) { group in
            for (i, hook) in hooks.enumerated() {
                group.addTask { (i, await each(hook)) }
            }
            var out = [HookOutcome?](repeating: nil, count: hooks.count)
            for await (i, o) in group { out[i] = o }
            return out.compactMap { $0 }
        }
    }
}

/// An error a hook throws with a message people can read.
public struct HookFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }

    static func describe(_ error: any Error) -> String {
        if let failure = error as? HookFailure { return failure.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "Offline" }
        return "Didn't work"
    }
}

/// How a call with a deadline ended.
public enum DeadlineResult<Value: Sendable>: Sendable {
    case finished(Value)
    case timedOut
    case failed(any Error)
}

/// Runs `body` until it finishes or `limit` passes, whichever is first. Unlike a task group, this
/// returns at the deadline even when `body` ignores cancellation (a stuck `Process`, a socket): the
/// slow work is cancelled and left to finish on its own.
public func withDeadline<Value: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async throws -> Value) async -> DeadlineResult<Value> {
    let once = Once<DeadlineResult<Value>>()
    return await withCheckedContinuation { continuation in
        let work = Task {
            do {
                let value = try await body()
                once.resume(continuation, with: .finished(value))
            } catch {
                once.resume(continuation, with: .failed(error))
            }
        }
        // The deadline runs on a dispatch timer, not the shared task pool, so a busy pool can't
        // make it late.
        let c = limit.components
        let seconds = Double(c.seconds) + Double(c.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if once.resume(continuation, with: .timedOut) { work.cancel() }
        }
    }
}

/// Resumes a continuation exactly once.
private final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<Value, Never>, with value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        continuation.resume(returning: value)
        return true
    }
}
