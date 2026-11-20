import Foundation

// The Gemini Live API wire protocol (WebSocket, JSON frames), the subset Zeno uses.
//
// Field names follow the API reference, checked on 20 Nov 2026:
//   https://ai.google.dev/api/live  (now redirects to https://aistudio.google.com/api-reference/live)
//   https://ai.google.dev/gemini-api/docs/live-guide  (→ aistudio.google.com/docs/live-api/capabilities)
// and the reference prototype's client (zeno-voice/src/live.js). Every optional field is left out of
// the JSON when nil, so a message carries only what we set. Unknown server fields are ignored.

/// Where Live sessions connect.
public enum LiveEndpoint {
    public static let host = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService"

    /// The constrained endpoint for an ephemeral token: `…BidiGenerateContentConstrained?access_token=…`.
    public static func constrainedURL(token: String, host: String = host) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
        return URL(string: "\(host).BidiGenerateContentConstrained?access_token=\(encoded)")!
    }

    /// "models/gemini-3.8-live" from "gemini-3.8-live" or "models/gemini-3.8-live".
    public static func modelPath(_ model: String) -> String {
        model.hasPrefix("models/") ? model : "models/\(model)"
    }
}

/// Input audio: 16-bit little-endian PCM, mono, 16 kHz.
public let liveInputMimeType = "audio/pcm;rate=16000"
/// Output audio arrives as 16-bit little-endian PCM, mono, 24 kHz.
public let liveOutputSampleRate = 24_000

// MARK: - Shared shapes

/// `{}`: an empty object (e.g. `inputAudioTranscription: {}`, `setupComplete: {}`).
public struct LiveEmpty: Codable, Equatable, Sendable {
    public init() {}
}

/// Inline bytes, base64 in JSON.
public struct LiveBlob: Codable, Equatable, Sendable {
    public let mimeType: String
    public let data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }

    public init(mimeType: String, bytes: Data) {
        self.init(mimeType: mimeType, data: bytes.base64EncodedString())
    }

    public var bytes: Data? { Data(base64Encoded: data) }

    /// The sample rate in a mime type such as "audio/pcm;rate=24000", if there is one.
    public var sampleRate: Int? {
        for parameter in mimeType.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0] == "rate" { return Int(pair[1]) }
        }
        return nil
    }

    public var isAudio: Bool { mimeType.hasPrefix("audio/") }
}

public struct LivePart: Codable, Equatable, Sendable {
    public var text: String?
    public var inlineData: LiveBlob?
    /// A thought summary from a thinking model: never spoken, never shown.
    public var thought: Bool?

    public init(text: String? = nil, inlineData: LiveBlob? = nil, thought: Bool? = nil) {
        self.text = text
        self.inlineData = inlineData
        self.thought = thought
    }
}

public struct LiveContent: Codable, Equatable, Sendable {
    public var role: String?
    public var parts: [LivePart]

    public init(role: String? = nil, parts: [LivePart]) {
        self.role = role
        self.parts = parts
    }

    public static func text(_ text: String, role: String? = nil) -> LiveContent {
        LiveContent(role: role, parts: [LivePart(text: text)])
    }
}

// MARK: - Client → server

public struct LiveSetup: Codable, Equatable, Sendable {
    public struct GenerationConfig: Codable, Equatable, Sendable {
        public var responseModalities: [String]
        public var speechConfig: SpeechConfig?

        public init(responseModalities: [String], speechConfig: SpeechConfig? = nil) {
            self.responseModalities = responseModalities
            self.speechConfig = speechConfig
        }
    }

    public struct SpeechConfig: Codable, Equatable, Sendable {
        public struct VoiceConfig: Codable, Equatable, Sendable {
            public var prebuiltVoiceConfig: PrebuiltVoiceConfig
        }
        public struct PrebuiltVoiceConfig: Codable, Equatable, Sendable {
            public var voiceName: String
        }

        public var voiceConfig: VoiceConfig

        public init(voiceName: String) {
            voiceConfig = VoiceConfig(prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: voiceName))
        }
    }

    public struct Tool: Codable, Equatable, Sendable {
        public var functionDeclarations: [FunctionDeclaration]

        public init(functionDeclarations: [FunctionDeclaration]) { self.functionDeclarations = functionDeclarations }
    }

    public struct FunctionDeclaration: Codable, Equatable, Sendable {
        public var name: String
        public var description: String
        /// An OpenAPI-style schema, as the API's `Schema` (types in upper case: OBJECT, STRING …).
        public var parameters: JSONValue

        public init(name: String, description: String, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public struct RealtimeInputConfig: Codable, Equatable, Sendable {
        public var automaticActivityDetection: AutomaticActivityDetection?
        /// `START_OF_ACTIVITY_INTERRUPTS` (barge-in) or `NO_INTERRUPTION`.
        public var activityHandling: String?
        /// `TURN_INCLUDES_ONLY_ACTIVITY`, `TURN_INCLUDES_ALL_INPUT` …; left to the server's default.
        public var turnCoverage: String?

        public init(automaticActivityDetection: AutomaticActivityDetection? = nil, activityHandling: String? = nil,
                    turnCoverage: String? = nil) {
            self.automaticActivityDetection = automaticActivityDetection
            self.activityHandling = activityHandling
            self.turnCoverage = turnCoverage
        }
    }

    public struct AutomaticActivityDetection: Codable, Equatable, Sendable {
        public var disabled: Bool?
        /// `START_SENSITIVITY_HIGH` / `START_SENSITIVITY_LOW`.
        public var startOfSpeechSensitivity: String?
        /// `END_SENSITIVITY_HIGH` / `END_SENSITIVITY_LOW`.
        public var endOfSpeechSensitivity: String?
        public var prefixPaddingMs: Int?
        public var silenceDurationMs: Int?

        public init(disabled: Bool? = nil, startOfSpeechSensitivity: String? = nil, endOfSpeechSensitivity: String? = nil,
                    prefixPaddingMs: Int? = nil, silenceDurationMs: Int? = nil) {
            self.disabled = disabled
            self.startOfSpeechSensitivity = startOfSpeechSensitivity
            self.endOfSpeechSensitivity = endOfSpeechSensitivity
            self.prefixPaddingMs = prefixPaddingMs
            self.silenceDurationMs = silenceDurationMs
        }
    }

    public struct ContextWindowCompression: Codable, Equatable, Sendable {
        public struct SlidingWindow: Codable, Equatable, Sendable {
            public var targetTokens: Int?
            public init(targetTokens: Int? = nil) { self.targetTokens = targetTokens }
        }

        public var slidingWindow: SlidingWindow
        public var triggerTokens: Int?

        public init(slidingWindow: SlidingWindow = SlidingWindow(), triggerTokens: Int? = nil) {
            self.slidingWindow = slidingWindow
            self.triggerTokens = triggerTokens
        }
    }

    /// `{}` asks the server for resumption handles; `{handle}` resumes an earlier session.
    public struct SessionResumption: Codable, Equatable, Sendable {
        public var handle: String?
        public init(handle: String? = nil) { self.handle = handle }
    }

    public var model: String
    public var generationConfig: GenerationConfig?
    public var systemInstruction: LiveContent?
    public var tools: [Tool]?
    public var realtimeInputConfig: RealtimeInputConfig?
    public var inputAudioTranscription: LiveEmpty?
    public var outputAudioTranscription: LiveEmpty?
    public var contextWindowCompression: ContextWindowCompression?
    public var sessionResumption: SessionResumption?

    public init(model: String, generationConfig: GenerationConfig? = nil, systemInstruction: LiveContent? = nil,
                tools: [Tool]? = nil, realtimeInputConfig: RealtimeInputConfig? = nil,
                inputAudioTranscription: LiveEmpty? = nil, outputAudioTranscription: LiveEmpty? = nil,
                contextWindowCompression: ContextWindowCompression? = nil, sessionResumption: SessionResumption? = nil) {
        self.model = model
        self.generationConfig = generationConfig
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.realtimeInputConfig = realtimeInputConfig
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
        self.contextWindowCompression = contextWindowCompression
        self.sessionResumption = sessionResumption
    }
}

public struct LiveRealtimeInput: Codable, Equatable, Sendable {
    public var audio: LiveBlob?
    /// Sent when the mic stops (mute, end of session), so the server flushes its activity detection.
    public var audioStreamEnd: Bool?
    public var text: String?

    public init(audio: LiveBlob? = nil, audioStreamEnd: Bool? = nil, text: String? = nil) {
        self.audio = audio
        self.audioStreamEnd = audioStreamEnd
        self.text = text
    }
}

public struct LiveClientContent: Codable, Equatable, Sendable {
    public var turns: [LiveContent]
    public var turnComplete: Bool

    public init(turns: [LiveContent], turnComplete: Bool) {
        self.turns = turns
        self.turnComplete = turnComplete
    }
}

public struct LiveFunctionResponse: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    /// What the tool returned. Zeno wraps it as `{"result": …}`, as the prototype does.
    public var response: JSONValue
    /// For non-blocking calls only: `SILENT`, `WHEN_IDLE` or `INTERRUPT`. Unset for Zeno's tools.
    public var scheduling: String?

    public init(id: String?, name: String, response: JSONValue, scheduling: String? = nil) {
        self.id = id
        self.name = name
        self.response = response
        self.scheduling = scheduling
    }
}

public struct LiveToolResponse: Codable, Equatable, Sendable {
    public var functionResponses: [LiveFunctionResponse]

    public init(functionResponses: [LiveFunctionResponse]) { self.functionResponses = functionResponses }
}

/// One frame the client sends: exactly one of these keys at the top level.
public enum LiveClientMessage: Codable, Equatable, Sendable {
    case setup(LiveSetup)
    case realtimeInput(LiveRealtimeInput)
    case clientContent(LiveClientContent)
    case toolResponse(LiveToolResponse)

    private enum CodingKeys: String, CodingKey { case setup, realtimeInput, clientContent, toolResponse }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setup(let value): try container.encode(value, forKey: .setup)
        case .realtimeInput(let value): try container.encode(value, forKey: .realtimeInput)
        case .clientContent(let value): try container.encode(value, forKey: .clientContent)
        case .toolResponse(let value): try container.encode(value, forKey: .toolResponse)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(LiveSetup.self, forKey: .setup) { self = .setup(value) }
        else if let value = try container.decodeIfPresent(LiveRealtimeInput.self, forKey: .realtimeInput) { self = .realtimeInput(value) }
        else if let value = try container.decodeIfPresent(LiveClientContent.self, forKey: .clientContent) { self = .clientContent(value) }
        else if let value = try container.decodeIfPresent(LiveToolResponse.self, forKey: .toolResponse) { self = .toolResponse(value) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a Live client message")) }
    }

    /// The frame as compact JSON text with sorted keys.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func parse(_ text: String) throws -> LiveClientMessage {
        try JSONDecoder().decode(LiveClientMessage.self, from: Data(text.utf8))
    }

    // Shorthands for the frames Zeno sends.

    /// 16 kHz PCM16 from the mic.
    public static func audio(_ pcm16k: Data) -> LiveClientMessage {
        .realtimeInput(LiveRealtimeInput(audio: LiveBlob(mimeType: liveInputMimeType, bytes: pcm16k)))
    }

    public static let audioStreamEnd = LiveClientMessage.realtimeInput(LiveRealtimeInput(audioStreamEnd: true))

    /// A complete user turn in text (the pickup cue, or typed text).
    public static func userText(_ text: String) -> LiveClientMessage {
        .clientContent(LiveClientContent(turns: [.text(text, role: "user")], turnComplete: true))
    }
}

// MARK: - Server → client

public struct LiveTranscription: Codable, Equatable, Sendable {
    public var text: String?
    /// BCP-47 of what was heard (input) or spoken (output), when the server says.
    public var languageCode: String?

    public init(text: String? = nil, languageCode: String? = nil) {
        self.text = text
        self.languageCode = languageCode
    }
}

public struct LiveServerContent: Codable, Equatable, Sendable {
    public var modelTurn: LiveContent?
    public var turnComplete: Bool?
    /// The user started speaking over Zeno: stop playback now and drop what's queued.
    public var interrupted: Bool?
    public var generationComplete: Bool?
    public var inputTranscription: LiveTranscription?
    public var outputTranscription: LiveTranscription?
    public var waitingForInput: Bool?

    public init(modelTurn: LiveContent? = nil, turnComplete: Bool? = nil, interrupted: Bool? = nil,
                generationComplete: Bool? = nil, inputTranscription: LiveTranscription? = nil,
                outputTranscription: LiveTranscription? = nil, waitingForInput: Bool? = nil) {
        self.modelTurn = modelTurn
        self.turnComplete = turnComplete
        self.interrupted = interrupted
        self.generationComplete = generationComplete
        self.inputTranscription = inputTranscription
        self.outputTranscription = outputTranscription
        self.waitingForInput = waitingForInput
    }
}

public struct LiveFunctionCall: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var args: JSONValue?

    public init(id: String?, name: String, args: JSONValue? = nil) {
        self.id = id
        self.name = name
        self.args = args
    }
}

public struct LiveToolCall: Codable, Equatable, Sendable {
    public var functionCalls: [LiveFunctionCall]

    public init(functionCalls: [LiveFunctionCall]) { self.functionCalls = functionCalls }

    private enum CodingKeys: String, CodingKey { case functionCalls }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        functionCalls = try container.decodeIfPresent([LiveFunctionCall].self, forKey: .functionCalls) ?? []
    }
}

public struct LiveToolCallCancellation: Codable, Equatable, Sendable {
    public var ids: [String]

    public init(ids: [String]) { self.ids = ids }

    private enum CodingKeys: String, CodingKey { case ids }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ids = try container.decodeIfPresent([String].self, forKey: .ids) ?? []
    }
}

public struct LiveGoAway: Codable, Equatable, Sendable {
    /// A protobuf Duration in JSON: "50s", "1.500s".
    public var timeLeft: String?

    public init(timeLeft: String? = nil) { self.timeLeft = timeLeft }

    /// `timeLeft` in seconds, when it parses.
    public var secondsLeft: Double? {
        guard var text = timeLeft?.trimmingCharacters(in: .whitespaces), text.hasSuffix("s") else { return nil }
        text.removeLast()
        return Double(text)
    }
}

public struct LiveSessionResumptionUpdate: Codable, Equatable, Sendable {
    public var newHandle: String?
    public var resumable: Bool?

    public init(newHandle: String? = nil, resumable: Bool? = nil) {
        self.newHandle = newHandle
        self.resumable = resumable
    }
}

public struct LiveUsageMetadata: Codable, Equatable, Sendable {
    public var promptTokenCount: Int?
    public var responseTokenCount: Int?
    public var totalTokenCount: Int?

    public init(promptTokenCount: Int? = nil, responseTokenCount: Int? = nil, totalTokenCount: Int? = nil) {
        self.promptTokenCount = promptTokenCount
        self.responseTokenCount = responseTokenCount
        self.totalTokenCount = totalTokenCount
    }
}

/// One frame from the server. The API sends one of the message kinds per frame, sometimes with
/// `usageMetadata` beside it, so each is optional here.
public struct LiveServerMessage: Codable, Equatable, Sendable {
    public var setupComplete: LiveEmpty?
    public var serverContent: LiveServerContent?
    public var toolCall: LiveToolCall?
    public var toolCallCancellation: LiveToolCallCancellation?
    public var goAway: LiveGoAway?
    public var sessionResumptionUpdate: LiveSessionResumptionUpdate?
    public var usageMetadata: LiveUsageMetadata?

    public init(setupComplete: LiveEmpty? = nil, serverContent: LiveServerContent? = nil, toolCall: LiveToolCall? = nil,
                toolCallCancellation: LiveToolCallCancellation? = nil, goAway: LiveGoAway? = nil,
                sessionResumptionUpdate: LiveSessionResumptionUpdate? = nil, usageMetadata: LiveUsageMetadata? = nil) {
        self.setupComplete = setupComplete
        self.serverContent = serverContent
        self.toolCall = toolCall
        self.toolCallCancellation = toolCallCancellation
        self.goAway = goAway
        self.sessionResumptionUpdate = sessionResumptionUpdate
        self.usageMetadata = usageMetadata
    }

    public static func parse(_ text: String) throws -> LiveServerMessage {
        try JSONDecoder().decode(LiveServerMessage.self, from: Data(text.utf8))
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
