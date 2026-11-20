import Foundation
import Albeit
import ZenAPI
import ZenFocus

extension AppModel {
    /// Wires Focus Mode to the backend and Zeno, and ends a block a crash left behind.
    func startFocusMode() {
        let svc = services
        focus.onStarted = { [weak self] block in
            #if DEBUG
            focusLog("[focus] start until=\(FocusClock.text(block.until)) " + (self?.focus.chips ?? []).map { "\($0.id)=\($0.state.rawValue)" + ($0.note.map { "(\($0))" } ?? "") }.joined(separator: " "))
            #endif
            self?.notch.speak(.init(feeling: .pleasant, kicker: "Focus Mode", line: "Focusing until \(FocusClock.text(block.until)). I'll keep watch."),
                              hold: .seconds(3), respectQuiet: false)
        }
        focus.onEnded = { [weak self] ended in
            #if DEBUG
            focusLog("[focus] end kept=\(ended.record.kept) min=\(ended.record.focusedMin) " + ended.endOutcomes.map { "\($0.id)=\($0.state.rawValue)" + ($0.note.map { "(\($0))" } ?? "") }.joined(separator: " ")
                  + " daily=\(ended.day):\(ended.daily.focusMin)/\(ended.daily.blocksKept)of\(ended.daily.blocksStarted)")
            #endif
            self?.focusEnded(ended)
        }
        focus.configure(sync: { svc.focus })
        afterHours.onWorkEnded = { [weak self] in self?.workDayEnded() }
        afterHours.start(focus: focus, sync: { svc.focus })
        #if DEBUG
        // Functional tests: ZEN_FOCUS_MINUTES=1 starts a block at launch; ZEN_FOCUS_END_AFTER=20 ends
        // it early after that many seconds.
        let env = ProcessInfo.processInfo.environment
        // ZEN_WEBHOOK_URL + ZEN_WEBHOOK_SECRET point the webhook at a local receiver
        // (scripts/webhook-receiver.mjs); the app saves the secret in its own Keychain item.
        if let url = env["ZEN_WEBHOOK_URL"], let secret = env["ZEN_WEBHOOK_SECRET"] {
            focus.settings.set(FocusSettings.webhookURLKey, url)
            FocusSecrets.shared.set(secret, FocusSecrets.webhookSecret)
        }
        if let m = env["ZEN_FOCUS_MINUTES"].flatMap(Int.init) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.focus.start(until: Date().addingTimeInterval(TimeInterval(m * 60)), source: .manual)
                if let s = env["ZEN_FOCUS_END_AFTER"].flatMap(Double.init) {
                    try? await Task.sleep(for: .seconds(s))
                    self?.focus.end()
                }
            }
        }
        #endif
    }

    func startFocus(minutes: Int, source: FocusSource = .manual) {
        focus.start(minutes: minutes, source: source)
    }

    func startFocus(until: Date, source: FocusSource = .manual) {
        focus.start(until: until, source: source)
    }

    /// A block ended: Zeno says so, then the catch-up reads what came in (on this Mac).
    func focusEnded(_ ended: FocusEnded) {
        let line = ended.record.kept ? "Block kept. Let's see what came in." : "Focus ended. Everything's back on."
        notch.speak(.init(feeling: ended.record.kept ? .happy : .pleasant, kicker: "Focus Mode", line: line),
                    hold: .seconds(3), respectQuiet: false)
        Task {
            await catchUp.focusEnded(since: ended.record.session.startAt)
            if case .waiting(let n) = catchUp.state {
                notch.speak(.init(feeling: .curious, kicker: "What did I miss?", line: n == 1 ? "1 message came in." : "\(n) messages came in."),
                            hold: .seconds(3), respectQuiet: false)
            }
        }
    }

    /// The end of work hours: Zeno nudges a wrap-up.
    func workDayEnded() {
        notch.speak(.init(feeling: .sleepy, kicker: "Work's done", line: "Wrap up, then log off."), hold: .seconds(3.4), respectQuiet: false)
        wrapUpOffered = true
    }
}

#if DEBUG
/// Functional tests read these lines on stderr (unbuffered).
func focusLog(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
#endif
