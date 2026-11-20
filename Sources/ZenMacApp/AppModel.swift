import SwiftUI
import Albeit
import ZenAPI
import MacUsage
import ZenVoice

/// The app's state. Views read this and call its intents; they never see a service.
@MainActor
@Observable
final class AppModel {
    enum Step: Int, CaseIterable { case story, seat, uses, quiet, count, bring, handoff }
    enum Stage: Equatable { case onboarding(Step), today }

    enum CodeState: Equatable {
        case idle, checking, found(CohortPreview), joined(CohortSummary), failed(String)
    }

    enum PairState: Equatable { case waiting, approving, paired, failed(String) }

    /// Who is signing in: a team member (the employee) or the person who runs the team (the employer).
    enum SignInRole: String, CaseIterable, Sendable { case member, admin }

    /// Where the hand-off leads, from the role picked and what the backend says after sign-in.
    enum HandoffPath: Equatable {
        /// A member: Today, with the join code ready when they haven't joined a group yet.
        case member(joined: Bool)
        /// An admin of this team: Today opens on Team admin.
        case adminTeam(String)
        /// Picked "I run a team" but administers none yet: the team is made on the web.
        case adminCreate
    }

    var stage: Stage = .onboarding(.story)
    /// Which story card opens first (debug tours start mid-story).
    var initialStoryIndex = 0
    var profile = Profile()
    /// Picked on the sign-in step, before Apple or Google. Most people are members.
    private(set) var signInRole: SignInRole = .member
    var codeText = "" { didSet { let clean = JoinCode.sanitize(codeText); if clean != codeText { codeText = clean } } }
    private(set) var codeState: CodeState = .idle
    private(set) var cohort: CohortSummary?
    private(set) var user: ZenUser? {
        didSet { if user != oldValue { Task { await admin.refreshTeam(services.admin) } } }
    }
    private(set) var pairing: PairingCode?
    private(set) var pairState: PairState = .waiting
    private(set) var snapshot: ScoreSnapshot?
    private(set) var accessibilityTrusted = AccessibilityAccess.isTrusted
    private(set) var lastNudge: (ZenoNudge, NudgeSource)?

    let notch = NotchModel()
    /// Today's dashboard: the day picked, the open pattern card, the search.
    let dashboard = DashboardModel()
    let frontmost = FrontmostTracker()
    /// The fakes until launch, then whatever the app target chose (`ZenMacBackend`).
    private(set) var services: Services = .fakes()

    /// The QR pairing on "Bring your day" (the iPhone scans, approves, the Mac signs in). Off for
    /// the buildathon demo build: the step is a plain sign-in. Flip to true to bring it back; the
    /// pairing flow, the QR and the iPhone's approve screen are all still here.
    static let qrPairingEnabled = false
    /// This model's switch (tests turn it on); starts as `qrPairingEnabled`.
    var qrPairing = AppModel.qrPairingEnabled

    /// Tests: run this model on given services.
    func use(_ services: Services) { self.services = services }
    var isDemo: Bool { services.isDemo }

    private var pairTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    func start() {
        services = ZenMacBackend.make()
        startFocusMode()
        Task { await admin.refreshTeam(services.admin) }
        makeVoice()
        startTalkShortcuts()
        #if DEBUG
        // Functional test: ZEN_VOICE_TRY=1 opens a voice session a few seconds after launch.
        if ProcessInfo.processInfo.environment["ZEN_VOICE_TRY"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                if let self, let voice = self.voice { await self.startVoice(voice, pickup: true) }
            }
        }
        #endif
        AppNap.holdOff()
        frontmost.start()
        followScore()
        Task {
            // Signed in on an earlier launch: straight to Today, and Zeno says welcome back.
            let person = await services.auth.currentUser()
            if let person { resume(signedIn: person) }
            try? await Task.sleep(for: .milliseconds(700))
            if let person {
                notch.speak(.init(feeling: .happy, kicker: Copy.Hello.backKicker, line: Copy.Hello.back(person.firstName)), hold: .seconds(3.2))
            } else {
                notch.speak(.init(feeling: .happy, kicker: Copy.Hello.kicker, line: Copy.Hello.line), hold: .seconds(3.2), respectQuiet: false)
            }
        }
        startWeekAndCalendar()
    }

    /// The account is already signed in (Firebase kept the session): the day syncs and, unless a
    /// later step is already showing, the app opens on Today. Before this, every launch began at
    /// the welcome story as if signed out, so signing in never seemed to stick.
    func resume(signedIn person: ZenUser) {
        user = person
        pairState = .paired
        startDaySync()
        stage = Self.launchStage(stage, signedIn: true)
    }

    /// Where a launch opens: Today when signed in and still on the story's first card; anything
    /// else (a debug tour's step, a person mid-onboarding) stays where it is.
    static func launchStage(_ current: Stage, signedIn: Bool) -> Stage {
        signedIn && current == .onboarding(.story) ? .today : current
    }

    // MARK: Onboarding

    var step: Step? { if case .onboarding(let s) = stage { s } else { nil } }

    func go(_ step: Step) {
        withAnimation(ZenMotion.container) { stage = .onboarding(step) }
        if step == .bring && qrPairing { startPairing() }
        if step == .count { startPermissionPolling() }
        if step == .handoff { playHandoff() }
    }

    func next() {
        guard let s = step else { return }
        if let n = Step(rawValue: s.rawValue + 1) { go(n) } else { finishOnboarding() }
    }

    func back() {
        guard let s = step, let p = Step(rawValue: s.rawValue - 1) else { return }
        go(p)
    }

    func finishOnboarding() {
        notch.quiet = profile.quiet
        preferences.values.quiet = profile.quiet
        withAnimation(ZenMotion.container) { stage = .today }
        Task { await refreshNudge(trigger: .hello) }
        if signInRole == .admin { Task { await openTeamAdminIfAdministering() } }
    }

    func choose(role: SignInRole) {
        guard role != signInRole else { return }
        withAnimation(ZenMotion.container) { signInRole = role }
        let line = role == .admin ? "Running a team? I'll show you its focus." : "Joining your team. Nice."
        notch.speak(.init(feeling: role == .admin ? .proud : .happy, kicker: Copy.Bring.roleKicker, line: line),
                    hold: .seconds(2.6), respectQuiet: false)
    }

    var handoffPath: HandoffPath {
        switch signInRole {
        case .member: .member(joined: cohort != nil)
        case .admin: admin.team.map { .adminTeam($0.name) } ?? .adminCreate
        }
    }

    /// An employer who administers a team lands on Team admin once Today shows; anyone else stays on Today.
    private func openTeamAdminIfAdministering() async {
        if admin.team == nil { await admin.refreshTeam(services.admin) }
        guard admin.team != nil, stage == .today else { return }
        // Today's sidebar listens for `navigate` once it's on screen.
        try? await Task.sleep(for: .milliseconds(450))
        navigate = .admin
    }

    /// Zeno shows a feeling in the notch (the story's feelings row). Onboarding ignores quiet hours.
    func showFeeling(_ index: Int) {
        let feelings: [ZenoFeeling] = [.happy, .pleasant, .curious, .proud, .sleepy]
        let i = (index % feelings.count + feelings.count) % feelings.count
        let line = Copy.feelingLines[i]
        notch.speak(.init(feeling: feelings[i], kicker: line.kicker, line: line.line), hold: .seconds(3.4), respectQuiet: false)
    }

    func choose(seat: Profile.Seat) {
        profile.seat = seat
        if seat == .personal { codeState = .idle; cohort = nil }
        let line: (ZenoFeeling, String) = switch seat {
        case .personal: (.pleasant, "Just us, then. I like it.")
        case .campus: (.happy, "A campus! Got your code?")
        case .team: (.curious, "A team. Which one?")
        }
        notch.speak(.init(feeling: line.0, kicker: "Make it yours", line: line.1), hold: .seconds(2.8), respectQuiet: false)
    }

    func checkCode() {
        guard let code = JoinCode(codeText) else { codeState = .failed(Copy.Seat.notFound); return }
        codeState = .checking
        Task {
            do {
                let preview = try await services.cohorts.preview(code: code)
                withAnimation(ZenMotion.container) { codeState = .found(preview) }
            } catch {
                withAnimation(ZenMotion.container) { codeState = .failed((error as? CohortError) == .offline ? Copy.Seat.offline : Copy.Seat.notFound) }
            }
        }
    }

    func joinCohort() {
        guard let code = JoinCode(codeText) else { return }
        codeState = .checking
        Task {
            do {
                let summary = try await services.cohorts.join(code: code)
                cohort = summary
                profile.cohortCode = code.value
                withAnimation(ZenMotion.container) { codeState = .joined(summary) }
                notch.speak(.init(feeling: .happy, kicker: summary.preview.name, line: "You're in. \(summary.preview.memberCount) people, one score."),
                            hold: .seconds(3), respectQuiet: false)
                try? await Task.sleep(for: .milliseconds(900))
                next()
            } catch {
                withAnimation(ZenMotion.container) { codeState = .failed((error as? CohortError) == .offline ? Copy.Seat.offline : Copy.Seat.notFound) }
            }
        }
    }

    func toggle(use: Profile.Use) {
        if profile.uses.contains(use) { profile.uses.remove(use) } else { profile.uses.insert(use) }
    }

    func choose(quiet: QuietHours) {
        withAnimation(ZenMotion.container) { profile.quiet = quiet }
        let line = quiet == .none ? "Got it. Nights only." : "I'll keep quiet \(quiet.summary.lowercased())."
        notch.speak(.init(feeling: .sleepy, kicker: "Quiet hours", line: line), hold: .seconds(2.8), respectQuiet: false)
    }

    func requestAccessibility() {
        AccessibilityAccess.request()
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let trusted = AccessibilityAccess.isTrusted
                if trusted != accessibilityTrusted { withAnimation(ZenMotion.container) { accessibilityTrusted = trusted } }
                if trusted { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startPairing() {
        pairTask?.cancel()
        pairState = .waiting
        pairTask = Task {
            do {
                let code = try await services.auth.newPairingCode()
                pairing = code
                let person = try await services.auth.waitForApproval(of: code)
                paired(person)
            } catch {
                if !Task.isCancelled { pairState = .failed((error as? AuthError) == .codeExpired ? Copy.Bring.expired : Copy.Seat.offline) }
            }
        }
    }

    /// Mock only: stands in for the iPhone approving the code.
    func simulateApproval() {
        pairTask?.cancel()
        paired(ZenUser(uid: "demo-kamal", displayName: "Kamal"))
    }

    /// The nonce whose hash went into the current Sign in with Apple request.
    private(set) var appleNonce = SignInNonce.make()

    func prepareAppleRequest() -> String {
        appleNonce = SignInNonce.make()
        return appleNonce.sha256
    }

    func signInWithApple(identityToken: Data?, fullName: PersonNameComponents?) {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8) else {
            pairState = .failed(qrPairing ? Copy.Bring.appleFailed : Copy.Bring.appleFailedNoCode)
            return
        }
        pairTask?.cancel()
        pairState = .approving
        let nonce = appleNonce.raw
        Task {
            do { paired(try await services.auth.signInWithApple(identityToken: token, rawNonce: nonce, fullName: fullName)) }
            catch { pairState = .failed(qrPairing ? Copy.Bring.appleFailed : Copy.Bring.appleFailedNoCode) }
        }
    }

    /// Google sign-in comes back through the app's URL scheme.
    func handle(url: URL) {
        _ = services.auth.handle(url: url)
    }

    func signInWithGoogle() {
        pairTask?.cancel()
        pairState = .approving
        Task {
            do { paired(try await services.auth.signInWithGoogle()) } catch { pairState = .failed(Copy.Seat.offline) }
        }
    }

    private func paired(_ person: ZenUser) {
        user = person
        pairState = .paired
        startDaySync()
        go(.handoff)
    }

    private func playHandoff() {
        let name = user?.firstName ?? "there"
        Task {
            snapshot = try? await services.scores.today()
            try? await Task.sleep(for: .milliseconds(760))
            notch.speak(.init(feeling: .happy, kicker: Copy.Handoff.kicker, line: Copy.Handoff.line(name)), hold: .seconds(3.4), respectQuiet: false)
        }
    }

    // MARK: Today

    func refreshNudge(trigger: NudgeContext.Trigger) async {
        let moment: PreferenceValues.Moment? = switch trigger {
        case .pickup: .pickup
        case .checkIn: .checkIn
        case .goodDay: .goodDay
        case .hello: nil
        }
        if let moment, !preferences.spend(moment) { return }
        let snap: ScoreSnapshot? = if let snapshot { snapshot } else { try? await services.scores.today() }
        snapshot = snap
        let hour = Calendar.current.component(.hour, from: Date())
        let context = NudgeContext(scoreTenths: snap?.score.tenths ?? 0, goodDaysThisWeek: snap?.week.goodDays ?? 0,
                                   weeklyStreak: snap?.week.weeklyStreak ?? 0, hourOfDay: hour, trigger: trigger)
        let result = await services.nudges.nudge(for: context)
        lastNudge = result
        // Nudges are written by rules on the server (founders, 20 Nov): never credited to Gemini.
        notch.speak(result.0, kicker: "Zeno")
    }

    // MARK: Week and calendar

    /// The person's calendar on this Mac. Zeno stays quiet in busy events.
    let calendarLink = CalendarLink()
    private(set) var streak: StreakCalendar?
    private(set) var review: (WeeklyReview, NudgeSource)?
    private(set) var reviewLoading = false
    /// The Today toast for a new review was read or closed.
    var reviewSeen = false
    private var headsUpGiven: Set<String> = []
    // TODO(buildathon): ZenCorePrivate's weekly review callable (Gemini Pro) once the private package lands.
    private let reviews = ResilientReviews(service: FakeReviews())

    /// Where everything this Mac keeps is saved: settings, tools, gold, the day sync's progress and
    /// Zeno's intents. `.standard` in the app; tests pass a scratch suite so they never touch it.
    let defaults: UserDefaults
    /// Zeno's settings, saved on this Mac.
    let preferences: ZenPreferences
    /// The tools the person (or their workspace) connected.
    let integrations: IntegrationsModel
    /// Focus Mode: the switch, the hooks, and what each did.
    let focus: FocusModel
    /// "What did I miss?" after a block.
    let catchUp = CatchUpModel()
    /// Work hours and the after-hours guard.
    let afterHours: AfterHoursGuard
    /// The end of work hours offered a wrap-up (Today shows the Wrap up card).
    var wrapUpOffered = false
    /// Plan my day and Wrap up.
    let dayPlan: DayPlanModel
    /// The person's team: Ask Zeno, the Focus Report link, the Zen Gold claim.
    let team = TeamModel()
    /// The team admin's view; its section shows only when this person administers a team.
    let admin = AdminModel()
    /// ⌃⌥Z from anywhere, and "Hey Zeno" (on-device, opt-in): talk to Zeno in the notch.
    let hotKey = TalkHotKey()
    let wake = WakeWordListener()
    /// "Hey Zeno" is on (off until the person turns it on).
    var wakeWordOn = false
    /// Opens Integrations on this tab (a card's "Set up hooks").
    var integrationsTab: IntegrationsSection.Tab?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = ZenPreferences(defaults: defaults)
        integrations = IntegrationsModel(defaults: defaults)
        focus = FocusModel(defaults: defaults)
        afterHours = AfterHoursGuard(defaults: defaults)
        dayPlan = DayPlanModel(defaults: defaults)
        wakeWordOn = defaults.bool(forKey: Self.wakeWordKey)
        goldLedger = GoldLedger(defaults: defaults)
        voiceLedger = OnDeviceLedger(store: ZenVoice.UserDefaultsKeyValueStore(defaults))
    }

    func startWeekAndCalendar() {
        // Zeno keeps quiet when switched off, and inside busy events if the person asked for that.
        notch.isBusy = { [calendarLink, preferences] date in
            !preferences.values.zenoInNotch || (preferences.values.quietInCalendarEvents && calendarLink.isBusy(at: date))
        }
        profile.quiet = preferences.values.quiet
        notch.quiet = preferences.values.quiet
        streak = StreakCalendar(records: WeekDemo.history(today: Date(), calendar: .current), today: Date(), calendar: .current)
        Task { await loadReview() }
        Task { await watchCalendar() }
    }

    func loadReview() async {
        reviewLoading = true
        let result = await reviews.review(for: WeekDemo.recap)
        withAnimation(ZenMotion.container) {
            review = result
            reviewLoading = false
            reviewSeen = false
        }
        if stage == .today, preferences.spend(.weeklyReview) {
            notch.speak(.init(feeling: .pleasant, kicker: "Weekly review", line: "Your week, read. It's on Today.", important: true), hold: .seconds(3.4))
        }
    }

    func connectCalendar() {
        Task {
            await calendarLink.connect()
            calendarLink.refresh()
        }
    }

    /// Every half minute: a heads-up in the notch 10 minutes before a busy event, once per event.
    private func watchCalendar() async {
        while !Task.isCancelled {
            calendarLink.refresh()
            let now = Date()
            if stage == .today, let next = calendarLink.nextBusy(after: now),
               next.start.timeIntervalSince(now) <= 10 * 60, !headsUpGiven.contains(next.id) {
                headsUpGiven.insert(next.id)
                guard preferences.spend(.calendar) else { try? await Task.sleep(for: .seconds(30)); continue }
                let time = next.start.formatted(date: .omitted, time: .shortened)
                notch.speak(.init(feeling: .pleasant, kicker: "Calendar · \(time)", line: "Busy at \(time). I'll keep quiet then.", important: true), hold: .seconds(4))
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    // MARK: Score and day sync

    private var scoreTask: Task<Void, Never>?
    private var usage: MacUsageMonitor?
    private var daySync: MacDaySync?
    private var foreground: NSObjectProtocol?

    /// The live score: a listener on the real backend (the same number on the iPhone and this Mac
    /// within seconds), a 30 s poll on the fakes.
    private func followScore() {
        scoreTask?.cancel()
        let scores = services.scores
        scoreTask = Task { [weak self] in
            for await next in scores.updates() {
                guard let self else { return }
                withAnimation(ZenMotion.container) { self.snapshot = next }
            }
        }
    }

    /// After sign-in: measure this Mac's distracting minutes and pull-backs and publish them. Today
    /// goes out throttled, at once when the app comes forward, and each finished day forced.
    func startDaySync() {
        guard daySync == nil else { daySync?.flush(); return }
        let monitor = MacUsageMonitor()
        let builder = ComputerDayReportBuilder(store: MacUsage.UserDefaultsKeyValueStore(defaults))
        let sync = MacDaySync(days: services.days, builder: builder, clock: SystemClock())
        monitor.start()
        monitor.publish(to: sync)
        usage = monitor
        daySync = sync
        recordMacScore(monitor: monitor, promiseHours: { builder.promiseHours })
        // Focus blocks kept while signed out go up now.
        Task { await focus.flushOutbox() }
        foreground = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.daySync?.flush() }
        }
    }

    /// Where this Mac's day stands, for Settings.
    var daySyncStatus: MacDaySync.Status? { daySync?.status }

    func signOut() {
        Task {
            try? await services.auth.signOut()
            usage?.stop()
            usage = nil
            daySync = nil
            if let foreground { NotificationCenter.default.removeObserver(foreground) }
            foreground = nil
            user = nil
            pairState = .waiting
        }
    }

    // MARK: Zen Gold

    let goldLedger: GoldLedger
    /// Gold pay is open on a won week, and for the whole week after one.
    var goldGate: GoldGate {
        let week = (snapshot ?? FakeSnapshot.value).week
        let finished = streak?.weeks.filter { !$0.isCurrent } ?? []
        return GoldGate(thisWeek: week, lastWeekWon: finished.last?.isWon ?? false)
    }

    func recordGoldOrder(units: Int, quote: GoldQuote) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        goldLedger.record(units: units, pricePaise: quote.lastPaise, week: monday)
    }

    // MARK: Zeno's voice

    /// Intents and focus sessions Zeno sets in conversation, kept on this Mac for the app's life.
    let voiceLedger: OnDeviceLedger
    /// Zeno's voice: Gemini Live with the mic on the real backend; the five-moment demo on fakes,
    /// labelled Demo wherever it shows.
    private(set) var voice: VoiceModel?

    private func makeVoice() {
        let name = user?.firstName ?? "there"
        voice = services.isDemo
            ? VoiceModel.demo(scores: services.scores, cards: services.cards, userName: name)
            : VoiceModel(tokens: services.voiceTokens, scores: services.scores, cards: services.cards,
                         ledger: voiceLedger, userName: name, audio: AVAudioVoiceIO())
        // Zeno finishes before the mic listens again: on a Mac's speakers Zeno would otherwise hear
        // itself and cut its own reply off (macOS can refuse echo cancellation).
        voice?.waitsForZeno = true
    }

    // MARK: Navigation

    /// A card asking to open a section of the sidebar (Today's Gold and month cards use it).
    var navigate: TodayView.Section?
    /// The ⌘K command palette is open.
    var paletteOpen = false

    // MARK: Settings

    func setQuiet(_ quiet: QuietHours) {
        preferences.values.quiet = quiet
        profile.quiet = quiet
        notch.quiet = quiet
    }

    /// Settings › Test: the real notch speaks now, whatever the hour.
    func testZeno(_ feeling: ZenoFeeling) {
        let lines: [ZenoFeeling: String] = [.happy: "Good day locked in. Nice.", .pleasant: "Stretch? You've been at it a while.",
                                            .curious: "Back again. Something on purpose?", .proud: "Week won. That's ten in a row.",
                                            .sleepy: "Bedtime soon. Last scroll?"]
        notch.speak(.init(feeling: feeling, kicker: "\(Copy.product) · test", line: lines[feeling] ?? "Hi, I'm Zeno."), hold: .seconds(3.4), respectQuiet: false)
    }

    func replayOnboarding() {
        withAnimation(ZenMotion.container) { stage = .onboarding(.story) }
    }
}
