import Foundation

/// A six-character code for joining a cohort or pairing a device.
/// Letters and digits without the look-alikes (no 0/O, no 1/I), so a typed code can't be misread.
// TODO(buildathon): confirm length and alphabet against Srinivas's contract file.
public struct JoinCode: Hashable, Sendable, CustomStringConvertible {
    public static let length = 6
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public let value: String

    /// Accepts what people type: lower case, spaces, dashes and the middle dot are ignored.
    public init?(_ raw: String) {
        let cleaned = raw.uppercased().filter { !" -·.".contains($0) }
        guard cleaned.count == Self.length, cleaned.allSatisfy(Self.alphabet.contains) else { return nil }
        value = cleaned
    }

    /// Keeps only characters a code can contain, capped at the length. For live text fields.
    public static func sanitize(_ raw: String) -> String {
        String(raw.uppercased().filter(alphabet.contains).prefix(length))
    }

    /// "K4M·7QX": two groups of three, easier to read aloud.
    public var display: String { "\(value.prefix(3))·\(value.suffix(3))" }

    public var description: String { display }
}

/// What a code shows before you join: enough to know it's the right group.
public struct CohortPreview: Equatable, Sendable {
    public enum Kind: String, Sendable { case campus, team }

    public let id: String
    public let name: String
    public let organisation: String
    public let kind: Kind
    public let memberCount: Int

    public init(id: String, name: String, organisation: String, kind: Kind, memberCount: Int) {
        self.id = id
        self.name = name
        self.organisation = organisation
        self.kind = kind
        self.memberCount = memberCount
    }
}

/// A cohort as a member sees it. Aggregates only, and only for groups of 5 or more.
public struct CohortSummary: Equatable, Sendable {
    public static let minimumGroupSize = 5

    public let preview: CohortPreview
    /// nil while the group is under the minimum size: nobody can be singled out.
    public let score: ZenScore?
    /// Share of member-days above 6.0 this week, 0...1. nil under the minimum size.
    public let goodDayRate: Double?

    public init(preview: CohortPreview, score: ZenScore?, goodDayRate: Double?) {
        let big = preview.memberCount >= Self.minimumGroupSize
        self.preview = preview
        self.score = big ? score : nil
        self.goodDayRate = big ? goodDayRate : nil
    }
}

public enum CohortError: Error, Equatable, Sendable {
    case invalidCode, notFound, offline
}

public protocol CohortService: Sendable {
    func preview(code: JoinCode) async throws(CohortError) -> CohortPreview
    func join(code: JoinCode) async throws(CohortError) -> CohortSummary
}
