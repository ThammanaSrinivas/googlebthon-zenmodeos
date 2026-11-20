import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZenAPI

/// Slack Web API requests, built pure (no network) so the tests can read them. A user token
/// (`xoxp-…`) from the Keychain, sent as a bearer header, form-encoded bodies. Scopes:
/// users.profile:write, dnd:write, search:read, im:read, im:history, users:read, chat:write.
public enum SlackAPI {
    public static let base = URL(string: "https://slack.com/api/")!

    /// The status people see while someone focuses. It expires on its own, so a crash still clears it.
    public static func setStatus(token: String, text: String, emoji: String, expiration: Date?) -> URLRequest {
        let profile: [String: Any] = [
            "status_text": String(text.prefix(100)),
            "status_emoji": emoji,
            "status_expiration": expiration.map { Int($0.timeIntervalSince1970) } ?? 0,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])) ?? Data("{}".utf8)
        return post("users.profile.set", token: token, form: [("profile", String(decoding: json, as: UTF8.self))])
    }

    public static func clearStatus(token: String) -> URLRequest {
        setStatus(token: token, text: "", emoji: "", expiration: nil)
    }

    /// Pauses notifications for `minutes` (Slack's own expiry).
    public static func snooze(token: String, minutes: Int) -> URLRequest {
        post("dnd.setSnooze", token: token, form: [("num_minutes", String(max(1, minutes)))])
    }

    public static func endSnooze(token: String) -> URLRequest {
        post("dnd.endSnooze", token: token, form: [])
    }

    public static func authTest(token: String) -> URLRequest {
        post("auth.test", token: token, form: [])
    }

    /// Messages that mention the person since `since` (search.messages).
    public static func searchMentions(token: String, userId: String, since: Date) -> URLRequest {
        let day = DateFormatter.slackDay.string(from: since.addingTimeInterval(-86_400))
        return post("search.messages", token: token, form: [("query", "<@\(userId)> after:\(day)"), ("sort", "timestamp"), ("count", "20")])
    }

    /// The person's direct-message channels.
    public static func listDMs(token: String) -> URLRequest {
        post("conversations.list", token: token, form: [("types", "im"), ("exclude_archived", "true"), ("limit", "50")])
    }

    /// One channel's messages since `since`.
    public static func history(token: String, channel: String, since: Date) -> URLRequest {
        post("conversations.history", token: token, form: [("channel", channel), ("oldest", ts(since)), ("limit", "20")])
    }

    public static func userInfo(token: String, user: String) -> URLRequest {
        post("users.info", token: token, form: [("user", user)])
    }

    /// Sends a reply now (only after the person approves it).
    public static func postMessage(token: String, channel: String, text: String, threadTs: String?) -> URLRequest {
        var form = [("channel", channel), ("text", text)]
        if let threadTs { form.append(("thread_ts", threadTs)) }
        return post("chat.postMessage", token: token, form: form)
    }

    /// Sends it at `at` instead ("Send at 9:30 AM?").
    public static func scheduleMessage(token: String, channel: String, text: String, at: Date, threadTs: String?) -> URLRequest {
        var form = [("channel", channel), ("text", text), ("post_at", String(Int(at.timeIntervalSince1970)))]
        if let threadTs { form.append(("thread_ts", threadTs)) }
        return post("chat.scheduleMessage", token: token, form: form)
    }

    static func post(_ method: String, token: String, form: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: base.appending(path: method), timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)
        return request
    }

    /// `a=1&b=two%20words`.
    public static func formEncode(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return pairs.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
    }

    /// Slack's message timestamp for a date ("1700000000.000000").
    public static func ts(_ date: Date) -> String { String(format: "%.6f", date.timeIntervalSince1970) }

    /// `{ok, error}`: every Slack answer carries them.
    public static func check(_ data: Data) throws -> [String: Any] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HookFailure("Slack sent something unexpected")
        }
        guard json["ok"] as? Bool == true else {
            throw HookFailure(describe(json["error"] as? String ?? "unknown"))
        }
        return json
    }

    static func describe(_ error: String) -> String {
        switch error {
        case "invalid_auth", "not_authed", "token_revoked", "account_inactive": "Slack token no longer works"
        case "missing_scope": "Slack app is missing a scope"
        case "ratelimited": "Slack asked us to slow down"
        default: "Slack said \(error)"
        }
    }
}

extension DateFormatter {
    /// search.messages' `after:` day.
    static let slackDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Slack during focus: a status that says until when, and paused notifications. Both expire on
/// their own; the end clears them anyway.
public struct SlackHook: FocusHook {
    public let id = "slack"
    public let displayName = "Slack"
    private let token: @Sendable () -> String?
    private let sender: any HTTPSending
    private let timeZone: TimeZone

    public init(token: @escaping @Sendable () -> String?, sender: any HTTPSending = URLSessionSender(), timeZone: TimeZone = .current) {
        self.token = token
        self.sender = sender
        self.timeZone = timeZone
    }

    /// "Focusing until 12:00".
    public static func statusText(until: Date, timeZone: TimeZone = .current) -> String {
        "Focusing until \(FocusClock.text(until, timeZone: timeZone))"
    }

    public static let emoji = ":no_bell:"
    /// A few minutes past the end, so a slow end never leaves a gap.
    public static let grace: TimeInterval = 120

    public func status() async -> HookStatus {
        guard let t = token(), t.hasPrefix("xox") else { return .needsSetup("Paste a Slack token") }
        return .ready
    }

    public func onFocusStart(_ session: FocusSession) async throws {
        guard let t = token() else { throw HookFailure("Not set up") }
        let minutes = max(1, Int((session.until.timeIntervalSinceNow / 60).rounded(.up)))
        async let status: Void = call(SlackAPI.setStatus(token: t, text: Self.statusText(until: session.until, timeZone: timeZone),
                                                         emoji: Self.emoji, expiration: session.until.addingTimeInterval(Self.grace)))
        async let snooze: Void = call(SlackAPI.snooze(token: t, minutes: minutes))
        _ = try await (status, snooze)
    }

    public func onFocusEnd(_ session: FocusSession, kept: Bool) async throws {
        guard let t = token() else { throw HookFailure("Not set up") }
        async let status: Void = call(SlackAPI.clearStatus(token: t))
        async let snooze: Void = endSnooze(t)
        _ = try await (status, snooze)
    }

    /// "snooze_not_active" means it already ended: that's fine.
    private func endSnooze(_ t: String) async throws {
        do { try await call(SlackAPI.endSnooze(token: t)) } catch let f as HookFailure where f.message.contains("snooze_not_active") {}
    }

    private func call(_ request: URLRequest) async throws {
        let (code, data) = try await sender.send(request)
        guard code == 200 else { throw HookFailure("Slack answered \(code)") }
        _ = try SlackAPI.check(data)
    }
}

/// End times as people read them: "12:00", "18:30" (24-hour, the Mac's zone).
public enum FocusClock {
    public static func text(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
