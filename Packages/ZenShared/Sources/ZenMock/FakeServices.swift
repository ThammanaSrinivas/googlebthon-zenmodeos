import Foundation
import ZenAPI
import ZenLogic

/// Fakes behind the real contracts, for the open-source build, the tests and the offline demo.
/// Everything they return is demo data and the app labels it so.
public enum ZenMock {
    public static let demoUser = ZenUser(uid: "demo-kamal", displayName: "Kamal")
    /// The demo cohort's code. Any other valid code is "not found".
    public static let demoCohortCode = JoinCode("ZEN4HS")!
}

public struct FakeAuth: AuthService {
    private let approvalDelay: Duration

    public init(approvalDelay: Duration = .seconds(3)) { self.approvalDelay = approvalDelay }

    public func currentUser() async -> ZenUser? { nil }

    public func signInWithGoogle() async throws(AuthError) -> ZenUser {
        try? await Task.sleep(for: .milliseconds(900))
        return ZenMock.demoUser
    }

    public func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws(AuthError) -> ZenUser {
        guard !identityToken.isEmpty else { throw .cancelled }
        let name = fullName?.givenName ?? ZenMock.demoUser.displayName
        return ZenUser(uid: "demo-apple", displayName: name)
    }

    @MainActor public func handle(url: URL) -> Bool { false }

    public func newPairingCode() async throws(AuthError) -> PairingCode {
        PairingCode(code: JoinCode("K4M7QX")!, expiresAt: Date().addingTimeInterval(5 * 60))
    }

    public func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser {
        do { try await Task.sleep(for: approvalDelay) } catch { throw .cancelled }
        guard code.expiresAt > Date() else { throw .codeExpired }
        return ZenMock.demoUser
    }

    /// The phone's side: any well-formed code is approved after a short pause.
    public func approvePairing(code: JoinCode) async throws(AuthError) {
        do { try await Task.sleep(for: .milliseconds(400)) } catch { throw .cancelled }
    }

    /// Nothing to forget: the fake never keeps a session.
    public func signOut() async throws(AuthError) {}
}

public struct FakeCohorts: CohortService {
    public static let demo = CohortPreview(
        id: "demo-hostel-4", name: "Hostel 4", organisation: "IIT Madras", kind: .campus, memberCount: 23)

    public init() {}

    public func preview(code: JoinCode) async throws(CohortError) -> CohortPreview {
        try? await Task.sleep(for: .milliseconds(450))
        guard code == ZenMock.demoCohortCode else { throw .notFound }
        return Self.demo
    }

    public func join(code: JoinCode) async throws(CohortError) -> CohortSummary {
        let preview = try await preview(code: code)
        return CohortSummary(preview: preview, score: ZenScore(tenths: 74), goodDayRate: 0.62)
    }
}

/// A rotating set of schema-valid lines, one per feeling, so the notch has something to say offline.
public struct FakeNudges: ZenoNudgeService {
    public static let lines: [ZenoNudge] = [
        ZenoNudge(feeling: .happy, line: "Good day locked in. 8.1 and rising."),
        ZenoNudge(feeling: .pleasant, line: "Stretch? You've earned a slow minute."),
        ZenoNudge(feeling: .curious, line: "Back again. Something on purpose?", action: .startFocus),
        ZenoNudge(feeling: .happy, line: "3 of 4 good days. One more wins it.", action: .openReview),
    ]

    private let index: Int

    public init(index: Int = 0) { self.index = index }

    public func nudge(for context: NudgeContext) async throws -> ZenoNudge {
        try await Task.sleep(for: .milliseconds(350))
        return Self.lines[(context.hourOfDay + index) % Self.lines.count]
    }
}

/// The demo day, live: `updates()` streams it, and `simulateSecondDevice` adds another Mac so the
/// UI can show the combine at work (lowest score wins, as the real backend does).
public struct FakeScores: ScoreService {
    private let live = LiveDemo()

    public init() {}

    public func today() async throws -> ScoreSnapshot {
        try await Task.sleep(for: .milliseconds(300))
        return live.snapshot(now: Date())
    }

    /// The demo day now, then every simulated change.
    public func updates() -> AsyncStream<ScoreSnapshot> { live.stream(now: Date()) }

    /// Another of the person's computers publishes today: its line appears and the day's score
    /// becomes the lowest of the phone's and the computers' summed minutes. The default lands at 6.5.
    @discardableResult
    public func simulateSecondDevice(minutes: Int = 260, pullBacks: Int = 3) -> ScoreSnapshot {
        live.setSecond((max(minutes, 0), max(pullBacks, 0)), now: Date())
    }

    /// Back to the demo day.
    @discardableResult
    public func removeSecondDevice() -> ScoreSnapshot { live.setSecond(nil, now: Date()) }

    /// Monday 7.2 · Tuesday 5.8 · Wednesday 8.1 · Thursday 5.4 · today 8.1, so the week reads
    /// "3 of 4 good days · one more wins the week".
    public static func snapshot(now: Date) -> ScoreSnapshot {
        let today = ZenScore(tenths: phoneTenths)
        let week = WeekProgress(
            days: [ZenScore(tenths: 72), ZenScore(tenths: 58), ZenScore(tenths: 81), ZenScore(tenths: 54), today, nil, nil],
            todayIndex: 4, streakBefore: 9)
        let devices = [
            DeviceLine(id: "iphone", kind: .iPhone, name: "Kamal's iPhone", detail: "Counted on the phone", isThisDevice: false),
            DeviceLine(id: "mac", kind: .mac, name: "This Mac", detail: "38 m distracting · 4 pull-backs", isThisDevice: true),
        ]
        return ScoreSnapshot(score: today, week: week, devices: devices, updatedAt: now.addingTimeInterval(-4))
    }

    /// The demo's parts: the iPhone's own 8.1 and this Mac's 38 minutes and 4 pull-backs on a 4-hour promise.
    static let phoneTenths = 81
    static let macMinutes = 38
    static let macPullBacks = 4
    static let promiseMinutes = 240

    /// The demo day with a second Mac's minutes and pull-backs added to this one's.
    static func snapshot(now: Date, second: (minutes: Int, pullBacks: Int)?) -> ScoreSnapshot {
        let base = snapshot(now: now)
        guard let second else { return base }
        let computers = ZenScoreRule.score(minutes: macMinutes + second.minutes, pullBacks: macPullBacks + second.pullBacks,
                                           promiseMinutes: promiseMinutes)
        let score = min(ZenScore(tenths: phoneTenths), computers)
        var days = base.week.days
        days[4] = score
        let studio = DeviceContribution(kind: .computer, platform: .macos, deviceId: "studio-mac", counted: true,
                                        minutes: second.minutes, pullBacks: second.pullBacks)
        let line = DeviceLine(id: "studio-mac", kind: .mac, name: "Studio Mac",
                              detail: ScoreSnapshotBuilder.detail(studio), isThisDevice: false)
        return ScoreSnapshot(score: score, week: WeekProgress(days: days, todayIndex: 4, streakBefore: 9),
                             devices: base.devices + [line], updatedAt: now)
    }
}

/// FakeScores' shared state: copies of one FakeScores see the same simulated devices.
final class LiveDemo: @unchecked Sendable {
    private let lock = NSLock()
    private var second: (minutes: Int, pullBacks: Int)?
    private var continuations: [UUID: AsyncStream<ScoreSnapshot>.Continuation] = [:]

    func snapshot(now: Date) -> ScoreSnapshot {
        FakeScores.snapshot(now: now, second: lock.withLock { second })
    }

    func stream(now: Date) -> AsyncStream<ScoreSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScoreSnapshot.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) } }
        let current = lock.withLock { () -> ScoreSnapshot in
            continuations[id] = continuation
            return FakeScores.snapshot(now: now, second: second)
        }
        continuation.yield(current)
        return stream
    }

    func setSecond(_ value: (minutes: Int, pullBacks: Int)?, now: Date) -> ScoreSnapshot {
        let (current, targets) = lock.withLock { () -> (ScoreSnapshot, [AsyncStream<ScoreSnapshot>.Continuation]) in
            second = value
            return (FakeScores.snapshot(now: now, second: value), Array(continuations.values))
        }
        for continuation in targets { continuation.yield(current) }
        return current
    }

    var subscriberCount: Int { lock.withLock { continuations.count } }
}
