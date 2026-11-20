// Zeno Voice's contract: Live tokens and Zen Cards (limits, language tags, no score anywhere).
import Foundation
import Testing
@testable import ZenAPI

@Suite("Zeno Voice contract")
struct VoiceContractTests {
    @Test("A Live token opens a session until connectBy and lasts until expiresAt")
    func tokenDates() {
        let now = Date(timeIntervalSince1970: 1_795_192_320)
        let token = LiveToken(token: "t", model: "gemini-3.8-live", voice: "Kore",
                              expiresAt: now.addingTimeInterval(1_800), connectBy: now.addingTimeInterval(60))
        #expect(token.canConnect(at: now.addingTimeInterval(59)))
        #expect(!token.canConnect(at: now.addingTimeInterval(60)))
        #expect(!token.isExpired(at: now.addingTimeInterval(60)))
        #expect(token.isExpired(at: now.addingTimeInterval(1_800)))
        // A connect-by after the end makes no sense: it is held to the end.
        let odd = LiveToken(token: "t", model: "m", voice: "v", expiresAt: now, connectBy: now.addingTimeInterval(60))
        #expect(odd.connectBy == now)
    }

    @Test("The token decodes from the backend's JSON")
    func tokenJSON() throws {
        let json = #"{"token":"auth_tokens/x","model":"gemini-3.8-live","voice":"Kore","expiresAt":1800,"connectBy":60}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let token = try decoder.decode(LiveToken.self, from: Data(json.utf8))
        #expect(token.connectBy == Date(timeIntervalSince1970: 60))
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1_800))
    }

    @Test("A draft trims and caps every field")
    func draftLimits() {
        #expect(ZenCardDraft.maxSummaryLength == 280 && ZenCardDraft.maxNoteLength == 120)
        #expect(ZenCardDraft.maxEarnedBackLength == 40 && ZenCardDraft.maxDriftLength == 80)
        let draft = ZenCardDraft(summary: "  " + String(repeating: "a", count: 300) + "  ", mood: .tired, language: " hi-Latn ",
                                 earnedBack: "A phone-free dinner, and a long walk by the lake", drift: "   ")
        #expect(draft.summary.count == ZenCardDraft.maxSummaryLength)
        #expect(draft.language == "hi-Latn")
        #expect(draft.earnedBack == "A phone-free dinner, and a long walk by")
        #expect(draft.drift == nil)
    }

    @Test("BCP-47 tags", arguments: [
        ("ta", true), ("hi-Latn", true), ("en-IN", true), ("ta-Latn-IN", true), ("fil", true),
        ("", false), ("t", false), ("tamil", false), ("ta_IN", false), ("ta-", false), ("த", false), ("en-toolongsubtag", false),
    ])
    func languageTags(tag: String, valid: Bool) {
        #expect(ZenCardDraft.isLanguageTag(tag) == valid)
        #expect(ZenCardDraft(summary: "x", mood: .happy, language: tag).language == (valid ? tag : "und"))
    }

    @Test("A card round-trips through JSON and has no score field")
    func cardCoding() throws {
        let card = ZenCard(id: "c1", summary: "Walked", mood: .happy, language: "ta", earnedBack: "A walk",
                           createdAt: Date(timeIntervalSince1970: 1_000))
        let shared = card.shared(at: Date(timeIntervalSince1970: 2_000))
        #expect(shared.isShared && !card.isShared)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(shared)
        #expect(try JSONDecoder().decode(ZenCard.self, from: data) == shared)
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["createdAt", "earnedBack", "id", "language", "mood", "sharedAt", "summary"])
    }

    @Test("Moods are exactly the five the agent may say")
    func moods() {
        #expect(ZenCard.Mood.allCases.map(\.rawValue) == ["happy", "pleasant", "neutral", "tired", "sad"])
    }
}
