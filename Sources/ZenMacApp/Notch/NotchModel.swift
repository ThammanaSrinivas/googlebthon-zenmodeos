import SwiftUI
import Albeit
import ZenAPI

/// What Zeno is saying in the notch, and the order things happen in when it speaks:
/// the shape opens, Zeno drops in, the words arrive; leaving runs in reverse.
@MainActor
@Observable
final class NotchModel {
    struct Moment: Equatable {
        var feeling: ZenoFeeling
        var kicker: String
        var line: String
        var detail: String?
    }

    private(set) var moment = Moment(feeling: .calm, kicker: "", line: "")
    private(set) var isOpen = false
    private(set) var zenoIn = false
    private(set) var wordsIn = false
    private(set) var replay = 0
    /// The pointer is over the open shape: it fades so the screen under it shows, and clicks go
    /// through to it (the panel never takes a click).
    var pointerOver = false
    #if DEBUG
    /// Debug tours: render the shape as if the pointer were over it.
    var debugHover = false
    #endif

    /// Class or work hours plus the night. Outside onboarding, Zeno says nothing inside them.
    var quiet: QuietHours = .none
    /// A busy event on a connected calendar: Zeno stays quiet then too (set by the calendar section).
    var isBusy: @MainActor (Date) -> Bool = { _ in false }
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var task: Task<Void, Never>?

    /// Zeno speaks. `hold: nil` keeps the line up until the next one.
    /// Returns false when quiet hours kept Zeno silent.
    @discardableResult
    func speak(_ next: Moment, hold: Duration? = .seconds(4), respectQuiet: Bool = true) -> Bool {
        let now = Date()
        if respectQuiet && (quiet.isQuiet(at: now, calendar: .current) || isBusy(now)) { return false }
        task?.cancel()
        task = Task { [weak self] in await self?.run(next, hold: hold) }
        return true
    }

    func speak(_ nudge: ZenoNudge, kicker: String, hold: Duration? = .seconds(5)) {
        speak(Moment(feeling: Self.feeling(for: nudge.notchFeeling), kicker: kicker, line: nudge.line), hold: hold)
    }

    func hush() {
        task?.cancel()
        task = Task { [weak self] in await self?.close() }
    }

    private func run(_ next: Moment, hold: Duration?) async {
        if reduceMotion {
            moment = next
            isOpen = true; zenoIn = true; wordsIn = true
            replay += 1
        } else {
            if isOpen {
                wordsIn = false
                guard await pause(.milliseconds(240)) else { return }
            }
            moment = next
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isOpen = true }
            guard await pause(.milliseconds(60)) else { return }
            let style = next.feeling
            withAnimation(.spring(response: style == .sad || style == .sleepy ? 0.8 : 0.4, dampingFraction: 0.62)) { zenoIn = true }
            replay += 1
            guard await pause(.milliseconds(460)) else { return }
            wordsIn = true
        }
        guard let hold, await pause(hold) else { return }
        await close()
    }

    private func close() async {
        wordsIn = false
        guard await pause(.milliseconds(reduceMotion ? 0 : 160)) else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.94)) { zenoIn = false }
        guard await pause(.milliseconds(reduceMotion ? 0 : 300)) else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.94)) { isOpen = false }
    }

    private func pause(_ d: Duration) async -> Bool {
        try? await Task.sleep(for: d)
        return !Task.isCancelled
    }

    static func feeling(for f: ZenoNudge.Feeling) -> ZenoFeeling {
        switch f {
        case .happy: .happy
        case .pleasant: .pleasant
        case .curious: .curious
        case .sad: .pleasant
        }
    }
}
