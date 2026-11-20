#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: renders the app's own windows to PNG, so screens can be checked and
/// shared without Screen Recording permission.
///   ZenModeMac --step seat --shot /tmp/seat   →   /tmp/seat.png and /tmp/seat-notch.png
/// Steps: story0 story1 story2 seat campus uses quiet count bring handoff today, and on Today:
/// today-yesterday (the day picker), today-card (a pattern card open), today-search, notch-hover, notch-important.
/// Liquid Glass is composited by the window server, so it renders flatter here than on screen.
@MainActor
enum DebugTour {
    static func runIfRequested(model: AppModel) {
        let args = ProcessInfo.processInfo.arguments
        guard let out = value(after: "--shot", in: args) else { return }
        let step = value(after: "--step", in: args) ?? "story0"
        apply(step, to: model)
        // --export <dir> writes the two share pictures (Today, the first pattern card) and quits.
        if let dir = value(after: "--export", in: args) {
            let dash = model.dashboard
            let week = FakeSnapshot.value.week
            if let png = ImageExport.png(TodayShareImage(score: dash.days[0].score, week: week, date: Date())) {
                try? png.write(to: URL(fileURLWithPath: dir + "/share-today.png"))
            }
            for card in dash.cards.prefix(3) {
                if let png = ImageExport.png(PatternShareImage(card: card, rank: dash.rank(of: card))) {
                    try? png.write(to: URL(fileURLWithPath: dir + "/share-\(card.id).png"))
                }
            }
        }
        Task { @MainActor in
            // --size 1360x1300 renders a taller window, to see a whole scrolling screen at once.
            if let size = value(after: "--size", in: args)?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                try? await Task.sleep(for: .milliseconds(300))
                for window in NSApp.windows where !(window is NotchPanel) && window.isVisible {
                    window.setContentSize(CGSize(width: size[0], height: size[1]))
                }
            }
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
        case "today-yesterday":
            model.finishOnboarding()
            model.dashboard.dayIndex = 1
        case "today-card":
            model.finishOnboarding()
            if let card = model.dashboard.cards.dropFirst(Int(value(after: "--card", in: ProcessInfo.processInfo.arguments) ?? "0") ?? 0).first {
                model.dashboard.open(card)
            }
        case "today-search":
            model.finishOnboarding()
            model.dashboard.query = value(after: "--query", in: ProcessInfo.processInfo.arguments) ?? "x"
        case "notch-hover":
            model.finishOnboarding()
            model.notch.debugHover = true
        case "notch-important":
            // An important moment held open, silent (no chime in a snapshot).
            model.finishOnboarding()
            model.notch.cues = nil
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                model.notch.speak(.init(feeling: .happy, kicker: "Focus Mode", line: "Block kept. Let's see what came in.",
                                        detail: "3 messages came in while you were away.", important: true),
                                  hold: nil, respectQuiet: false)
            }
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
