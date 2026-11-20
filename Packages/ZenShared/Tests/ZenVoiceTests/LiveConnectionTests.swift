// What a session hands its transport when it connects: the URL built from a LiveToken, and the
// frames that follow. No network: a fake server records everything. URLSessionLiveTransport itself
// only exists on Apple platforms; its offline checks at the bottom run on macOS only.
import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenVoice

@Suite("Live connection: URL and framing")
struct LiveConnectionTests {
    private func connect(token value: String, options: ZenoSession.Options = .init()) async throws -> FakeLiveServer {
        let clock = ManualVoiceClock(T.now)
        let server = FakeLiveServer()
        let session = ZenoSession(transport: server, tools: GatedTools(), user: "Kamal", clock: clock, options: options)
        try await session.connect(token: T.token(value, clock: clock))
        await session.sendText(ZenoAgent.pickupCue)
        await session.close()
        return server
    }

    @Test("The token is the URL's one query value, however odd its characters")
    func tokenInTheURL() async throws {
        let value = "fake/tok+en=1&key=evil#frag ?x"
        let server = try await connect(token: value)
        let url = try #require(await server.urls.first)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "wss")
        #expect(parts.host == "generativelanguage.googleapis.com")
        #expect(parts.path == "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")
        #expect(parts.queryItems == [URLQueryItem(name: "access_token", value: value)])
        #expect(parts.fragment == nil)
    }

    @Test("The token goes only in the URL: never in the setup or any later frame")
    func tokenNeverInAFrame() async throws {
        let value = "fake-ephemeral-token-in-url-only"
        let server = try await connect(token: value)
        let sent = await server.sent
        #expect(sent.count == 2) // the setup, then the pickup cue
        guard case .setup(let setup) = sent.first else { Issue.record("the setup goes first"); return }
        #expect(setup.model == "models/gemini-3.8-live")
        #expect(setup.generationConfig?.speechConfig?.voiceConfig.prebuiltVoiceConfig.voiceName == "Kore")
        for message in sent { #expect(!(try message.jsonString()).contains("ephemeral-token")) }
    }

    @Test("A host option replaces only the host part of the endpoint")
    func customHost() async throws {
        let server = try await connect(token: "fake-token", options: .init(host: "wss://live.example.test/ws/zeno"))
        let url = try #require(await server.urls.first)
        #expect(url.absoluteString == "wss://live.example.test/ws/zeno.BidiGenerateContentConstrained?access_token=fake-token")
    }
}

#if canImport(Darwin)
@Suite("URLSession transport, offline")
struct URLSessionLiveTransportOfflineTests {
    @Test("Before connecting, receive ends at once, send throws, and close is safe")
    func beforeConnect() async throws {
        let transport = URLSessionLiveTransport()
        #expect(try await transport.receive() == nil)
        await #expect(throws: URLError.self) { try await transport.send("{}") }
        await transport.close()
        #expect(try await transport.receive() == nil)
    }
}
#endif
