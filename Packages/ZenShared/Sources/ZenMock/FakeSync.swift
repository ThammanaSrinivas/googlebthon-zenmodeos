import Foundation
import ZenAPI
import ZenLogic

/// An in-memory sync backend that behaves like the real one: it checks what each device sends,
/// runs ZenLogic's `CombineRule` on every publish (lowest score wins, as the server does), and
/// streams the `ScoreSnapshot` every device would show. For previews, the demo and end-to-end tests.
///
/// One account, one clock: `now` is injectable so tests can move time.
public actor FakeSync: DaySyncService, ScoreService {
    /// The most computers one account keeps, as the backend caps it.
    public static let maxComputers = 16

    private let thisDeviceId: String?
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let streakBefore: Int
    private var deviceLimit: Int
    private var history: [DayKey: Int]
    private var phone: PhoneDayInput?
    private var computers: [String: ComputerDayInput] = [:]
    private var offline = false
    private var signedIn = true
    private var subscribers: [UUID: AsyncStream<ScoreSnapshot>.Continuation] = [:]

    /// - Parameters:
    ///   - thisDeviceId: the line marked "This …": a computer's device id, or
    ///     `ScoreSnapshotBuilder.phoneLineId` on the phone.
    ///   - history: earlier combined days (tenths), for the week strip.
    public init(thisDeviceId: String? = nil, history: [DayKey: Int] = [:], streakBefore: Int = 0,
                deviceLimit: Int = CombineRule.defaultDeviceLimit, timeZone: TimeZone = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.thisDeviceId = thisDeviceId
        self.history = history
        self.streakBefore = streakBefore
        self.deviceLimit = deviceLimit
        self.timeZone = timeZone
        self.now = now
    }

    /// Seeded with a demo week before today (7.2, 5.8, 8.1, 5.4, …) and a 9-week streak, like FakeScores.
    public static func demo(thisDeviceId: String? = nil, timeZone: TimeZone = .current,
                            now: @escaping @Sendable () -> Date = { Date() }) -> FakeSync {
        FakeSync(thisDeviceId: thisDeviceId, history: demoWeek(before: DayKeys.key(for: now(), in: timeZone)),
                 streakBefore: 9, timeZone: timeZone, now: now)
    }

    /// The demo scores for the days of `today`'s week before it.
    public static func demoWeek(before today: DayKey) -> [DayKey: Int] {
        guard let date = LocalDate.parse(today) else { return [:] }
        let tenths = [72, 58, 81, 54, 70, 65]
        let monday = date.weekStart
        return Dictionary(uniqueKeysWithValues: (0..<monday.daysUntil(date)).map {
            (monday.plusDays($0).description, tenths[$0])
        })
    }

    // MARK: - Simulation controls

    public func setOffline(_ offline: Bool) { self.offline = offline }

    public func setSignedIn(_ signedIn: Bool) {
        self.signedIn = signedIn
        if !signedIn {
            phone = nil
            computers = [:]
        }
        broadcast()
    }

    public func setDeviceLimit(_ limit: Int) {
        deviceLimit = min(max(limit, 1), Self.maxComputers + 1)
        broadcast()
    }

    /// "Another Mac" from one call: a computer's day for today, its sequence growing by itself.
    @discardableResult
    public func simulateComputer(deviceId: String = String(repeating: "f", count: 32), minutes: Int, pullBacks: Int = 0,
                                 promiseHours: Int = CoreConstants.PLACEHOLDER_PROMISE_HOURS) throws(SyncError) -> ScoreSnapshot {
        let sequence = (computers[deviceId]?.report.sequence ?? 0) + 1
        try store(computer: ComputerDayReport(deviceId: deviceId, day: todayKey(), countedMinutes: minutes, pullBacks: pullBacks,
                                              promiseMinutes: promiseHours * 60, sequence: sequence))
        return snapshot()
    }

    /// "The iPhone" from one call: its score for today, nothing else.
    @discardableResult
    public func simulatePhone(score tenths: Int, platform: DevicePlatform = .ios) throws(SyncError) -> ScoreSnapshot {
        try store(phone: PhoneDayReport(platform: platform, day: todayKey(), score: ZenScore(tenths: tenths)))
        return snapshot()
    }

    /// The combined day right now, as the backend would hold it.
    public func combinedDay() -> CombinedDay? {
        CombineRule.combine(phone: phone, computers: Array(computers.values), deviceLimit: deviceLimit, now: now())
    }

    public var subscriberCount: Int { subscribers.count }

    // MARK: - DaySyncService

    public func publish(phone report: PhoneDayReport) async throws(SyncError) {
        try check()
        try store(phone: report)
    }

    public func publish(computer report: ComputerDayReport) async throws(SyncError) {
        try check()
        try store(computer: report)
    }

    // MARK: - ScoreService

    public func today() async throws -> ScoreSnapshot {
        try check()
        return snapshot()
    }

    public nonisolated func updates() -> AsyncStream<ScoreSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScoreSnapshot.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        Task { await self.subscribe(id, continuation) }
        return stream
    }

    // MARK: - Internals

    private func check() throws(SyncError) {
        guard signedIn else { throw .signedOut }
        guard !offline else { throw .offline }
    }

    /// The backend's checks on a phone's day, then the combine.
    private func store(phone report: PhoneDayReport) throws(SyncError) {
        guard report.platform.isPhone, (25...100).contains(report.score.tenths) else { throw .rejected }
        if let minutes = report.minutes, !(0...1_500).contains(minutes) { throw .rejected }
        try checkDay(report.day)
        phone = PhoneDayInput(report: report, writtenAt: now())
        recombine()
    }

    /// The backend's checks on a computer's day; a lower sequence never replaces a higher one.
    private func store(computer report: ComputerDayReport) throws(SyncError) {
        guard Self.isDeviceId(report.deviceId), !report.platform.isPhone, report.platform != .ipados,
              (0...1_500).contains(report.countedMinutes), (0...1_000).contains(report.pullBacks),
              (60...720).contains(report.promiseMinutes), report.promiseMinutes % 60 == 0, report.sequence >= 0
        else { throw .rejected }
        try checkDay(report.day)
        if let existing = computers[report.deviceId] {
            guard report.sequence >= existing.report.sequence else { return }
        } else if computers.count >= Self.maxComputers {
            throw .rejected
        }
        computers[report.deviceId] = ComputerDayInput(report: report, writtenAt: now())
        recombine()
    }

    private func checkDay(_ day: DayKey) throws(SyncError) {
        guard DayKeys.isValid(day), day <= DayKeys.latestAllowed(now: now()) else { throw .rejected }
    }

    private func recombine() {
        if let combined = combinedDay() { history[combined.day] = combined.score.tenths }
        broadcast()
    }

    private func snapshot() -> ScoreSnapshot {
        ScoreSnapshotBuilder.make(combined: combinedDay(), history: history, streakBefore: streakBefore,
                                  today: todayKey(), thisDeviceId: thisDeviceId, now: now())
    }

    private func todayKey() -> DayKey { DayKeys.key(for: now(), in: timeZone) }

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<ScoreSnapshot>.Continuation) {
        subscribers[id] = continuation
        continuation.yield(snapshot())
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    private func broadcast() {
        guard !subscribers.isEmpty else { return }
        let current = snapshot()
        for continuation in subscribers.values { continuation.yield(current) }
    }

    static func isDeviceId(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
