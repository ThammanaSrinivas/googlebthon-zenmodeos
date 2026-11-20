import AVFoundation
import Foundation
import Speech
import Testing
@testable import ZenMacApp

@Suite("“Hey Zeno”")
struct WakeWordTests {
    @Test("Zeno's name as a whole word, with how speech recognition spells it")
    func heard() {
        #expect(WakeWord.heard("Hey Zeno"))
        #expect(WakeWord.heard("hey, zeno, what's my score"))
        #expect(WakeWord.heard("Okay Xeno"))
        #expect(WakeWord.heard("hi zino"))
        #expect(WakeWord.heard("ZENO"))
    }

    @Test("Not ZenMode, not words that merely contain it")
    func notHeard() {
        #expect(!WakeWord.heard("open ZenMode OS"))
        #expect(!WakeWord.heard("xenophobia is a word"))
        #expect(!WakeWord.heard("zenodo"))
        #expect(!WakeWord.heard(""))
    }

    @Test("Only the live session counts: a cancelled one's late callback never restarts listening")
    func onlyTheLiveSession() {
        // The loop of 21 Nov: the 50 s restart cancels a session, its "ended" arrives late.
        #expect(WakeWord.reaction(to: "", done: true, live: false, listening: true) == .ignore)
        #expect(WakeWord.reaction(to: "hey zeno", done: true, live: false, listening: true) == .ignore)
        // The live session ending on its own starts a fresh one; its words can wake Zeno.
        #expect(WakeWord.reaction(to: "", done: true, live: true, listening: true) == .restart)
        #expect(WakeWord.reaction(to: "okay hey Zeno", done: false, live: true, listening: true) == .wake)
        #expect(WakeWord.reaction(to: "open ZenMode", done: false, live: true, listening: true) == .ignore)
        // Turned off: nothing.
        #expect(WakeWord.reaction(to: "hey zeno", done: true, live: true, listening: false) == .ignore)
    }

    // The crash of 21 Nov: allowing speech recognition called back on TCC's queue into a
    // main-actor-only closure, and Swift 6 trapped. Apple's three callbacks must run anywhere.
    @Test("The listener's callbacks run on Apple's own threads without trapping")
    func callbacksOffTheMainThread() async {
        let heard: (String, Bool) = await withCheckedContinuation { c in
            let deliver = WakeWordListener.onResult { text, done in c.resume(returning: (text, done)) }
            DispatchQueue.global().async { deliver(nil, NSError(domain: "test", code: 1)) }
        }
        #expect(heard.0.isEmpty && heard.1)

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        nonisolated(unsafe) let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        nonisolated(unsafe) let tap = WakeWordListener.feed(SFSpeechAudioBufferRecognitionRequest())
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { tap(buffer, AVAudioTime(hostTime: 0)); c.resume() }
        }
    }
}
