import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("Today: Get set up")
@MainActor
struct SetupChecklistTests {
    @Test("Seven steps in order; the webhook is the one optional step")
    func steps() {
        let p = SetupProgress.make(dnd: false, slack: false, calendar: false, webhook: false, workHours: false, team: false, talked: false)
        #expect(p.steps.map(\.id) == [.dnd, .slack, .calendar, .webhook, .workHours, .team, .talk])
        #expect(p.steps.filter(\.isOptional).map(\.id) == [.webhook])
        #expect(p.total == 6 && p.doneCount == 0 && p.fraction == 0)
        #expect(p.label == "0 of 6 done")
        #expect(p.next?.id == .dnd)
        #expect(!p.isComplete)
    }

    @Test("Done counts required steps only; the next step skips what's done and the optional one")
    func progress() {
        let p = SetupProgress.make(dnd: true, slack: true, calendar: false, webhook: true, workHours: false, team: true, talked: false)
        #expect(p.doneCount == 3)
        #expect(p.label == "3 of 6 done")
        #expect(p.fraction == 0.5)
        #expect(p.next?.id == .calendar)
    }

    @Test("Complete without the webhook; the optional step never holds the list open")
    func complete() {
        let p = SetupProgress.make(dnd: true, slack: true, calendar: true, webhook: false, workHours: true, team: true, talked: true)
        #expect(p.isComplete)
        #expect(p.next == nil)
        #expect(p.fraction == 1)
    }

    @Test("Every step has a title, a line, a symbol and an action; notes carry through")
    func copy() {
        let p = SetupProgress.make(dnd: false, slack: false, calendar: false, webhook: false, workHours: true, team: false, talked: false,
                                   notes: [.workHours: "09:30–18:30"])
        for s in p.steps {
            #expect(!s.title.isEmpty && !s.detail.isEmpty && !s.symbol.isEmpty && !s.action.isEmpty)
        }
        #expect(p.steps.first { $0.id == .workHours }?.note == "09:30–18:30")
        #expect(p.steps.first { $0.id == .talk }?.detail.contains(TalkHotKey.display) == true)
        #expect(p.steps.first { $0.id == .talk }?.action == "Try it")
    }
}

@Suite("Today: the Zen Cards stack")
struct ZenCardStackTests {
    @Test("Languages read by name, with Hinglish for Hindi in Latin script")
    func languages() {
        #expect(ZenCardLabels.language("ta") == "Tamil")
        #expect(ZenCardLabels.language("hi-Latn") == "Hinglish")
        #expect(ZenCardLabels.language("hi") == "Hindi")
        #expect(ZenCardLabels.language("en-IN") == "English")
        #expect(ZenCardLabels.language("und") == "Any language")
    }

    @Test("Click order wraps: the top card goes to the back")
    func order() {
        #expect(ZenCardLabels.order(count: 3, front: 0) == [0, 1, 2])
        #expect(ZenCardLabels.order(count: 3, front: 1) == [1, 2, 0])
        #expect(ZenCardLabels.order(count: 3, front: 2) == [2, 0, 1])
        #expect(ZenCardLabels.order(count: 0, front: 0).isEmpty)
    }

    @Test("Back to front the stack leans −6°, 3°, −2°, and fans wider than it rests")
    func tilt() {
        #expect(Array(ZenCardLabels.angles.prefix(3).reversed()) == [-6, 3, -2])
        for (rest, fan) in zip(ZenCardLabels.angles.dropFirst(), ZenCardLabels.fanAngles.dropFirst()) {
            #expect(abs(fan) > abs(rest))
        }
    }

    @Test("Every mood has a Zeno face and a label; samples carry no score")
    func moods() {
        #expect(ZenCardLabels.feeling(.tired) == .sleepy)
        #expect(ZenCardLabels.feeling(.neutral) == .calm)
        #expect(ZenCardLabels.mood(.pleasant) == "Pleasant")
        let samples = ZenCardLabels.samples(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(samples.count == 3)
        #expect(Set(samples.map(\.language)) == ["ta", "hi-Latn", "en-IN"])
        #expect(samples.allSatisfy { $0.summary.count <= ZenCardDraft.maxSummaryLength })
    }
}

@Suite("Today: the compartments")
struct TodaySectionTests {
    @Test("Five numbered sections in reading order")
    func sections() {
        #expect(TodaySection.allCases.map(\.title) == ["Now", "Your day", "Work", "Rewards & circle", "Play"])
        #expect(TodaySection.allCases.map(\.number) == ["01", "02", "03", "04", "05"])
        #expect(TodaySection.allCases.allSatisfy { !$0.line.isEmpty })
    }
}
