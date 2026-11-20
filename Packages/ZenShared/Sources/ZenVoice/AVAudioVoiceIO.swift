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
///
/// Every session gets a fresh engine and player: one start that failed half way (player attached,
/// voice processing switched on) used to leave the shared engine broken, so every later session
/// said "the mic is off" until the app restarted. And when the Mac refuses voice processing (another
/// engine already on the input, some devices), the mic opens without it rather than not at all.
public final class AVAudioVoiceIO: VoiceAudioIO, @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var running = false
    private var playbackFormat: AVAudioFormat
    /// False when this session's mic opened without echo cancellation.
    public private(set) var echoCancelling = false
    /// Buffers scheduled and not yet played out of the speakers.
    private let pending = PendingBuffers()

    public var isPlaying: Bool { pending.count > 0 }

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

        do {
            try open(voiceProcessing: true, onChunk: onChunk)
            echoCancelling = true
        } catch {
            Self.log("voice processing refused (\(error)); opening the mic without it")
            do {
                try open(voiceProcessing: false, onChunk: onChunk)
                echoCancelling = false
            } catch {
                Self.log("the mic didn't open: \(error)")
                throw error
            }
        }
        player.play()
        running = true
    }

    /// One attempt on a fresh engine and player; on failure nothing is left running.
    private func open(voiceProcessing: Bool, onChunk: @escaping @Sendable (MicChunk) -> Void) throws {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        let input = engine.inputNode
        if voiceProcessing { try input.setVoiceProcessingEnabled(true) }
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
            engine.stop()
            throw error
        }
    }

    /// Debug builds: why the mic did or didn't open, on stderr.
    private static func log(_ line: String) {
        #if DEBUG
        FileHandle.standardError.write(Data(("[voice] " + line + "\n").utf8))
        #endif
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
        pending.add()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [pending] _ in pending.done() }
        if !player.isPlaying { player.play() }
    }

    /// Drops everything queued (barge-in) and keeps the player ready for the next reply.
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        player.stop()
        pending.reset()
        player.play()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        pending.reset()
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

public enum VoiceIOError: Error, Equatable, Sendable {
    case noMicrophone
}

/// Buffers on their way out of the speakers; completions arrive on an audio thread.
private final class PendingBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func add() { lock.withLock { n += 1 } }
    func done() { lock.withLock { n = max(0, n - 1) } }
    func reset() { lock.withLock { n = 0 } }
}

/// The tap runs on an audio thread; the pipeline's state is guarded here.
private final class PipelineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: MicPipeline

    init(_ pipeline: MicPipeline) { self.pipeline = pipeline }

    func process(_ frame: [Float]) -> [MicChunk] { lock.withLock { pipeline.process(frame) } }
}
#endif
