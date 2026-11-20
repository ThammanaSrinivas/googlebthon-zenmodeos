import Foundation
import ZenAPI

/// A tiny key-value store (UserDefaults on the Mac, memory in tests).
public protocol FocusKeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class MemoryFocusStore: FocusKeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ data: Data?, forKey key: String) { lock.withLock { values[key] = data } }
}

public struct UserDefaultsFocusStore: FocusKeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}

/// The block in progress, saved before any hook runs so a crash can still end it on the next launch.
public struct ActiveFocus: Codable, Equatable, Sendable {
    public let session: FocusBlock
    public var started: [String: HookState]
}

/// A block that just ended, and what each hook did.
public struct FocusEnded: Equatable, Sendable {
    public let record: FocusRecord
    public let endOutcomes: [HookOutcome]
    public let daily: DailyFocus
    public let day: String
}

/// Focus Mode's core, the same on every Mac: start a block, run the hooks, end it (on time, early
/// or after a crash), and write the session, the day and `live/focus`. Network writes wait at most
/// a few seconds; Firestore queues them while offline, and a signed-out Mac keeps them for later.
public actor FocusEngine {
    public static let activeKey = "zen.focus.active"
    public static let ledgerKey = "zen.focus.daily"
    public static let outboxKey = "zen.focus.outbox"
    /// Ending within this much of the end time still keeps the block.
    public static let keptGrace: TimeInterval = 60
    public static let writeDeadline: Duration = .seconds(4)

    private let runner: HookRunner
    private let hooks: @Sendable () -> [any FocusHook]
    private let store: any FocusKeyValueStore
    private let sync: @Sendable () -> (any FocusSyncService)?
    private let now: @Sendable () -> Date
    private let timeZone: TimeZone

    public init(runner: HookRunner = HookRunner(), hooks: @escaping @Sendable () -> [any FocusHook],
                store: any FocusKeyValueStore, sync: @escaping @Sendable () -> (any FocusSyncService)?,
                now: @escaping @Sendable () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.runner = runner
        self.hooks = hooks
        self.store = store
        self.sync = sync
        self.now = now
        self.timeZone = timeZone
    }

    /// The block in progress, if any (also after a relaunch).
    public var active: ActiveFocus? { load(ActiveFocus.self, Self.activeKey) }

    /// Starts a block that ends at `until`. A second start while focusing returns the running one.
    public func start(until: Date, source: FocusSource) async -> (FocusBlock, [HookOutcome]) {
        if let running = active {
            return (running.session, running.started.map { HookOutcome(id: $0.key, displayName: $0.key, state: $0.value) })
        }
        let session = FocusBlock(startAt: now(), until: until, source: source)
        save(ActiveFocus(session: session, started: [:]), Self.activeKey)
        let outcomes = await runner.start(session, hooks: hooks())
        save(ActiveFocus(session: session, started: Dictionary(uniqueKeysWithValues: outcomes.map { ($0.id, $0.state) })), Self.activeKey)
        await write { try await $0.setLive(LiveFocus(active: true, until: session.until)) }
        return (session, outcomes)
    }

    /// Ends the block now (early or on time). Nil when nothing is running.
    public func end() async -> FocusEnded? {
        guard let running = active else { return nil }
        let endAt = min(now(), running.session.until.addingTimeInterval(Self.keptGrace))
        return await finish(running, endAt: endAt, recovering: false)
    }

    /// After a crash or a quit mid-block: end it with the hooks, as kept if its time ran out.
    public func recover() async -> FocusEnded? {
        await flushOutbox()
        guard let running = active else { return nil }
        let endAt = min(now(), running.session.until)
        return await finish(running, endAt: endAt, recovering: true)
    }

    /// Today's totals so far (the ledger is the Mac's own copy of `daily`).
    public func daily(on day: String) -> DailyFocus {
        (load([String: DailyFocus].self, Self.ledgerKey) ?? [:])[day] ?? DailyFocus()
    }

    /// Adds after-hours minutes to a day and writes it.
    public func addAfterHours(minutes: Int, day: String) async {
        guard minutes > 0 else { return }
        var ledger = load([String: DailyFocus].self, Self.ledgerKey) ?? [:]
        var d = ledger[day] ?? DailyFocus()
        d.afterHoursMin += minutes
        ledger[day] = d.clamped
        save(ledger, Self.ledgerKey)
        let daily = d.clamped
        await write { try await $0.saveDaily(daily, day: day) }
    }

    /// Sets the day's Zen Score (tenths, 25…100) and writes the day, only when it changed.
    public func setZenScore(_ tenths: Int, day: String) async {
        guard (25...100).contains(tenths) else { return }
        var ledger = load([String: DailyFocus].self, Self.ledgerKey) ?? [:]
        var d = ledger[day] ?? DailyFocus()
        guard d.zenScoreTenths != tenths else { return }
        d.zenScoreTenths = tenths
        ledger[day] = d.clamped
        save(ledger, Self.ledgerKey)
        let daily = d.clamped
        await write { try await $0.saveDaily(daily, day: day) }
    }

    /// Writes waiting from a signed-out stretch go up once someone signs in.
    public func flushOutbox() async {
        guard let sync = sync() else { return }
        let pending = load([FocusRecord].self, Self.outboxKey) ?? []
        guard !pending.isEmpty else { return }
        var left: [FocusRecord] = []
        for record in pending {
            if case .failed(let error) = await withDeadline(Self.writeDeadline, { try await sync.save(record) }),
               (error as? FocusSyncError) == .signedOut {
                left.append(record)
            }
        }
        save(left.isEmpty ? nil : left, Self.outboxKey)
    }

    public func dayKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func finish(_ running: ActiveFocus, endAt: Date, recovering: Bool) async -> FocusEnded {
        let session = running.session
        let kept = endAt >= session.until.addingTimeInterval(-Self.keptGrace)
        let endOutcomes: [HookOutcome]
        if running.started.isEmpty {
            // The start never finished (a crash while hooks ran): end everything that's set up.
            endOutcomes = await runner.endAll(session, kept: kept, hooks: hooks())
        } else {
            let started = running.started.map { HookOutcome(id: $0.key, displayName: $0.key, state: $0.value) }
            endOutcomes = await runner.end(session, kept: kept, hooks: hooks(), started: started)
        }
        let record = FocusRecord(session: session, endAt: endAt, kept: kept, hooks: running.started)
        save(Optional<ActiveFocus>.none, Self.activeKey)

        let day = dayKey(session.startAt)
        var ledger = load([String: DailyFocus].self, Self.ledgerKey) ?? [:]
        var d = ledger[day] ?? DailyFocus()
        d.focusMin += record.focusedMin
        d.blocksStarted += 1
        if kept { d.blocksKept += 1 }
        d = d.clamped
        ledger[day] = d
        save(ledger, Self.ledgerKey)

        let daily = d
        await write { try await $0.setLive(.idle) }
        await saveRecord(record)
        await write { try await $0.saveDaily(daily, day: day) }
        return FocusEnded(record: record, endOutcomes: endOutcomes, daily: d, day: day)
    }

    private func saveRecord(_ record: FocusRecord) async {
        guard let sync = sync() else { return queue(record) }
        if case .failed(let error) = await withDeadline(Self.writeDeadline, { try await sync.save(record) }),
           (error as? FocusSyncError) == .signedOut {
            queue(record)
        }
    }

    private func queue(_ record: FocusRecord) {
        var pending = load([FocusRecord].self, Self.outboxKey) ?? []
        pending.append(record)
        save(Array(pending.suffix(50)), Self.outboxKey)
    }

    private func write(_ body: @escaping @Sendable (any FocusSyncService) async throws -> Void) async {
        guard let sync = sync() else { return }
        _ = await withDeadline(Self.writeDeadline) { try await body(sync) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        store.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
