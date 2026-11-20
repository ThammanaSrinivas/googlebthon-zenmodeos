import SwiftUI
import ZenMacApp

/// The signed Mac app (Sign in with Apple, Keychain, the Google URL scheme). Everything else lives
/// in the ZenMacApp library, shared with `swift run ZenModeMac`.
@main
struct ZenModeOSMacApp: App {
    @NSApplicationDelegateAdaptor(ZenMacAppDelegate.self) private var delegate
    var body: some Scene { ZenMacScene(delegate: delegate) }
}
