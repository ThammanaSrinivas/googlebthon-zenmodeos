import AppKit
import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// Integrations › Focus Mode: each hook, whether it's ready, and how to set it up. Tokens and
/// secrets go to the Keychain and never leave this Mac.
struct FocusHooksTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Text("Every hook runs when a block starts and again when it ends, all at once. One that fails never stops focus; its chip says so.")
                .zenType(.body).foregroundStyle(Color.zen.textBody)
                .frame(maxWidth: 680, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: ZenSpace.s4, alignment: .top)], spacing: ZenSpace.s4) {
                DNDSetup()
                SlackSetup()
                CalendarSetup()
                WebhookSetup()
            }
        }
    }
}

/// The frame every hook card shares: an icon, the name, a status line, then its own controls.
private struct HookCard<Content: View>: View {
    let symbol: String
    let name: String
    let status: String
    let ready: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.surfaceTint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    HStack(spacing: 6) {
                        Circle().fill(ready ? Color.zen.brandFill : Color.zen.textCaption.opacity(0.5)).frame(width: 7, height: 7)
                        Text(status).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.lg)
    }
}

private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
        Text("\(n)").font(ZenFont.number(11)).foregroundStyle(Color.zen.textBrand).frame(width: 14)
        Text(text).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Do Not Disturb

private struct DNDSetup: View {
    @Environment(AppModel.self) private var model
    @State private var missing: [String]?
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        let ready = missing?.isEmpty == true
        HookCard(symbol: "moon.fill", name: "Mac Do Not Disturb",
                 status: missing == nil ? "Checking…" : ready ? "Ready: both Shortcuts found" : "Needs the two Focus Shortcuts", ready: ready) {
            if !ready {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open Shortcuts and make a new shortcut named “\(ShortcutsDNDHook.onShortcut)”.")
                    step(2, "Add Set Focus: turn Do Not Disturb On until Turned Off.")
                    step(3, "Make “\(ShortcutsDNDHook.offShortcut)”: Set Focus, turn Do Not Disturb Off.")
                }
            }
            HStack(spacing: ZenSpace.s2) {
                if !ready {
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
                Button("Check again") { Task { await check() } }.buttonStyle(ZenLinkButtonStyle())
                if ready {
                    Button(testing ? "Testing…" : "Test") { Task { await test() } }.buttonStyle(ZenLinkButtonStyle()).disabled(testing)
                }
                Spacer(minLength: 0)
                FocusToggle(key: FocusSettings.dndKey, label: "Use Do Not Disturb")
            }
            if let result { Text(result).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
        }
        .task { await check() }
    }

    private func check() async {
        missing = await ShortcutsDNDHook(runner: ProcessRunner()).missing()
    }

    private func test() async {
        testing = true
        let hook = ShortcutsDNDHook(runner: ProcessRunner())
        let b = FocusBlock(id: "test", startAt: Date(), until: Date().addingTimeInterval(60), source: .manual)
        do {
            try await hook.onFocusStart(b)
            try? await Task.sleep(for: .seconds(2))
            try await hook.onFocusEnd(b, kept: true)
            result = "Do Not Disturb went on, then off."
        } catch {
            result = (error as? HookFailure)?.message ?? "It didn't run."
        }
        testing = false
    }
}

// MARK: Slack

private struct SlackSetup: View {
    @State private var token = ""
    @State private var who: String?
    @State private var error: String?
    @State private var saved = FocusSecrets.shared.value(FocusSecrets.slackToken) != nil
    @State private var busy = false

    var body: some View {
        HookCard(symbol: "number", name: "Slack",
                 status: saved ? (who.map { "Connected as \($0)" } ?? "Connected") : "Paste a user token (xoxp-…)", ready: saved) {
            if saved {
                Text("While you focus: “Focusing until 12:00” and notifications paused. Both expire on their own.")
                    .zenType(.caption).foregroundStyle(Color.zen.textCaption).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: ZenSpace.s2) {
                    Button("Disconnect") { FocusSecrets.shared.set(nil, FocusSecrets.slackToken); saved = false; who = nil }
                        .buttonStyle(ZenLinkButtonStyle())
                    Spacer(minLength: 0)
                    FocusToggle(key: FocusSettings.slackKey, label: "Use Slack")
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "api.slack.com/apps › your ZenMode OS app › OAuth & Permissions.")
                    step(2, "Copy the User OAuth Token and paste it here. It stays in this Mac's Keychain.")
                }
                HStack(spacing: ZenSpace.s2) {
                    SecureField("xoxp-…", text: $token).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        .accessibilityLabel("Slack user token")
                    Button(busy ? "Checking…" : "Connect") { Task { await connect() } }
                        .buttonStyle(ZenPrimaryButtonStyle()).disabled(busy || !token.hasPrefix("xox"))
                }
            }
            if let error { Text(error).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct) }
        }
        .task { if saved { await whoAmI() } }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let json = try await SlackSession.call(SlackAPI.authTest(token: t))
            FocusSecrets.shared.set(t, FocusSecrets.slackToken)
            token = ""
            saved = true
            error = nil
            who = SlackSession.who(json)
        } catch {
            self.error = (error as? HookFailure)?.message ?? "Couldn't reach Slack."
        }
    }

    private func whoAmI() async {
        guard let t = FocusSecrets.shared.value(FocusSecrets.slackToken),
              let json = try? await SlackSession.call(SlackAPI.authTest(token: t)) else { return }
        who = SlackSession.who(json)
    }
}

/// Slack calls from the app (outside a hook).
enum SlackSession {
    static func call(_ request: URLRequest) async throws -> [String: Any] {
        let (code, data) = try await URLSessionSender().send(request)
        guard code == 200 else { throw HookFailure("Slack answered \(code)") }
        return try SlackAPI.check(data)
    }

    static func who(_ json: [String: Any]) -> String? {
        guard let user = json["user"] as? String else { return nil }
        return (json["team"] as? String).map { "@\(user) in \($0)" } ?? "@\(user)"
    }
}

// MARK: Calendar

private struct CalendarSetup: View {
    @Environment(AppModel.self) private var model
    @AppStorage(FocusSettings.calendarIdKey) private var calendarId = ""

    var body: some View {
        let connected = model.calendarLink.state == .connected
        let calendars = connected ? CalendarFocusHook.writableCalendars() : []
        HookCard(symbol: "calendar.badge.clock", name: "Calendar focus block",
                 status: connected ? "Ready: a busy “Focus” event for each block" : "Connect your calendar", ready: connected) {
            Text("Through macOS Calendar: add your Google account there and the block shows in Google Calendar too.")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ZenSpace.s2) {
                if connected {
                    Picker("Calendar", selection: $calendarId) {
                        Text("Default calendar").tag("")
                        ForEach(calendars, id: \.id) { c in Text("\(c.title) · \(c.source)").tag(c.id) }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                    .accessibilityLabel("Calendar for focus blocks")
                } else {
                    Button("Connect calendar") { Task { await model.calendarLink.connect() } }.buttonStyle(ZenPrimaryButtonStyle())
                }
                Spacer(minLength: 0)
                FocusToggle(key: FocusSettings.calendarKey, label: "Add focus blocks")
            }
        }
    }
}

// MARK: Webhook

private struct WebhookSetup: View {
    @AppStorage(FocusSettings.webhookURLKey) private var url = ""
    @State private var draft = ""
    @State private var secret = FocusSecrets.shared.value(FocusSecrets.webhookSecret)
    @State private var result: String?
    @State private var showSecret = false

    var body: some View {
        let ready = !url.isEmpty && secret != nil
        HookCard(symbol: "point.3.connected.trianglepath.dotted", name: "Webhook",
                 status: ready ? "Ready: signed posts on start and end" : "Add an https URL", ready: ready) {
            Text("POST {event, session_id, start_at, until, kept, source}, signed X-ZenMode-Signature: sha256=HMAC. No name, no email, no apps.")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ZenSpace.s2) {
                TextField("https://…", text: $draft).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Webhook URL")
                    .onSubmit(save)
                Button("Save", action: save).buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(URL(string: draft).map(Webhook.isAllowed) != true)
            }
            if let secret {
                HStack(spacing: ZenSpace.s2) {
                    Text(showSecret ? secret : String(repeating: "•", count: 16)).font(ZenFont.number(11)).foregroundStyle(Color.zen.textBody)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button(showSecret ? "Hide" : "Show secret") { showSecret.toggle() }.buttonStyle(ZenLinkButtonStyle())
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                    }.buttonStyle(ZenLinkButtonStyle())
                    Spacer(minLength: 0)
                    if ready { Button("Send test") { Task { await test() } }.buttonStyle(ZenLinkButtonStyle()) }
                }
            }
            if let result { Text(result).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
        }
        .onAppear { draft = url }
    }

    private func save() {
        guard let u = URL(string: draft.trimmingCharacters(in: .whitespaces)), Webhook.isAllowed(u) else { return }
        url = u.absoluteString
        if secret == nil {
            let s = Webhook.newSecret()
            FocusSecrets.shared.set(s, FocusSecrets.webhookSecret)
            secret = s
        }
        result = "Saved."
    }

    private func test() async {
        guard let u = URL(string: url), let secret else { return }
        let hook = WebhookHook(config: { WebhookConfig(url: u, secret: secret) })
        let b = FocusBlock(id: "test", startAt: Date(), until: Date().addingTimeInterval(25 * 60), source: .manual)
        do {
            try await hook.onFocusStart(b)
            result = "Sent a signed focus_start."
        } catch {
            result = (error as? HookFailure)?.message ?? "It didn't send."
        }
    }
}

/// On/off for one hook, saved with Focus Mode's settings.
private struct FocusToggle: View {
    let key: String
    let label: String
    @AppStorage private var on: Bool

    init(key: String, label: String) {
        self.key = key
        self.label = label
        _on = AppStorage(wrappedValue: true, key)
    }

    var body: some View {
        Toggle(label, isOn: $on).toggleStyle(.switch).labelsHidden().controlSize(.small)
            .accessibilityLabel(label)
            .help(label)
    }
}
