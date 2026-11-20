import Foundation

/// The label the notch shows beside a transcript: "Tanglish", "Hindi", "English" …
///
/// Gemini reports a BCP-47 code; code-switched speech written in Latin letters ("ta-Latn",
/// or "ta" with a transcript in Latin script) reads as Tanglish or Hinglish.
public enum LanguageLabel {
    static let names: [String: String] = [
        "ta": "Tamil", "hi": "Hindi", "en": "English", "te": "Telugu", "kn": "Kannada", "ml": "Malayalam",
        "mr": "Marathi", "bn": "Bengali", "gu": "Gujarati", "pa": "Punjabi", "ur": "Urdu", "or": "Odia",
    ]

    static let latinMixes: [String: String] = ["ta": "Tanglish", "hi": "Hinglish", "te": "Tenglish", "kn": "Kanglish"]

    public static func label(for code: String?, text: String = "") -> String? {
        guard let code, !code.isEmpty else { return nil }
        let parts = code.split(separator: "-").map(String.init)
        let language = parts[0].lowercased()
        let latinTag = parts.dropFirst().contains { $0.lowercased() == "latn" }
        if let mix = latinMixes[language], latinTag || (!text.isEmpty && isMostlyLatin(text)) { return mix }
        return names[language] ?? code
    }

    /// More Latin letters than other letters.
    static func isMostlyLatin(_ text: String) -> Bool {
        var latin = 0, other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if scalar.isASCII || (0x00C0...0x024F).contains(scalar.value) { latin += 1 } else { other += 1 }
        }
        return latin > other
    }
}
