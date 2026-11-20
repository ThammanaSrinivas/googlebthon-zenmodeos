// SHA-256 (FIPS 180-4) in pure Swift: one copy for every platform that has no CryptoKit (Linux CI),
// used by SignInNonce there, by the Zen Score grid digests in the tests, and (as HMAC) to sign
// Focus Mode's webhooks.
public struct PortableSHA256: Sendable {
    public init() {}

    /// Lower-case hex SHA-256 of `bytes`.
    public static func hex(_ bytes: [UInt8]) -> String {
        var hash = PortableSHA256()
        hash.update(bytes)
        return hash.hexDigest()
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var state: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    private var block = [UInt8](repeating: 0, count: 64)
    private var filled = 0
    private var length: UInt64 = 0
    private var schedule = [UInt32](repeating: 0, count: 64)

    public mutating func update(_ bytes: [UInt8]) {
        length += UInt64(bytes.count)
        for byte in bytes {
            block[filled] = byte
            filled += 1
            if filled == 64 { compress() }
        }
    }

    /// The digest in lowercase hex. The hash is spent afterwards.
    public mutating func hexDigest() -> String {
        digest().map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }

    /// The 32-byte digest. The hash is spent afterwards.
    public mutating func digest() -> [UInt8] {
        let bits = length &* 8
        update([0x80])
        while filled != 56 { update([0]) }
        update((0..<8).reversed().map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) })
        return state.flatMap { word in (0..<4).reversed().map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    }

    /// HMAC-SHA256 (RFC 2104) of `message` with `key`.
    public static func hmac(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var k = key
        if k.count > 64 {
            var h = PortableSHA256()
            h.update(k)
            k = h.digest()
        }
        k += [UInt8](repeating: 0, count: 64 - k.count)
        var inner = PortableSHA256()
        inner.update(k.map { $0 ^ 0x36 })
        inner.update(message)
        var outer = PortableSHA256()
        outer.update(k.map { $0 ^ 0x5c })
        outer.update(inner.digest())
        return outer.digest()
    }

    /// Lower-case hex HMAC-SHA256.
    public static func hmacHex(key: [UInt8], message: [UInt8]) -> String {
        hmac(key: key, message: message).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }

    private mutating func compress() {
        for t in 0..<16 {
            schedule[t] = UInt32(block[4 * t]) << 24 | UInt32(block[4 * t + 1]) << 16 | UInt32(block[4 * t + 2]) << 8 | UInt32(block[4 * t + 3])
        }
        for t in 16..<64 {
            let s0 = rotr(schedule[t - 15], 7) ^ rotr(schedule[t - 15], 18) ^ (schedule[t - 15] >> 3)
            let s1 = rotr(schedule[t - 2], 17) ^ rotr(schedule[t - 2], 19) ^ (schedule[t - 2] >> 10)
            schedule[t] = schedule[t - 16] &+ s0 &+ schedule[t - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, h) = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
        for t in 0..<64 {
            let t1 = h &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ Self.k[t] &+ schedule[t]
            let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
            (h, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
        }
        for (i, word) in [a, b, c, d, e, f, g, h].enumerated() { state[i] &+= word }
        filled = 0
    }

    private func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { x >> n | x << (32 - n) }
}
