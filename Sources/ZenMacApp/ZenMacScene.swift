import SwiftUI
import Albeit

/// The Mac app's one window. The app target (Xcode) and the `swift run` executable both host it:
///
///     @main struct ZenModeOSMacApp: App {
///         @NSApplicationDelegateAdaptor(ZenMacAppDelegate.self) private var delegate
///         var body: some Scene { ZenMacScene(delegate: delegate) }
///     }
public struct ZenMacScene: Scene {
    let delegate: ZenMacAppDelegate

    public init(delegate: ZenMacAppDelegate) { self.delegate = delegate }

    public var body: some Scene {
        Window(Copy.product, id: "main") {
            RootView()
                .environment(delegate.model)
                .frame(minWidth: 1040, minHeight: 680)
                // Google sign-in returns through the REVERSED_CLIENT_ID URL scheme.
                .onOpenURL { url in delegate.model.handle(url: url) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
    }
}

@MainActor
public final class ZenMacAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchPanelController?

    override public init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchPanelController(model: model.notch)
        model.start()
        #if DEBUG
        DebugTour.runIfRequested(model: model)
        #endif
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.stage {
            case .onboarding: OnboardingView()
            case .today: TodayView()
            }
        }
        .transition(.opacity)
        // Albeit's light is the designed ground; the ink (dark) pass comes with the night backdrop.
        .preferredColorScheme(.light)
    }
}
