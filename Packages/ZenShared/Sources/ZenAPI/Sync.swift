import Foundation

// Cross-device sync: what each device sends, and the live score every device shows.
//
// The founders' rule (20 Nov 2026): the account's one Zen Score for a day is the LOWEST of the
// phone's score and the score of the computers' summed distracting minutes. Every device, and the
// person's seat in a cohort, show that same number within seconds of any device publishing.
// An iPhone sends its Zen Score only: its Screen Time minutes never leave it (DPLA 3.3.3(P)).
// The rule itself lives in ZenLogic (`CombineRule`), identical to the server's.

/// The kind of device a report comes from.
public enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case ios, ipados, macos, android, windows, linux

    /// The phone's place in the combine is held by an iPhone or an Android phone.
    public var isPhone: Bool { self == .ios || self == .android }
    /// Apple's Screen Time platforms: their minutes never leave the device.
    public var scoreOnly: Bool { self == .ios || self == .ipados }
}

/// A local calendar day as "yyyy-MM-dd" in ASCII digits, in the time zone it was lived in.
public typealias DayKey = String

/// The phone's day. An iPhone sends `minutes: nil` (score only), always.
public struct PhoneDayReport: Codable, Equatable, Sendable {
    public let platform: DevicePlatform
    public let day: DayKey
    public let score: ZenScore
    /// An Android phone's screen time in minutes. Always nil from an iPhone.
    public let minutes: Int?

    public init(platform: DevicePlatform, day: DayKey, score: ZenScore, minutes: Int? = nil) {
        self.platform = platform
        self.day = day
        self.score = score
        self.minutes = platform.scoreOnly ? nil : minutes
    }
}

/// A computer's day (the Mac app). MacUsage builds these.
public struct ComputerDayReport: Codable, Equatable, Sendable {
    /// 32 lowercase hex characters, random per install, never a hardware id.
    public let deviceId: String
    public let platform: DevicePlatform
    public let day: DayKey
    /// Distracting minutes counted today, 0–1500.
    public let countedMinutes: Int
    /// Times the person came back from a distraction today, 0–1000.
    public let pullBacks: Int
    /// The day's promise in minutes, whole hours, 60–720.
    public let promiseMinutes: Int
    /// Only grows, per computer: a late, older write can never replace a newer one.
    public let sequence: Int64

    public init(deviceId: String, platform: DevicePlatform = .macos, day: DayKey, countedMinutes: Int,
                pullBacks: Int, promiseMinutes: Int, sequence: Int64) {
        self.deviceId = deviceId
        self.platform = platform
        self.day = day
        self.countedMinutes = countedMinutes
        self.pullBacks = pullBacks
        self.promiseMinutes = promiseMinutes
        self.sequence = sequence
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case signedOut, offline, rejected, unavailable
}

/// Sends this device's day. Safe to call often: the backend keeps the newest and ignores repeats.
public protocol DaySyncService: Sendable {
    func publish(phone: PhoneDayReport) async throws(SyncError)
    func publish(computer: ComputerDayReport) async throws(SyncError)
}

extension ScoreService {
    /// Live updates by polling `today()`, for services that can't push. The real backend overrides
    /// this with a listener that updates within seconds.
    public func pollingUpdates(every interval: Duration) -> AsyncStream<ScoreSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let snapshot = try? await today() { continuation.yield(snapshot) }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Default for `updates()`: poll every 30 seconds.
    public func updates() -> AsyncStream<ScoreSnapshot> { pollingUpdates(every: .seconds(30)) }
}
