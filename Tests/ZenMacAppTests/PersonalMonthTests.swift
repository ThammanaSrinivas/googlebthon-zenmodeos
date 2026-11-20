import Foundation
import Testing
@testable import ZenMacApp

@Suite("Zen Circle · You: the month and what it says")
struct PersonalMonthTests {
    private func blank(mindfulHour: Int) -> PersonalMonth {
        PersonalMonth(hours: MonthHours(cells: Array(repeating: .rest, count: 720), mindfulHour: mindfulHour, mindfulDay: 0))
    }

    @Test("The demo month is 30 days of 24 hours, the same on every launch")
    func demoShape() {
        let a = PersonalMonth.make(seed: 0x5EED_2026), b = PersonalMonth.demo
        #expect(a.hours.cells.count == 720)
        #expect(a.hours.cells == b.hours.cells)
        #expect(a.calmestHour == b.calmestHour)
        #expect(PersonalMonth.make(seed: 1).hours.cells != a.hours.cells)
    }

    @Test("The demo builder is a deep worker, calmest in the afternoon")
    func demoReads() {
        let m = PersonalMonth.demo
        #expect(m.closest == .deepWorker)
        #expect((13..<18).contains(m.calmestHour))
        #expect(m.focusHours > m.unplannedHours)
        #expect(m.onPurposeShare > 0.5 && m.onPurposeShare <= 1)
    }

    @Test("The brightest day is a focused hour at the calmest hour, after mid-month")
    func brightestDay() {
        let h = PersonalMonth.demo.hours
        #expect((15..<30).contains(h.mindfulDay))
        #expect(h.feel(day: h.mindfulDay, hour: h.mindfulHour) == .focus)
    }

    @Test("Counts read straight from the hours")
    func counts() {
        let m = PersonalMonth.demo
        #expect(m.focusHours == m.hours.cells.filter { $0 == .focus }.count)
        #expect(m.unplannedHours == m.hours.cells.filter { $0 == .unplanned }.count)
    }

    @Test("A month spent at rest is not on purpose, and not a crash")
    func allRest() {
        #expect(blank(mindfulHour: 14).onPurposeShare == 0)
    }

    @Test("The calmest hour in words", arguments: [
        (4, "Late at night"), (5, "Early morning"), (8, "Early morning"), (9, "Late morning"), (11, "Late morning"),
        (12, "Around lunch"), (13, "Around lunch"), (14, "Mid-afternoon"), (16, "Mid-afternoon"),
        (17, "Early evening"), (20, "Early evening"), (21, "Late at night"), (0, "Late at night"),
    ])
    func calmestPart(hour: Int, words: String) {
        #expect(blank(mindfulHour: hour).calmestPart == words)
    }

    @Test("Each archetype's own month is closest to itself", arguments: Archetype.allCases)
    func archetypeFindsItself(_ a: Archetype) {
        #expect(PersonalMonth(hours: a.month(seed: 2026)).closest == a)
    }

    @Test("An archetype's month is the same for the same seed, and calmest where it says")
    func archetypeMonths() {
        for a in Archetype.allCases {
            let m = a.month(seed: 99)
            #expect(m.cells.count == 720)
            #expect(m.cells == a.month(seed: 99).cells)
            #expect(m.mindfulHour == a.mindfulHour)
            #expect(!a.name.isEmpty && !a.line.isEmpty)
        }
        #expect(Set(Archetype.allCases.map(\.mindfulHour)).count == Archetype.allCases.count)
    }

    @Test("Cosine similarity: 1 for the same shape, 0 against nothing")
    func similarity() {
        let v = [0.2, 0.5, 0.1]
        #expect(abs(PersonalMonth.similarity(v, v) - 1) < 1e-9)
        #expect(abs(PersonalMonth.similarity(v, v.map { $0 * 3 }) - 1) < 1e-9)
        #expect(PersonalMonth.similarity(v, [0, 0, 0]) == 0)
        #expect(abs(PersonalMonth.similarity([1, 0], [0, 1])) < 1e-9)
    }

    @Test("A profile is 24 screen-on shares then 24 focus shares (weighted twice)")
    func profile() {
        let p = PersonalMonth.profile(PersonalMonth.demo.hours)
        #expect(p.count == 48)
        #expect(p.prefix(24).allSatisfy { (0...1).contains($0) })
        #expect(p.suffix(24).allSatisfy { (0...2).contains($0) })
    }
}
