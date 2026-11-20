import AppKit
import AVFAudio
import CoreAudio
import Foundation
import Observation
import ZenAPI

/// How Zeno's voice behaves, saved on this Mac. Every rule is something the Mac can check by
/// itself, so the voice adapts without anyone touching a setting twice.
struct VoiceValues: Codable, Equatable, Sendable {
    /// When Zeno may talk out loud.
    enum When: String, Codable, CaseIterable, Sendable {
        case tapOnly, moments

        var label: String {
            switch self {
            case .tapOnly: "Only when I tap the notch"
            case .moments: "Also for its moments"
            }
        }

        var detail: String {
            switch self {
            case .tapOnly: "Zeno answers when you ask. Moments stay as words in the notch."
            case .moments: "A good day, a calendar heads-up and the weekly review are said out loud too."
            }
        }
    }

    /// Zeno's manner. Each persona suggests a Gemini voice; the person can pick another.
    enum Persona: String, Codable, CaseIterable, Sendable {
        case calm, warm, bright

        var label: String {
            switch self {
            case .calm: "Calm"
            case .warm: "Warm"
            case .bright: "Bright"
            }
        }

        var detail: String {
            switch self {
            case .calm: "Few words, low and even."
            case .warm: "Friendly, a little slower."
            case .bright: "Upbeat, quick to cheer."
            }
        }

        /// A Gemini Live voice that suits the manner.
        var suggestedVoice: String {
            switch self {
            case .calm: "Kore"
            case .warm: "Aoede"
            case .bright: "Puck"
            }
        }
    }

    /// The language Zeno answers in. Auto follows whatever the person speaks, code-mix included.
    enum Language: String, Codable, CaseIterable, Sendable {
        case auto, english, tamil, hindi, tanglish, hinglish

        var label: String {
            switch self {
            case .auto: "Match me"
            case .english: "English"
            case .tamil: "Tamil"
            case .hindi: "Hindi"
            case .tanglish: "Tanglish"
            case .hinglish: "Hinglish"
            }
        }

        /// The system voice for spoken demo lines and previews.
        var speechCode: String {
            switch self {
            case .auto, .english: "en-IN"
            case .tamil, .tanglish: "ta-IN"
            case .hindi, .hinglish: "hi-IN"
            }
        }
    }

    var enabled = true
    var when: When = .tapOnly
    var persona: Persona = .calm
    var geminiVoice = "Kore"
    var language: Language = .auto
    /// 0.8 (slower) to 1.3 (quicker).
    var speed = 1.0
    /// 0 to 1.
    var volume = 0.8
    // Adaptive rules
    var headphonesOnly = false
    var quietWhenQuiet = true
    var softerAfterNine = true
    var captionsAlways = true
    var neverInMeetings = true

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceValues()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        when = (try? c.decode(When.self, forKey: .when)) ?? d.when
        persona = (try? c.decode(Persona.self, forKey: .persona)) ?? d.persona
        geminiVoice = (try? c.decode(String.self, forKey: .geminiVoice)) ?? d.geminiVoice
        language = (try? c.decode(Language.self, forKey: .language)) ?? d.language
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? d.volume
        headphonesOnly = (try? c.decode(Bool.self, forKey: .headphonesOnly)) ?? d.headphonesOnly
        quietWhenQuiet = (try? c.decode(Bool.self, forKey: .quietWhenQuiet)) ?? d.quietWhenQuiet
        softerAfterNine = (try? c.decode(Bool.self, forKey: .softerAfterNine)) ?? d.softerAfterNine
        captionsAlways = (try? c.decode(Bool.self, forKey: .captionsAlways)) ?? d.captionsAlways
        neverInMeetings = (try? c.decode(Bool.self, forKey: .neverInMeetings)) ?? d.neverInMeetings
    }
}

/// What the rules say right now: whether Zeno would speak out loud, how loudly, and why.
struct VoiceVerdict: Equatable {
    enum Mode: Equatable { case speaks, softly, captionsOnly, off }
    let mode: Mode
    let reason: String
    let volume: Double

    /// The rules in order: off beats everything; then meetings, quiet hours, headphones; then the
    /// evening's softer voice.
    static func evaluate(_ v: VoiceValues, now: Date, calendar: Calendar, quiet: QuietHours,
                         inMeeting: Bool, headphones: Bool) -> VoiceVerdict {
        guard v.enabled else { return VoiceVerdict(mode: .off, reason: VoiceCopy.verdictOff, volume: 0) }
        if v.neverInMeetings && inMeeting { return VoiceVerdict(mode: .captionsOnly, reason: VoiceCopy.verdictMeeting, volume: 0) }
        if v.quietWhenQuiet && quiet.isQuiet(at: now, calendar: calendar) {
            return VoiceVerdict(mode: .captionsOnly, reason: VoiceCopy.verdictQuiet, volume: 0)
        }
        if v.headphonesOnly && !headphones { return VoiceVerdict(mode: .captionsOnly, reason: VoiceCopy.verdictHeadphones, volume: 0) }
        if v.softerAfterNine && calendar.component(.hour, from: now) >= 21 {
            return VoiceVerdict(mode: .softly, reason: VoiceCopy.verdictSoft, volume: v.volume * 0.55)
        }
        return VoiceVerdict(mode: .speaks, reason: headphones ? VoiceCopy.verdictHeadphonesOn : VoiceCopy.verdictSpeaks, volume: v.volume)
    }
}

@MainActor
@Observable
final class VoicePreferences {
    static let shared = VoicePreferences()

    var values: VoiceValues { didSet { if values != oldValue { save() } } }
    private static let key = "zen.voice.preferences.v1"
    /// The store these choices came from; changes go back to the same one.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(VoiceValues.self, from: data) {
            values = saved
        } else {
            values = VoiceValues()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: Self.key) }
    }
}

/// Where sound is going: headphones (wired or Bluetooth) or the Mac's speakers.
enum AudioRoute {
    static func isHeadphones() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }

        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr,
           transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }
        // The built-in output reports headphones as its data source when something is plugged in.
        var source = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
                                             mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr {
            return source == 0x6864706E // 'hdpn'
        }
        return false
    }
}

/// The microphone grant, read and requested the system's way.
enum MicAccess {
    enum State: Equatable { case undetermined, granted, denied }

    static var state: State {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    static func request() async -> State {
        if state == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return .denied
        }
        return await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }
}
