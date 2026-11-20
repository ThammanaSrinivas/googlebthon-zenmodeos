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
        .defaultSize(width: 1360, height: 880)
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
        // Every system control (switches, pickers, sliders, progress) in the brand green, not the
        // Mac's accent colour, so a switch that's on reads as on in light and dark.
        .tint(Color.zen.brandFill)
        .preferredColorScheme(scheme)
    }

    /// Paper, ink, or whatever the Mac is set to. ZEN_APPEARANCE=dark|light forces one (debug renders).
    private var scheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["ZEN_APPEARANCE"] {
        case "dark": return .dark
        case "light": return .light
        default: break
        }
        #endif
        switch model.preferences.values.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
