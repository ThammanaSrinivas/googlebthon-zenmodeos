// Which names ZenMode OS shows to other people (App Store Guideline 1.2): cohort names and display
// names. Ported step for step from the ZenMode OS iOS core logic; the server applies the same
// matching, and both replay Tests/ZenLogicTests/Vectors/name_policy_v1.json.
import Foundation

public enum NameVerdict: String, Sendable {
    /// Show it.
    case ok
    /// It holds a listed word.
    case offensive
    /// A link, an email or a phone number, which a name never needs.
    case contact
}

public enum NamePolicy {
    // Written without \b, \w or \s: ICU and JavaScript read those differently, and both sides must give
    // the same verdict.
    private static let contact: [NSRegularExpression] = [
        "(https?://|www\\.|t\\.me/|wa\\.me/)",
        "[a-z0-9-]\\.(com|net|org|in|io|me|co|xyz|app|link|ly|gg)(?![a-z0-9])",
        "@[a-z0-9_-]+\\.[a-z]",
        "([0-9][ .-]?){10,}",
    ].map { try! NSRegularExpression(pattern: $0) }

    /// Characters people swap in for letters.
    private static let lookalikes: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "@": "a", "$": "s", "!": "i", "|": "i",
    ]

    private static let marks: Set<Unicode.GeneralCategory> = [.nonspacingMark, .spacingMark, .enclosingMark]
    private static let letters: Set<Unicode.GeneralCategory> = [
        .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
    ]

    /// The verdict on one name, as typed.
    public static func check(_ name: String) -> NameVerdict {
        let lower = name.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        if contact.contains(where: { $0.firstMatch(in: lower, range: range) != nil }) { return .contact }
        let found = nameWords(name)
        // "assss" is still "ass": a run of 3 or more of one letter counts as 2.
        if found.contains(where: { words.contains(squeeze($0, keeping: 2)) }) { return .offensive }
        // Spacing, dots and stretching don't hide a stem: "f.u.c.k", "fuuuck".
        let squeezed = squeeze(found.joined(), keeping: 1)
        return stems.contains(where: { squeezed.contains($0) }) ? .offensive : .ok
    }

    /// A name as other people may see it: the name itself, or nil when it can't be shown (the reader
    /// shows its own fallback).
    public static func shown(_ name: String?) -> String? {
        guard let name, check(name) == .ok else { return nil }
        return name
    }

    /// The name's words: lowercase, accents gone, look-alikes read as letters, split on anything that
    /// isn't a letter.
    static func nameWords(_ name: String) -> [String] {
        let folded = name.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !marks.contains($0.properties.generalCategory) }
            .map { lookalikes[$0] ?? $0 }
        var words: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in folded {
            if letters.contains(scalar.properties.generalCategory) {
                current.append(scalar)
            } else if !current.isEmpty {
                words.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
    }

    /// `text` with every run of one scalar cut to at most `keeping` of it.
    private static func squeeze(_ text: String, keeping: Int) -> String {
        var out = String.UnicodeScalarView()
        var last: Unicode.Scalar?
        var run = 0
        for scalar in text.unicodeScalars {
            run = scalar == last ? run + 1 : 1
            last = scalar
            if run <= keeping { out.append(scalar) }
        }
        return String(out)
    }
}
