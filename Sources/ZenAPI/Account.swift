import Foundation

public struct ZenUser: Equatable, Sendable {
    public let uid: String
    public let displayName: String

    public init(uid: String, displayName: String) {
        self.uid = uid
        self.displayName = displayName
    }

    /// "Kamal" from "Kamal Senthilkumar".
    public var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? displayName }
}

/// The code a computer shows so a phone can bring the person's day over (Flow 02).
public struct PairingCode: Equatable, Sendable {
    public let code: JoinCode
    public let expiresAt: Date

    public init(code: JoinCode, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }

    /// What the QR code opens on the phone.
    public var url: URL { URL(string: "https://zenmodeos.com/pair/\(code.value)")! }
}

public enum AuthError: Error, Equatable, Sendable {
    case cancelled, codeExpired, offline, unavailable
}

public protocol AuthService: Sendable {
    func currentUser() async -> ZenUser?
    func signInWithGoogle() async throws(AuthError) -> ZenUser
    /// A fresh code; codes rotate every 5 minutes and work once.
    func newPairingCode() async throws(AuthError) -> PairingCode
    /// Returns once a phone approves the code.
    func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser
}
