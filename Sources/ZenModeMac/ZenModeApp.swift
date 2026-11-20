import SwiftUI
import Albeit

@main
struct ZenModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(Copy.product, id: "main") {
            RootView()
                .environment(delegate.model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchPanelController(model: model.notch)
        model.start()
        #if DEBUG
        DebugTour.runIfRequested(model: model)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
