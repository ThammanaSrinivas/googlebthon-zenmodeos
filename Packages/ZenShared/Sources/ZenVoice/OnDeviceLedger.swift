import Foundation
import ZenAPI
import ZenLogic

// The on-device ledger: everything Zeno does that never leaves the device (founders, 20 Nov 2026).
// Intent sessions with their timers, focus sessions, app pauses and today's pickups live here and
// in the app's own storage; app names are never sent to the backend. Ported from the prototype's
// ledger (zeno-voice/src/ledger.js) without its mocked score moves: the Zen Score is the account's
// real, combined score (ScoreService), never nudged by a voice command.

/// The limits every tool clamps to, as the prototype's ledger did.
public enum ZenoLimits {
    public static let intentMinutes = 1...180
    public static let defaultIntentMinutes = 5
    public static let focusMinutes = 5...240
    public static let defaultFocusMinutes = 25
    public static let pauseSeconds = 3...30
    public static let defaultPauseSeconds = 7
    /// The most overrun a single session can record (12 hours).
    public static let overrunMinutes = 0...720
    public static let maxAppNameLength = 40
    public static let maxPurposeLength = 80
    public static let maxLabelLength = 60
    public static let maxQuietApps = 10
    /// Ended sessions kept for the day's history.
    public static let keptIntents = 50
}

public struct IntentSession: Codable, Equatable, Sendable, Identifiable {
    public enum EndReason: String, Codable, Sendable {
        /// The person (or Zeno, for them) ended it.
        case ended
        /// A new intent took its place.
        case replaced
    }

    public let id: String
    public let app: String
    public let purpose: String
    public let minutes: Int
    public let startedAt: Date
    public let endsAt: Date
    public var endedAt: Date?
    public var overrunMinutes: Int?
    public var endReason: EndReason?
    /// True once the "time's up" nudge has fired.
    public var timeUpNotified: Bool

    public var isOpen: Bool { endedAt == nil }

    /// Nil while open; true when it ended within the minutes asked for.
    public var onTime: Bool? { endedAt == nil ? nil : (overrunMinutes ?? 0) == 0 }

    /// Seconds left on the island timer (negative once past).
    public func secondsLeft(at now: Date) -> TimeInterval { endsAt.timeIntervalSince(now) }
}

public struct FocusSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let minutes: Int
    public let quietApps: [String]
    public let startedAt: Date
    public let endsAt: Date
    public var endedAt: Date?

    public func isActive(at now: Date) -> Bool { endedAt == nil && now < endsAt }

    public func secondsLeft(at now: Date) -> TimeInterval { endsAt.timeIntervalSince(now) }
}

public struct AppPause: Codable, Equatable, Sendable {
    public let app: String
    public let seconds: Int
    public let since: Date
}

/// Today's pickups, in the device's time zone.
public struct PickupTally: Codable, Equatable, Sendable {
    public let day: DayKey
    public var total: Int
    public var withIntent: Int

    public init(day: DayKey, total: Int = 0, withIntent: Int = 0) {
        self.day = day
        self.total = total
        self.withIntent = withIntent
    }
}

/// What changed, for the UI (the island timer, the focus pill, the pause list).
public enum LedgerEvent: Equatable, Sendable {
    case intentStarted(IntentSession)
    case intentEnded(IntentSession)
    /// The minutes asked for are up and the session is still open: time for a gentle nudge.
    case intentTimeUp(IntentSession)
    case focusStarted(FocusSession)
    case focusEnded(FocusSession)
    case paused(AppPause)
    case unpaused(app: String)
    case pickup(PickupTally)
}

/// The ledger's state at one moment: what `get_zen_status` reports from the device.
public struct LedgerStatus: Equatable, Sendable {
    public let pickups: PickupTally
    public let activeIntent: IntentSession?
    public let focus: FocusSession?
    public let pausedApps: [AppPause]
}

public actor OnDeviceLedger {
    struct State: Codable, Equatable {
        var intents: [IntentSession] = []
        var focus: FocusSession?
        var pauses: [AppPause] = []
        var pickups: PickupTally?
        /// Whether the latest pickup has had an intent declared, so one pickup counts once.
        var latestPickupHasIntent = false
        var lastCardId: String?
        var nextId = 1
    }

    public static let storageKey = "zeno.ledger.v1"

    private let clock: any VoiceClock
    private let store: any KeyValueStore
    private let timeZone: TimeZone
    private var state: State
    private var listeners: [UUID: AsyncStream<LedgerEvent>.Continuation] = [:]

    public init(clock: any VoiceClock = SystemVoiceClock(), store: any KeyValueStore = InMemoryKeyValueStore(),
                timeZone: TimeZone = .current) {
        self.clock = clock
        self.store = store
        self.timeZone = timeZone
        if let data = store.data(forKey: Self.storageKey), let saved = try? Self.decoder.decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    // MARK: Events

    /// Every change from now on. Each call gets its own stream.
    public func events() -> AsyncStream<LedgerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LedgerEvent.self)
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }

    private func emit(_ event: LedgerEvent) {
        for continuation in listeners.values { continuation.yield(event) }
    }

    // MARK: Intents

    /// Starts an intent session, ending (as replaced) any that is still open. Returns the new
    /// session and the one it replaced.
    @discardableResult
    public func startIntent(app: String, purpose: String, minutes: Int) -> (session: IntentSession, replaced: IntentSession?) {
        let replaced = state.intents.lastIndex(where: \.isOpen).map { finishIntent(at: $0, overrun: 0, reason: .replaced) }
        let now = clock.now
        let minutes = minutes.clamped(to: ZenoLimits.intentMinutes)
        let session = IntentSession(
            id: "s\(takeId())", app: app, purpose: purpose, minutes: minutes, startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)), endedAt: nil, overrunMinutes: nil,
            endReason: nil, timeUpNotified: false)
        state.intents.append(session)
        if state.intents.count > ZenoLimits.keptIntents { state.intents.removeFirst(state.intents.count - ZenoLimits.keptIntents) }
        markPickupIntent()
        save()
        emit(.intentStarted(session))
        return (session, replaced)
    }

    /// Ends the session with `id`, or the open one. The overrun is the larger of the one given and
    /// the one the clock measured (whole minutes past the end). Nil when there is nothing to end.
    public func endIntent(id: String? = nil, overrunMinutes: Int = 0) -> IntentSession? {
        let index = id.flatMap { id in state.intents.lastIndex { $0.id == id && $0.isOpen } }
            ?? state.intents.lastIndex(where: \.isOpen)
        guard let index else { return nil }
        let measured = max(0, Int(clock.now.timeIntervalSince(state.intents[index].endsAt) / 60))
        let overrun = max(overrunMinutes, measured).clamped(to: ZenoLimits.overrunMinutes)
        let ended = finishIntent(at: index, overrun: overrun, reason: .ended)
        save()
        return ended
    }

    private func finishIntent(at index: Int, overrun: Int, reason: IntentSession.EndReason) -> IntentSession {
        state.intents[index].endedAt = clock.now
        state.intents[index].overrunMinutes = overrun
        state.intents[index].endReason = reason
        let ended = state.intents[index]
        emit(.intentEnded(ended))
        return ended
    }

    public var activeIntent: IntentSession? { state.intents.last(where: \.isOpen) }

    public var intents: [IntentSession] { state.intents }

    // MARK: Focus

    /// Starts focus, replacing any running one.
    @discardableResult
    public func startFocus(minutes: Int, label: String, quietApps: [String]) -> FocusSession {
        if let running = activeFocus { endFocus(running) }
        let now = clock.now
        let minutes = minutes.clamped(to: ZenoLimits.focusMinutes)
        let focus = FocusSession(id: "f\(takeId())", label: label, minutes: minutes, quietApps: quietApps,
                                 startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)), endedAt: nil)
        state.focus = focus
        save()
        emit(.focusStarted(focus))
        return focus
    }

    /// Ends focus early. Nil when none is running.
    @discardableResult
    public func endFocus() -> FocusSession? {
        guard let running = activeFocus else { return nil }
        let ended = endFocus(running)
        save()
        return ended
    }

    @discardableResult
    private func endFocus(_ running: FocusSession) -> FocusSession {
        var ended = running
        ended.endedAt = min(clock.now, running.endsAt)
        state.focus = ended
        emit(.focusEnded(ended))
        return ended
    }

    public var activeFocus: FocusSession? {
        guard let focus = state.focus, focus.isActive(at: clock.now) else { return nil }
        return focus
    }

    // MARK: Pauses

    /// Puts a pause in front of `app`, or changes its length (apps match without case).
    @discardableResult
    public func pause(app: String, seconds: Int) -> AppPause {
        let pause = AppPause(app: app, seconds: seconds.clamped(to: ZenoLimits.pauseSeconds), since: clock.now)
        if let index = state.pauses.firstIndex(where: { $0.app.lowercased() == app.lowercased() }) {
            state.pauses[index] = AppPause(app: state.pauses[index].app, seconds: pause.seconds, since: state.pauses[index].since)
        } else {
            state.pauses.append(pause)
        }
        save()
        let stored = state.pauses.first { $0.app.lowercased() == app.lowercased() }!
        emit(.paused(stored))
        return stored
    }

    public func unpause(app: String) {
        let before = state.pauses.count
        state.pauses.removeAll { $0.app.lowercased() == app.lowercased() }
        guard state.pauses.count != before else { return }
        save()
        emit(.unpaused(app: app))
    }

    public var pauses: [AppPause] { state.pauses }

    /// How long to hold `app` before it opens, if it is paused.
    public func pauseSeconds(for app: String) -> Int? {
        state.pauses.first { $0.app.lowercased() == app.lowercased() }?.seconds
    }

    // MARK: Pickups

    /// The person picked up the phone (or opened Zeno from the notch).
    @discardableResult
    public func recordPickup() -> PickupTally {
        var tally = today()
        tally.total += 1
        state.pickups = tally
        state.latestPickupHasIntent = false
        save()
        emit(.pickup(tally))
        return tally
    }

    /// Today's tally (zeros on a new day).
    public func today() -> PickupTally {
        let day = DayKeys.key(for: clock.now, in: timeZone)
        if let tally = state.pickups, tally.day == day { return tally }
        return PickupTally(day: day)
    }

    private func markPickupIntent() {
        var tally = today()
        guard tally.total > tally.withIntent, !state.latestPickupHasIntent else { return }
        tally.withIntent += 1
        state.pickups = tally
        state.latestPickupHasIntent = true
    }

    // MARK: Cards (only the id: the card itself lives on the backend)

    public func setLastCard(id: String) {
        state.lastCardId = id
        save()
    }

    public var lastCardId: String? { state.lastCardId }

    // MARK: Status and timers

    public func status() -> LedgerStatus {
        LedgerStatus(pickups: today(), activeIntent: activeIntent, focus: activeFocus, pausedApps: state.pauses)
    }

    /// Fires what the clock has reached: "time's up" once per open session, and the end of a focus
    /// session. Returns what it fired. Call it every second or so while the island shows a timer.
    @discardableResult
    public func checkTimers() -> [LedgerEvent] {
        let now = clock.now
        var fired: [LedgerEvent] = []
        for index in state.intents.indices where state.intents[index].isOpen && !state.intents[index].timeUpNotified
            && now >= state.intents[index].endsAt {
            state.intents[index].timeUpNotified = true
            fired.append(.intentTimeUp(state.intents[index]))
        }
        if let focus = state.focus, focus.endedAt == nil, now >= focus.endsAt {
            var ended = focus
            ended.endedAt = focus.endsAt
            state.focus = ended
            fired.append(.focusEnded(ended))
        }
        if !fired.isEmpty { save() }
        fired.forEach(emit)
        return fired
    }

    /// Checks the timers every `interval` until the task is cancelled.
    public func runTimers(every interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            checkTimers()
            try? await Task.sleep(for: interval)
        }
    }

    // MARK: Storage

    private func takeId() -> Int {
        defer { state.nextId += 1 }
        return state.nextId
    }

    private func save() {
        store.set(try? Self.encoder.encode(state), forKey: Self.storageKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
