import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

/// A throwaway defaults suite per test, so nothing touches the real settings.
func scratchDefaults() -> UserDefaults {
    let name = "fake.zenmode.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Suite("Preferences: Zeno's daily budget and saving")
@MainActor
struct ZenPreferencesTests {
    @Test("Defaults: Zeno in the notch, gentle (two lines a day), every moment, nights quiet only")
    func defaults() {
        let v = PreferenceValues()
        #expect(v.zenoInNotch && v.frequency == .gentle && v.frequency.perDay == 2)
        #expect(v.moments == Set(PreferenceValues.Moment.allCases))
        #expect(v.quiet == .none && v.quietInCalendarEvents)
        #expect(v.islandScore && v.islandGoodDay && v.islandFocus && v.islandReactions)
    }

    @Test("Lines a day per frequency", arguments: [(PreferenceValues.Frequency.gentle, 2), (.balanced, 4), (.chatty, 6)])
    func perDay(f: PreferenceValues.Frequency, n: Int) {
        #expect(f.perDay == n)
    }

    @Test("Saved choices come back on the next launch")
    func persists() {
        let d = scratchDefaults()
        let prefs = ZenPreferences(defaults: d)
        prefs.values.frequency = .chatty
        prefs.values.quiet = .workHours
        prefs.values.moments = [.goodDay]
        let again = ZenPreferences(defaults: d)
        #expect(again.values.frequency == .chatty)
        #expect(again.values.quiet == .workHours)
        #expect(again.values.moments == [.goodDay])
    }

    @Test("A corrupt saved file falls back to the defaults")
    func corrupt() {
        let d = scratchDefaults()
        d.set(Data("not json".utf8), forKey: "zen.preferences.v1")
        #expect(ZenPreferences(defaults: d).values == PreferenceValues())
    }

    @Test("Gentle: two lines a day, then Zeno holds back until tomorrow")
    func budget() {
        let prefs = ZenPreferences(defaults: scratchDefaults())
        let morning = nov(20, 9), evening = nov(20, 19), tomorrow = nov(21, 9)
        #expect(prefs.spend(.pickup, now: morning, calendar: india))
        #expect(prefs.spend(.goodDay, now: morning, calendar: india))
        #expect(!prefs.spend(.checkIn, now: evening, calendar: india))
        #expect(prefs.spend(.checkIn, now: tomorrow, calendar: india))
    }

    @Test("Chatty allows six")
    func chatty() {
        let prefs = ZenPreferences(defaults: scratchDefaults())
        prefs.values.frequency = .chatty
        let spent = (0..<8).map { _ in prefs.spend(.pickup, now: nov(20, 10), calendar: india) }
        #expect(spent.filter { $0 }.count == 6)
    }

    @Test("A moment switched off, or Zeno out of the notch, never speaks and costs nothing")
    func switchedOff() {
        let prefs = ZenPreferences(defaults: scratchDefaults())
        prefs.values.moments.remove(.calendar)
        #expect(!prefs.spend(.calendar, now: nov(20, 10), calendar: india))
        prefs.values.zenoInNotch = false
        #expect(!prefs.spend(.goodDay, now: nov(20, 10), calendar: india))
        prefs.values.zenoInNotch = true
        #expect(prefs.spend(.goodDay, now: nov(20, 10), calendar: india))
        #expect(prefs.spend(.pickup, now: nov(20, 10), calendar: india))
    }

    @Test("Every moment, frequency and appearance has words")
    func labels() {
        for m in PreferenceValues.Moment.allCases { #expect(!m.title.isEmpty && m.example.hasPrefix("\"")) }
        #expect(Set(PreferenceValues.Frequency.allCases.map(\.label)).count == 3)
        #expect(PreferenceValues.Appearance.allCases.map(\.label) == ["Match the Mac", "Paper", "Ink"])
    }

    @Test("Unknown values in a saved file fall back one field at a time")
    func unknownValues() throws {
        let json = #"{"frequency":"loud","appearance":"dark","pattern":"Spiral","islandFocus":false}"#
        let v = try JSONDecoder().decode(PreferenceValues.self, from: Data(json.utf8))
        #expect(v.frequency == .gentle)
        #expect(v.appearance == .dark)
        #expect(v.pattern == .bloom)
        #expect(v.islandFocus == false && v.islandScore == true)
    }
}
