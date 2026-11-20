import Foundation

/// A Zen Card: the evening note Zeno turns into something the person can share with their circle.
///
/// Privacy (founders, 20 Nov 2026): a card carries the note, a mood and the language it was spoken
/// in. It never carries a score, so a shared card never puts a number next to a name; the backend
/// adds the sharer's display name when it shows the card to the circle.
public struct ZenCard: Codable, Equatable, Sendable, Identifiable {
    public enum Mood: String, Codable, CaseIterable, Sendable {
        case happy, pleasant, neutral, tired, sad
    }

    public let id: String
    /// One line in the person's own language and script.
    public let summary: String
    public let mood: Mood
    /// BCP-47, e.g. "ta", "hi-Latn" (Hinglish), "en-IN".
    public let language: String
    /// What they earned back today, in a few words.
    public let earnedBack: String?
    /// Where time slipped, if they said so.
    public let drift: String?
    public let createdAt: Date
    /// When it was shared with the circle; nil while it is private.
    public let sharedAt: Date?

    public init(id: String, summary: String, mood: Mood, language: String, earnedBack: String? = nil,
                drift: String? = nil, createdAt: Date, sharedAt: Date? = nil) {
        self.id = id
        self.summary = summary
        self.mood = mood
        self.language = language
        self.earnedBack = earnedBack
        self.drift = drift
        self.createdAt = createdAt
        self.sharedAt = sharedAt
    }

    public var isShared: Bool { sharedAt != nil }

    /// The same card, shared at `date`.
    public func shared(at date: Date) -> ZenCard {
        ZenCard(id: id, summary: summary, mood: mood, language: language, earnedBack: earnedBack, drift: drift,
                createdAt: createdAt, sharedAt: date)
    }
}

/// What the app asks the backend to save. The initialiser trims and caps every field, so a draft is
/// always within the limits the backend enforces too.
public struct ZenCardDraft: Codable, Equatable, Sendable {
    // The backend's limits (it is the source; these match it exactly).
    public static let maxSummaryLength = 280
    public static let maxEarnedBackLength = 40
    public static let maxDriftLength = 80
    /// The note sent with a share.
    public static let maxNoteLength = 120
    /// The language when the given one isn't a BCP-47 tag: "undetermined".
    public static let unknownLanguage = "und"

    public let summary: String
    public let mood: ZenCard.Mood
    public let language: String
    public let earnedBack: String?
    public let drift: String?

    public init(summary: String, mood: ZenCard.Mood, language: String, earnedBack: String? = nil, drift: String? = nil) {
        self.summary = Self.clip(summary, Self.maxSummaryLength) ?? ""
        self.mood = mood
        self.language = Self.isLanguageTag(language) ? language.trimmingCharacters(in: .whitespaces) : Self.unknownLanguage
        self.earnedBack = Self.clip(earnedBack, Self.maxEarnedBackLength)
        self.drift = Self.clip(drift, Self.maxDriftLength)
    }

    /// Trimmed, capped, and trimmed again where the cut fell; nil when nothing is left.
    public static func clip(_ text: String?, _ limit: Int) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A plausible BCP-47 tag: a 2–3 letter language, then 1–8 character subtags ("ta", "hi-Latn", "en-IN").
    public static func isLanguageTag(_ tag: String) -> Bool {
        let parts = tag.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, (2...3).contains(first.count), first.allSatisfy(\.isASCIILetter) else { return false }
        return parts.dropFirst().allSatisfy { (1...8).contains($0.count) && $0.allSatisfy(\.isASCIIAlphanumeric) }
    }
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
}

/// Saves and shares Zen Cards. The real one is the backend; ZenMock's `FakeZenCards` keeps them in memory.
public protocol ZenCardService: Sendable {
    /// Saves a private card and returns it with its id and creation time.
    func save(_ draft: ZenCardDraft) async throws -> ZenCard
    /// Shares a saved card with the person's circle, with an optional short note.
    func share(cardId: String, note: String?) async throws -> ZenCard
    /// The person's latest cards, newest first.
    func recent() async throws -> [ZenCard]
}
