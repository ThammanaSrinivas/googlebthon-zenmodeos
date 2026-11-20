import Foundation
import ZenAPI

/// Hands out demo Live tokens shaped like the backend's (connect within a minute, a 30-minute
/// session). They open nothing on Gemini: use them with the scripted replay (ZenVoice's
/// `ScriptedLiveTransport`), or set `failure` to show the error states.
public struct FakeVoiceTokens: VoiceTokenService {
    public static let demoToken = "demo-live-token"
    public static let connectWindow: TimeInterval = 60
    public static let sessionLifetime: TimeInterval = 30 * 60

    private let failure: VoiceError?
    private let now: @Sendable () -> Date

    public init(failure: VoiceError? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.failure = failure
        self.now = now
    }

    public func liveToken() async throws(VoiceError) -> LiveToken {
        if let failure { throw failure }
        let minted = now()
        return LiveToken(token: Self.demoToken, model: "gemini-3.8-live", voice: "Kore",
                         expiresAt: minted.addingTimeInterval(Self.sessionLifetime),
                         connectBy: minted.addingTimeInterval(Self.connectWindow))
    }
}

/// Zen Cards in memory, newest first. Copies share their cards, like the real backend.
public struct FakeZenCards: ZenCardService {
    public enum Failure: Error, Equatable, Sendable { case notFound, offline }

    private let store = CardStore()
    private let failing: Bool
    private let now: @Sendable () -> Date

    public init(failing: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.failing = failing
        self.now = now
    }

    public func save(_ draft: ZenCardDraft) async throws -> ZenCard {
        if failing { throw Failure.offline }
        return store.save(draft, at: now())
    }

    public func share(cardId: String, note: String?) async throws -> ZenCard {
        if failing { throw Failure.offline }
        guard let card = store.share(id: cardId, note: ZenCardDraft.clip(note, ZenCardDraft.maxNoteLength), at: now()) else {
            throw Failure.notFound
        }
        return card
    }

    public func recent() async throws -> [ZenCard] {
        if failing { throw Failure.offline }
        return store.all()
    }

    /// The note sent with each share, by card id (for tests and the demo UI).
    public var notes: [String: String] { store.notes() }
}

final class CardStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cards: [ZenCard] = []
    private var sharedNotes: [String: String] = [:]

    func save(_ draft: ZenCardDraft, at date: Date) -> ZenCard {
        lock.withLock {
            let card = ZenCard(id: "card-\(cards.count + 1)", summary: draft.summary, mood: draft.mood,
                               language: draft.language, earnedBack: draft.earnedBack, drift: draft.drift, createdAt: date)
            cards.insert(card, at: 0)
            return card
        }
    }

    func share(id: String, note: String?, at date: Date) -> ZenCard? {
        lock.withLock {
            guard let index = cards.firstIndex(where: { $0.id == id }) else { return nil }
            let shared = cards[index].isShared ? cards[index] : cards[index].shared(at: date)
            cards[index] = shared
            if let note { sharedNotes[id] = note }
            return shared
        }
    }

    func all() -> [ZenCard] { lock.withLock { cards } }

    func notes() -> [String: String] { lock.withLock { sharedNotes } }
}
