import Foundation

// Pure audio maths, the Swift twin of the prototype's mic worklet (zeno-voice/src/mic-worklet.js):
// the mic is resampled to 16 kHz, converted to 16-bit little-endian PCM and sent in 40 ms chunks;
// Zeno's 24 kHz PCM16 replies are turned back into floats for playback. No AVFoundation here, so
// it all tests on Linux; `AVAudioVoiceIO` wraps it on Apple platforms.

public enum PCM {
    /// The rate Gemini Live expects from the mic.
    public static let inputRate: Double = 16_000
    /// The rate Zeno's audio arrives at.
    public static let outputRate: Double = 24_000
    /// 40 ms at 16 kHz.
    public static let samplesPerChunk = 640

    /// One sample, clamped to [-1, 1], as the worklet writes it: negatives scale by 32768,
    /// positives by 32767, truncated toward zero (as an Int16Array store does).
    public static func int16(_ sample: Float) -> Int16 {
        let s = sample.isNaN ? 0 : min(max(sample, -1), 1)
        return Int16(s < 0 ? s * 32_768 : s * 32_767)
    }

    /// 16-bit little-endian PCM bytes from floats.
    public static func int16LE(_ samples: [Float]) -> Data { int16LE(samples.map(int16)) }

    public static func int16LE(_ samples: [Int16]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample)
            data.append(UInt8(truncatingIfNeeded: bits))
            data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return data
    }

    /// Samples from 16-bit little-endian PCM bytes (a trailing odd byte is ignored).
    public static func int16Samples(_ data: Data) -> [Int16] {
        let bytes = [UInt8](data)
        var samples = [Int16]()
        samples.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            samples.append(Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8))
            index += 2
        }
        return samples
    }

    /// Floats in [-1, 1) for playback, as the prototype plays them (sample / 32768).
    public static func floats(_ data: Data) -> [Float] { int16Samples(data).map { Float($0) / 32_768 } }

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    /// RMS of PCM16 bytes, on the [-1, 1] scale.
    public static func rms(int16LE data: Data) -> Float {
        let samples = int16Samples(data)
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { acc, s in let f = Float(s) / 32_768; return acc + f * f }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Milliseconds of audio in PCM16 mono bytes at `rate`.
    public static func durationMs(bytes: Int, rate: Double) -> Double { Double(bytes / 2) / rate * 1_000 }
}

/// Streaming linear-interpolation resampler, the worklet's algorithm: it keeps its read position
/// and the previous frame's last sample, so frames of any size join without clicks. When it
/// downsamples it first runs a moving average as wide as the ratio (3 samples for 48 → 16 kHz),
/// a cheap low-pass that nulls the band that would otherwise fold back into speech.
public struct LinearResampler: Sendable {
    public let inputRate: Double
    public let outputRate: Double
    public let ratio: Double
    private var position: Double = 0
    private var previous: Float = 0
    private let filterWidth: Int
    private var history: [Float]

    public init(inputRate: Double, outputRate: Double = PCM.inputRate, antiAlias: Bool = true) {
        precondition(inputRate > 0 && outputRate > 0, "Rates must be positive")
        self.inputRate = inputRate
        self.outputRate = outputRate
        ratio = inputRate / outputRate
        filterWidth = antiAlias && ratio > 1.25 ? Int(ratio.rounded()) : 1
        history = Array(repeating: 0, count: max(filterWidth - 1, 0))
    }

    public mutating func process(_ frame: [Float]) -> [Float] {
        guard !frame.isEmpty else { return [] }
        let input = lowPass(frame)
        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) / ratio) + 2)
        var p = position
        while true {
            let i0 = Int(p.rounded(.down))
            if i0 + 1 >= input.count { break }
            let s0 = i0 < 0 ? previous : input[i0]
            let s1 = input[i0 + 1]
            output.append(s0 + (s1 - s0) * Float(p - Double(i0)))
            p += ratio
        }
        position = p - Double(input.count)
        previous = input[input.count - 1]
        return output
    }

    private mutating func lowPass(_ frame: [Float]) -> [Float] {
        guard filterWidth > 1 else { return frame }
        let padded = history + frame
        var output = [Float](repeating: 0, count: frame.count)
        var sum = padded[0..<filterWidth - 1].reduce(0, +)
        for i in 0..<frame.count {
            sum += padded[i + filterWidth - 1]
            output[i] = sum / Float(filterWidth)
            sum -= padded[i]
        }
        history = Array(padded.suffix(filterWidth - 1))
        return output
    }
}

/// Packs samples into fixed-size chunks (40 ms at 16 kHz by default).
public struct PCMChunker: Sendable {
    public let samplesPerChunk: Int
    private var pending: [Int16] = []

    public init(samplesPerChunk: Int = PCM.samplesPerChunk) {
        precondition(samplesPerChunk > 0, "A chunk has at least one sample")
        self.samplesPerChunk = samplesPerChunk
    }

    public var pendingCount: Int { pending.count }

    /// Whole chunks ready to send; the rest waits for more samples.
    public mutating func append(_ samples: [Int16]) -> [[Int16]] {
        pending.append(contentsOf: samples)
        var chunks: [[Int16]] = []
        while pending.count >= samplesPerChunk {
            chunks.append(Array(pending.prefix(samplesPerChunk)))
            pending.removeFirst(samplesPerChunk)
        }
        return chunks
    }

    /// What's left, as a short last chunk (nil when nothing is).
    public mutating func flush() -> [Int16]? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return pending
    }
}

/// One 40 ms mic chunk, ready for `realtimeInput.audio`, with its level for the meter and the
/// local end-of-speech timer.
public struct MicChunk: Equatable, Sendable {
    public let pcm: Data
    public let rms: Float

    public init(pcm: Data, rms: Float) {
        self.pcm = pcm
        self.rms = rms
    }

    public init(samples: [Int16]) {
        pcm = PCM.int16LE(samples)
        rms = PCM.rms(int16LE: pcm)
    }
}

/// Mic frames at the hardware rate in, 16 kHz PCM16 chunks out: resample, convert, chunk.
public struct MicPipeline: Sendable {
    private var resampler: LinearResampler
    private var chunker: PCMChunker

    public init(inputRate: Double, samplesPerChunk: Int = PCM.samplesPerChunk) {
        resampler = LinearResampler(inputRate: inputRate)
        chunker = PCMChunker(samplesPerChunk: samplesPerChunk)
    }

    public mutating func process(_ frame: [Float]) -> [MicChunk] {
        chunker.append(resampler.process(frame).map(PCM.int16)).map(MicChunk.init(samples:))
    }
}
