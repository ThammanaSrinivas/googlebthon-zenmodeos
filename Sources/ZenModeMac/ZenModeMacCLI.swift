import SwiftUI
import ZenMacApp

/// `swift run ZenModeMac` and scripts/build-mac-app.sh: the same app as the Xcode target, unsigned,
/// for fast local runs and the snapshot tour. Sign in with Apple needs the signed Xcode build.
@main
struct ZenModeMacCLI: App {
    @NSApplicationDelegateAdaptor(ZenMacAppDelegate.self) private var delegate
    var body: some Scene { ZenMacScene(delegate: delegate) }
}
