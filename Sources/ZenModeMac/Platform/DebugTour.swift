#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: renders the app's own windows to PNG, so screens can be checked and
/// shared without Screen Recording permission.
///   ZenModeMac --step seat --shot /tmp/seat   →   /tmp/seat.png and /tmp/seat-notch.png
/// Steps: story0 story1 story2 seat campus uses quiet count bring handoff today.
/// Liquid Glass is composited by the window server, so it renders flatter here than on screen.
@MainActor
enum DebugTour {
    static func runIfRequested(model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard let out = value(after: "--shot", in: args) else { return }
        let step = value(after: "--step", in: args) ?? "story0"
        apply(step, to: model)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(value(after: "--wait", in: args) ?? "3.2") ?? 3.2))
            for window in NSApp.windows where window.isVisible {
                let suffix = window is NotchPanel ? "-notch" : ""
                save(window, to: out + suffix + ".png")
            }
            NSApp.terminate(nil)
        }
    }

    private static func apply(_ step: String, to model: AppModel) {
        switch step {
        case "story1": model.initialStoryIndex = 1
        case "story2": model.initialStoryIndex = 2
        case "seat": model.stage = .onboarding(.seat)
        case "campus":
            model.stage = .onboarding(.seat)
            model.choose(seat: .campus)
            model.codeText = "ZEN4HS"
            model.checkCode()
        case "uses":
            model.stage = .onboarding(.uses)
            model.toggle(use: .study)
            model.toggle(use: .build)
        case "quiet":
            model.stage = .onboarding(.quiet)
            model.toggle(use: .study)
            model.choose(quiet: .classHours)
        case "count": model.go(.count)
        case "bring": model.go(.bring)
        case "handoff": model.simulateApproval()
        case "today": model.finishOnboarding()
        default: break
        }
    }

    private static func save(_ window: NSWindow, to path: String) {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
