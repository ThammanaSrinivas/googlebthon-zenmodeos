import Foundation
import Albeit
import ZenAPI
import ZenFocus
import ZenLogic
import MacUsage

extension AppModel {
    /// Wires Focus Mode to the backend and Zeno, and ends a block a crash left behind.
    func startFocusMode() {
        #if DEBUG
        let sync: (any FocusSyncService)? = services.focus.map { LoggingFocusSync(inner: $0) }
        #else
        let sync = services.focus
        #endif
        focus.onStarted = { [weak self] block in
            #if DEBUG
            focusLog("[focus] start until=\(FocusClock.text(block.until)) " + (self?.focus.chips ?? []).map { "\($0.id)=\($0.state.rawValue)" + ($0.note.map { "(\($0))" } ?? "") }.joined(separator: " "))
            #endif
            self?.notch.speak(.init(feeling: .pleasant, kicker: "Focus Mode", line: "Focusing until \(FocusClock.text(block.until)). I'll keep watch."),
                              hold: .seconds(3), respectQuiet: false)
        }
        focus.onEnded = { [weak self] ended in
            #if DEBUG
            focusLog("[focus] end kept=\(ended.record.kept) min=\(ended.record.focusedMin) " + ended.endOutcomes.map { "\($0.id)=\($0.state.rawValue)" + ($0.note.map { "(\($0))" } ?? "") }.joined(separator: " ")
                  + " daily=\(ended.day):\(ended.daily.focusMin)/\(ended.daily.blocksKept)of\(ended.daily.blocksStarted)")
            #endif
            self?.focusEnded(ended)
        }
        focus.configure(sync: { sync })
        afterHours.onWorkEnded = { [weak self] in self?.workDayEnded() }
        followVoiceFocus()
        afterHours.start(focus: focus, sync: { sync })
        #if DEBUG
        // Functional tests: ZEN_FOCUS_MINUTES=1 starts a block at launch; ZEN_FOCUS_END_AFTER=20 ends
        // it early after that many seconds.
        let env = ProcessInfo.processInfo.environment
        // ZEN_WEBHOOK_URL + ZEN_WEBHOOK_SECRET point the webhook at a local receiver
        // (scripts/webhook-receiver.mjs); the app saves the secret in its own Keychain item.
        if let url = env["ZEN_WEBHOOK_URL"], let secret = env["ZEN_WEBHOOK_SECRET"] {
            focus.settings.set(FocusSettings.webhookURLKey, url)
            FocusSecrets.shared.set(secret, FocusSecrets.webhookSecret)
        }
        if let m = env["ZEN_FOCUS_MINUTES"].flatMap(Int.init) {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.focus.start(until: Date().addingTimeInterval(TimeInterval(m * 60)), source: .manual)
                if let s = env["ZEN_FOCUS_END_AFTER"].flatMap(Double.init) {
                    try? await Task.sleep(for: .seconds(s))
                    self?.focus.end()
                }
            }
        }
        #endif
    }

    /// "Zeno, focus 25 minutes" by voice: Zeno's start_focus becomes a Focus Mode block (source voice).
    func followVoiceFocus() {
        Task { [weak self] in
            var seen: String?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard let f = voice?.activeFocus, f.id != seen else { continue }
                seen = f.id
                if !focus.isFocusing, f.endsAt > Date().addingTimeInterval(90) {
                    startFocus(until: f.endsAt, source: .voice)
                }
            }
        }
    }

    /// This Mac's own Zen Score (never the account's combined one, so no iPhone number reaches the
    /// team) goes on the daily record every minute it changes: the team's good-day rate reads it.
    func recordMacScore(monitor: MacUsageMonitor, promiseHours: @escaping @MainActor () -> Int) {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let day = monitor.today
                let score = ZenScoreRule.score(minutes: day.countedMinutes, pullBacks: day.pullBacks, promiseMinutes: promiseHours() * 60)
                await focus.recordZenScore(score.tenths)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func startFocus(minutes: Int, source: FocusSource = .manual) {
        focus.start(minutes: minutes, source: source)
    }

    func startFocus(until: Date, source: FocusSource = .manual) {
        focus.start(until: until, source: source)
    }

    /// A block ended: Zeno says so, then the catch-up reads what came in (on this Mac).
    func focusEnded(_ ended: FocusEnded) {
        let line = ended.record.kept ? "Block kept. Let's see what came in." : "Focus ended. Everything's back on."
        notch.speak(.init(feeling: ended.record.kept ? .happy : .pleasant, kicker: "Focus Mode", line: line, important: true),
                    hold: .seconds(3), respectQuiet: false)
        // The block's hooks have just cleared Slack and Do Not Disturb: after hours, the evening goes back on.
        Task { await afterHours.blockEnded() }
        Task {
            await catchUp.focusEnded(since: ended.record.session.startAt)
            if case .waiting(let n) = catchUp.state {
                notch.speak(.init(feeling: .curious, kicker: "What did I miss?", line: n == 1 ? "1 message came in." : "\(n) messages came in.", important: true),
                            hold: .seconds(3), respectQuiet: false)
            }
        }
    }

    /// Plan my day: today's calendar and the open tasks, through zenoPlanDay.
    func planMyDay() async {
        let end = afterHours.hours.end
        await dayPlan.planDay(work: services.work, events: calendarLink.events, dayEnd: end, cohortId: team.team?.cohortId)
    }

    /// Wrap up: done and open tasks with today's focus, through zenoWrapUp.
    func wrapUpDay() async {
        await dayPlan.wrapUp(work: services.work, today: await focus.today())
    }

    /// The end of work hours: Zeno nudges a wrap-up.
    func workDayEnded() {
        notch.speak(.init(feeling: .sleepy, kicker: "Work's done", line: "Wrap up, then log off.", important: true), hold: .seconds(3.4), respectQuiet: false)
        wrapUpOffered = true
    }
}

#if DEBUG
/// Functional tests read these lines on stderr (unbuffered).
func focusLog(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
#endif

#if DEBUG
/// Debug builds: every focus write and how it went, on stderr, for the functional tests.
struct LoggingFocusSync: FocusSyncService {
    let inner: any FocusSyncService

    private func log<T>(_ what: String, _ body: () async throws(FocusSyncError) -> T) async throws(FocusSyncError) -> T {
        do {
            let v = try await body()
            focusLog("[sync] \(what) ok")
            return v
        } catch {
            focusLog("[sync] \(what) \(error)")
            throw error
        }
    }

    func setLive(_ live: LiveFocus) async throws(FocusSyncError) {
        try await log("live active=\(live.active)") { () async throws(FocusSyncError) in try await inner.setLive(live) }
    }
    func save(_ record: FocusRecord) async throws(FocusSyncError) {
        try await log("session kept=\(record.kept)") { () async throws(FocusSyncError) in try await inner.save(record) }
    }
    func saveDaily(_ daily: DailyFocus, day: String) async throws(FocusSyncError) {
        try await log("daily \(day) focus=\(daily.focusMin) kept=\(daily.blocksKept)/\(daily.blocksStarted) after=\(daily.afterHoursMin) score=\(daily.zenScoreTenths.map(String.init) ?? "-")") { () async throws(FocusSyncError) in
            try await inner.saveDaily(daily, day: day)
        }
    }
    func saveWorkHours(_ hours: WorkHours) async throws(FocusSyncError) {
        try await log("work_hours") { () async throws(FocusSyncError) in try await inner.saveWorkHours(hours) }
    }
    func liveFocus() -> AsyncStream<LiveFocus> { inner.liveFocus() }
}
#endif
