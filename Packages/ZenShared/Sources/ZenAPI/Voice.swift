import Foundation

// Zeno Voice: the app's side of the contract (founders, 20 Nov 2026).
//
// The Gemini API key never reaches a device. The app asks the backend for a single-use, short-lived
// ephemeral token that already locks the Live model, Zeno's system instruction and its tools, and
// connects to Gemini Live with it (ZenVoice's ZenoSession). Intents, focus sessions and app pauses
// stay on the device; only Zen Cards (the evening note) go to the backend, through ZenCardService.

/// One Gemini Live session's credentials, minted by the backend for the signed-in person.
public struct LiveToken: Codable, Equatable, Sendable {
    /// The ephemeral token, used once as `access_token` on the constrained Live endpoint.
    public let token: String
    /// The Live model the token is locked to, e.g. "gemini-3.8-live" (with or without "models/").
    public let model: String
    /// The prebuilt voice Zeno speaks with, e.g. "Kore".
    public let voice: String
    /// When a session opened with it must end (about 30 minutes after minting).
    public let expiresAt: Date
    /// The deadline to open the session (about a minute after minting). Past it, ask for a new token.
    public let connectBy: Date

    public init(token: String, model: String, voice: String, expiresAt: Date, connectBy: Date) {
        self.token = token
        self.model = model
        self.voice = voice
        self.expiresAt = expiresAt
        self.connectBy = min(connectBy, expiresAt)
    }

    /// True while a new session can still be opened with this token.
    public func canConnect(at now: Date) -> Bool { now < connectBy }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }
}

public enum VoiceError: Error, Equatable, Sendable {
    /// Nobody is signed in: a token is only minted for an account.
    case signedOut
    /// No network, or the connection dropped and couldn't be resumed.
    case offline
    /// Zeno Voice is switched off for this account or build.
    case disabled
    /// Too many sessions in a short time; try again later.
    case rateLimited
    /// The backend or Gemini Live didn't answer as expected.
    case unavailable
}

/// Mints Live tokens. The real one is the backend; ZenMock's `FakeVoiceTokens` stands in offline.
public protocol VoiceTokenService: Sendable {
    func liveToken() async throws(VoiceError) -> LiveToken
}
