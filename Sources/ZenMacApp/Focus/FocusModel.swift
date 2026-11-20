import Foundation
import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// Focus Mode's settings: which hooks are on and where they point. Secrets live in the Keychain
/// (FocusSecrets); everything here is plain preferences.
struct FocusSettings: @unchecked Sendable {
    let defaults: UserDefaults

    static let dndKey = "zen.focus.dnd"
    static let slackKey = "zen.focus.slack"
    static let calendarKey = "zen.focus.calendar"
    static let calendarIdKey = "zen.focus.calendarId"
    static let webhookURLKey = "zen.focus.webhookURL"

    private func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
    var dnd: Bool { flag(Self.dndKey) }
    var slack: Bool { flag(Self.slackKey) }
    var calendar: Bool { flag(Self.calendarKey) }
    var calendarId: String? { defaults.string(forKey: Self.calendarIdKey) }
    var webhookURL: URL? { defaults.string(forKey: Self.webhookURLKey).flatMap(URL.init(string:)) }

    func set(_ key: String, _ value: Any?) { defaults.set(value, forKey: key) }

    var slackToken: String? { slack ? FocusSecrets.shared.value(FocusSecrets.slackToken) : nil }

    var webhook: WebhookConfig? {
        guard let url = webhookURL, let secret = FocusSecrets.shared.value(FocusSecrets.webhookSecret) else { return nil }
        return WebhookConfig(url: url, secret: secret)
    }

    /// The hooks, in the order their chips show.
    func hooks() -> [any FocusHook] {
        let s = self
        return [
            ShortcutsDNDHook(runner: ProcessRunner(), enabled: { s.dnd }),
            SlackHook(token: { s.slackToken }),
            CalendarFocusHook(enabled: { s.calendar }, calendarId: { s.calendarId }),
            WebhookHook(config: { s.webhook }),
        ]
    }
}

/// Focus Mode on the Mac: one switch that silences every tool. Shows the end time, never a
/// countdown, and one chip per hook. An early end asks once, then marks the block not kept.
@MainActor
@Observable
final class FocusModel {
    enum Phase: Equatable { case idle, starting, focusing, ending }

    /// The lengths offered: 25, 50, 90 minutes, or until a clock time.
    static let lengths = [25, 50, 90]

    private(set) var phase: Phase = .idle
    private(set) var block: FocusBlock?
    private(set) var chips: [HookOutcome] = []
    /// The last block that ended (the catch-up reads it).
    private(set) var lastEnded: FocusEnded?
    /// "End early?" is showing.
    var confirmingEarlyEnd = false
    /// Called once a block has ended and been written (catch-up, the notch).
    @ObservationIgnored var onEnded: ((FocusEnded) -> Void)?
    @ObservationIgnored var onStarted: ((FocusBlock) -> Void)?

    let settings: FocusSettings
    @ObservationIgnored private var engine: FocusEngine
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var sync: @Sendable () -> (any FocusSyncService)? = { nil }

    init(defaults: UserDefaults = .standard) {
        settings = FocusSettings(defaults: defaults)
        let s = settings
        engine = FocusEngine(hooks: { s.hooks() }, store: UserDefaultsFocusStore(defaults), sync: { nil })
    }

    /// Wires the backend (after sign-in) and ends a block a crash left behind.
    func configure(sync: @escaping @Sendable () -> (any FocusSyncService)?) {
        self.sync = sync
        let s = settings
        let store = UserDefaultsFocusStore(s.defaults)
        engine = FocusEngine(hooks: { s.hooks() }, store: store, sync: sync)
        Task { await resume() }
    }

    var isFocusing: Bool { phase == .focusing || phase == .starting }

    /// "Focus until 12:00".
    var untilText: String? { block.map { "Focus until \(FocusClock.text($0.until))" } }

    /// The next whole or half hour at least 30 minutes away ("until 12:00").
    static func suggestedUntil(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now.addingTimeInterval(30 * 60))
        let m = c.minute ?? 0
        c.minute = m == 0 ? 0 : (m <= 30 ? 30 : 60)
        return cal.date(from: c) ?? now.addingTimeInterval(3600)
    }

    func start(minutes: Int, source: FocusSource = .manual) {
        start(until: Date().addingTimeInterval(TimeInterval(min(max(minutes, 5), 720) * 60)), source: source)
    }

    func start(until: Date, source: FocusSource = .manual) {
        guard phase == .idle, until > Date().addingTimeInterval(60) else { return }
        phase = .starting
        chips = []
        let engine = engine
        Task {
            let (b, outcomes) = await engine.start(until: until, source: source)
            withAnimation(ZenMotion.container) {
                block = b
                chips = outcomes
                phase = .focusing
            }
            schedule(b)
            onStarted?(b)
        }
    }

    /// The End button: on time ends straight away; early asks once.
    func requestEnd() {
        guard phase == .focusing, let block else { return }
        if Date() < block.until.addingTimeInterval(-FocusEngine.keptGrace) {
            confirmingEarlyEnd = true
        } else {
            end()
        }
    }

    func end() {
        guard phase == .focusing else { return }
        confirmingEarlyEnd = false
        phase = .ending
        timer?.cancel()
        let engine = engine
        Task {
            let ended = await engine.end()
            finish(ended)
        }
    }

    /// Debug renders: a block in progress with chips, without running any hook.
    func debugShow(_ b: FocusBlock, chips: [HookOutcome]) {
        block = b
        self.chips = chips
        phase = .focusing
    }

    private func finish(_ ended: FocusEnded?) {
        withAnimation(ZenMotion.container) {
            block = nil
            chips = []
            phase = .idle
            if let ended { lastEnded = ended }
        }
        if let ended { onEnded?(ended) }
    }

    /// A relaunch mid-block: carry on if there's time left, else end it (kept) with every hook.
    private func resume() async {
        if let running = await engine.active, running.session.until > Date() {
            block = running.session
            chips = running.started.map { HookOutcome(id: $0.key, displayName: Self.name($0.key), state: $0.value) }
                .sorted { Self.order($0.id) < Self.order($1.id) }
            phase = .focusing
            schedule(running.session)
        } else if let ended = await engine.recover() {
            finish(ended)
        }
    }

    private func schedule(_ b: FocusBlock) {
        timer?.cancel()
        timer = Task { [weak self] in
            let wait = b.until.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    /// Adds after-hours minutes to today (the after-hours guard).
    func addAfterHours(minutes: Int, day: String) async {
        await engine.addAfterHours(minutes: minutes, day: day)
    }

    /// Days this week (Monday to today) with at least one kept block: a Zen Gold week needs 5.
    func keptDaysThisWeek() async -> Int {
        let e = engine
        var n = 0
        for day in ISOWeek.daysSoFar(Date()) where await e.daily(on: day).blocksKept > 0 { n += 1 }
        return n
    }

    /// Today's Zen Score on the daily record, written only when it changes.
    func recordZenScore(_ tenths: Int) async {
        let e = engine
        await e.setZenScore(tenths, day: e.dayKey(Date()))
    }

    func today() async -> DailyFocus {
        let e = engine
        return await e.daily(on: e.dayKey(Date()))
    }

    static func name(_ id: String) -> String {
        ["dnd": "Do Not Disturb", "slack": "Slack", "calendar": "Calendar", "webhook": "Webhook"][id] ?? id.capitalized
    }

    static func order(_ id: String) -> Int { ["dnd", "slack", "calendar", "webhook"].firstIndex(of: id) ?? 9 }
}
