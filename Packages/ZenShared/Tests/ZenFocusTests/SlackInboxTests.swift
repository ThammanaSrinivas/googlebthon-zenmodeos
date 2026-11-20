import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import ZenAPI
@testable import ZenFocus

/// Answers each Slack method with canned JSON; records what was sent.
final class SlackStub: HTTPSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [URLRequest] = []
    var sent: [URLRequest] { lock.withLock { _sent } }
    let answers: [String: String]
    init(_ answers: [String: String]) { self.answers = answers }
    func send(_ request: URLRequest) async throws -> (Int, Data) {
        lock.withLock { _sent.append(request) }
        let method = request.url!.lastPathComponent
        if method == "conversations.history" {
            let channel = form(request)["channel"] ?? ""
            return (200, Data((answers["history:\(channel)"] ?? #"{"ok":true,"messages":[]}"#).utf8))
        }
        if method == "users.info" {
            let user = form(request)["user"] ?? ""
            return (200, Data((answers["user:\(user)"] ?? #"{"ok":false,"error":"user_not_found"}"#).utf8))
        }
        return (200, Data((answers[method] ?? #"{"ok":true}"#).utf8))
    }
}

@Suite("Slack catch-up inbox")
struct SlackInboxTests {
    let since = Date(timeIntervalSince1970: 1_795_149_000)

    func stub() -> SlackStub {
        SlackStub([
            "auth.test": #"{"ok":true,"user_id":"UME","user":"kamal","team":"ZenMode OS"}"#,
            "search.messages": #"""
            {"ok":true,"messages":{"matches":[
              {"ts":"1795150000.000100","user":"URAVI","text":"<@UME> can you review the UPI PR?","channel":{"id":"C1","is_im":false},"permalink":"https://x.slack.com/archives/C1/p1795150000000100?thread_ts=1795149900.000001"},
              {"ts":"1795140000.000100","user":"URAVI","text":"<@UME> old one","channel":{"id":"C1"}},
              {"ts":"1795150500.000100","user":"UME","text":"<@UME> me","channel":{"id":"C1"}}
            ]}}
            """#,
            "conversations.list": #"{"ok":true,"channels":[{"id":"D1","user":"UPRIYA"},{"id":"D2","user":"UX"}]}"#,
            "history:D1": #"{"ok":true,"messages":[{"ts":"1795151000.000200","user":"UPRIYA","text":"Lunch at 1? &amp; bring the deck <https://deck.example|deck>"},{"ts":"1795151100.000200","user":"UPRIYA","subtype":"channel_join","text":"joined"}]}"#,
            "user:URAVI": #"{"ok":true,"user":{"name":"ravi","profile":{"real_name":"Ravi"}}}"#,
            "user:UPRIYA": #"{"ok":true,"user":{"name":"priya","profile":{"real_name":""},"real_name":"Priya S"}}"#,
        ])
    }

    @Test("Mentions and DMs since the start, newest first, without my own or old ones")
    func messages() async throws {
        let s = stub()
        let inbox = try await SlackInbox(token: "xoxp-1", sender: s).messages(since: since)
        #expect(inbox.map(\.fromLabel) == ["Priya S", "Ravi"])
        #expect(inbox[0].isDM && inbox[0].threadTs == nil && inbox[0].channel == "D1")
        #expect(inbox[0].text == "Lunch at 1? & bring the deck deck")
        #expect(inbox[1].threadTs == "1795149900.000001")
        #expect(inbox[1].text == "@someone can you review the UPI PR?")
        #expect(inbox[1].item == CatchUpItem(source: .slack, fromLabel: "Ravi", text: "@someone can you review the UPI PR?"))
    }

    @Test("A reply goes in the thread for a mention, and can be scheduled")
    func reply() async throws {
        let s = stub()
        let inbox = SlackInbox(token: "xoxp-1", sender: s)
        let m = InboxMessage(channel: "C1", ts: "1.1", threadTs: "1.0", fromLabel: "Ravi", text: "x", isDM: false)
        try await inbox.reply(to: m, text: "On it")
        #expect(s.sent.last?.url?.lastPathComponent == "chat.postMessage")
        #expect(form(s.sent.last!)["thread_ts"] == "1.0")
        try await inbox.reply(to: m, text: "Tomorrow", at: Date(timeIntervalSince1970: 1_795_233_600))
        #expect(s.sent.last?.url?.lastPathComponent == "chat.scheduleMessage")
        #expect(form(s.sent.last!)["post_at"] == "1795233600")
    }

    @Test("A revoked token fails the fetch")
    func revoked() async {
        let s = SlackStub(["auth.test": #"{"ok":false,"error":"token_revoked"}"#])
        await #expect(throws: HookFailure("Slack token no longer works")) { _ = try await SlackInbox(token: "x", sender: s).messages(since: since) }
    }

    @Test("Cleaning turns Slack markup into words and caps the length")
    func clean() {
        #expect(SlackInbox.clean("<!here> see <#C1|payments>") == "@here see #payments")
        #expect(SlackInbox.clean(String(repeating: "a", count: 1500)).count == 1000)
    }
}
