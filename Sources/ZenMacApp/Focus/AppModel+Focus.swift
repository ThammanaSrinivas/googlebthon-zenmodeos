import Foundation
import Albeit
import ZenAPI
import ZenFocus

extension AppModel {
    /// Wires Focus Mode to the backend and Zeno, and ends a block a crash left behind.
    func startFocusMode() {
        let svc = services
        focus.onStarted = { [weak self] block in
            self?.notch.speak(.init(feeling: .pleasant, kicker: "Focus Mode", line: "Focusing until \(FocusClock.text(block.until)). I'll keep watch."),
                              hold: .seconds(3), respectQuiet: false)
        }
        focus.onEnded = { [weak self] ended in
            self?.focusEnded(ended)
        }
        focus.configure(sync: { svc.focus })
    }

    func startFocus(minutes: Int, source: FocusSource = .manual) {
        focus.start(minutes: minutes, source: source)
    }

    func startFocus(until: Date, source: FocusSource = .manual) {
        focus.start(until: until, source: source)
    }

    /// A block ended: Zeno says so, then the catch-up runs.
    func focusEnded(_ ended: FocusEnded) {
        let line = ended.record.kept ? "Block kept. Let's see what came in." : "Focus ended. Everything's back on."
        notch.speak(.init(feeling: ended.record.kept ? .happy : .pleasant, kicker: "Focus Mode", line: line),
                    hold: .seconds(3), respectQuiet: false)
    }
}
