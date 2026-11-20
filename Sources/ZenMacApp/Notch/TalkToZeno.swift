import AVFoundation
import Carbon.HIToolbox
import Foundation
import Speech
import Albeit
import ZenVoice

/// "Hey Zeno" and "Zeno" as whole words, with the spellings speech recognition tends to write
/// for it. "ZenMode" never counts.
enum WakeWord {
    static let names: Set<String> = ["zeno", "xeno", "zino", "zeeno", "zenno", "zenoh", "zeenu", "zenu"]

    static func heard(_ transcript: String) -> Bool {
        let words = transcript.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        return words.contains { names.contains($0) }
    }
}

/// ⌃⌥Z from any app: talk to Zeno in the notch. A Carbon hot key, so it needs no permission and
/// never sees any other key.
@MainActor
final class TalkHotKey {
    static let display = "⌃⌥Z"
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var fire: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        guard ref == nil else { return }
        Self.fire = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { TalkHotKey.fire?() } }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5A454E4F), id: 1) // "ZENO"
        RegisterEventHotKey(UInt32(kVK_ANSI_Z), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}

/// Listens on this Mac for "Hey Zeno", on the device only (Apple's on-device speech recognition):
/// no audio or words leave the Mac and nothing is kept. Off until the person turns it on; the
/// microphone is released while Zeno talks and taken back after.
@MainActor
@Observable
final class WakeWordListener {
    enum State: Equatable { case off, needsPermission, listening, unavailable }

    private(set) var state: State = .off
    @ObservationIgnored var onWake: (() -> Void)?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var restart: Task<Void, Never>?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")) ?? SFSpeechRecognizer()

    func start() async {
        guard state != .listening else { return }
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard speech == .authorized, mic else { state = .needsPermission; return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        begin(recognizer)
    }

    func stop() {
        restart?.cancel()
        restart = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        if state == .listening { state = .off }
    }

    private func begin(_ recognizer: SFSpeechRecognizer) {
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in request?.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch { state = .unavailable; return }
        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let done = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.state == .listening else { return }
                    if WakeWord.heard(text) {
                        self.stop()
                        self.onWake?()
                    } else if done {
                        self.scheduleRestart(recognizer)
                    }
                }
            }
        }
        // Recognition tasks end after about a minute: start a fresh one before that.
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled else { return }
            self?.begin(recognizer)
        }
    }

    private func scheduleRestart(_ recognizer: SFSpeechRecognizer) {
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.begin(recognizer)
        }
    }
}

extension AppModel {
    static let wakeWordKey = "zen.voice.wakeWord"

    /// Turns "Hey Zeno" on or off (saved).
    func setWakeWord(_ on: Bool) {
        wakeWordOn = on
        defaults.set(on, forKey: Self.wakeWordKey)
        Task { if on { await wake.start() } else { wake.stop() } }
    }

    /// ⌃⌥Z everywhere, and "Hey Zeno" when it's on.
    func startTalkShortcuts() {
        hotKey.register { [weak self] in self?.talkToZeno() }
        wake.onWake = { [weak self] in self?.talkToZeno() }
        if wakeWordOn { Task { await wake.start() } }
    }

    /// Talk to Zeno in the notch: starts a voice session (or ends the one running). The notch shows
    /// that Zeno is listening, then Zeno's words as they come.
    func talkToZeno() {
        guard let voice else { return }
        if [.connecting, .listening, .thinking, .speaking].contains(voice.state) {
            Task { await voice.stop() }
            return
        }
        wake.stop()
        notch.speak(.init(feeling: .curious, kicker: "Zeno · listening", line: "I'm listening."), hold: nil, respectQuiet: false)
        Task {
            await voice.start(pickup: false)
            await mirrorVoiceInNotch(voice)
            if wakeWordOn { try? await Task.sleep(for: .seconds(1)); await wake.start() }
        }
    }

    /// Zeno's latest words in the notch while the session runs; a calm line when it can't connect.
    private func mirrorVoiceInNotch(_ voice: VoiceModel) async {
        var shown = ""
        while !Task.isCancelled {
            switch voice.state {
            case .error:
                let line = voice.error == .signedOut ? "Sign in to talk to me." : "I can't talk just now. Try again soon."
                notch.speak(.init(feeling: .pleasant, kicker: "Zeno", line: line), hold: .seconds(3), respectQuiet: false)
                return
            case .ended, .idle:
                notch.hush()
                return
            default:
                if let last = voice.lines.last(where: { $0.speaker == .zeno }), last.text != shown, !last.text.isEmpty {
                    shown = last.text
                    notch.speak(.init(feeling: .happy, kicker: "Zeno", line: String(last.text.suffix(90))), hold: nil, respectQuiet: false)
                }
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
