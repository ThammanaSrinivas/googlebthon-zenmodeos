// The Zeno Voice fakes: demo tokens and in-memory Zen Cards.
import Foundation
import Testing
import ZenAPI
@testable import ZenMock

@Suite("Zeno Voice fakes")
struct FakeVoiceTests {
    @Test("Demo tokens: connect within a minute, a 30-minute session; a failure is thrown as given")
    func tokens() async throws {
        let now = Date(timeIntervalSince1970: 1_795_192_320)
        let token = try await FakeVoiceTokens(now: { now }).liveToken()
        #expect(token.token == FakeVoiceTokens.demoToken)
        #expect(token.connectBy == now.addingTimeInterval(60))
        #expect(token.expiresAt == now.addingTimeInterval(30 * 60))
        await #expect(throws: VoiceError.signedOut) { try await FakeVoiceTokens(failure: .signedOut).liveToken() }
    }

    @Test("A share note is capped at the backend's 120 characters")
    func noteLimit() async throws {
        let cards = FakeZenCards()
        let card = try await cards.save(ZenCardDraft(summary: "One", mood: .happy, language: "en"))
        _ = try await cards.share(cardId: card.id, note: String(repeating: "n", count: 200))
        #expect(cards.notes[card.id]?.count == 120)
    }

    @Test("Cards save newest first, share once, keep the note; copies see the same cards")
    func cards() async throws {
        let cards = FakeZenCards(now: { Date(timeIntervalSince1970: 10) })
        let first = try await cards.save(ZenCardDraft(summary: "One", mood: .happy, language: "en"))
        let second = try await cards.save(ZenCardDraft(summary: "Two", mood: .tired, language: "ta"))
        #expect(try await cards.recent().map(\.id) == [second.id, first.id])
        let shared = try await cards.share(cardId: first.id, note: "  Phone-free dinner  ")
        #expect(shared.sharedAt == Date(timeIntervalSince1970: 10))
        #expect(cards.notes == [first.id: "Phone-free dinner"])
        let copy = cards
        #expect(try await copy.recent().first { $0.id == first.id }?.isShared == true)
        await #expect(throws: FakeZenCards.Failure.notFound) { try await cards.share(cardId: "nope", note: nil) }
    }

    @Test("A failing card service fails every call")
    func failing() async {
        let cards = FakeZenCards(failing: true)
        await #expect(throws: FakeZenCards.Failure.offline) { try await cards.save(ZenCardDraft(summary: "x", mood: .happy, language: "en")) }
        await #expect(throws: FakeZenCards.Failure.offline) { try await cards.recent() }
    }
}
