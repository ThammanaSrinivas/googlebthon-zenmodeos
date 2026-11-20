import Foundation

/// The time the ledger and the session read. The app uses `SystemVoiceClock`; tests and the demo
/// replay move a `ManualVoiceClock` by hand, so timers run without waiting.
public protocol VoiceClock: Sendable {
    var now: Date { get }
}

public struct SystemVoiceClock: VoiceClock {
    public init() {}
    public var now: Date { Date() }
}

public final class ManualVoiceClock: VoiceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_795_000_000)) { current = start }

    public var now: Date { lock.withLock { current } }

    public func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }

    public func set(_ date: Date) { lock.withLock { current = date } }
}

/// Where the ledger keeps its state between launches: UserDefaults in the app, memory in tests.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? { lock.withLock { values[key] } }

    public func set(_ data: Data?, forKey key: String) { lock.withLock { values[key] = data } }
}

/// UserDefaults is thread-safe; it just isn't marked Sendable.
public struct UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
