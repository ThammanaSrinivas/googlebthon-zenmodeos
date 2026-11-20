import AVFoundation
import SwiftUI
import Albeit
import ZenAPI
import ZenVoice

enum VoiceCopy {
    static let title = "Zeno's voice"
    static let caption = "Zeno can answer out loud. It adapts to where you are, so you rarely touch this twice."
    static let master = "Zeno speaks out loud"
    static let when = "When Zeno may talk"
    static let soundTitle = "How it sounds"
    static let persona = "Manner"
    static let voice = "Gemini voice"
    static let language = "Language"
    static let speed = "Speed"
    static let volume = "Volume"
    static let sample = "Hear a sample"
    static let adaptiveTitle = "Adapts by itself"
    static let adaptiveCaption = "Checked every time Zeno is about to speak."
    static let headphonesOnly = "Only with headphones"
    static let headphonesDetail = "On the speakers, Zeno shows captions instead."
    static let quietWhenQuiet = "Silent in quiet hours"
    static let quietWhenQuietDetail = "Your class or work hours, and every night."
    static let neverInMeetings = "Never out loud in meetings"
    static let neverInMeetingsDetail = "Busy calendar events get captions only."
    static let softer = "Softer after 9 pm"
    static let softerDetail = "About half the volume, so evenings stay calm."
    static let captions = "Captions always on"
    static let captionsDetail = "Every word Zeno says also shows in the notch."
    static let privacy = "Audio goes to Google Gemini for the reply and isn't stored. Zeno hears only what you say after you tap."
    static let micTitle = "Microphone"
    static let micGranted = "Allowed"
    static let micDenied = "Off in System Settings"
    static let micUndetermined = "Not asked yet"
    static let micAllow = "Allow microphone"
    static let micOpen = "Open System Settings"
    static let nowTitle = "Right now"
    static let verdictOff = "Zeno's voice is off. Lines stay as words in the notch."
    static let verdictMeeting = "You're in a calendar event, so Zeno shows captions only."
    static let verdictQuiet = "It's quiet hours, so Zeno shows captions only."
    static let verdictHeadphones = "No headphones, so Zeno shows captions only."
    static let verdictSoft = "After 9 pm, so Zeno speaks softly."
    static let verdictSpeaks = "Zeno would speak out loud on the Mac's speakers."
    static let verdictHeadphonesOn = "Zeno would speak in your headphones."
    static let sampleLine = "Hi, I'm Zeno. What are you here for?"
    static let tryTitle = "Talk to Zeno"
    static let tryCaption = "Try it here. On the notch, a tap does the same."
    static let start = "Talk to Zeno"
    static let stop = "End"
    static let typePrompt = "Or type to Zeno"
    static let voiceOff = "Turn Zeno's voice on to try it."
}

/// Settings › Voice, on the left of the page.
struct VoiceSettingsGroups: View {
    @Environment(AppModel.self) private var model
    @State private var prefs = VoicePreferences.shared
    @State private var mic = MicAccess.state
    @State private var speaker = ZenoSpeaker()

    var body: some View {
        @Bindable var prefs = prefs
        let v = prefs.values
        VStack(spacing: ZenSpace.s4) {
            SettingsGroup(title: VoiceCopy.title, caption: VoiceCopy.caption) {
                SwitchRow(title: VoiceCopy.master, isOn: $prefs.values.enabled)
                VoiceNowBanner(values: v)
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Text(VoiceCopy.when).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    ForEach(VoiceValues.When.allCases, id: \.self) { w in
                        WhenRow(when: w, selected: v.when == w) { prefs.values.when = w }
                    }
                }
                .disabled(!v.enabled).opacity(v.enabled ? 1 : 0.45)
            }

            SettingsGroup(title: VoiceCopy.soundTitle) {
                VStack(alignment: .leading, spacing: ZenSpace.s4) {
                    labelled(VoiceCopy.persona) {
                        HStack(spacing: ZenSpace.s2) {
                            ForEach(VoiceValues.Persona.allCases, id: \.self) { p in
                                PersonaChip(persona: p, selected: v.persona == p) {
                                    prefs.values.persona = p
                                    prefs.values.geminiVoice = p.suggestedVoice
                                }
                            }
                        }
                    }
                    labelled(VoiceCopy.voice) {
                        Picker(VoiceCopy.voice, selection: $prefs.values.geminiVoice) {
                            ForEach(ZenoAgent.voices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 160)
                    }
                    labelled(VoiceCopy.language) {
                        FlowLayout(spacing: ZenSpace.s2, lineSpacing: ZenSpace.s2) {
                            ForEach(VoiceValues.Language.allCases, id: \.self) { l in
                                SettingsChip(title: l.label, selected: v.language == l) { prefs.values.language = l }
                            }
                        }
                    }
                    labelled(VoiceCopy.speed) {
                        HStack(spacing: ZenSpace.s3) {
                            Slider(value: $prefs.values.speed, in: 0.8...1.3, step: 0.05).frame(width: 200).tint(Color.zen.brandFill)
                            Text(String(format: "%.2f×", v.speed)).font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption)
                        }
                    }
                    labelled(VoiceCopy.volume) {
                        HStack(spacing: ZenSpace.s3) {
                            Slider(value: $prefs.values.volume, in: 0...1).frame(width: 200).tint(Color.zen.brandFill)
                            Text("\(Int(v.volume * 100))%").font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption)
                        }
                    }
                    Button(VoiceCopy.sample) { speaker.say(VoiceCopy.sampleLine, language: v.language.speechCode, values: v) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
                .disabled(!v.enabled).opacity(v.enabled ? 1 : 0.45)
            }

            SettingsGroup(title: VoiceCopy.adaptiveTitle, caption: VoiceCopy.adaptiveCaption) {
                SwitchRow(title: VoiceCopy.headphonesOnly, detail: VoiceCopy.headphonesDetail, isOn: $prefs.values.headphonesOnly)
                SwitchRow(title: VoiceCopy.quietWhenQuiet, detail: VoiceCopy.quietWhenQuietDetail, isOn: $prefs.values.quietWhenQuiet)
                SwitchRow(title: VoiceCopy.neverInMeetings, detail: VoiceCopy.neverInMeetingsDetail, isOn: $prefs.values.neverInMeetings)
                SwitchRow(title: VoiceCopy.softer, detail: VoiceCopy.softerDetail, isOn: $prefs.values.softerAfterNine)
                SwitchRow(title: VoiceCopy.captions, detail: VoiceCopy.captionsDetail, isOn: $prefs.values.captionsAlways)
            }
            .disabled(!v.enabled).opacity(v.enabled ? 1 : 0.45)

            SettingsGroup(title: VoiceCopy.micTitle, caption: VoiceCopy.privacy) {
                HStack {
                    Label(micLabel, systemImage: mic == .granted ? "mic.fill" : "mic.slash")
                        .font(ZenFont.text(13.5, .semibold))
                        .foregroundStyle(mic == .granted ? Color.zen.textBrand : Color.zen.textHeading)
                    Spacer()
                    if mic != .granted {
                        Button(mic == .denied ? VoiceCopy.micOpen : VoiceCopy.micAllow) {
                            Task { mic = await MicAccess.request() }
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                    }
                }
            }
        }
        .animation(ZenMotion.container, value: v)
        .onAppear { mic = MicAccess.state }
    }

    private var micLabel: String {
        switch mic {
        case .granted: VoiceCopy.micGranted
        case .denied: VoiceCopy.micDenied
        case .undetermined: VoiceCopy.micUndetermined
        }
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s4) {
            Text(title).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading).frame(width: 96, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// "Right now": what the rules make of this moment, live.
private struct VoiceNowBanner: View {
    @Environment(AppModel.self) private var model
    let values: VoiceValues

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let verdict = VoiceVerdict.evaluate(values, now: tl.date, calendar: .current, quiet: model.preferences.values.quiet,
                                                inMeeting: model.calendarLink.isBusy(at: tl.date), headphones: AudioRoute.isHeadphones())
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: icon(verdict.mode))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verdict.mode == .speaks || verdict.mode == .softly ? Color.zen.textBrand : Color.zen.textCaption)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.zen.surfaceTint))
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(VoiceCopy.nowTitle)
                    Text(verdict.reason).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(ZenSpace.s3)
            .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.6)))
            .accessibilityElement(children: .combine)
        }
    }

    private func icon(_ mode: VoiceVerdict.Mode) -> String {
        switch mode {
        case .speaks: "speaker.wave.2.fill"
        case .softly: "speaker.wave.1.fill"
        case .captionsOnly: "captions.bubble"
        case .off: "speaker.slash"
        }
    }
}

/// One "when may Zeno talk" choice: a cell that fills when picked, the label and what it means.
private struct WhenRow: View {
    let when: VoiceValues.When
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenSpace.s3) {
                RoundedRectangle(cornerRadius: ZenRadius.cell + 1, style: .continuous)
                    .fill(selected ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.05))
                    .overlay { if !selected { RoundedRectangle(cornerRadius: ZenRadius.cell + 1).strokeBorder(Color.zen.borderOutline, lineWidth: 1) } }
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(when.label).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(when.detail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ZenSpace.s3).padding(.vertical, ZenSpace.s3)
            .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                .fill(selected ? Color.zen.surfaceTint.opacity(0.9) : Color.zen.surfaceCard.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(when.label). \(when.detail)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct PersonaChip: View {
    let persona: VoiceValues.Persona
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.label).font(ZenFont.text(13.5, .semibold))
                Text(persona.detail).font(ZenFont.text(11.5)).opacity(0.75)
            }
            .foregroundStyle(selected ? Color.zen.onActionPrimary : Color.zen.textHeading)
            .padding(.horizontal, ZenSpace.s3).padding(.vertical, ZenSpace.s2)
            .frame(width: 128, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(selected ? Color.zen.actionPrimary : Color.zen.surfaceSunk))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(persona.label). \(persona.detail)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Speaks lines with the system voice: the demo's scripted lines and the sample, at the chosen
/// speed and the volume the rules allow right now.
@MainActor
final class ZenoSpeaker {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String, language: String, values: VoiceValues, volume override: Double? = nil) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-IN")
        u.rate = Float(Double(AVSpeechUtteranceDefaultSpeechRate) * values.speed)
        u.volume = Float(override ?? values.volume)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}

/// Settings › Voice, on the right: a notch-like panel to try a conversation. On the fakes it plays
/// the five-moment demo and says so.
struct TalkToZenoPanel: View {
    @Environment(AppModel.self) private var model
    @State private var prefs = VoicePreferences.shared
    @State private var speaker = ZenoSpeaker()
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Eyebrow(VoiceCopy.tryTitle)
                Spacer()
                if model.voice?.isDemo != false { DemoTag("Demo") }
            }
            if let voice = model.voice, prefs.values.enabled {
                island(voice)
                controls(voice)
            } else {
                Text(VoiceCopy.voiceOff).zenType(.body).foregroundStyle(Color.zen.textBody)
                Button(VoiceCopy.master) { prefs.values.enabled = true }.buttonStyle(ZenLinkButtonStyle())
            }
            Text(VoiceCopy.tryCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
        .onDisappear { Task { await model.voice?.stop(); speaker.stop() } }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["ZEN_VOICE_DEMO"] == "1", let voice = model.voice { await begin(voice) }
        }
        #endif
    }

    /// The black island: Zeno, the state, the caption, the transcript, the tool card.
    private func island(_ voice: VoiceModel) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                ZenoView(feeling(voice.state)).frame(width: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stateLabel(voice.state).uppercased()).font(ZenFont.number(10)).tracking(1)
                        .foregroundStyle(Color.zen.brandSoft)
                    if let caption = voice.caption {
                        Text(caption).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.islandDetail)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let ms = voice.latencyMs {
                        Text("First sound in \(ms) ms").font(ZenFont.number(11)).foregroundStyle(Color.zen.islandDetail)
                    }
                }
                Spacer(minLength: 0)
                if let clock = voice.demoClock {
                    Text(clock).font(ZenFont.number(11)).foregroundStyle(Color.zen.islandDetail)
                }
            }
            if voice.lines.isEmpty {
                Text(ZenoAgent.pickupQuestion).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.islandText.opacity(0.55))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: ZenSpace.s2) {
                            ForEach(voice.lines) { line in
                                TranscriptBubble(line: line).id(line.id)
                            }
                        }
                    }
                    .frame(height: 220)
                    .onChange(of: voice.lines.count) { _, _ in
                        if let last = voice.lines.last { withAnimation(ZenMotion.calm(ZenMotion.t2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
            if let card = voice.card { ToolCardView(card: card) }
            if let error = voice.error {
                Text(errorLine(error)).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.islandDetail)
            }
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.zen.island))
        .environment(\.colorScheme, .dark)
        .animation(ZenMotion.container, value: voice.lines.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zeno, \(stateLabel(voice.state))")
    }

    private func controls(_ voice: VoiceModel) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                if voice.isActive {
                    Button(VoiceCopy.stop) { Task { await voice.stop(); speaker.stop() } }
                        .buttonStyle(ZenSecondaryButtonStyle())
                } else {
                    Button { Task { await begin(voice) } } label: { Label(VoiceCopy.start, systemImage: "waveform") }
                        .buttonStyle(ZenPrimaryButtonStyle())
                }
            }
            if voice.isActive {
                HStack(spacing: ZenSpace.s2) {
                    TextField(VoiceCopy.typePrompt, text: $typed)
                        .textFieldStyle(.plain).font(ZenFont.text(13.5))
                        .padding(.horizontal, ZenSpace.s3).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: ZenRadius.md).fill(Color.zen.surfaceCard.opacity(0.7)))
                        .onSubmit { send(voice) }
                    Button { send(voice) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(Color.zen.textBrand)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Send")
                }
            }
        }
    }

    private func begin(_ voice: VoiceModel) async {
        let values = prefs.values
        voice.onDemoLine = { [speaker, model] line in
            guard line.speaker == .zeno else { return }
            let verdict = VoiceVerdict.evaluate(values, now: Date(), calendar: .current, quiet: model.preferences.values.quiet,
                                                inMeeting: model.calendarLink.isBusy(at: Date()), headphones: AudioRoute.isHeadphones())
            guard verdict.mode == .speaks || verdict.mode == .softly else { return }
            let code = values.language == .auto ? (line.language.hasPrefix("ta") ? "ta-IN" : line.language.hasPrefix("hi") ? "hi-IN" : "en-IN")
                                                : values.language.speechCode
            speaker.say(line.text, language: code, values: values, volume: verdict.volume)
        }
        await voice.start(pickup: false)
    }

    private func send(_ voice: VoiceModel) {
        let text = typed
        typed = ""
        Task { await voice.sendText(text) }
    }

    private func feeling(_ s: VoiceState) -> ZenoFeeling {
        switch s {
        case .idle, .ended: .calm
        case .connecting, .thinking: .curious
        case .listening: .pleasant
        case .speaking: .happy
        case .error: .pleasant
        }
    }

    private func stateLabel(_ s: VoiceState) -> String {
        switch s {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .ended: "Ended"
        case .error: "Couldn't connect"
        }
    }

    private func errorLine(_ e: VoiceError) -> String {
        switch e {
        case .signedOut: "Sign in to talk to Zeno."
        case .offline: "Offline. Zeno's back when you are."
        case .disabled: "The mic is off. You can still type to Zeno."
        case .rateLimited: "Lots of chats just now. Try again in a minute."
        default: "Zeno couldn't answer just now. Try again."
        }
    }
}

/// One transcript line: Zeno on the left, you on the right, the language as a small label.
private struct TranscriptBubble: View {
    let line: TranscriptLine

    var body: some View {
        let mine = line.speaker == .user
        HStack {
            if mine { Spacer(minLength: 30) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(line.text + (line.wasCut ? " …" : ""))
                    .font(ZenFont.text(13.5, mine ? .regular : .semibold))
                    .foregroundStyle(mine ? Color.zen.islandDetail : Color.zen.islandText)
                    .multilineTextAlignment(mine ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(line.isFinal ? 1 : 0.7)
                if let label = line.languageLabel {
                    Text(label.uppercased()).font(ZenFont.number(9)).tracking(0.8).foregroundStyle(Color.zen.brandSoft.opacity(0.8))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mine ? Color.white.opacity(0.06) : Color.white.opacity(0.1)))
            if !mine { Spacer(minLength: 30) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mine ? "You" : "Zeno"): \(line.text)")
    }
}

/// What Zeno just did with a tool, as one quiet card.
private struct ToolCardView: View {
    let card: ToolCard

    var body: some View {
        let (symbol, title, detail) = content
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x0B2A0E))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.zen.brandSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.islandText)
                Text(detail).font(ZenFont.text(12)).foregroundStyle(Color.zen.islandDetail).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(ZenSpace.s3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }

    private var content: (String, String, String) {
        switch card {
        case .status(let s):
            return ("chart.bar", "Your day", s.score.map { "Zen Score \($0.text)" } ?? "Score not in yet")
        case .intent(let i):
            return ("timer", "\(i.app) · \(i.minutes) min", "For: \(i.purpose)")
        case .intentEnded(let i):
            return ("checkmark.circle", "\(i.app) done", "For: \(i.purpose)")
        case .focus(let f):
            return ("moon.stars", "Focus · \(f.minutes) min", f.label)
        case .pause(let p):
            return ("pause.circle", "\(p.app) paused", "For \(p.seconds / 60) min")
        case .zenCard(let c):
            return ("rectangle.stack", "Zen Card saved", c.summary)
        }
    }
}
