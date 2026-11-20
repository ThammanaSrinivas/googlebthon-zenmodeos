import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZenAPI

/// The signed webhook (contract v4): `POST {event, session_id, start_at, until, kept?, source}` with
/// `X-ZenMode-Signature: sha256=<hex HMAC-SHA256 of the raw body with the person's secret>`.
/// No uid, no email, no app names.
public enum Webhook {
    public static let signatureHeader = "X-ZenMode-Signature"

    public enum Event: String, Sendable { case focusStart = "focus_start", focusEnd = "focus_end" }

    /// The body, with its keys in a fixed order so a signature can be checked byte for byte.
    public static func body(_ event: Event, session: FocusBlock, kept: Bool?, timeZone: TimeZone = .current) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = timeZone
        var fields: [(String, String)] = [
            ("event", quoted(event.rawValue)),
            ("session_id", quoted(session.id)),
            ("start_at", quoted(iso.string(from: session.startAt))),
            ("until", quoted(iso.string(from: session.until))),
        ]
        if let kept { fields.append(("kept", kept ? "true" : "false")) }
        fields.append(("source", quoted(session.source.rawValue)))
        return Data(("{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}").utf8)
    }

    /// `sha256=<hex>`.
    public static func signature(body: Data, secret: String) -> String {
        "sha256=" + PortableSHA256.hmacHex(key: Array(secret.utf8), message: Array(body))
    }

    /// Whether `header` signs `body` with `secret` (what a receiver checks).
    public static func verify(body: Data, secret: String, header: String) -> Bool {
        let expected = Array(signature(body: body, secret: secret).utf8)
        let given = Array(header.utf8)
        guard expected.count == given.count else { return false }
        return zip(expected, given).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public static func request(url: URL, _ event: Event, session: FocusBlock, kept: Bool?, secret: String,
                               timeZone: TimeZone = .current) -> URLRequest {
        let body = body(event, session: session, kept: kept, timeZone: timeZone)
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ZenMode OS", forHTTPHeaderField: "User-Agent")
        request.setValue(signature(body: body, secret: secret), forHTTPHeaderField: signatureHeader)
        request.httpBody = body
        return request
    }

    /// A new secret: 32 random bytes, hex.
    public static func newSecret() -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<32).map { _ in
            let b = UInt8.random(in: 0...255, using: &g)
            return (b < 16 ? "0" : "") + String(b, radix: 16)
        }.joined()
    }

    /// Only https (or http to this Mac, for testing) is allowed.
    public static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return url.host?.isEmpty == false
        case "http": return ["localhost", "127.0.0.1"].contains(url.host ?? "")
        default: return false
        }
    }

    private static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}

/// Sends a request and answers with the HTTP status (the hooks' one network seam; tests fake it).
public protocol HTTPSending: Sendable {
    func send(_ request: URLRequest) async throws -> (Int, Data)
}

public struct URLSessionSender: HTTPSending {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Int, Data) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

/// Webhook settings: where to post and the secret to sign with (the secret lives in the Keychain).
public struct WebhookConfig: Equatable, Sendable {
    public let url: URL
    public let secret: String
    public init(url: URL, secret: String) {
        self.url = url
        self.secret = secret
    }
}

public struct WebhookHook: FocusHook {
    public let id = "webhook"
    public let displayName = "Webhook"
    private let config: @Sendable () -> WebhookConfig?
    private let sender: any HTTPSending

    public init(config: @escaping @Sendable () -> WebhookConfig?, sender: any HTTPSending = URLSessionSender()) {
        self.config = config
        self.sender = sender
    }

    public func status() async -> HookStatus {
        guard let c = config() else { return .needsSetup("Add a webhook URL") }
        return Webhook.isAllowed(c.url) ? .ready : .needsSetup("Use an https URL")
    }

    public func onFocusStart(_ session: FocusBlock) async throws {
        try await post(.focusStart, session, kept: nil)
    }

    public func onFocusEnd(_ session: FocusBlock, kept: Bool) async throws {
        try await post(.focusEnd, session, kept: kept)
    }

    private func post(_ event: Webhook.Event, _ session: FocusBlock, kept: Bool?) async throws {
        guard let c = config() else { throw HookFailure("Not set up") }
        let (code, _) = try await sender.send(Webhook.request(url: c.url, event, session: session, kept: kept, secret: c.secret))
        guard (200..<300).contains(code) else { throw HookFailure("The server answered \(code)") }
    }
}
