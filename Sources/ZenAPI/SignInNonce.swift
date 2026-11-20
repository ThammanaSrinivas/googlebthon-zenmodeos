import CryptoKit
import Foundation

/// The nonce for Sign in with Apple. The request carries its SHA-256; the raw value goes to the
/// backend with Apple's identity token, which proves the token was minted for this request.
public struct SignInNonce: Sendable, Equatable {
    public let raw: String

    public init(raw: String) { self.raw = raw }

    /// 32 characters from a URL-safe alphabet, from the system's secure random source.
    public static func make(length: Int = 32) -> SignInNonce {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return SignInNonce(raw: String((0..<length).map { _ in alphabet.randomElement(using: &generator)! }))
    }

    /// Lower-case hex SHA-256 of `raw`, the form Apple's request expects.
    public var sha256: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
