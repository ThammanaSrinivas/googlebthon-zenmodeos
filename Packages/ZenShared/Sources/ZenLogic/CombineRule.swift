// The cross-device combine, v1: how an account's devices become its one Zen Score for a day.
//
// The server runs the same rule (its own port) on every device write and the fakes run this one,
// so the apps, the fakes and the server always agree. Both replay
// Tests/ZenLogicTests/Vectors/combine_v1.json; change the rule only together with the server's.
import Foundation
import ZenAPI

/// The phone's last report and when the backend stored it (the backend's clock).
public struct PhoneDayInput: Sendable, Equatable {
    public let report: PhoneDayReport
    public let writtenAt: Date

    public init(report: PhoneDayReport, writtenAt: Date) {
        self.report = report
        self.writtenAt = writtenAt
    }
}

/// One computer's last report and when the backend stored it (the backend's clock).
public struct ComputerDayInput: Sendable, Equatable {
    public let report: ComputerDayReport
    public let writtenAt: Date

    public init(report: ComputerDayReport, writtenAt: Date) {
        self.report = report
        self.writtenAt = writtenAt
    }
}

/// One device's part in the account's combined day.
public struct DeviceContribution: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable { case phone, computer }

    public let kind: Kind
    public let platform: DevicePlatform
    /// The computer's device id; nil for the phone.
    public let deviceId: String?
    /// It counts toward the combined score (fresh, on the combined day, within the plan's limit).
    public let counted: Bool
    /// This device's own score for its day.
    public let score: ZenScore?
    /// This device's minutes, only for a device whose minutes may be shown (never an iPhone's).
    public let minutes: Int?
    /// A computer's pull-backs; nil for the phone.
    public let pullBacks: Int?
    public let lastSeen: Date?

    public init(kind: Kind, platform: DevicePlatform, deviceId: String? = nil, counted: Bool,
                score: ZenScore? = nil, minutes: Int? = nil, pullBacks: Int? = nil, lastSeen: Date? = nil) {
        self.kind = kind
        self.platform = platform
        self.deviceId = deviceId
        self.counted = counted
        self.score = score
        self.minutes = platform.scoreOnly ? nil : minutes
        self.pullBacks = pullBacks
        self.lastSeen = lastSeen
    }
}

/// The account's one day across all its devices: what every device shows and the cohort seat holds.
public struct CombinedDay: Sendable, Equatable {
    public let day: DayKey
    public let score: ZenScore
    /// The minutes that may be shown (computers + an Android phone); nil when none may.
    public let minutes: Int?
    /// A fresh iPhone counts today: show the score only, never minutes.
    public let scoreOnly: Bool
    /// The phone (if any), then every computer by device id.
    public let devices: [DeviceContribution]
    public let updatedAt: Date

    public init(day: DayKey, score: ZenScore, minutes: Int?, scoreOnly: Bool,
                devices: [DeviceContribution], updatedAt: Date) {
        self.day = day
        self.score = score
        self.minutes = scoreOnly ? nil : minutes
        self.scoreOnly = scoreOnly
        self.devices = devices
        self.updatedAt = updatedAt
    }

    /// Devices that count today.
    public var countedDevices: [DeviceContribution] { devices.filter(\.counted) }
}

/// Combine v1 ("lowest score wins").
///
/// 1. The phone is **fresh** when it wrote within 18 h of now.
/// 2. The **holders** are the computers that wrote within the last 7 days, newest first (ties by
///    device id), at most `deviceLimit − 1` of them: the phone always holds one place.
/// 3. The day **T** is the fresh phone's day; otherwise the latest day a holder is on, ignoring a
///    day past UTC + 14 h of now (a wrong clock). Neither → no combined day.
/// 4. On T count the holders whose day is T: their minutes and pull-backs add up, the largest
///    promise counts. An Android phone that is fresh adds its own minutes; an iPhone never has any.
/// 5. No holder on T → the phone's own score. Otherwise the Zen Score of the summed minutes, and
///    never above a fresh phone's own score.
/// 6. A fresh iPhone on T makes the day **score only**: no minutes go anywhere.
/// 7. `devices` lists the phone (if any), then every computer by device id, each marked counted or not.
public enum CombineRule {
    public static let version = 1

    /// A phone that wrote this recently decides the account's day; an older write is stale.
    public static let phoneFresh: TimeInterval = 18 * 3_600
    /// How long a computer holds its place after its last write.
    public static let placeHeld: TimeInterval = 7 * 86_400
    /// Free: the phone and one computer.
    public static let defaultDeviceLimit = 2

    /// The phone wrote within `phoneFresh` of `now` (a write stamped after `now` is fresh too).
    public static func isFresh(_ phone: PhoneDayInput, now: Date) -> Bool {
        now.timeIntervalSince(phone.writtenAt) <= phoneFresh
    }

    /// The places a device limit leaves the computers: the phone always holds one.
    public static func computerSlots(deviceLimit: Int) -> Int { max(deviceLimit - 1, 0) }

    /// The computers holding a place at `now`, newest write first, ties by device id.
    public static func holders(_ computers: [ComputerDayInput], deviceLimit: Int, now: Date) -> [ComputerDayInput] {
        let held = computers.filter { now.timeIntervalSince($0.writtenAt) <= placeHeld }
        return Array(newestFirst(held).prefix(computerSlots(deviceLimit: deviceLimit)))
    }

    /// The account's day T at `now`; nil when there is neither a fresh phone nor a holder.
    public static func day(phone: PhoneDayInput?, holders: [ComputerDayInput], now: Date) -> DayKey? {
        if let phone, isFresh(phone, now: now) { return phone.report.day }
        let latest = DayKeys.latestAllowed(now: now)
        // yyyy-MM-dd in ASCII digits sorts as text in date order.
        return holders.map(\.report.day).filter { $0 <= latest }.max()
    }

    /// The account's combined day at `now`, or nil when no device can decide one.
    public static func combine(phone: PhoneDayInput?, computers: [ComputerDayInput],
                               deviceLimit: Int = defaultDeviceLimit, now: Date) -> CombinedDay? {
        let holders = holders(computers, deviceLimit: deviceLimit, now: now)
        guard let day = day(phone: phone, holders: holders, now: now) else { return nil }

        let freshPhone = phone.flatMap { isFresh($0, now: now) && $0.report.day == day ? $0 : nil }
        let counted = holders.filter { $0.report.day == day }
        let countedIds = Set(counted.map(\.report.deviceId))

        let phoneMinutes = freshPhone.flatMap { $0.report.platform == .android ? $0.report.minutes : nil }
        let computerMinutes = counted.reduce(0) { $0 + $1.report.countedMinutes }
        let anyMinutes = phoneMinutes != nil || !counted.isEmpty
        let totalMinutes = (phoneMinutes ?? 0) + computerMinutes

        let score: ZenScore
        if let promise = counted.map(\.report.promiseMinutes).max() {
            let pullBacks = counted.reduce(0) { $0 + $1.report.pullBacks }
            let computed = ZenScoreRule.score(minutes: totalMinutes, pullBacks: pullBacks, promiseMinutes: promise)
            score = freshPhone.map { min($0.report.score, computed) } ?? computed
        } else if let freshPhone {
            score = freshPhone.report.score
        } else {
            return nil // unreachable: T came from a fresh phone or a holder on T
        }

        let scoreOnly = freshPhone?.report.platform.scoreOnly ?? false
        var devices: [DeviceContribution] = []
        if let phone {
            devices.append(DeviceContribution(
                kind: .phone, platform: phone.report.platform, counted: freshPhone != nil,
                score: phone.report.score, minutes: phone.report.minutes, lastSeen: phone.writtenAt))
        }
        for computer in computers.sorted(by: { $0.report.deviceId < $1.report.deviceId }) {
            let r = computer.report
            devices.append(DeviceContribution(
                kind: .computer, platform: r.platform, deviceId: r.deviceId,
                counted: countedIds.contains(r.deviceId), score: ownScore(r),
                minutes: r.countedMinutes, pullBacks: r.pullBacks, lastSeen: computer.writtenAt))
        }
        return CombinedDay(day: day, score: score, minutes: anyMinutes ? totalMinutes : nil,
                           scoreOnly: scoreOnly, devices: devices, updatedAt: now)
    }

    /// A computer's own Zen Score for its own day.
    public static func ownScore(_ report: ComputerDayReport) -> ZenScore {
        ZenScoreRule.score(minutes: report.countedMinutes, pullBacks: report.pullBacks,
                           promiseMinutes: report.promiseMinutes)
    }

    private static func newestFirst(_ computers: [ComputerDayInput]) -> [ComputerDayInput] {
        computers.sorted {
            $0.writtenAt != $1.writtenAt ? $0.writtenAt > $1.writtenAt : $0.report.deviceId < $1.report.deviceId
        }
    }
}
