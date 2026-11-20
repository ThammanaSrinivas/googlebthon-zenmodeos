// The Gemini Live wire format: golden JSON for what the client sends, and decoding of every server
// message Zeno handles. Field names per https://ai.google.dev/api/live (checked 20 Nov 2026).
import Foundation
import Testing
@testable import ZenVoice

@Suite("Live protocol: client frames")
struct LiveClientFrameTests {
    @Test("The setup message matches the prototype's, plus session resumption")
    func setupGolden() throws {
        let frame = try LiveClientMessage.setup(ZenoAgent.setup(model: "gemini-3.8-live", voice: "Kore", user: "Kamal")).jsonString()
        let json = try JSONValue.parse(frame)
        let setup = try #require(json["setup"])
        let expected: JSONValue = [
            "model": "models/gemini-3.8-live",
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Kore"]]],
            ],
            "systemInstruction": ["parts": [["text": .string(ZenoAgent.systemInstruction(user: "Kamal"))]]],
            "realtimeInputConfig": [
                "automaticActivityDetection": ["silenceDurationMs": 600],
                "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
            ],
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:],
            "contextWindowCompression": ["slidingWindow": [:]],
            "sessionResumption": [:],
            "tools": setup["tools"]!, // checked on its own below
        ]
        #expect(setup == expected)
        #expect(json.objectValue?.keys.sorted() == ["setup"])
        let declarations = try #require(setup["tools"]?.arrayValue?.first?["functionDeclarations"]?.arrayValue)
        #expect(declarations.compactMap { $0["name"]?.stringValue } == ZenoAgent.ToolName.allCases.map(\.rawValue))
        // The setup carries exactly the shared declarations (the backend's tool file), and
        // set_intent asks for the prototype's arguments.
        let shared = try JSONValue.parse(String(decoding: try JSONEncoder().encode(ZenoAgent.toolDeclarations), as: UTF8.self))
        #expect(JSONValue.array(declarations) == shared)
        let setIntent = declarations[1]["parameters"]
        #expect(setIntent?["properties"]?.objectValue?.keys.sorted() == ["app", "minutes", "purpose"])
        #expect(setIntent?["required"] == ["app", "minutes"])
    }

    @Test("A resumed setup carries the handle; a model path is never doubled")
    func setupResumes() throws {
        let setup = ZenoAgent.setup(model: "models/gemini-3.8-live", voice: "Puck", user: "Asha", resumptionHandle: "h-42")
        let json = try JSONValue.parse(try LiveClientMessage.setup(setup).jsonString())
        #expect(json["setup"]?["sessionResumption"] == ["handle": "h-42"])
        #expect(json["setup"]?["model"] == "models/gemini-3.8-live")
        #expect(json["setup"]?["generationConfig"]?["speechConfig"]?["voiceConfig"]?["prebuiltVoiceConfig"]?["voiceName"] == "Puck")
    }

    @Test("A mic chunk is base64 PCM16 at 16 kHz in realtimeInput.audio")
    func audioGolden() throws {
        let pcm = PCM.int16LE([Int16(0), Int16.max, Int16.min])
        #expect(try LiveClientMessage.audio(pcm).jsonString()
            == #"{"realtimeInput":{"audio":{"data":"AAD/fwCA","mimeType":"audio/pcm;rate=16000"}}}"#)
    }

    @Test("The end of the audio stream, a text turn and a tool response")
    func otherGoldens() throws {
        #expect(try LiveClientMessage.audioStreamEnd.jsonString() == #"{"realtimeInput":{"audioStreamEnd":true}}"#)
        #expect(try LiveClientMessage.userText("Hi Zeno").jsonString()
            == #"{"clientContent":{"turnComplete":true,"turns":[{"parts":[{"text":"Hi Zeno"}],"role":"user"}]}}"#)
        let response = LiveClientMessage.toolResponse(LiveToolResponse(functionResponses: [
            LiveFunctionResponse(id: "fc-1", name: "set_intent",
                                 response: ["result": ["ok": true, "minutes": 2, "app": "Instagram"]]),
        ]))
        #expect(try response.jsonString()
            == #"{"toolResponse":{"functionResponses":[{"id":"fc-1","name":"set_intent","response":{"result":{"app":"Instagram","minutes":2,"ok":true}}}]}}"#)
    }

    @Test("Client frames parse back to what was sent")
    func roundTrip() throws {
        let messages: [LiveClientMessage] = [
            .setup(ZenoAgent.setup(model: "gemini-3.8-live", voice: "Kore", user: "Kamal", resumptionHandle: "h")),
            .audio(Data([1, 2, 3, 4])), .audioStreamEnd, .userText("नमस्ते"),
            .toolResponse(LiveToolResponse(functionResponses: [LiveFunctionResponse(id: nil, name: "x", response: ["a": [1, 2.5, nil]])])),
        ]
        for message in messages { #expect(try LiveClientMessage.parse(message.jsonString()) == message) }
    }

    @Test("The constrained endpoint carries the token, percent-encoded")
    func constrainedURL() {
        let url = LiveEndpoint.constrainedURL(token: "auth_tokens/a+b=c")
        #expect(url.absoluteString == "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained?access_token=auth_tokens%2Fa%2Bb%3Dc")
    }
}

@Suite("Live protocol: server frames")
struct LiveServerFrameTests {
    @Test("setupComplete")
    func setupComplete() throws {
        let message = try LiveServerMessage.parse(#"{"setupComplete":{}}"#)
        #expect(message.setupComplete != nil)
        #expect(message.serverContent == nil)
    }

    @Test("Model audio, with its rate, and a thought part")
    func modelAudio() throws {
        let message = try LiveServerMessage.parse(#"""
        {"serverContent":{"modelTurn":{"role":"model","parts":[
          {"text":"planning","thought":true},
          {"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AAD/fw=="}}]}}}
        """#)
        let parts = try #require(message.serverContent?.modelTurn?.parts)
        #expect(parts[0].thought == true)
        let blob = try #require(parts[1].inlineData)
        #expect(blob.isAudio)
        #expect(blob.sampleRate == 24_000)
        #expect(PCM.int16Samples(try #require(blob.bytes)) == [0, Int16.max])
    }

    @Test("Interrupted, transcriptions with their language, turn complete")
    func content() throws {
        let interrupted = try LiveServerMessage.parse(#"{"serverContent":{"interrupted":true}}"#)
        #expect(interrupted.serverContent?.interrupted == true)
        let heard = try LiveServerMessage.parse(#"{"serverContent":{"inputTranscription":{"text":"Nahi nahi, 45 minute","languageCode":"hi-IN"}}}"#)
        #expect(heard.serverContent?.inputTranscription == LiveTranscription(text: "Nahi nahi, 45 minute", languageCode: "hi-IN"))
        let spoken = try LiveServerMessage.parse(#"{"serverContent":{"outputTranscription":{"text":"Ho gaya."},"generationComplete":true}}"#)
        #expect(spoken.serverContent?.outputTranscription?.text == "Ho gaya.")
        #expect(spoken.serverContent?.generationComplete == true)
        let done = try LiveServerMessage.parse(#"{"serverContent":{"turnComplete":true,"waitingForInput":true}}"#)
        #expect(done.serverContent?.turnComplete == true)
        #expect(done.serverContent?.waitingForInput == true)
    }

    @Test("A tool call with free-form args, and its cancellation")
    func toolCall() throws {
        let call = try LiveServerMessage.parse(#"""
        {"toolCall":{"functionCalls":[{"id":"fc-7","name":"start_focus","args":{"minutes":45,"label":"Client demo prep","quiet_apps":["WhatsApp"]}}]}}
        """#)
        let fc = try #require(call.toolCall?.functionCalls.first)
        #expect(fc.id == "fc-7")
        #expect(fc.name == "start_focus")
        #expect(fc.args == ["minutes": 45, "label": "Client demo prep", "quiet_apps": ["WhatsApp"]])
        let cancel = try LiveServerMessage.parse(#"{"toolCallCancellation":{"ids":["fc-7","fc-8"]}}"#)
        #expect(cancel.toolCallCancellation?.ids == ["fc-7", "fc-8"])
        #expect(try LiveServerMessage.parse(#"{"toolCall":{}}"#).toolCall?.functionCalls == [])
    }

    @Test("goAway's time left, resumption updates and usage")
    func sessionManagement() throws {
        let away = try LiveServerMessage.parse(#"{"goAway":{"timeLeft":"50s"}}"#)
        #expect(away.goAway?.secondsLeft == 50)
        #expect(LiveGoAway(timeLeft: "1.500s").secondsLeft == 1.5)
        #expect(LiveGoAway(timeLeft: "soon").secondsLeft == nil)
        let update = try LiveServerMessage.parse(#"{"sessionResumptionUpdate":{"newHandle":"h-9","resumable":true}}"#)
        #expect(update.sessionResumptionUpdate == LiveSessionResumptionUpdate(newHandle: "h-9", resumable: true))
        let usage = try LiveServerMessage.parse(#"{"usageMetadata":{"promptTokenCount":120,"responseTokenCount":30,"totalTokenCount":150,"responseTokensDetails":[{"modality":"AUDIO","tokenCount":30}]}}"#)
        #expect(usage.usageMetadata == LiveUsageMetadata(promptTokenCount: 120, responseTokenCount: 30, totalTokenCount: 150))
    }

    @Test("Fields Zeno doesn't use are ignored")
    func unknownFields() throws {
        let message = try LiveServerMessage.parse(#"{"voiceActivity":{"type":"ACTIVITY_START"},"serverContent":{"interactionStatus":"X","turnComplete":true}}"#)
        #expect(message.serverContent?.turnComplete == true)
    }
}

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Whole numbers go out as integers, fractions as decimals")
    func numbers() {
        let value: JSONValue = ["a": 5, "b": 2.5, "c": -3, "d": true, "e": nil, "f": "x"]
        #expect(value.jsonString() == #"{"a":5,"b":2.5,"c":-3,"d":true,"e":null,"f":"x"}"#)
    }

    @Test("Booleans stay booleans when decoded")
    func decodesBooleans() throws {
        #expect(try JSONValue.parse("[true, 1, \"1\"]") == [true, 1, "1"])
    }

    @Test("numberLike follows JavaScript's Number()", arguments: [
        (JSONValue.number(45), 45.0 as Double?), ("45", 45), (" 7 ", 7), ("", 0), (.null, 0), (true, 1),
        ("forty", nil), (["x"], nil),
    ] as [(JSONValue, Double?)])
    func numberLike(value: JSONValue, expected: Double?) {
        #expect(value.numberLike == expected)
    }
}
