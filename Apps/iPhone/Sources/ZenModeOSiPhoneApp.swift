import Foundation
import SwiftUI
import ZenAPI
import ZenMock
import ZenPhoneApp
#if canImport(ZenCorePrivate)
    import ZenCorePrivate
#endif

/// The iPhone app. Everything lives in the ZenPhoneApp library; this file picks the backend: the
/// private package when it's present and configured, the fakes otherwise.
@main
struct ZenModeOSiPhoneApp: App {
    init() {
        ZenPhoneBackend.make = Self.backend
        ZenPhoneBackend.focusActivity = { FocusActivityController() }
    }

    var body: some Scene {
        WindowGroup { ZenPhoneRoot() }
    }

    @MainActor
    static func backend() -> PhoneServices {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ZEN_DEMO_FOCUS"] != nil { return demoFocus() }
        #endif
        #if canImport(ZenCorePrivate)
        if ProcessInfo.processInfo.environment["ZEN_USE_MOCK"] == nil, ZenCorePrivate.hasFirebaseConfig {
            let live = ZenCorePrivate.services()
            return PhoneServices(auth: live.auth, scores: live.scores, days: live.days,
                                 voiceTokens: live.voiceTokens, cards: live.cards, focus: live.focus, isDemo: false)
        }
        #endif
        return .fakes()
    }

    #if DEBUG
    /// ZEN_DEMO_FOCUS=1 (debug builds): the fakes, already signed in, with the Mac focusing for the
    /// next 50 minutes, so the line, the Lock Screen and the Island can be seen without a Mac.
    @MainActor
    private static func demoFocus() -> PhoneServices {
        let focus = FakeFocusSync()
        Task { try? await focus.setLive(LiveFocus(active: true, until: Date().addingTimeInterval(50 * 60))) }
        let fakes = PhoneServices.fakes(focus: focus)
        return PhoneServices(auth: SignedInDemoAuth(), scores: fakes.scores, days: fakes.days,
                             voiceTokens: fakes.voiceTokens, cards: fakes.cards, focus: focus, isDemo: true)
    }
    #endif
}

#if DEBUG
/// The fake sign-in, with the demo person already remembered.
private struct SignedInDemoAuth: AuthService {
    private let fake = FakeAuth()

    func currentUser() async -> ZenUser? { ZenMock.demoUser }
    func signInWithGoogle() async throws(AuthError) -> ZenUser { try await fake.signInWithGoogle() }
    func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws(AuthError) -> ZenUser {
        try await fake.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, fullName: fullName)
    }
    @MainActor func handle(url: URL) -> Bool { fake.handle(url: url) }
    func newPairingCode() async throws(AuthError) -> PairingCode { try await fake.newPairingCode() }
    func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser { try await fake.waitForApproval(of: code) }
    func approvePairing(code: JoinCode) async throws(AuthError) { try await fake.approvePairing(code: code) }
    func signOut() async throws(AuthError) { try await fake.signOut() }
}
#endif
