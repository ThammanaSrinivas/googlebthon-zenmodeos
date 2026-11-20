import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenMacApp

/// An AuthService that counts pairing calls and otherwise does nothing.
final class RecordingAuth: AuthService, @unchecked Sendable {
    private let lock = NSLock()
    private var _codes = 0
    var codesAsked: Int { lock.withLock { _codes } }

    func currentUser() async -> ZenUser? { nil }
    func signInWithGoogle() async throws(AuthError) -> ZenUser { throw .unavailable }
    func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws(AuthError) -> ZenUser {
        throw .unavailable
    }
    @MainActor func handle(url: URL) -> Bool { false }
    func newPairingCode() async throws(AuthError) -> PairingCode {
        lock.withLock { _codes += 1 }
        return try await FakeAuth().newPairingCode()
    }
    func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser {
        try? await Task.sleep(for: .seconds(60))
        throw .unavailable
    }
}

@MainActor
@Suite("Bring your day: the QR pairing switch")
struct QRPairingSwitchTests {
    private func model(_ auth: RecordingAuth, qr: Bool) -> AppModel {
        let m = AppModel(defaults: scratchDefaults())
        m.notch.reduceMotion = true
        let fakes = Services.fakes()
        m.use(Services(auth: auth, nudges: FakeNudges(), cohorts: fakes.cohorts, scores: fakes.scores, days: fakes.days,
                       voiceTokens: fakes.voiceTokens, cards: fakes.cards, isDemo: true))
        m.qrPairing = qr
        return m
    }

    @Test("The demo build ships with the QR pairing off")
    func offByDefault() {
        #expect(AppModel.qrPairingEnabled == false)
        #expect(AppModel(defaults: scratchDefaults()).qrPairing == false)
    }

    @Test("Off: entering the step never asks for a pairing code, and none appears")
    func off() async {
        let auth = RecordingAuth()
        let m = model(auth, qr: false)
        m.go(.bring)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(auth.codesAsked == 0)
        #expect(m.pairing == nil)
        #expect(m.step == .bring)
    }

    @Test("On: the old behaviour, one code asked for and shown")
    func on() async {
        let auth = RecordingAuth()
        let m = model(auth, qr: true)
        m.go(.bring)
        #expect(await eventually { m.pairing != nil })
        #expect(auth.codesAsked == 1)
    }

    @Test("Off, the copy never says scan")
    func copy() {
        #expect(!Copy.Bring.signInBody.lowercased().contains("scan"))
        #expect(!Copy.Bring.appleFailedNoCode.lowercased().contains("scan"))
        #expect(!Copy.Bring.signInCard.lowercased().contains("scan"))
    }
}
