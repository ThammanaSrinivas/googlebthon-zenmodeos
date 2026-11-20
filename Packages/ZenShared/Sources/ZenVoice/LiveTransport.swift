import Foundation

/// A WebSocket carrying JSON text frames. `URLSessionLiveTransport` is the real one (Apple
/// platforms); `ScriptedLiveTransport` replays the demo; tests use their own. One transport can
/// connect again after `close()`, which is how a session resumes after a `goAway`.
public protocol LiveTransport: Sendable {
    /// Opens a connection, replacing any open one.
    func connect(to url: URL) async throws
    func send(_ frame: String) async throws
    /// The next frame; nil once the connection has closed.
    func receive() async throws -> String?
    func close() async
}

/// Plays mic audio in and Zeno's voice out. `AVAudioVoiceIO` is the real one on Apple platforms.
public protocol VoiceAudioIO: AnyObject, Sendable {
    /// Starts the mic; `onChunk` gets 40 ms of 16 kHz PCM16 at a time, on any thread.
    func start(onChunk: @escaping @Sendable (MicChunk) -> Void) throws
    /// Queues Zeno's PCM16 for playback.
    func play(_ pcm: Data, sampleRate: Int)
    /// Drops everything queued: the user barged in.
    func flush()
    func stop()
    /// Zeno's audio is still coming out of the speakers (queued buffers not yet played).
    var isPlaying: Bool { get }
}

extension VoiceAudioIO {
    /// Audio that can't tell when playback ends (test fakes): Zeno's queued duration decides alone.
    public var isPlaying: Bool { false }
}

/// A first-in, first-out queue of frames with one waiting reader, for transports built on callbacks
/// (the scripted replay, test fakes).
public actor LiveFrameQueue {
    private var buffer: [String] = []
    private var finished = false
    private var waiter: CheckedContinuation<String?, Never>?

    public init() {}

    public func push(_ frame: String) {
        guard !finished else { return }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: frame)
        } else {
            buffer.append(frame)
        }
    }

    /// No more frames: the reader gets nil once the buffer is drained.
    public func finish() {
        finished = true
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: nil)
        }
    }

    /// Opens the queue again, empty (a new connection).
    public func reset() {
        buffer.removeAll()
        finished = false
    }

    public func next() async -> String? {
        if !buffer.isEmpty { return buffer.removeFirst() }
        if finished { return nil }
        return await withCheckedContinuation { waiter = $0 }
    }
}
