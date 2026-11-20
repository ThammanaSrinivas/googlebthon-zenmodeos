import Foundation

/// Zeno, the agent: who it is, what it may do, and the tools it can call. Ported from the reference
/// prototype (zeno-voice/src/agent.js) with the product's privacy decisions (20 Nov 2026):
/// intents, focus and pauses run on this device; a shared Zen Card never carries a score.
///
/// The backend locks the model, this instruction and these declarations into the ephemeral token,
/// and the setup message the client sends must match them, so this file is the one copy the app
/// sends; the backend's copy must produce the same JSON (`ZenoAgent.setup(…)`).
public enum ZenoAgent {
    public struct Model: Equatable, Sendable {
        public let id: String
        public let label: String
    }

    public static let models: [Model] = [
        Model(id: "gemini-3.8-live", label: "Gemini 3.8 Live"),
        Model(id: "gemini-3.8-live-extended-thinking", label: "Gemini 3.8 Live · extended thinking"),
        Model(id: "gemini-3.1-flash-live-preview", label: "Gemini 3.1 Flash Live (preview)"),
        Model(id: "gemini-2.5-flash-native-audio-preview-12-2025", label: "Gemini 2.5 Flash native audio (preview)"),
    ]

    public static let defaultModel = "gemini-3.8-live"

    public static let voices = ["Kore", "Puck", "Aoede", "Charon", "Leda", "Orus", "Zephyr"]
    public static let defaultVoice = "Kore"

    /// How long a pause ends the user's turn, for the server's activity detection.
    public static let silenceDurationMs = 600

    /// What the app sends when the person picks up the phone (or taps the notch), so Zeno opens
    /// with its one question.
    public static let pickupCue = "The user just picked up the phone. Greet them by name in one short line and ask what they are here for."

    /// The question Zeno asks at a pickup, shown before the first audio arrives.
    public static let pickupQuestion = "What are you here for?"

    // MARK: - System instruction

    public static func systemInstruction(user: String) -> String {
        """
        You are Zeno, the voice of ZenMode OS. You live in the phone's notch and you are \(user)'s calm friend, not a coach and not a blocker.

        WHY YOU EXIST
        About half of all phone pickups happen out of habit, with no clear intent. You turn that reflex into a choice: when \(user) picks up the phone you ask what they are here for, listen, and act on it at once through your tools.

        LANGUAGE
        - Reply in the language and the mix the user just used. Tanglish gets Tanglish, Hinglish gets Hinglish, Tamil gets Tamil, Hindi gets Hindi, English gets English. Keep app names and numbers in English if the user did.
        - Understand Indian accents, code-switched sentences and half sentences. If a number is unclear, pick the most likely one and say it back.

        HOW YOU SPEAK
        - One or two short sentences, under 15 words where you can. Warm, plain, a little playful.
        - Never shame. Never say "you failed". A deduction is information. If the day went past the promise, say tomorrow starts fresh.
        - If the user interrupts or corrects you, stop, take the new value and act on that one.

        HOW YOU ACT
        - Every stated intent becomes a tool call before you confirm it. Do not just talk about it.
        - "I want to check / watch / reply ... for N minutes" -> set_intent(app, purpose, minutes). If no minutes were given, offer a short default (2 to 10) and set it.
        - "I need to focus / study / work" -> start_focus(minutes, label). It holds notifications and the named apps on this device.
        - "Stop me from opening X / put a pause on X" -> pause_app(app).
        - "How am I doing / what's my score" -> get_zen_status, then say the score with one decimal and one fact.
        - "I'm done" -> end_session.
        - An evening note about the day -> log_reflection with a one-line summary in the user's own language, what they earned back and any drift. Then offer to share the Zen Card with their circle, and call share_with_circle only if they say yes.
        - After a tool returns, confirm in one sentence using the returned numbers.

        PRIVACY
        Screen Time stays on the device, and so do intents, focus sessions and pauses. Never ask for app contents, messages or contacts. The circle only ever sees the Zen Cards the user chooses to share, never a score next to their name.
        """
    }

    // MARK: - Tools

    public enum ToolName: String, CaseIterable, Sendable {
        case getZenStatus = "get_zen_status"
        case setIntent = "set_intent"
        case endSession = "end_session"
        case startFocus = "start_focus"
        case pauseApp = "pause_app"
        case logReflection = "log_reflection"
        case shareWithCircle = "share_with_circle"
    }

    /// Zeno's seven tools, read from `zeno_voice_tools_v1.json`: the backend generates that file
    /// from the declarations it locks into every ephemeral token, and the private repo's
    /// check-vectors.sh keeps this copy byte-identical. One source, so the model and this app's
    /// toolbox always agree on names and arguments.
    public static let toolDeclarations: [LiveSetup.FunctionDeclaration] = {
        struct File: Decodable { let tools: [LiveSetup.FunctionDeclaration] }
        guard let url = Bundle.module.url(forResource: "zeno_voice_tools_v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            preconditionFailure("ZenVoice's bundled zeno_voice_tools_v1.json is missing or unreadable")
        }
        return file.tools
    }()

    // MARK: - Setup

    /// The setup message, as the prototype sends it, plus session resumption: audio replies in the
    /// token's voice, server-side activity detection where the user's speech interrupts Zeno, both
    /// transcriptions, a sliding context window, and resumption handles (pass `handle` to resume).
    public static func setup(model: String, voice: String, user: String, resumptionHandle: String? = nil) -> LiveSetup {
        LiveSetup(
            model: LiveEndpoint.modelPath(model),
            generationConfig: .init(responseModalities: ["AUDIO"], speechConfig: .init(voiceName: voice)),
            systemInstruction: .text(systemInstruction(user: user)),
            tools: [.init(functionDeclarations: toolDeclarations)],
            realtimeInputConfig: .init(
                automaticActivityDetection: .init(silenceDurationMs: silenceDurationMs),
                activityHandling: "START_OF_ACTIVITY_INTERRUPTS"),
            inputAudioTranscription: LiveEmpty(),
            outputAudioTranscription: LiveEmpty(),
            contextWindowCompression: .init(),
            sessionResumption: .init(handle: resumptionHandle))
    }
}
