import Foundation
import SwiftUI
import ZenAPI
import ZenMacApp
#if canImport(ZenCorePrivate)
    import ZenCorePrivate
#endif

/// The signed Mac app (Sign in with Apple, Keychain, the Google URL scheme). Everything else lives
/// in the ZenMacApp library, shared with `swift run ZenModeMac`. This file is the one place that
/// picks the backend: the private package when it's present and configured, the fakes otherwise.
@main
struct ZenModeOSMacApp: App {
    @NSApplicationDelegateAdaptor(ZenMacAppDelegate.self) private var delegate

    init() {
        ZenMacBackend.make = Self.backend
    }

    var body: some Scene { ZenMacScene(delegate: delegate) }

    @MainActor
    static func backend() -> Services {
        #if canImport(ZenCorePrivate)
        if ProcessInfo.processInfo.environment["ZEN_USE_MOCK"] == nil, ZenCorePrivate.hasFirebaseConfig {
            let live = ZenCorePrivate.services()
            TeamWeb.base = ZenCorePrivate.webBase
            return Services(auth: live.auth, nudges: live.nudges, cohorts: live.cohorts,
                            scores: live.scores, days: live.days,
                            voiceTokens: live.voiceTokens, cards: live.cards,
                            focus: live.focus, work: live.work, team: live.team, admin: live.admin, isDemo: false)
        }
        #endif
        return .fakes()
    }
}
