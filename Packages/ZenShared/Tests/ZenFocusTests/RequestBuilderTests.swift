import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import ZenAPI
@testable import ZenFocus

/// Records requests and answers with a fixed response; never touches the network.
final class FakeSender: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    var sent: [URLRequest] { lock.withLock { _sent } }
    let code: Int
    let body: String
    init(code: Int = 200, body: String = #"{"ok":true}"#) {
        self.code = code
        self.body = body
    }
    func send(_ request: URLRequest) async throws -> (Int, Data) {
        lock.withLock { _sent.append(request) }
        return (code, Data(body.utf8))
    }
}

func form(_ r: URLRequest) -> [String: String] {
    let s = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
    var out: [String: String] = [:]
    for pair in s.split(separator: "&") {
        let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
        out[kv[0]] = kv.count > 1 ? kv[1] : ""
    }
    return out
}

@Suite("HMAC and the webhook")
struct WebhookTests {
    @Test("HMAC-SHA256 matches RFC 4231 test case 2")
    func rfc4231() {
        let mac = PortableSHA256.hmacHex(key: Array("Jefe".utf8), message: Array("what do ya want for nothing?".utf8))
        #expect(mac == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    @Test("HMAC with a key longer than a block (RFC 4231 test case 6)")
    func longKey() {
        let key = [UInt8](repeating: 0xaa, count: 131)
        let mac = PortableSHA256.hmacHex(key: key, message: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))
        #expect(mac == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    @Test("SHA-256 hex is unchanged (empty string)")
    func sha() {
        #expect(PortableSHA256.hex([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("The body is the contract's, in a fixed order, with no uid or email")
    func body() {
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        let s = FocusSession(id: "s1", startAt: Date(timeIntervalSince1970: 1_795_149_000), until: Date(timeIntervalSince1970: 1_795_152_000), source: .manual)
        let start = String(decoding: Webhook.body(.focusStart, session: s, kept: nil, timeZone: ist), as: UTF8.self)
        #expect(start == #"{"event":"focus_start","session_id":"s1","start_at":"2026-11-20T10:00:00+05:30","until":"2026-11-20T10:50:00+05:30","source":"manual"}"#)
        let end = String(decoding: Webhook.body(.focusEnd, session: s, kept: true, timeZone: ist), as: UTF8.self)
        #expect(end.contains(#""kept":true"#))
        #expect(!end.contains("uid") && !end.contains("email"))
        #expect((try? JSONSerialization.jsonObject(with: Data(end.utf8))) != nil)
    }

    @Test("The request is signed and a receiver can verify it; a changed byte fails")
    func signed() {
        let r = Webhook.request(url: URL(string: "https://example.com/hook")!, .focusStart, session: session(), kept: nil, secret: "s3cret")
        let header = r.value(forHTTPHeaderField: Webhook.signatureHeader) ?? ""
        #expect(header.hasPrefix("sha256=") && header.count == 7 + 64)
        #expect(r.httpMethod == "POST")
        #expect(Webhook.verify(body: r.httpBody!, secret: "s3cret", header: header))
        #expect(!Webhook.verify(body: r.httpBody!, secret: "other", header: header))
        var tampered = r.httpBody!
        tampered[tampered.count - 3] ^= 1
        #expect(!Webhook.verify(body: tampered, secret: "s3cret", header: header))
    }

    @Test("Only https URLs (or this Mac) are allowed")
    func allowed() {
        #expect(Webhook.isAllowed(URL(string: "https://webhook.site/abc")!))
        #expect(Webhook.isAllowed(URL(string: "http://localhost:8787/x")!))
        #expect(!Webhook.isAllowed(URL(string: "http://example.com/x")!))
        #expect(!Webhook.isAllowed(URL(string: "file:///etc/passwd")!))
    }

    @Test("The hook posts start and end, and a 500 fails it")
    func hook() async throws {
        let sender = FakeSender(code: 200, body: "")
        let hook = WebhookHook(config: { WebhookConfig(url: URL(string: "https://example.com/h")!, secret: "k") }, sender: sender)
        #expect(await hook.status() == .ready)
        try await hook.onFocusStart(session())
        try await hook.onFocusEnd(session(), kept: false)
        #expect(sender.sent.count == 2)
        #expect(String(decoding: sender.sent[1].httpBody!, as: UTF8.self).contains(#""kept":false"#))
        let failing = WebhookHook(config: { WebhookConfig(url: URL(string: "https://example.com/h")!, secret: "k") }, sender: FakeSender(code: 500))
        await #expect(throws: HookFailure.self) { try await failing.onFocusStart(session()) }
        let unset = WebhookHook(config: { nil }, sender: sender)
        #expect(await unset.status() == .needsSetup("Add a webhook URL"))
    }

    @Test("Secrets are 64 hex characters and differ")
    func secrets() {
        let a = Webhook.newSecret(), b = Webhook.newSecret()
        #expect(a.count == 64 && a != b && a.allSatisfy(\.isHexDigit))
    }
}

@Suite("Slack requests")
struct SlackTests {
    let token = "xoxp-test"

    @Test("Status: text, emoji and an expiry, bearer token, form body")
    func status() throws {
        let until = Date(timeIntervalSince1970: 1_763_620_200)
        let r = SlackAPI.setStatus(token: token, text: "Focusing until 12:00", emoji: ":no_bell:", expiration: until)
        #expect(r.url?.absoluteString == "https://slack.com/api/users.profile.set")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-test")
        let profile = try #require(form(r)["profile"])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(profile.utf8)) as? [String: Any])
        #expect(json["status_text"] as? String == "Focusing until 12:00")
        #expect(json["status_emoji"] as? String == ":no_bell:")
        #expect(json["status_expiration"] as? Int == 1_763_620_200)
    }

    @Test("Clearing sends an empty status with no expiry")
    func clear() throws {
        let profile = try #require(form(SlackAPI.clearStatus(token: token))["profile"])
        #expect(profile.contains(#""status_text":"""#) && profile.contains(#""status_expiration":0"#))
    }

    @Test("Snooze and end snooze")
    func snooze() {
        let r = SlackAPI.snooze(token: token, minutes: 50)
        #expect(r.url?.lastPathComponent == "dnd.setSnooze")
        #expect(form(r)["num_minutes"] == "50")
        #expect(form(SlackAPI.snooze(token: token, minutes: 0))["num_minutes"] == "1")
        #expect(SlackAPI.endSnooze(token: token).url?.lastPathComponent == "dnd.endSnooze")
    }

    @Test("Schedule a message for 9:30 AM")
    func schedule() {
        let at = Date(timeIntervalSince1970: 1_763_697_600)
        let r = SlackAPI.scheduleMessage(token: token, channel: "D1", text: "Thanks, on it tomorrow", at: at, threadTs: "1.2")
        #expect(r.url?.lastPathComponent == "chat.scheduleMessage")
        #expect(form(r)["post_at"] == "1763697600")
        #expect(form(r)["text"] == "Thanks, on it tomorrow")
        #expect(form(r)["thread_ts"] == "1.2")
    }

    @Test("Form encoding escapes &, = and spaces")
    func encoding() {
        #expect(SlackAPI.formEncode([("q", "a&b=c d")]) == "q=a%26b%3Dc%20d")
    }

    @Test("Slack errors become words")
    func errors() {
        #expect(throws: HookFailure("Slack token no longer works")) { try SlackAPI.check(Data(#"{"ok":false,"error":"invalid_auth"}"#.utf8)) }
        #expect(throws: HookFailure.self) { try SlackAPI.check(Data("<html>".utf8)) }
        #expect((try? SlackAPI.check(Data(#"{"ok":true}"#.utf8))) != nil)
    }

    @Test("The hook sets the status and the snooze, then clears both")
    func hook() async throws {
        let sender = FakeSender()
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        let hook = SlackHook(token: { "xoxp-1" }, sender: sender, timeZone: ist)
        let s = FocusSession(id: "s", startAt: Date(), until: Date().addingTimeInterval(50 * 60), source: .manual)
        try await hook.onFocusStart(s)
        try await hook.onFocusEnd(s, kept: true)
        let methods = Set(sender.sent.map { $0.url!.lastPathComponent })
        #expect(methods == ["users.profile.set", "dnd.setSnooze", "dnd.endSnooze"])
        #expect(sender.sent.filter { $0.url!.lastPathComponent == "users.profile.set" }.count == 2)
        #expect(SlackHook.statusText(until: Date(timeIntervalSince1970: 1_763_620_200), timeZone: ist) == "Focusing until 12:00")
    }

    @Test("No token: needs setup; a revoked token fails the hook")
    func setup() async {
        #expect(await SlackHook(token: { nil }).status() == .needsSetup("Paste a Slack token"))
        let hook = SlackHook(token: { "xoxp-1" }, sender: FakeSender(body: #"{"ok":false,"error":"token_revoked"}"#))
        await #expect(throws: HookFailure.self) { try await hook.onFocusStart(session()) }
    }
}

final class FakeCommands: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _ran: [[String]] = []
    var ran: [[String]] { lock.withLock { _ran } }
    let shortcuts: [String]
    let failRun: Bool
    init(shortcuts: [String], failRun: Bool = false) {
        self.shortcuts = shortcuts
        self.failRun = failRun
    }
    func run(_ executable: String, _ arguments: [String]) async throws -> (code: Int32, output: String) {
        lock.withLock { _ran.append(arguments) }
        if arguments.first == "list" { return (0, shortcuts.joined(separator: "\n") + "\n") }
        return (failRun ? 1 : 0, "")
    }
}

@Suite("Do Not Disturb through Shortcuts")
struct DNDTests {
    @Test("Ready when both Shortcuts exist; runs On then Off")
    func ready() async throws {
        let cmds = FakeCommands(shortcuts: ["Other", "ZenMode Focus On", "ZenMode Focus Off"])
        let hook = ShortcutsDNDHook(runner: cmds)
        #expect(await hook.status() == .ready)
        try await hook.onFocusStart(session())
        try await hook.onFocusEnd(session(), kept: true)
        #expect(cmds.ran.suffix(2) == [["run", "ZenMode Focus On"], ["run", "ZenMode Focus Off"]])
    }

    @Test("Missing Shortcuts: needs setup, says which")
    func missing() async {
        #expect(await ShortcutsDNDHook(runner: FakeCommands(shortcuts: [])).status() == .needsSetup("Add the two Focus Shortcuts"))
        #expect(await ShortcutsDNDHook(runner: FakeCommands(shortcuts: ["ZenMode Focus On"])).status() == .needsSetup("Add “ZenMode Focus Off”"))
    }

    @Test("Switched off; a Shortcut that fails throws")
    func offAndFailing() async {
        #expect(await ShortcutsDNDHook(runner: FakeCommands(shortcuts: []), enabled: { false }).status() == .off)
        let hook = ShortcutsDNDHook(runner: FakeCommands(shortcuts: ["ZenMode Focus On", "ZenMode Focus Off"], failRun: true))
        await #expect(throws: HookFailure.self) { try await hook.onFocusStart(session()) }
    }
}
