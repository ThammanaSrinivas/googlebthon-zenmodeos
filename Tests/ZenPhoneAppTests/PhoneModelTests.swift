import AuthenticationServices
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenPhoneApp

/// Waits (up to `timeout`) for `condition`, checking every millisecond.
@MainActor
private func eventually(_ timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

/// An auth service that answers at once, or fails the way it's told to.
private struct ScriptedAuth: AuthService {
    var signedIn: ZenUser?
    var googleError: AuthError?
    var approveError: AuthError?

    func currentUser() async -> ZenUser? { signedIn }

    func signInWithGoogle() async throws(AuthError) -> ZenUser {
        if let googleError { throw googleError }
        return ZenUser(uid: "fake-google-uid", displayName: "Fake Person")
    }

    func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws(AuthError) -> ZenUser {
        ZenUser(uid: "fake-apple-uid", displayName: "Fake")
    }

    @MainActor func handle(url: URL) -> Bool { false }

    func newPairingCode() async throws(AuthError) -> PairingCode {
        PairingCode(code: JoinCode("K4M7QX")!, expiresAt: .distantFuture)
    }

    func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser { throw .cancelled }

    func approvePairing(code: JoinCode) async throws(AuthError) {
        if let approveError { throw approveError }
    }
}

/// Records every day the phone sends.
private final class RecordingDays: DaySyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var _phone: [PhoneDayReport] = []
    private var _computer: [ComputerDayReport] = []
    var phone: [PhoneDayReport] { lock.withLock { _phone } }
    var computer: [ComputerDayReport] { lock.withLock { _computer } }

    func publish(phone: PhoneDayReport) async throws(SyncError) { lock.withLock { _phone.append(phone) } }
    func publish(computer: ComputerDayReport) async throws(SyncError) { lock.withLock { _computer.append(computer) } }
}

@MainActor
private func phone(_ auth: ScriptedAuth = ScriptedAuth(), days: RecordingDays = RecordingDays()) -> PhoneModel {
    PhoneModel(services: PhoneServices(auth: auth, scores: FakeScores(), days: days, voiceTokens: FakeVoiceTokens(),
                                       cards: FakeZenCards(), isDemo: true))
}

@Suite("iPhone: signing in")
@MainActor
struct PhoneSignInTests {
    @Test("The default backend is the fakes")
    func fakes() {
        #expect(PhoneServices.fakes().isDemo)
        #expect(ZenPhoneBackend.make().isDemo)
    }

    @Test("Starts signed out; a remembered account signs straight in and follows the score")
    func remembered() async {
        let m = phone(ScriptedAuth(signedIn: ZenUser(uid: "fake-uid", displayName: "Fake Person")))
        #expect(m.user == nil && m.snapshot == nil && !m.signingIn)
        m.start()
        #expect(await eventually { m.user != nil })
        #expect(m.user?.firstName == "Fake")
        #expect(await eventually { m.snapshot != nil })
        #expect(m.snapshot?.score.tenths == 81)
    }

    @Test("Nobody remembered: it stays signed out")
    func notRemembered() async {
        let m = phone()
        m.start()
        for _ in 0..<50 { await Task.yield() }
        #expect(m.user == nil)
    }

    @Test("Google: signing in, then signed in with the live score")
    func google() async {
        let m = phone()
        m.signInWithGoogle()
        #expect(m.signingIn)
        #expect(await eventually { !m.signingIn })
        #expect(m.user?.uid == "fake-google-uid" && m.signInError == nil)
        #expect(await eventually { m.snapshot?.score.tenths == 81 })
    }

    @Test("A cancelled Google sign-in shows no error; any other failure does")
    func googleFailures() async {
        let cancelled = phone(ScriptedAuth(googleError: .cancelled))
        cancelled.signInWithGoogle()
        #expect(await eventually { !cancelled.signingIn })
        #expect(cancelled.user == nil && cancelled.signInError == nil)

        let offline = phone(ScriptedAuth(googleError: .offline))
        offline.signInWithGoogle()
        #expect(await eventually { !offline.signingIn })
        #expect(offline.user == nil && offline.signInError == PhoneCopy.signInFailed)
    }

    @Test("Apple's sheet failing shows the error and signs nobody in")
    func appleFailure() {
        let m = phone()
        m.finishApple(.failure(URLError(.cancelled)))
        #expect(m.signInError == PhoneCopy.signInFailed)
        #expect(m.user == nil && !m.signingIn)
    }

    @Test("Each Apple request gets a fresh nonce hash")
    func nonce() {
        let m = phone()
        let a = m.prepareAppleRequest(), b = m.prepareAppleRequest()
        #expect(a != b)
        #expect(a.count == 64 && a.allSatisfy { $0.isHexDigit })
    }

    @Test("Signing out forgets the person and the score")
    func signOut() async {
        let m = phone()
        m.signInWithGoogle()
        #expect(await eventually { m.snapshot != nil })
        m.signOut()
        #expect(await eventually { m.user == nil && m.snapshot == nil })
    }
}

@Suite("iPhone: the score leaves as a score, never minutes")
@MainActor
struct PhonePublishTests {
    @Test("Until Screen Time measures the day, the phone publishes nothing")
    func nothingMeasured() async {
        let days = RecordingDays()
        let m = phone(days: days)
        m.signInWithGoogle()
        #expect(await eventually { m.user != nil })
        await m.publishToday()
        #expect(days.phone.isEmpty && days.computer.isEmpty)
    }

    @Test("Signed out, it publishes nothing")
    func signedOut() async {
        let days = RecordingDays()
        await phone(days: days).publishToday()
        #expect(days.phone.isEmpty)
    }

    @Test("An iPhone's report can't carry minutes, even when handed some")
    func scoreOnly() throws {
        let r = PhoneDayReport(platform: .ios, day: "2026-11-20", score: ZenScore(tenths: 81), minutes: 240)
        #expect(r.minutes == nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any]
        #expect(json?["minutes"] == nil)
        #expect(PhoneDayReport(platform: .ipados, day: "2026-11-20", score: ZenScore(tenths: 81), minutes: 5).minutes == nil)
    }
}

@Suite("iPhone: approving a Mac")
@MainActor
struct PhonePairingTests {
    @Test("A pairing link asks first, never approves silently")
    func link() {
        let m = phone()
        m.handle(url: URL(string: "https://zenmodeos.com/pair/k4m7qx")!)
        #expect(m.pairing == .confirm(JoinCode("K4M7QX")!))
    }

    @Test("Other links and broken codes are ignored", arguments: [
        "https://zenmodeos.com/pair/K4M", "https://zenmodeos.com/join/K4M7QX", "https://zenmodeos.com/", "https://zenmodeos.com/pair",
    ])
    func ignored(_ link: String) {
        let m = phone()
        m.handle(url: URL(string: link)!)
        #expect(m.pairing == .idle)
    }

    @Test("Typed codes are cleaned as they're typed, and checked before asking")
    func typed() {
        let m = phone()
        m.codeText = "k4m-7qx!"
        #expect(m.codeText == "K4M7QX")
        m.reviewCode()
        #expect(m.pairing == .confirm(JoinCode("K4M7QX")!))
        m.codeText = "K4M"
        m.reviewCode()
        #expect(m.pairing == .failed(PhoneCopy.badCode))
        m.cancelPairing()
        #expect(m.pairing == .idle)
    }

    @Test("Approving: approving, then approved, and the typed code is cleared")
    func approve() async {
        let m = phone()
        m.codeText = "K4M7QX"
        m.approve(JoinCode("K4M7QX")!)
        #expect(m.pairing == .approving)
        #expect(await eventually { m.pairing == .approved })
        #expect(m.codeText.isEmpty)
    }

    @Test("An expired code and other failures read differently", arguments: [
        (AuthError.codeExpired, PhoneCopy.codeChanged), (.offline, PhoneCopy.pairFailed), (.unavailable, PhoneCopy.pairFailed),
    ])
    func approveFails(error: AuthError, message: String) async {
        let m = phone(ScriptedAuth(approveError: error))
        m.codeText = "K4M7QX"
        m.approve(JoinCode("K4M7QX")!)
        #expect(await eventually { m.pairing == .failed(message) })
        #expect(m.codeText == "K4M7QX")
    }

    @Test("The fake auth approves any well-formed code")
    func fakeApproves() async {
        let m = PhoneModel(services: .fakes())
        m.approve(JoinCode("K4M7QX")!)
        #expect(await eventually { m.pairing == .approved })
    }
}
