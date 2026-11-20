import Foundation

/// One line from Zeno. The server asks Gemini Flash for it with a response schema; the app only
/// ever shows a nudge that passed `validated()`, and falls back to `ZenoNudge.fallback` otherwise.
///
/// Rules decide *when* Zeno speaks; Gemini decides *what* it says.
public struct ZenoNudge: Codable, Equatable, Sendable {
    /// The feelings the schema allows. The notch maps them to Zeno's eight (see `notchFeeling`).
    public enum Feeling: String, Codable, CaseIterable, Sendable {
        case happy, pleasant, curious, sad
    }

    /// At most one action per nudge.
    public enum Action: String, Codable, CaseIterable, Sendable {
        case none
        case startFocus = "start_focus"
        case openReview = "open_review"
        case reactCircle = "react_circle"
    }

    public let feeling: Feeling
    public let line: String
    public let action: Action

    public init(feeling: Feeling, line: String, action: Action = .none) {
        self.feeling = feeling
        self.line = line
        self.action = action
    }

    /// The schema's limit on `line`, in characters.
    public static let maxLineLength = 40

    /// Shown whenever the live nudge fails, times out, or breaks a guardrail.
    public static let fallback = ZenoNudge(feeling: .pleasant, line: "Still here. Your day counts itself.")

    /// Zeno in the notch is never sad: a cost is information, not a punishment (Flow 04).
    public var notchFeeling: Feeling { feeling == .sad ? .pleasant : feeling }

    /// Checks the line against the guardrails the app can check on its own. The server checks
    /// the rest (kindness, no medical claims) before the line ever arrives.
    public func validated() throws(NudgeRejection) -> ZenoNudge {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.count <= Self.maxLineLength else { throw .tooLong(trimmed.count) }
        if Self.minutesPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            throw .mentionsMinutes
        }
        return ZenoNudge(feeling: feeling, line: trimmed, action: action)
    }

    /// "41 minutes", "3 h", "2 hrs": a nudge never quotes time spent.
    private static let minutesPattern = try! NSRegularExpression(
        pattern: #"\b\d+\s*(m|min|mins|minutes?|h|hr|hrs|hours?)\b"#, options: [.caseInsensitive])
}

public enum NudgeRejection: Error, Equatable, Sendable {
    case empty
    case tooLong(Int)
    case mentionsMinutes
}

/// What the server may send Gemini: outcomes only. Never minutes, apps or sessions.
public struct NudgeContext: Codable, Equatable, Sendable {
    public enum Trigger: String, Codable, Sendable {
        case pickup, goodDay = "good_day", checkIn = "check_in", hello
    }

    public let scoreTenths: Int
    public let goodDaysThisWeek: Int
    public let weeklyStreak: Int
    public let hourOfDay: Int
    public let trigger: Trigger

    public init(scoreTenths: Int, goodDaysThisWeek: Int, weeklyStreak: Int, hourOfDay: Int, trigger: Trigger) {
        self.scoreTenths = scoreTenths
        self.goodDaysThisWeek = goodDaysThisWeek
        self.weeklyStreak = weeklyStreak
        self.hourOfDay = hourOfDay
        self.trigger = trigger
    }
}

/// Where a shown nudge came from, so the UI can say "written by Gemini" honestly.
public enum NudgeSource: String, Sendable {
    case gemini, fallback
}

public protocol ZenoNudgeService: Sendable {
    func nudge(for context: NudgeContext) async throws -> ZenoNudge
    /// Who writes the lines this service returns. The live model is `.gemini` (the default);
    /// anything canned (fakes, the offline demo) says `.fallback`, so a line is never credited to Gemini
    /// when Gemini didn't write it.
    var source: NudgeSource { get }
}

extension ZenoNudgeService {
    public var source: NudgeSource { .gemini }
}

/// Wraps any nudge service with a timeout, validation and the fixed fallback, so callers always
/// get a line they can show.
public struct ResilientNudges: Sendable {
    private let service: any ZenoNudgeService
    private let timeout: Duration

    public init(_ service: any ZenoNudgeService, timeout: Duration = .seconds(4)) {
        self.service = service
        self.timeout = timeout
    }

    public func nudge(for context: NudgeContext) async -> (ZenoNudge, NudgeSource) {
        let service = self.service
        let timeout = self.timeout
        let live: ZenoNudge? = await withTaskGroup(of: ZenoNudge?.self) { group in
            group.addTask { try? await service.nudge(for: context).validated() }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let live { return (live, service.source) }
        return (.fallback, .fallback)
    }
}
