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

@Suite("Notch: important moments, their sound and their tap")
@MainActor
struct NotchImportantTests {
    private let plain = NotchModel.Moment(feeling: .pleasant, kicker: "Fake", line: "Fake line.")
    private var important: NotchModel.Moment { var m = plain; m.important = true; return m }

    @Test("An important moment stays about 20 seconds; a plain one keeps its own hold; open stays open")
    func holds() {
        #expect(NotchModel.hold(for: important, requested: .seconds(3)) == .seconds(20))
        #expect(NotchModel.hold(for: important, requested: .seconds(30)) == .seconds(30))
        #expect(NotchModel.hold(for: plain, requested: .seconds(3)) == .seconds(3))
        #expect(NotchModel.hold(for: important, requested: nil) == nil)
    }

    @Test("An important moment lights the rim while it's up, and it goes out on close")
    func attention() async {
        let n = NotchModel()
        n.reduceMotion = true
        n.speak(important, hold: nil, respectQuiet: false)
        #expect(await eventually { n.wordsIn })
        #expect(n.attention)
        n.hush()
        #expect(await eventually { !n.isOpen })
        #expect(!n.attention)
        n.speak(plain, hold: nil, respectQuiet: false)
        #expect(await eventually { n.wordsIn })
        #expect(!n.attention)
    }

    @Test("The sounds ease in from silence and ring out to silence, quietly")
    func sounds() {
        for samples in [NotchCues.chime(notes: [(783.99, 0), (1174.66, 0.11)], length: 1.3, decay: 0.42),
                        NotchCues.chime(notes: [(1046.5, 0), (698.46, 0.09)], length: 0.95, decay: 0.3, level: 0.7)] {
            #expect(!samples.isEmpty)
            #expect(abs(samples.first!) < 0.001 && abs(samples.last!) < 0.001)
            let peak = samples.map(abs).max()!
            #expect(peak <= 0.5 + 1e-6 && peak > 0.2)
            // Eased in: the first 5 ms stay well under the peak.
            #expect(samples.prefix(Int(0.005 * NotchCues.sampleRate)).map(abs).max()! < peak * 0.2)
        }
    }

    @Test("They're real WAV files AVAudioPlayer can open")
    func wav() {
        let data = NotchCues.arrival
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data.count == 44 + Int(1.3 * NotchCues.sampleRate) * 2)
    }

    @Test("Turned off, Zeno's sounds stay silent")
    func off() {
        let cues = NotchCues()
        let defaults = UserDefaults(suiteName: "zen.test.cues.\(UUID().uuidString)")!
        cues.defaults = defaults
        defaults.set(false, forKey: NotchCues.soundsKey)
        #expect(!cues.soundsOn)
    }
}
