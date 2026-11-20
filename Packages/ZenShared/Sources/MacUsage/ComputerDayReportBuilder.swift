// Turns the tracker's day into the report the Mac publishes: this install's random device id, a
// sequence that only grows, and the day's promise.
import Foundation
import ZenAPI
import ZenLogic

/// Where the builder keeps its few values between launches.
public protocol KeyValueStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

/// For tests and previews.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) { self.values = values }

    public func string(forKey key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ value: String?, forKey key: String) { lock.withLock { values[key] = value } }
}

/// The app's own defaults (thread-safe, as UserDefaults is).
public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
}

public final class ComputerDayReportBuilder: @unchecked Sendable {
    enum Keys {
        static let deviceId = "zen.computer.deviceId"
        static let sequence = "zen.computer.sequence"
        static let promiseHours = "zen.computer.promiseHours"
    }

    /// The contract's bounds for a computer's day.
    public static let maxCountedMinutes = 1_500
    public static let maxPullBacks = 1_000

    private let store: any KeyValueStore
    private let platform: DevicePlatform
    private let lock = NSLock()

    public init(store: any KeyValueStore, platform: DevicePlatform = .macos) {
        self.store = store
        self.platform = platform
    }

    /// This install's id: 32 random lowercase hex digits, made once and kept. Never a hardware id.
    public var deviceId: String {
        lock.withLock {
            if let id = store.string(forKey: Keys.deviceId), Self.isDeviceId(id) { return id }
            var generator = SystemRandomNumberGenerator()
            let id = Self.randomDeviceId(using: &generator)
            store.set(id, forKey: Keys.deviceId)
            return id
        }
    }

    /// The day's promise in whole hours, 1–12 (4 until the person picks one).
    public var promiseHours: Int {
        get {
            lock.withLock {
                store.string(forKey: Keys.promiseHours).flatMap(Int.init).map(Self.clampPromise)
                    ?? CoreConstants.PLACEHOLDER_PROMISE_HOURS
            }
        }
        set { lock.withLock { store.set(String(Self.clampPromise(newValue)), forKey: Keys.promiseHours) } }
    }

    /// The report for `day`. Every call takes the next sequence number, so a later report always
    /// wins over an earlier one on the backend.
    public func report(for day: UsageDay) -> ComputerDayReport {
        let id = deviceId
        let promise = promiseHours
        let sequence: Int64 = lock.withLock {
            let next = (store.string(forKey: Keys.sequence).flatMap(Int64.init) ?? 0) + 1
            store.set(String(next), forKey: Keys.sequence)
            return next
        }
        return ComputerDayReport(deviceId: id, platform: platform, day: day.day,
                                 countedMinutes: min(max(day.countedMinutes, 0), Self.maxCountedMinutes),
                                 pullBacks: min(max(day.pullBacks, 0), Self.maxPullBacks),
                                 promiseMinutes: promise * 60, sequence: sequence)
    }

    static func clampPromise(_ hours: Int) -> Int {
        min(max(hours, CoreConstants.PROMISE_MIN_DAILY_HOURS), CoreConstants.PROMISE_MAX_DAILY_HOURS)
    }

    static func randomDeviceId<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let hex = Array("0123456789abcdef")
        return String((0..<32).map { _ in hex[Int(generator.next() % 16)] })
    }

    static func isDeviceId(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
