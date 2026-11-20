import Foundation
import ZenAPI

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

    public func newPairingCode() async throws(AuthError) -> PairingCode {
        PairingCode(code: JoinCode("K4M7QX")!, expiresAt: Date().addingTimeInterval(5 * 60))
    }

    public func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser {
        do { try await Task.sleep(for: approvalDelay) } catch { throw .cancelled }
        guard code.expiresAt > Date() else { throw .codeExpired }
        return ZenMock.demoUser
    }
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

public struct FakeScores: ScoreService {
    public init() {}

    public func today() async throws -> ScoreSnapshot {
        try await Task.sleep(for: .milliseconds(300))
        return Self.snapshot(now: Date())
    }

    /// Monday 7.2 · Tuesday 5.8 · Wednesday 8.1 · Thursday 5.4 · today 8.1, so the week reads
    /// "3 of 4 good days · one more wins the week".
    public static func snapshot(now: Date) -> ScoreSnapshot {
        let today = ZenScore(tenths: 81)
        let week = WeekProgress(
            days: [ZenScore(tenths: 72), ZenScore(tenths: 58), ZenScore(tenths: 81), ZenScore(tenths: 54), today, nil, nil],
            todayIndex: 4, streakBefore: 9)
        let devices = [
            DeviceLine(id: "iphone", kind: .iPhone, name: "Kamal's iPhone", detail: "Counted on the phone", isThisDevice: false),
            DeviceLine(id: "mac", kind: .mac, name: "This Mac", detail: "38 m distracting · 4 pull-backs", isThisDevice: true),
        ]
        return ScoreSnapshot(score: today, week: week, devices: devices, updatedAt: now.addingTimeInterval(-4))
    }
}
