import Foundation
import Testing
import Albeit
import ZenAPI
import ZenMock
import ZenVoice
@testable import ZenMacApp

// Functional test: Zeno's voice demo on the Mac's own fake set (Services.fakes(), what AppModel
// wires on the open-source build), played at full speed, with every line it voices handed to the
// notch the way Settings › Talk to Zeno does. The ZenShared tests cover the replay in depth; this
// one checks the Mac's wiring: the same score in the voice and on Today, the island's focus and
// pause, and the notch's last line.

@Suite("Notch + voice: the demo plays through on the Mac's fakes")
@MainActor
struct VoiceNotchFlowTests {
    @Test("Five moments: transcript, focus and pause on the island, the score Today shows, the notch's last line")
    func demo() async throws {
        let services = Services.fakes()
        let today = try await services.scores.today()
        let voice = VoiceModel.demo(scores: services.scores, cards: services.cards, userName: "Kamal", pace: 0,
                                    sleep: { _ in await Task.yield() })
        let notch = NotchModel()
        notch.reduceMotion = true
        var spoken: [String] = []
        voice.onDemoLine = { line in
            guard line.speaker == .zeno else { return }
            spoken.append(line.text)
            notch.speak(.init(feeling: .pleasant, kicker: "Zeno · Demo", line: line.text), hold: nil, respectQuiet: false)
        }
        #expect(voice.isDemo && voice.state == .idle)

        await voice.start(pickup: true)
        #expect(await eventually(.seconds(20)) { !voice.isActive })

        #expect(voice.state == .ended && voice.error == nil)
        // The transcript: Zeno opens with its one question, and every line ended.
        #expect(voice.lines.first?.text == "Hey Kamal. What are you here for?")
        #expect(voice.lines.allSatisfy { $0.isFinal })
        #expect(voice.lines.filter { $0.wasCut }.count == 1) // the barge-in
        // The voice reads the same score Today shows.
        let status = voice.lines.first { $0.text.hasPrefix("Zen Score") }?.text
        #expect(status == "Zen Score \(today.score.text). \(today.week.goodDays) of 4 good days, one more wins the week.")
        // The island: the 45-minute focus still running, WhatsApp paused 7 seconds, no intent left open.
        let focus = try #require(voice.activeFocus)
        #expect(focus.minutes == 45)
        #expect(voice.activeIntent == nil && voice.timeUp == nil)
        #expect(await voice.ledger.pauseSeconds(for: "WhatsApp") == 7)
        // The notch voiced every Zeno line, and shows the last one.
        #expect(!spoken.isEmpty)
        #expect(await eventually { notch.moment.line == spoken.last })
        #expect(notch.isOpen && notch.wordsIn)
        #expect(voice.demoClock == "22:41")
    }
}
