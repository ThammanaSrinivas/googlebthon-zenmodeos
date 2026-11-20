import CoreGraphics
import Foundation
import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// The after-hours guard (the right to disconnect). At the end of work hours: a wrap-up nudge,
/// Slack "Offline, back 9:30 AM" (it expires when work starts), and the Mac goes quiet (Do Not
/// Disturb). Minutes the Mac is in use after hours go to `daily.after_hours_min`. When work starts
/// again, everything comes back.
@MainActor
@Observable
final class AfterHoursGuard {
    static let hoursKey = "zen.workHours"
    static let enabledKey = "zen.afterHours.enabled"
    static let offlineKey = "zen.afterHours.offline"
    /// The Mac counts as in use when the last input was this recent.
    static let idleLimit: TimeInterval = 120
    static let tick: Duration = .seconds(30)
    static let flushEvery = 5

    private let defaults: UserDefaults
    private(set) var hours: WorkHours
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Self.enabledKey) } }
    /// The evening is on: Slack says offline and the Mac is quiet.
    private(set) var offline: Bool { didSet { defaults.set(offline, forKey: Self.offlineKey) } }
    /// After-hours minutes counted today and not yet written.
    private(set) var pendingMinutes = 0
    private(set) var lastStatus: String?

    /// Wrap-up nudge (Zeno in the notch, the Wrap up card).
    @ObservationIgnored var onWorkEnded: (() -> Void)?
    @ObservationIgnored private var wasWork: Bool?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastCounted: Date?
    @ObservationIgnored private weak var focus: FocusModel?
    @ObservationIgnored private var sync: @Sendable () -> (any FocusSyncService)? = { nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hours = defaults.data(forKey: Self.hoursKey).flatMap { try? JSONDecoder().decode(WorkHours.self, from: $0) }
            ?? WorkHours(tz: TimeZone.current.identifier)
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        offline = defaults.bool(forKey: Self.offlineKey)
    }

    var window: WorkWindow? { WorkWindow(hours) }

    func isAfterHours(_ now: Date = Date()) -> Bool { enabled && (window.map { !$0.isWorkTime(now) } ?? false) }

    func nextWorkStart(after now: Date = Date()) -> Date? { window?.nextStart(after: now) }

    func start(focus: FocusModel, sync: @escaping @Sendable () -> (any FocusSyncService)?) {
        self.focus = focus
        self.sync = sync
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.step(now: Date())
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    func save(_ new: WorkHours) {
        guard WorkWindow(new) != nil else { return }
        hours = new
        defaults.set(try? JSONEncoder().encode(new), forKey: Self.hoursKey)
        wasWork = nil
        let s = sync
        Task { try? await s()?.saveWorkHours(new) }
    }

    /// The demo's "6:30 PM": run the end of the day now.
    func endWorkNow() async {
        await workEnded(now: Date())
    }

    /// Back to work: Slack's status cleared, Do Not Disturb off.
    func backToWork() async {
        offline = false
        lastStatus = nil
        let s = FocusSettings(defaults: defaults)
        if let token = s.slackToken { _ = try? await SlackSession.call(SlackAPI.clearStatus(token: token)) }
        if s.dnd, focus?.isFocusing != true { _ = try? await ProcessRunner().run(ShortcutsDNDHook.tool, ["run", ShortcutsDNDHook.offShortcut]) }
    }

    private func step(now: Date) async {
        guard enabled, let window else { return }
        let isWork = window.isWorkTime(now)
        switch AfterHours.step(wasWork: wasWork, isWork: isWork) {
        case .workEnded: await workEnded(now: now)
        case .workStarted: if offline { await backToWork() }
        case .none: break
        }
        wasWork = isWork
        await count(now: now, isWork: isWork)
    }

    private func workEnded(now: Date) async {
        onWorkEnded?()
        offline = true
        let s = FocusSettings(defaults: defaults)
        guard let back = window?.nextStart(after: now) else { return }
        let text = AfterHours.statusText(back: back, now: now, timeZone: window?.timeZone ?? .current)
        lastStatus = text
        if let token = s.slackToken {
            async let status = SlackSession.call(SlackAPI.setStatus(token: token, text: text, emoji: ":crescent_moon:", expiration: back))
            async let snooze = SlackSession.call(SlackAPI.snooze(token: token, minutes: max(1, Int(back.timeIntervalSince(now) / 60))))
            _ = try? await (status, snooze)
        }
        if s.dnd, focus?.isFocusing != true {
            _ = await withDeadline(.seconds(5)) { try await ProcessRunner().run(ShortcutsDNDHook.tool, ["run", ShortcutsDNDHook.onShortcut]) }
        }
    }

    /// One minute per tick-minute the Mac is in use outside work hours; written every few minutes.
    private func count(now: Date, isWork: Bool) async {
        defer { lastCounted = now }
        guard !isWork, let last = lastCounted, now.timeIntervalSince(last) < 120, Self.idleSeconds() < Self.idleLimit else { return }
        let before = Int(last.timeIntervalSince1970 / 60), after = Int(now.timeIntervalSince1970 / 60)
        pendingMinutes += max(0, after - before)
        if pendingMinutes >= Self.flushEvery { await flush(now: now) }
    }

    func flush(now: Date = Date()) async {
        guard pendingMinutes > 0, let focus else { return }
        let n = pendingMinutes
        pendingMinutes = 0
        await focus.addAfterHours(minutes: n, day: FocusDayKey.key(now))
    }

    /// Seconds since the last keyboard or pointer input.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

enum FocusDayKey {
    static func key(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Integrations › Focus Mode: work hours and the after-hours guard.
struct WorkHoursCard: View {
    @Environment(AppModel.self) private var model
    @State private var start = Date()
    @State private var end = Date()
    @State private var days: Set<Int> = []
    @State private var running = false

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let g = model.afterHours
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.surfaceTint))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work hours · after-hours guard").font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(g.offline ? (g.lastStatus ?? "Offline for the evening") : "At the end: a wrap-up, Slack “Offline”, and the Mac goes quiet.")
                        .zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer(minLength: 0)
                Toggle("After-hours guard", isOn: Binding(get: { g.enabled }, set: { g.enabled = $0 }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            HStack(spacing: ZenSpace.s3) {
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            }
            .font(ZenFont.text(13))
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    let on = days.contains(d)
                    Button(Self.dayNames[d - 1]) { if on { days.remove(d) } else { days.insert(d) } }
                        .buttonStyle(.plain)
                        .font(ZenFont.text(12, on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textBody)
                        .frame(width: 40, height: 26)
                        .background(Capsule().fill(on ? Color.zen.actionPrimary : Color.zen.surfaceCard.opacity(0.8)))
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            HStack(spacing: ZenSpace.s2) {
                Button("Save hours") { save() }.buttonStyle(ZenPrimaryButtonStyle())
                Button(running ? "Running…" : "Try the evening now") {
                    running = true
                    Task { await g.endWorkNow(); running = false }
                }
                .buttonStyle(ZenSecondaryButtonStyle()).disabled(running)
                if g.offline { Button("Back to work") { Task { await g.backToWork() } }.buttonStyle(ZenLinkButtonStyle()) }
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.lg)
        .onAppear(perform: load)
    }

    private func load() {
        let h = model.afterHours.hours
        start = DayPlanner.date(h.start, on: Date()) ?? Date()
        end = DayPlanner.date(h.end, on: Date()) ?? Date()
        days = Set(h.days)
    }

    private func save() {
        model.afterHours.save(WorkHours(start: DayPlanner.text(start), end: DayPlanner.text(end), days: days.sorted(), tz: TimeZone.current.identifier))
    }
}
