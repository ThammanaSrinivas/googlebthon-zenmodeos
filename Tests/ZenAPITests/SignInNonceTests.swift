import Testing
@testable import ZenAPI

@Suite("Sign in with Apple nonce")
struct SignInNonceTests {
    @Test("The hash is lower-case hex SHA-256 of the raw nonce")
    func knownHash() {
        #expect(SignInNonce(raw: "abc").sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("Fresh nonces are 32 URL-safe characters and never repeat")
    func fresh() {
        let a = SignInNonce.make(), b = SignInNonce.make()
        #expect(a.raw.count == 32)
        #expect(a != b)
        #expect(a.raw.allSatisfy { $0.isLetter || $0.isNumber || "-._".contains($0) })
    }
}
