// The audio maths that runs on every mic frame and every reply: PCM16 conversion, the streaming
// resampler (with its low-pass), 40 ms chunking.
import Foundation
import Testing
@testable import ZenVoice

@Suite("PCM maths")
struct PCMTests {
    @Test("Floats to PCM16 the way the worklet writes them", arguments: [
        (Float(1), Int16.max), (-1, Int16.min), (0, 0), (0.5, 16_383), (-0.5, -16_384), (2, Int16.max), (-7, Int16.min),
        (.nan, 0),
    ] as [(Float, Int16)])
    func toInt16(sample: Float, expected: Int16) {
        #expect(PCM.int16(sample) == expected)
    }

    @Test("Little-endian bytes, both ways")
    func littleEndian() {
        let data = PCM.int16LE([Int16(1), -2, Int16.max, Int16.min])
        #expect([UInt8](data) == [0x01, 0x00, 0xFE, 0xFF, 0xFF, 0x7F, 0x00, 0x80])
        #expect(PCM.int16Samples(data) == [1, -2, Int16.max, Int16.min])
        #expect(PCM.int16Samples(data + Data([0x05])) == [1, -2, Int16.max, Int16.min]) // odd byte dropped
    }

    @Test("24 kHz replies become floats for playback (sample / 32768)")
    func toFloats() {
        #expect(PCM.floats(PCM.int16LE([Int16(16_384), Int16.min, 0])) == [0.5, -1, 0])
    }

    @Test("Durations and levels")
    func durationAndRMS() {
        #expect(PCM.durationMs(bytes: 1_280, rate: 16_000) == 40)
        #expect(PCM.durationMs(bytes: 4_800, rate: 24_000) == 100)
        #expect(PCM.rms([]) == 0)
        #expect(abs(PCM.rms([0.5, -0.5, 0.5, -0.5]) - 0.5) < 1e-6)
        #expect(MicChunk(samples: Array(repeating: 0, count: 640)).rms == 0)
        #expect(abs(MicChunk(samples: [16_384, -16_384]).rms - 0.5) < 1e-6)
    }

    @Test("48 kHz → 16 kHz keeps a third of the samples")
    func ratio() {
        var resampler = LinearResampler(inputRate: 48_000)
        let output = resampler.process(Array(repeating: 0.25, count: 4_800))
        #expect(output.count == 1_600)
    }

    @Test("Frames of any size join without a seam (same output as one big frame)")
    func streaming() {
        let input = (0..<4_410).map { Float(sin(Double($0) * 0.05)) }
        var whole = LinearResampler(inputRate: 44_100)
        let expected = whole.process(input)
        var pieces = LinearResampler(inputRate: 44_100)
        var output: [Float] = []
        var index = 0
        for size in [128, 1, 333, 1_024, 7, 2_917] where index < input.count {
            let end = min(index + size, input.count)
            output += pieces.process(Array(input[index..<end]))
            index = end
        }
        #expect(output.count == expected.count)
        #expect(zip(output, expected).allSatisfy { abs($0 - $1) < 1e-5 })
        #expect(abs(Double(output.count) - Double(input.count) * 16_000 / 44_100) <= 1)
    }

    @Test("At the same rate it passes samples through, one frame behind at the seams")
    func passThrough() {
        var resampler = LinearResampler(inputRate: 16_000)
        let first = resampler.process([1, 2, 3, 4].map { Float($0) / 10 })
        let second = resampler.process([5, 6].map { Float($0) / 10 })
        #expect(first + second == [1, 2, 3, 4, 5].map { Float($0) / 10 })
    }

    @Test("A steady level stays steady")
    func dc() {
        var resampler = LinearResampler(inputRate: 48_000)
        let output = resampler.process(Array(repeating: 0.5, count: 960))
        #expect(output.dropFirst(2).allSatisfy { abs($0 - 0.5) < 1e-6 })
    }

    @Test("Speech-band tones pass; tones above 8 kHz are held back instead of folding into speech")
    func antiAlias() {
        func tone(_ hz: Double, count: Int = 4_800) -> [Float] {
            (0..<count).map { Float(sin(2 * .pi * hz * Double($0) / 48_000)) }
        }
        var speech = LinearResampler(inputRate: 48_000)
        #expect(PCM.rms(speech.process(tone(1_000))) > 0.65)

        var filtered = LinearResampler(inputRate: 48_000)
        var raw = LinearResampler(inputRate: 48_000, antiAlias: false)
        let high = tone(12_000)
        let withFilter = PCM.rms(filtered.process(high))
        let without = PCM.rms(raw.process(high))
        #expect(without > 0.6)
        #expect(withFilter < 0.4 * without)
    }

    @Test("Chunks are 640 samples (40 ms at 16 kHz); the rest waits")
    func chunking() {
        var chunker = PCMChunker()
        #expect(chunker.append(Array(repeating: 1, count: 1_000)).map(\.count) == [640])
        #expect(chunker.pendingCount == 360)
        #expect(chunker.append(Array(repeating: 2, count: 280)).map(\.count) == [640])
        #expect(chunker.pendingCount == 0)
        #expect(chunker.append([3, 3]).isEmpty)
        #expect(chunker.flush() == [3, 3])
        #expect(chunker.flush() == nil)
    }

    @Test("The mic pipeline turns 48 kHz frames into 1,280-byte chunks")
    func pipeline() {
        var pipeline = MicPipeline(inputRate: 48_000)
        var chunks: [MicChunk] = []
        for _ in 0..<10 { chunks += pipeline.process(Array(repeating: 0.1, count: 480)) } // ten 10 ms frames
        #expect(chunks.count == 2)
        #expect(chunks.allSatisfy { $0.pcm.count == 1_280 })
        #expect(abs(chunks[1].rms - 0.1) < 1e-3)
    }

    @Test("A blob's bytes survive base64 and its rate parses")
    func blob() {
        let pcm = PCM.int16LE([Int16(-1), 2, 300])
        let blob = LiveBlob(mimeType: "audio/pcm;rate=24000", bytes: pcm)
        #expect(blob.bytes == pcm)
        #expect(blob.sampleRate == 24_000)
        #expect(LiveBlob(mimeType: "audio/pcm", data: "").sampleRate == nil)
        #expect(LiveBlob(mimeType: "image/png", data: "").isAudio == false)
    }
}
