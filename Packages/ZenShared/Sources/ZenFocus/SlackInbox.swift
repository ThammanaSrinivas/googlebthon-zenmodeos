import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZenAPI

/// One Slack message that came in during focus, and where a reply goes. Read on this Mac with the
/// person's own token; only `text` and `fromLabel` go to zenoCatchUp, on their tap, never stored.
public struct InboxMessage: Equatable, Sendable {
    public let channel: String
    public let ts: String
    /// The thread to reply in (a channel mention); nil for a DM.
    public let threadTs: String?
    public let fromLabel: String
    public let text: String
    public let isDM: Bool

    public init(channel: String, ts: String, threadTs: String?, fromLabel: String, text: String, isDM: Bool) {
        self.channel = channel
        self.ts = ts
        self.threadTs = threadTs
        self.fromLabel = fromLabel
        self.text = text
        self.isDM = isDM
    }

    public var item: CatchUpItem { CatchUpItem(source: .slack, fromLabel: fromLabel, text: text) }
}

/// Mentions and DMs since a time: auth.test, search.messages, conversations.list (im) and
/// conversations.history, with names from users.info. At most 30, newest first.
public struct SlackInbox: Sendable {
    public static let maxItems = 30
    /// DMs looked at: the most recently active ones Slack lists first.
    public static let maxDMs = 12

    private let token: String
    private let sender: any HTTPSending

    public init(token: String, sender: any HTTPSending = URLSessionSender()) {
        self.token = token
        self.sender = sender
    }

    public func messages(since: Date) async throws -> [InboxMessage] {
        let me = try await call(SlackAPI.authTest(token: token))["user_id"] as? String ?? ""
        var names = NameCache()
        var out: [InboxMessage] = []

        // Mentions in channels.
        let search = try await call(SlackAPI.searchMentions(token: token, userId: me, since: since))
        let matches = ((search["messages"] as? [String: Any])?["matches"] as? [[String: Any]]) ?? []
        for m in matches {
            guard let ts = m["ts"] as? String, Self.date(ts) >= since, let user = m["user"] as? String, user != me,
                  let channel = (m["channel"] as? [String: Any])?["id"] as? String else { continue }
            let isIM = (m["channel"] as? [String: Any])?["is_im"] as? Bool ?? false
            let label = try await names.name(user, m["username"] as? String) { try await self.userName(user) }
            out.append(InboxMessage(channel: channel, ts: ts, threadTs: isIM ? nil : (Self.threadTs(fromPermalink: m["permalink"] as? String) ?? ts),
                                    fromLabel: label, text: Self.clean(m["text"] as? String ?? ""), isDM: isIM))
        }

        // Direct messages.
        let list = try await call(SlackAPI.listDMs(token: token))
        let ims = ((list["channels"] as? [[String: Any]]) ?? []).prefix(Self.maxDMs)
        for im in ims {
            guard let channel = im["id"] as? String else { continue }
            let history = (try? await call(SlackAPI.history(token: token, channel: channel, since: since))) ?? [:]
            for m in (history["messages"] as? [[String: Any]]) ?? [] {
                guard let ts = m["ts"] as? String, Self.date(ts) >= since, let user = m["user"] as? String, user != me,
                      m["subtype"] == nil else { continue }
                let label = try await names.name(user, nil) { try await self.userName(user) }
                out.append(InboxMessage(channel: channel, ts: ts, threadTs: nil, fromLabel: label,
                                        text: Self.clean(m["text"] as? String ?? ""), isDM: true))
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.channel + "/" + $0.ts).inserted && !$0.text.isEmpty }
            .sorted { Self.date($0.ts) > Self.date($1.ts) }
            .prefix(Self.maxItems).map { $0 }
    }

    /// Sends an approved reply: in the thread for a channel mention, straight into a DM.
    public func reply(to message: InboxMessage, text: String, at: Date? = nil) async throws {
        let request = at.map { SlackAPI.scheduleMessage(token: token, channel: message.channel, text: text, at: $0, threadTs: message.threadTs) }
            ?? SlackAPI.postMessage(token: token, channel: message.channel, text: text, threadTs: message.threadTs)
        _ = try await call(request)
    }

    private func userName(_ user: String) async throws -> String {
        let info = try await call(SlackAPI.userInfo(token: token, user: user))
        let u = info["user"] as? [String: Any]
        let profile = u?["profile"] as? [String: Any]
        for name in [profile?["real_name"], u?["real_name"], u?["name"]].compactMap({ $0 as? String }) where !name.isEmpty {
            return name
        }
        return "Someone"
    }

    private func call(_ request: URLRequest) async throws -> [String: Any] {
        let (code, data) = try await sender.send(request)
        guard code == 200 else { throw HookFailure("Slack answered \(code)") }
        return try SlackAPI.check(data)
    }

    /// Slack's "1700000000.000100" as a date.
    static func date(_ ts: String) -> Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }

    /// A permalink's `thread_ts` (a mention inside a thread replies in that thread).
    static func threadTs(fromPermalink link: String?) -> String? {
        guard let link, let items = URLComponents(string: link)?.queryItems else { return nil }
        return items.first { $0.name == "thread_ts" }?.value
    }

    /// Mentions and links as words: "<@U1>" → "@someone", "<https://x|label>" → "label".
    public static func clean(_ text: String) -> String {
        var s = text
        let patterns: [(String, String)] = [
            (#"<@[A-Z0-9]+(\|([^>]+))?>"#, "@someone"),
            (#"<#[A-Z0-9]+\|([^>]+)>"#, "#$1"),
            (#"<(https?://[^|>]+)\|([^>]+)>"#, "$2"),
            (#"<(https?://[^>]+)>"#, "$1"),
            (#"<!(here|channel|everyone)>"#, "@$1"),
        ]
        for (p, t) in patterns {
            s = s.replacingOccurrences(of: p, with: t, options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
    }
}

/// users.info once per person per fetch.
struct NameCache {
    private var names: [String: String] = [:]
    mutating func name(_ id: String, _ hint: String?, lookup: () async throws -> String) async throws -> String {
        if let n = names[id] { return n }
        let n = (try? await lookup()) ?? hint ?? "Someone"
        names[id] = String(n.prefix(60))
        return names[id]!
    }
}
