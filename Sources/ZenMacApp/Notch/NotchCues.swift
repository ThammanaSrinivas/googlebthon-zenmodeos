import AppKit
import AVFoundation

/// What Zeno adds when it arrives with something worth a beat of attention: a sound and a tap.
///
/// The sounds are made here, so no files ship: a soft, rising pair of bell tones as Zeno arrives and
/// one falling pair as it leaves. Each eases in (a smooth 30 ms attack, then the player's own volume
/// fade) and rings out over a long tail that ends in silence, quiet enough to sit under music. The tap
/// is the trackpad's gentlest haptic, felt only when a finger is on it. Silent when the Mac's
/// user-interface sound effects are off, or when the person turns Zeno's sounds off.
@MainActor
final class NotchCues {
    /// Off when false (on until the person says otherwise).
    static let soundsKey = "zen.notch.sounds"

    var defaults: UserDefaults = .standard
    private var playing: [AVAudioPlayer] = []

    /// Zeno's sounds play: the person hasn't turned them off, nor the Mac's interface sounds
    /// (System Settings › Sound › Play user interface sound effects).
    var soundsOn: Bool {
        if defaults.object(forKey: Self.soundsKey) as? Bool == false { return false }
        if UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Int == 0 { return false }
        return true
    }

    /// Zeno arrives with something that matters.
    func arrive() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        play(Self.arrival, volume: 0.32)
    }

    /// Zeno tucks back into the notch.
    func leave() {
        play(Self.departure, volume: 0.2)
    }

    private func play(_ wav: Data, volume: Float) {
        guard soundsOn, let player = try? AVAudioPlayer(data: wav) else { return }
        playing.removeAll { !$0.isPlaying }
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(volume, fadeDuration: 0.12)
        playing.append(player)
    }

    // MARK: The sounds (pure, tested)

    nonisolated static let sampleRate = 44_100.0

    /// G5 then D6, a fifth up: "here's something".
    nonisolated static let arrival = wav(chime(notes: [(783.99, 0), (1174.66, 0.11)], length: 1.3, decay: 0.42))
    /// C6 then F5, falling: "that's all".
    nonisolated static let departure = wav(chime(notes: [(1046.5, 0), (698.46, 0.09)], length: 0.95, decay: 0.3, level: 0.7))

    /// Soft bell tones: each note a sine with two quickly fading overtones, a smooth (smoothstep)
    /// 30 ms attack and an exponential ring; the last 160 ms ease to silence. Peak `0.5 × level`.
    nonisolated static func chime(notes: [(freq: Double, at: Double)], length: Double, decay: Double,
                                  level: Double = 1) -> [Float] {
        let count = Int(length * sampleRate)
        guard count > 0 else { return [] }
        var out = [Double](repeating: 0, count: count)
        for (k, note) in notes.enumerated() {
            let start = Int(note.at * sampleRate)
            guard start < count else { continue }
            let gain = k == 0 ? 1.0 : 0.8
            let w = 2 * Double.pi * note.freq
            for i in start..<count {
                let t = Double(i - start) / sampleRate
                let envelope = smoothstep(min(t / 0.03, 1)) * exp(-t / decay)
                let tone = sin(w * t)
                    + 0.28 * sin(2 * w * t) * exp(-t / (decay * 0.5))
                    + 0.08 * sin(3.01 * w * t) * exp(-t / (decay * 0.3))
                out[i] += gain * envelope * tone
            }
        }
        let tail = min(Int(0.16 * sampleRate), count)
        for j in 0..<tail {
            out[count - 1 - j] *= smoothstep(Double(j) / Double(tail))
        }
        let peak = out.map(abs).max() ?? 0
        let scale = peak > 0 ? 0.5 * min(max(level, 0), 1) / peak : 0
        return out.map { Float($0 * scale) }
    }

    /// 16-bit mono PCM in a WAV container, for `AVAudioPlayer(data:)`.
    nonisolated static func wav(_ samples: [Float]) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func put(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        put("RIFF"); put32(UInt32(36 + pcm.count)); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16)
        put("data"); put32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }

    private nonisolated static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
