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
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            Text("Every hook runs when a block starts and again when it ends, all at once. One that fails never stops focus; its card says so.")
                .zenType(.body).foregroundStyle(Color.zen.textBody)
                .frame(maxWidth: 680, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            pair { DNDSetup() } and: { SlackSetup() }
            pair { CalendarSetup() } and: { WebhookSetup() }
            WorkHoursCard()
        }
    }

    /// Two cards side by side, the same height.
    private func pair<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder and b: () -> B) -> some View {
        HStack(alignment: .top, spacing: ZenSpace.s4) {
            a().frame(maxWidth: .infinity, maxHeight: .infinity)
            b().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The frame every hook card shares: an icon, the name and whether it's ready (a symbol and words,
/// never colour alone), then its own controls, then (for most) its switch, labelled, at the foot.
struct HookCard<Content: View>: View {
    let symbol: String
    let name: String
    let status: String
    let ready: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceTint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    HStack(spacing: 5) {
                        Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ready ? Color.zen.textBrand : Color.zen.textCaption)
                        Text(status).font(ZenFont.text(12.5, ready ? .medium : .regular))
                            .foregroundStyle(ready ? Color.zen.textBrand : Color.zen.textCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
    }
}

/// A hook's on/off, at the foot of its card: a hairline, the words, the switch.
struct HookSwitchRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(spacing: ZenSpace.s3) {
            Spacer(minLength: 0)
            Rectangle().fill(Color.zen.borderHairline).frame(height: 1)
            HStack(spacing: ZenSpace.s3) {
                Text(label).font(ZenFont.text(13, .medium)).foregroundStyle(Color.zen.textHeading)
                    .accessibilityHidden(true)
                Spacer(minLength: ZenSpace.s2)
                Text(isOn ? "On" : "Off").font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                    .accessibilityHidden(true)
                Toggle(label, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    .tint(Color.zen.brandFill)
                    .accessibilityLabel(label)
                    .help(label)
            }
            .frame(minHeight: 28)
        }
    }
}

/// A text field in the app's style: a raised well with an outline that turns green while typing.
struct HookField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    let label: String
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(ZenFont.text(13))
        .foregroundStyle(Color.zen.textHeading)
        .focused($focused)
        .padding(.horizontal, ZenSpace.s3)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
            .strokeBorder(focused ? Color.zen.textBrand : Color.zen.borderOutline, lineWidth: focused ? 1.5 : 1))
        .accessibilityLabel(label)
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
            HStack(spacing: ZenSpace.s4) {
                if !ready {
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
                if ready {
                    Button(testing ? "Testing…" : "Test it") { Task { await test() } }.buttonStyle(ZenSecondaryButtonStyle()).disabled(testing)
                }
                Button("Check again") { Task { await check() } }.buttonStyle(ZenLinkButtonStyle())
            }
            if let result { Text(result).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
            FocusToggle(key: FocusSettings.dndKey, label: "Do Not Disturb while I focus")
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
                Button("Disconnect") { FocusSecrets.shared.set(nil, FocusSecrets.slackToken); saved = false; who = nil }
                    .buttonStyle(ZenLinkButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "api.slack.com/apps › your ZenMode OS app › OAuth & Permissions.")
                    step(2, "Copy the User OAuth Token and paste it here. It stays in this Mac's Keychain.")
                }
                HStack(spacing: ZenSpace.s2) {
                    HookField(placeholder: "xoxp-…", text: $token, secure: true, label: "Slack user token")
                        .frame(maxWidth: 280)
                        .onSubmit { if token.hasPrefix("xox") { Task { await connect() } } }
                    Button(busy ? "Checking…" : "Connect") { Task { await connect() } }
                        .buttonStyle(ZenPrimaryButtonStyle()).disabled(busy || !token.hasPrefix("xox"))
                }
            }
            if let error { Text(error).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct) }
            if saved { FocusToggle(key: FocusSettings.slackKey, label: "Slack status while I focus") }
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
            if connected {
                HStack(spacing: ZenSpace.s3) {
                    Text("Add blocks to").font(ZenFont.text(13)).foregroundStyle(Color.zen.textBody)
                    Picker("Calendar", selection: $calendarId) {
                        Text("Default calendar").tag("")
                        ForEach(calendars, id: \.id) { c in Text("\(c.title) · \(c.source)").tag(c.id) }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                    .accessibilityLabel("Calendar for focus blocks")
                }
            } else {
                Button("Connect calendar") { Task { await model.calendarLink.connect() } }.buttonStyle(ZenPrimaryButtonStyle())
            }
            FocusToggle(key: FocusSettings.calendarKey, label: "Focus blocks on my calendar")
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
                HookField(placeholder: "https://…", text: $draft, label: "Webhook URL")
                    .onSubmit(save)
                Button(draft == url && !url.isEmpty ? "Saved" : "Save", action: save).buttonStyle(ZenSecondaryButtonStyle())
                    .disabled(draft == url || URL(string: draft).map(Webhook.isAllowed) != true)
            }
            if let secret {
                HStack(spacing: ZenSpace.s4) {
                    Text(showSecret ? secret : String(repeating: "•", count: 16)).font(ZenFont.number(11)).foregroundStyle(Color.zen.textBody)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button(showSecret ? "Hide" : "Show secret") { showSecret.toggle() }.buttonStyle(ZenLinkButtonStyle())
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                    }.buttonStyle(ZenLinkButtonStyle())
                    Spacer(minLength: 0)
                    if ready { Button("Send a test") { Task { await test() } }.buttonStyle(ZenLinkButtonStyle()) }
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
        HookSwitchRow(label: label, isOn: $on)
    }
}
