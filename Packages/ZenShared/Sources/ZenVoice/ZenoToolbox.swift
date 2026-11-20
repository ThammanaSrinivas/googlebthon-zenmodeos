import Foundation
import ZenAPI
import ZenLogic

/// What a tool call produced: the JSON that goes back to Gemini, and what the island should show.
public struct ToolOutcome: Equatable, Sendable {
    public let result: JSONValue
    public let card: ToolCard?

    public init(result: JSONValue, card: ToolCard? = nil) {
        self.result = result
        self.card = card
    }

    public var ok: Bool { result["ok"]?.boolValue ?? false }

    static func failure(_ message: String) -> ToolOutcome {
        ToolOutcome(result: ["ok": false, "error": .string(message)])
    }
}

/// The card the notch or island shows for a tool's result.
public enum ToolCard: Equatable, Sendable {
    case status(ZenStatus)
    case intent(IntentSession)
    case intentEnded(IntentSession)
    case focus(FocusSession)
    case pause(AppPause)
    case zenCard(ZenCard)
}

/// The account's state as `get_zen_status` reads it: the combined Zen Score from the backend, and
/// the device's own ledger.
public struct ZenStatus: Equatable, Sendable {
    /// Nil when the score couldn't be read (offline, signed out).
    public let score: ZenScore?
    public let week: WeekProgress?
    public let ledger: LedgerStatus
}

/// Runs a tool call. `ZenoToolbox` is the real one; tests can stand in their own.
public protocol ZenoToolExecutor: Sendable {
    func call(_ name: String, args: JSONValue) async -> ToolOutcome
}

/// Executes Zeno's seven tools: validates and clamps the arguments exactly as the prototype's
/// ledger did, runs them on the on-device ledger (intents, focus, pauses), reads the live score
/// from `ScoreService`, and saves and shares Zen Cards through `ZenCardService`. Returns the JSON
/// the prototype returned, adapted: no simulated score moves, and nothing that would put a score
/// on a shared card.
public struct ZenoToolbox: ZenoToolExecutor {
    public let ledger: OnDeviceLedger
    private let scores: any ScoreService
    private let cards: any ZenCardService
    private let scoreTimeout: Duration

    public init(ledger: OnDeviceLedger, scores: any ScoreService, cards: any ZenCardService,
                scoreTimeout: Duration = .seconds(4)) {
        self.ledger = ledger
        self.scores = scores
        self.cards = cards
        self.scoreTimeout = scoreTimeout
    }

    public func call(_ name: String, args: JSONValue) async -> ToolOutcome {
        let args = args.objectValue ?? [:]
        switch ZenoAgent.ToolName(rawValue: name) {
        case .getZenStatus: return await getZenStatus()
        case .setIntent: return await setIntent(args)
        case .endSession: return await endSession(args)
        case .startFocus: return await startFocus(args)
        case .pauseApp: return await pauseApp(args)
        case .logReflection: return await logReflection(args)
        case .shareWithCircle: return await shareWithCircle(args)
        case nil: return .failure("unknown tool \(name)")
        }
    }

    // MARK: get_zen_status

    func getZenStatus() async -> ToolOutcome {
        let snapshot = await readScore()
        let ledger = await ledger.status()
        let status = ZenStatus(score: snapshot?.score, week: snapshot?.week, ledger: ledger)
        var result: [String: JSONValue] = [
            "ok": true,
            "score_available": .bool(snapshot != nil),
            "good_day_threshold": 6.0,
            "good_days_needed_to_win_week": .int(WeekProgress.goodDaysToWin),
            "pickups_today": .int(ledger.pickups.total),
            "pickups_with_intent": .int(ledger.pickups.withIntent),
            "active_session": ledger.activeIntent.map(Self.json) ?? .null,
            "focus": ledger.focus.map(Self.json) ?? .null,
            "paused_apps": .array(ledger.pausedApps.map { .string($0.app) }),
        ]
        if let snapshot {
            result["score"] = .number(Double(snapshot.score.tenths) / 10)
            result["score_text"] = .string(snapshot.score.text)
            result["good_day"] = .bool(snapshot.score.isGoodDay)
            result["good_days_this_week"] = .int(snapshot.week.goodDays)
            result["week_won"] = .bool(snapshot.week.isWon)
            result["weekly_streak_weeks"] = .int(snapshot.week.weeklyStreak)
            result["week_line"] = .string(snapshot.week.statusLine)
            if let change = Self.changeSinceYesterday(snapshot.week) { result["change_since_yesterday"] = .number(change) }
        }
        return ToolOutcome(result: .object(result), card: .status(status))
    }

    private func readScore() async -> ScoreSnapshot? {
        let scores = self.scores
        let timeout = scoreTimeout
        return await withTaskGroup(of: ScoreSnapshot?.self) { group in
            group.addTask { try? await scores.today() }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Today minus yesterday, one decimal, when both days have a score.
    static func changeSinceYesterday(_ week: WeekProgress) -> Double? {
        guard let today = week.todayIndex, today > 0, let now = week.days[today], let before = week.days[today - 1] else {
            return nil
        }
        return Double(now.tenths - before.tenths) / 10
    }

    // MARK: set_intent

    func setIntent(_ args: [String: JSONValue]) async -> ToolOutcome {
        let app = Self.text(args["app"], limit: ZenoLimits.maxAppNameLength) ?? "Phone"
        let purpose = Self.text(args["purpose"], limit: ZenoLimits.maxPurposeLength) ?? ""
        let minutes = Self.wholeNumber(args["minutes"], default: ZenoLimits.defaultIntentMinutes)
            .clamped(to: ZenoLimits.intentMinutes)
        let (session, replaced) = await ledger.startIntent(app: app, purpose: purpose, minutes: minutes)
        var result: [String: JSONValue] = [
            "ok": true, "session_id": .string(session.id), "app": .string(app), "minutes": .int(minutes),
            "ends_at": .string(Self.iso(session.endsAt)),
        ]
        if let replaced { result["replaced_session_id"] = .string(replaced.id) }
        return ToolOutcome(result: .object(result), card: .intent(session))
    }

    // MARK: end_session

    func endSession(_ args: [String: JSONValue]) async -> ToolOutcome {
        let id = Self.text(args["session_id"], limit: 40)
        let overrun = Self.wholeNumber(args["overrun_minutes"], default: 0).clamped(to: ZenoLimits.overrunMinutes)
        guard let ended = await ledger.endIntent(id: id, overrunMinutes: overrun) else {
            return .failure("no open session")
        }
        return ToolOutcome(result: [
            "ok": true, "session_id": .string(ended.id), "app": .string(ended.app), "minutes": .int(ended.minutes),
            "on_time": .bool(ended.onTime ?? true), "overrun_minutes": .int(ended.overrunMinutes ?? 0),
        ], card: .intentEnded(ended))
    }

    // MARK: start_focus

    func startFocus(_ args: [String: JSONValue]) async -> ToolOutcome {
        let minutes = Self.wholeNumber(args["minutes"], default: ZenoLimits.defaultFocusMinutes)
            .clamped(to: ZenoLimits.focusMinutes)
        let label = Self.text(args["label"], limit: ZenoLimits.maxLabelLength) ?? "Focus"
        var quiet: [String] = []
        for value in args["quiet_apps"]?.arrayValue ?? [] {
            guard let app = Self.text(value, limit: ZenoLimits.maxAppNameLength),
                  !quiet.contains(where: { $0.lowercased() == app.lowercased() }) else { continue }
            quiet.append(app)
            if quiet.count == ZenoLimits.maxQuietApps { break }
        }
        let focus = await ledger.startFocus(minutes: minutes, label: label, quietApps: quiet)
        return ToolOutcome(result: [
            "ok": true, "focus_id": .string(focus.id), "minutes": .int(minutes), "label": .string(label),
            "ends_at": .string(Self.iso(focus.endsAt)), "quiet_apps": .array(quiet.map(JSONValue.string)),
            "scope": "this device",
        ], card: .focus(focus))
    }

    // MARK: pause_app

    func pauseApp(_ args: [String: JSONValue]) async -> ToolOutcome {
        let app = Self.text(args["app"], limit: ZenoLimits.maxAppNameLength) ?? "Instagram"
        let seconds = Self.wholeNumber(args["seconds"], default: ZenoLimits.defaultPauseSeconds)
            .clamped(to: ZenoLimits.pauseSeconds)
        let pause = await ledger.pause(app: app, seconds: seconds)
        let all = await ledger.pauses
        return ToolOutcome(result: [
            "ok": true, "app": .string(pause.app), "seconds": .int(pause.seconds),
            "paused_apps": .array(all.map { .string($0.app) }),
        ], card: .pause(pause))
    }

    // MARK: log_reflection

    func logReflection(_ args: [String: JSONValue]) async -> ToolOutcome {
        guard let summary = Self.text(args["summary"], limit: ZenCardDraft.maxSummaryLength) else {
            return .failure("the note is empty")
        }
        let mood = args["mood"]?.stringValue.flatMap { ZenCard.Mood(rawValue: $0.lowercased()) } ?? .pleasant
        let language = Self.text(args["language"], limit: 35) ?? "en"
        let draft = ZenCardDraft(summary: summary, mood: mood, language: language,
                                 earnedBack: Self.text(args["earned_back"], limit: 200),
                                 drift: Self.text(args["drift"], limit: 200))
        let card: ZenCard
        do { card = try await cards.save(draft) } catch { return .failure("could not save the Zen Card") }
        await ledger.setLastCard(id: card.id)
        return ToolOutcome(result: [
            "ok": true, "question": "What did you earn back today?", "card": Self.json(card),
        ], card: .zenCard(card))
    }

    // MARK: share_with_circle

    func shareWithCircle(_ args: [String: JSONValue]) async -> ToolOutcome {
        guard let cardId = await ledger.lastCardId else { return .failure("no Zen Card to share yet") }
        let note = Self.text(args["note"], limit: ZenCardDraft.maxNoteLength)
        let card: ZenCard
        do { card = try await cards.share(cardId: cardId, note: note) } catch {
            return .failure("could not share the Zen Card")
        }
        // include_score from the prototype is ignored on purpose: a shared card never carries a score.
        return ToolOutcome(result: [
            "ok": true, "card_id": .string(card.id), "shared": true, "score_included": false, "note": .text(note),
        ], card: .zenCard(card))
    }

    // MARK: Argument helpers

    /// JavaScript's `Math.round(Number(x) || fallback)`: missing, unparseable and zero all fall back.
    static func wholeNumber(_ value: JSONValue?, default fallback: Int) -> Int {
        guard let number = value?.numberLike, number != 0 else { return fallback }
        let rounded = (number + 0.5).rounded(.down) // Math.round: halves go up
        return Int(max(min(rounded, 1e9), -1e9))
    }

    /// A trimmed, capped string; numbers are written out; nil when empty or missing.
    static func text(_ value: JSONValue?, limit: Int) -> String? {
        let raw: String?
        switch value {
        case .string(let text): raw = text
        // Whole numbers as integers, while they fit one exactly (Int64 traps on 1e20 and beyond).
        case .number(let number): raw = number.rounded() == number && abs(number) < 9.0e15 ? String(Int64(number)) : String(number)
        default: raw = nil
        }
        return ZenCardDraft.clip(raw, limit)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func json(_ session: IntentSession) -> JSONValue {
        ["session_id": .string(session.id), "app": .string(session.app), "purpose": .string(session.purpose),
         "minutes": .int(session.minutes), "ends_at": .string(iso(session.endsAt))]
    }

    static func json(_ focus: FocusSession) -> JSONValue {
        ["focus_id": .string(focus.id), "label": .string(focus.label), "minutes": .int(focus.minutes),
         "ends_at": .string(iso(focus.endsAt)), "quiet_apps": .array(focus.quietApps.map(JSONValue.string))]
    }

    static func json(_ card: ZenCard) -> JSONValue {
        ["id": .string(card.id), "summary": .string(card.summary), "mood": .string(card.mood.rawValue),
         "language": .string(card.language), "earned_back": .text(card.earnedBack), "drift": .text(card.drift),
         "shared": .bool(card.isShared)]
    }
}
