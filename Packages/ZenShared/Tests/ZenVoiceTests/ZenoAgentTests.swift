// Zeno's instruction and tool declarations, as data, and the language labels the notch shows.
import Foundation
import Testing
@testable import ZenVoice

@Suite("Zeno, the agent")
struct ZenoAgentTests {
    @Test("Seven tools, in the prototype's order, each an OBJECT schema")
    func declarations() {
        #expect(ZenoAgent.toolDeclarations.map(\.name) == ZenoAgent.ToolName.allCases.map(\.rawValue))
        #expect(ZenoAgent.toolDeclarations.count == 7)
        for declaration in ZenoAgent.toolDeclarations {
            #expect(declaration.parameters["type"] == "OBJECT")
            #expect(declaration.parameters["properties"]?.objectValue != nil)
            #expect(!declaration.description.isEmpty)
        }
    }

    @Test("Required arguments match the prototype")
    func required() {
        let required = Dictionary(uniqueKeysWithValues: ZenoAgent.toolDeclarations.map {
            ($0.name, $0.parameters["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        })
        #expect(required == [
            "get_zen_status": [], "set_intent": ["app", "minutes"], "end_session": [], "start_focus": ["minutes", "label"],
            "pause_app": ["app"], "log_reflection": ["summary", "mood", "language"], "share_with_circle": [],
        ])
    }

    @Test("A shared card can't ask for a score; moods match ZenCard's five")
    func privacyInTheSchema() {
        let share = ZenoAgent.toolDeclarations.first { $0.name == "share_with_circle" }!
        #expect(share.parameters["properties"]?["include_score"] == nil)
        let reflection = ZenoAgent.toolDeclarations.first { $0.name == "log_reflection" }!
        #expect(reflection.parameters["properties"]?["mood"]?["enum"] == ["happy", "pleasant", "neutral", "tired", "sad"])
    }

    @Test("The instruction names the person and the brand, and keeps the privacy promise")
    func instruction() {
        let text = ZenoAgent.systemInstruction(user: "Asha")
        #expect(text.hasPrefix("You are Zeno, the voice of ZenMode OS."))
        #expect(text.contains("Asha's calm friend"))
        #expect(text.contains("never a score next to their name"))
        for tool in ZenoAgent.ToolName.allCases { #expect(text.contains(tool.rawValue)) }
    }

    @Test("Defaults are among the listed models and voices")
    func defaults() {
        #expect(ZenoAgent.models.map(\.id).contains(ZenoAgent.defaultModel))
        #expect(ZenoAgent.voices.contains(ZenoAgent.defaultVoice))
        #expect(LiveEndpoint.modelPath("gemini-3.8-live") == "models/gemini-3.8-live")
    }
}

@Suite("Language labels")
struct LanguageLabelTests {
    @Test("Codes and scripts to the label beside a transcript", arguments: [
        ("ta-Latn", "", "Tanglish"), ("ta", "Insta-la rendu nimisham", "Tanglish"), ("ta-IN", "இன்னைக்கு வாக்கிங்", "Tamil"),
        ("hi-Latn", "", "Hinglish"), ("hi", "Mujhe focus chahiye", "Hinglish"), ("hi", "मुझे फोकस चाहिए", "Hindi"),
        ("en", "How's my day", "English"), ("en-IN", "", "English"), ("fr", "", "fr"),
    ])
    func labels(code: String, text: String, expected: String) {
        #expect(LanguageLabel.label(for: code, text: text) == expected)
    }

    @Test("No code, no label")
    func none() {
        #expect(LanguageLabel.label(for: nil) == nil)
        #expect(LanguageLabel.label(for: "") == nil)
    }
}
