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
}
