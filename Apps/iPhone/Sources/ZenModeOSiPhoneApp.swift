import Foundation
import SwiftUI
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
    }

    var body: some Scene {
        WindowGroup { ZenPhoneRoot() }
    }

    @MainActor
    static func backend() -> PhoneServices {
        #if canImport(ZenCorePrivate)
        if ProcessInfo.processInfo.environment["ZEN_USE_MOCK"] == nil, ZenCorePrivate.hasFirebaseConfig {
            let live = ZenCorePrivate.services()
            return PhoneServices(auth: live.auth, scores: live.scores, days: live.days,
                                 voiceTokens: live.voiceTokens, cards: live.cards, focus: live.focus, isDemo: false)
        }
        #endif
        return .fakes()
    }
}
