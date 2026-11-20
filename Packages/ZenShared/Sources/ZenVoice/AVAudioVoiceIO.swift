#if canImport(AVFAudio)
import AVFAudio
import Foundation

/// The mic and the speaker on Apple platforms: an `AVAudioEngine` input tap turned into 16 kHz
/// PCM16 chunks (`MicPipeline`), and an `AVAudioPlayerNode` that plays Zeno's 24 kHz replies.
/// Voice processing (echo cancellation) is on, so Zeno's own voice doesn't barge in on itself.
///
/// The app asks for the mic first (`AVAudioApplication.requestRecordPermission()`), with
/// NSMicrophoneUsageDescription in Info.plist; on the Mac, the hardened runtime also needs the
/// audio-input entitlement. `start` throws when the mic can't open.
public final class AVAudioVoiceIO: VoiceAudioIO, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var running = false
    private var playbackFormat: AVAudioFormat

    public init() {
        playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: PCM.outputRate, channels: 1,
                                       interleaved: false)!
    }

    public func start(onChunk: @escaping @Sendable (MicChunk) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try audioSession.setActive(true)
        #endif

        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceIOError.noMicrophone
        }
        let pipeline = PipelineBox(MicPipeline(inputRate: inputFormat.sampleRate))
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frame = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            for chunk in pipeline.process(frame) { onChunk(chunk) }
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        player.play()
        running = true
    }

    public func play(_ pcm: Data, sampleRate: Int) {
        let samples = PCM.floats(pcm)
        guard !samples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        if Double(sampleRate) != playbackFormat.sampleRate,
           let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1,
                                      interleaved: false) {
            // A different rate: reconnect the player at it (the mixer converts).
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playbackFormat = format
            player.play()
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Drops everything queued (barge-in) and keeps the player ready for the next reply.
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        player.stop()
        player.play()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

public enum VoiceIOError: Error, Equatable, Sendable {
    case noMicrophone
}

/// The tap runs on an audio thread; the pipeline's state is guarded here.
private final class PipelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: MicPipeline

    init(_ pipeline: MicPipeline) { self.pipeline = pipeline }

    func process(_ frame: [Float]) -> [MicChunk] { lock.withLock { pipeline.process(frame) } }
}
#endif
