import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("Zeno's voice: the adaptive rules")
struct VoiceVerdictTests {
    private func verdict(_ v: VoiceValues = VoiceValues(), at date: Date, quiet: QuietHours = .none,
                         meeting: Bool = false, headphones: Bool = false) -> VoiceVerdict {
        VoiceVerdict.evaluate(v, now: date, calendar: india, quiet: quiet, inMeeting: meeting, headphones: headphones)
    }

    @Test("Off beats everything")
    func off() {
        var v = VoiceValues()
        v.enabled = false
        let r = verdict(v, at: nov(20, 14), meeting: true, headphones: true)
        #expect(r == VoiceVerdict(mode: .off, reason: VoiceCopy.verdictOff, volume: 0))
    }

    @Test("A busy calendar event gets captions only, before quiet hours are even checked")
    func meeting() {
        let r = verdict(at: nov(20, 23), meeting: true)
        #expect(r.mode == .captionsOnly && r.reason == VoiceCopy.verdictMeeting && r.volume == 0)
        var v = VoiceValues()
        v.neverInMeetings = false
        #expect(verdict(v, at: nov(20, 14), meeting: true).mode == .speaks)
    }

    @Test("Quiet hours: every night, and the chosen block on its weekdays")
    func quiet() {
        #expect(verdict(at: nov(20, 23)).reason == VoiceCopy.verdictQuiet)       // 23:00
        #expect(verdict(at: nov(20, 6, 59)).mode == .captionsOnly)               // before 7
        #expect(verdict(at: nov(20, 10), quiet: .classHours).reason == VoiceCopy.verdictQuiet) // Friday class
        #expect(verdict(at: nov(21, 10), quiet: .classHours).mode == .speaks)     // Saturday: no class
        var v = VoiceValues()
        v.quietWhenQuiet = false
        #expect(verdict(v, at: nov(20, 10), quiet: .classHours).mode == .speaks)
    }

    @Test("Headphones only: captions on the speakers, the voice in headphones")
    func headphones() {
        var v = VoiceValues()
        v.headphonesOnly = true
        #expect(verdict(v, at: nov(20, 14)).reason == VoiceCopy.verdictHeadphones)
        let on = verdict(v, at: nov(20, 14), headphones: true)
        #expect(on.mode == .speaks && on.reason == VoiceCopy.verdictHeadphonesOn && on.volume == v.volume)
    }

    @Test("After 9 pm, softly at about half the volume")
    func softer() {
        let r = verdict(at: nov(20, 21, 30))
        #expect(r.mode == .softly && r.reason == VoiceCopy.verdictSoft)
        #expect(abs(r.volume - 0.8 * 0.55) < 1e-9)
        var v = VoiceValues()
        v.softerAfterNine = false
        #expect(verdict(v, at: nov(20, 21, 30)).mode == .speaks)
        #expect(verdict(at: nov(20, 20, 59)).mode == .speaks)
    }

    @Test("In the day, on the speakers, at the chosen volume")
    func speaks() {
        var v = VoiceValues()
        v.volume = 0.6
        #expect(verdict(v, at: nov(20, 14)) == VoiceVerdict(mode: .speaks, reason: VoiceCopy.verdictSpeaks, volume: 0.6))
    }
}

@Suite("Zeno's voice: saved values")
struct VoiceValuesTests {
    @Test("Defaults: on, tap only, calm Kore, match my language, every adaptive rule but headphones-only")
    func defaults() {
        let v = VoiceValues()
        #expect(v.enabled && v.when == .tapOnly && v.persona == .calm && v.geminiVoice == "Kore" && v.language == .auto)
        #expect(v.speed == 1 && v.volume == 0.8)
        #expect(!v.headphonesOnly && v.quietWhenQuiet && v.softerAfterNine && v.captionsAlways && v.neverInMeetings)
        #expect(v.geminiVoice == v.persona.suggestedVoice)
    }

    @Test("A saved file from an older build keeps what it has")
    func tolerant() throws {
        let json = #"{"persona":"bright","language":"tanglish","volume":0.3,"when":"sometimes"}"#
        let v = try JSONDecoder().decode(VoiceValues.self, from: Data(json.utf8))
        #expect(v.persona == .bright && v.language == .tanglish && v.volume == 0.3)
        #expect(v.when == .tapOnly && v.geminiVoice == "Kore" && v.enabled)
    }

    @Test("Values survive a round trip")
    func roundTrip() throws {
        var v = VoiceValues()
        v.persona = .warm
        v.geminiVoice = "Aoede"
        v.speed = 1.2
        v.headphonesOnly = true
        #expect(try JSONDecoder().decode(VoiceValues.self, from: JSONEncoder().encode(v)) == v)
    }

    @Test("Each persona suggests its own Gemini voice")
    func personas() {
        #expect(VoiceValues.Persona.allCases.map(\.suggestedVoice) == ["Kore", "Aoede", "Puck"])
        for p in VoiceValues.Persona.allCases { #expect(!p.label.isEmpty && !p.detail.isEmpty) }
    }

    @Test("Code-mixed languages speak with their parent language's voice")
    func speechCodes() {
        let codes = Dictionary(uniqueKeysWithValues: VoiceValues.Language.allCases.map { ($0, $0.speechCode) })
        #expect(codes[.auto] == "en-IN" && codes[.english] == "en-IN")
        #expect(codes[.tamil] == "ta-IN" && codes[.tanglish] == "ta-IN")
        #expect(codes[.hindi] == "hi-IN" && codes[.hinglish] == "hi-IN")
        #expect(VoiceValues.Language.auto.label == "Match me")
    }
}

@Suite("Zeno's voice: VoicePreferences")
@MainActor
struct VoicePreferencesStoreTests {
    @Test("It reads what the given store holds")
    func reads() throws {
        let d = scratchDefaults()
        var v = VoiceValues()
        v.persona = .bright
        d.set(try JSONEncoder().encode(v), forKey: "zen.voice.preferences.v1")
        #expect(VoicePreferences(defaults: d).values.persona == .bright)
        #expect(VoicePreferences(defaults: scratchDefaults()).values == VoiceValues())
    }

    @Test("A change is saved to the store it was given")
    func savesToGivenStore() {
        let d = scratchDefaults()
        let prefs = VoicePreferences(defaults: d)
        prefs.values.persona = .warm
        #expect(VoicePreferences(defaults: d).values.persona == .warm)
    }
}
