// Display names and cohort names as typed: tidied, length-capped and checked by NamePolicy before
// they're sent, so the UI can say what's wrong right where it was typed.
import Foundation

public enum DisplayName {
    /// The longest display name the backend keeps.
    public static let maxDisplayNameLength = 40
    /// The longest cohort name the backend keeps.
    public static let maxCohortNameLength = 30
    /// What other people see when a person's name can't be shown.
    public static let fallback = "Zen friend"

    public enum Problem: Equatable, Sendable {
        case empty
        case tooLong(max: Int)
        case notAllowed(NameVerdict)
    }

    /// `name` with its ends trimmed and every run of whitespace (newlines included) as one space.
    public static func tidy(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// The tidied name, or why it can't be used. Length counts characters as people see them.
    public static func validate(_ name: String, maxLength: Int = maxDisplayNameLength) -> Result<String, Problem> {
        let tidied = tidy(name)
        if tidied.isEmpty { return .failure(.empty) }
        if tidied.count > maxLength { return .failure(.tooLong(max: maxLength)) }
        let verdict = NamePolicy.check(tidied)
        return verdict == .ok ? .success(tidied) : .failure(.notAllowed(verdict))
    }

    /// The name to show for another person: theirs when it may be shown, else `fallback`.
    public static func shown(_ name: String?) -> String {
        guard let name else { return fallback }
        let tidied = tidy(name)
        return tidied.isEmpty ? fallback : (NamePolicy.shown(tidied) ?? fallback)
    }

    /// A short message for a problem, for under the text field.
    public static func message(for problem: Problem) -> String {
        switch problem {
        case .empty: return "Type a name first."
        case .tooLong(let max): return "Keep it to \(max) characters."
        case .notAllowed(.contact): return "Names can't hold links, emails or phone numbers."
        case .notAllowed: return "Please pick a different name."
        }
    }
}

extension DisplayName.Problem: Error {}
