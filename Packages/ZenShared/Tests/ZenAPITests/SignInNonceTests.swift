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

@Suite("Portable SHA-256")
struct PortableSHA256Tests {
    /// FIPS 180-4 examples: the digest SignInNonce falls back to where CryptoKit doesn't exist.
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ])
    func matchesTheStandardVectors(input: String, digest: String) {
        #expect(PortableSHA256.hex(Array(input.utf8)) == digest)
        #expect(SignInNonce(raw: input).sha256 == digest)
    }
}
