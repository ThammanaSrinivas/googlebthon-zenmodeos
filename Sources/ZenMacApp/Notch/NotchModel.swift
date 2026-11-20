import SwiftUI
import Albeit
import ZenAPI

/// What Zeno is saying in the notch, and the order things happen in when it speaks:
/// the shape pours out of the notch, Zeno drops in, the words arrive; leaving runs in reverse.
/// A moment marked `important` stays about 20 seconds and arrives with a soft chime and a tap on
/// the trackpad (`NotchCues`); everything else passes in a few seconds, silently.
@MainActor
@Observable
final class NotchModel {
    struct Moment: Equatable {
        var feeling: ZenoFeeling
        var kicker: String
        var line: String
        var detail: String?
        /// Worth a beat of attention: held about 20 s, with a sound and a tap as it arrives.
        var important = false
    }

    /// How long an important moment stays up.
    static let importantHold: Duration = .seconds(20)
    /// The shape pours out with a little give, and tucks back without any.
    static let pour = Animation.spring(response: 0.52, dampingFraction: 0.78)
    static let tuck = Animation.spring(response: 0.42, dampingFraction: 1)

    private(set) var moment = Moment(feeling: .calm, kicker: "", line: "")
    private(set) var isOpen = false
    private(set) var zenoIn = false
    private(set) var wordsIn = false
    private(set) var replay = 0
    /// An important moment is up: the shape wears a lit rim in the feeling's colour.
    private(set) var attention = false
    /// The sound and the tap (set by the app; nil in tests, so they're silent).
    var cues: NotchCues?
    /// In a chat, Zeno is hearing you: your loudness (0…1). Nil when Zeno isn't listening.
    var hearing: Double?
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
        if respectQuiet && (isBusy(now) || quiet.isQuiet(at: now, calendar: .current)) { return false }
        task?.cancel()
        let hold = Self.hold(for: next, requested: hold)
        task = Task { [weak self] in await self?.run(next, hold: hold) }
        return true
    }

    /// An important moment stays at least `importantHold`; one held open (`nil`) stays open.
    static func hold(for moment: Moment, requested: Duration?) -> Duration? {
        guard let requested else { return nil }
        return moment.important ? max(requested, importantHold) : requested
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
            attention = next.important
            isOpen = true; zenoIn = true; wordsIn = true
            replay += 1
            if next.important { cues?.arrive() }
        } else {
            if isOpen {
                wordsIn = false
                guard await pause(.milliseconds(240)) else { return }
            }
            moment = next
            if next.important { cues?.arrive() }
            withAnimation(Self.pour) {
                isOpen = true
                attention = next.important
            }
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
        if isOpen && attention { cues?.leave() }
        wordsIn = false
        guard await pause(.milliseconds(reduceMotion ? 0 : 160)) else { return }
        withAnimation(Self.tuck) { zenoIn = false }
        guard await pause(.milliseconds(reduceMotion ? 0 : 300)) else { return }
        withAnimation(Self.tuck) {
            isOpen = false
            attention = false
        }
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
