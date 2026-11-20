import Foundation
import Testing
import Albeit
import ZenAPI
@testable import ZenMacApp

/// Quiet every minute of every day: the night plus a block covering the whole day, all week.
let alwaysQuiet = QuietHours(weekdays: Set(1...7), start: 0, end: 24 * 60)

@Suite("Notch: what Zeno says, and when")
@MainActor
struct NotchModelTests {
    private let hello = NotchModel.Moment(feeling: .happy, kicker: "Fake kicker", line: "Fake line.")

    private func notch(reduceMotion: Bool = true) -> NotchModel {
        let n = NotchModel()
        n.reduceMotion = reduceMotion
        return n
    }

    @Test("It starts closed and silent")
    func closed() {
        let n = notch()
        #expect(!n.isOpen && !n.zenoIn && !n.wordsIn && n.replay == 0)
        #expect(n.moment.line.isEmpty)
    }

    @Test("Speaking opens the shape, brings Zeno in, then the words; no hold keeps it up")
    func speaks() async {
        let n = notch()
        #expect(n.speak(hello, hold: nil, respectQuiet: false))
        #expect(await eventually { n.wordsIn })
        #expect(n.isOpen && n.zenoIn && n.moment == hello && n.replay == 1)
    }

    @Test("With motion, the order is the shape, Zeno, then the words")
    func order() async {
        let n = notch(reduceMotion: false)
        n.speak(hello, hold: nil, respectQuiet: false)
        #expect(await eventually { n.isOpen })
        #expect(!n.wordsIn)
        #expect(await eventually { n.wordsIn })
        #expect(n.isOpen && n.zenoIn)
    }

    @Test("A held line closes on its own, in reverse")
    func holdCloses() async {
        let n = notch()
        n.speak(hello, hold: .milliseconds(5), respectQuiet: false)
        #expect(await eventually { n.replay == 1 })
        #expect(await eventually { !n.isOpen })
        #expect(!n.zenoIn && !n.wordsIn)
        #expect(n.moment == hello) // the last line stays for the next open
    }

    @Test("Hush closes it")
    func hush() async {
        let n = notch()
        n.speak(hello, hold: nil, respectQuiet: false)
        #expect(await eventually { n.wordsIn })
        n.hush()
        #expect(await eventually { !n.isOpen && !n.zenoIn && !n.wordsIn })
    }

    @Test("Quiet hours keep Zeno silent, unless onboarding asks")
    func quiet() async {
        let n = notch()
        n.quiet = alwaysQuiet
        #expect(!n.speak(hello, hold: nil))
        #expect(!n.isOpen && n.moment.line.isEmpty)
        #expect(n.speak(hello, hold: nil, respectQuiet: false))
        #expect(await eventually { n.wordsIn })
    }

    @Test("A busy calendar event keeps Zeno silent too")
    func busy() {
        let n = notch()
        var asked: Date?
        n.isBusy = { asked = $0; return true }
        #expect(!n.speak(hello, hold: nil))
        #expect(asked != nil)
    }

    @Test("The next line replaces the last")
    func replaces() async {
        let n = notch()
        let next = NotchModel.Moment(feeling: .sleepy, kicker: "Fake", line: "Second line.")
        n.speak(hello, hold: nil, respectQuiet: false)
        #expect(await eventually { n.wordsIn })
        n.speak(next, hold: nil, respectQuiet: false)
        #expect(await eventually { n.moment == next })
        #expect(n.replay == 2)
    }

    @Test("Gemini's four feelings map onto Zeno's, sad never shown as sad")
    func feelings() {
        #expect(NotchModel.feeling(for: .happy) == .happy)
        #expect(NotchModel.feeling(for: .pleasant) == .pleasant)
        #expect(NotchModel.feeling(for: .curious) == .curious)
        #expect(NotchModel.feeling(for: .sad) == .pleasant)
        #expect(ZenoNudge(feeling: .sad, line: "Fake").notchFeeling == .pleasant)
    }
}
