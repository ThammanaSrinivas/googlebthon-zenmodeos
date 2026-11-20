import AuthenticationServices
import Foundation
import Observation
import SwiftUI
import ZenAPI
import ZenLogic
import ZenMock

/// The iPhone's backend, chosen by the app target at launch (Apps/iPhone), the fakes otherwise.
public struct PhoneServices: Sendable {
    public let auth: any AuthService
    public let scores: any ScoreService
    public let days: any DaySyncService
    public let voiceTokens: any VoiceTokenService
    public let cards: any ZenCardService
    /// The Mac's focus. The iPhone only reads `live/focus`; it never writes a focus doc.
    public let focus: any FocusSyncService
    public let isDemo: Bool

    public init(auth: any AuthService, scores: any ScoreService, days: any DaySyncService,
                voiceTokens: any VoiceTokenService, cards: any ZenCardService, focus: any FocusSyncService,
                isDemo: Bool) {
        self.auth = auth
        self.scores = scores
        self.days = days
        self.voiceTokens = voiceTokens
        self.cards = cards
        self.focus = focus
        self.isDemo = isDemo
    }

    public static func fakes(focus: FakeFocusSync = FakeFocusSync()) -> PhoneServices {
        PhoneServices(auth: FakeAuth(), scores: FakeScores(), days: FakeSync.demo(),
                      voiceTokens: FakeVoiceTokens(), cards: FakeZenCards(), focus: focus, isDemo: true)
    }
}

@MainActor
public enum ZenPhoneBackend {
    public static var make: @MainActor () -> PhoneServices = { .fakes() }
    /// The Live Activity for the Mac's focus; the app target sets the ActivityKit one.
    public static var focusActivity: @MainActor () -> any FocusActivityControlling = { NoFocusActivity() }
}

/// What the iPhone measured today, if anything. Screen Time (DeviceActivity) fills this; until it
/// does, the phone publishes nothing rather than a number it didn't measure.
@MainActor
protocol PhoneDayMeasure {
    func scoreToday() async -> ZenScore?
}

// TODO(buildathon): a DeviceActivity report extension that scores the day on the phone.
struct NotMeasuredYet: PhoneDayMeasure {
    func scoreToday() async -> ZenScore? { nil }
}

@MainActor
@Observable
final class PhoneModel {
    enum Pairing: Equatable { case idle, confirm(JoinCode), approving, approved, failed(String) }

    let services: PhoneServices
    private(set) var user: ZenUser?
    private(set) var snapshot: ScoreSnapshot?
    private(set) var signingIn = false
    private(set) var signInError: String?
    private(set) var pairing: Pairing = .idle
    var codeText = "" { didSet { let clean = JoinCode.sanitize(codeText); if clean != codeText { codeText = clean } } }
    /// The Mac's `live/focus`, as last heard (idle while signed out).
    private(set) var liveFocus: LiveFocus = .idle
    /// The Mac's focus end time while it's still ahead: what the app's line and the Island show.
    private(set) var focusingUntil: Date?

    private var nonce = SignInNonce.make()
    private var scoreTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    /// The Mac's word has arrived since sign-in. Until it does, an adopted activity stays up.
    private var heardFromMac = false
    /// A refused start is tried again a few times (a cold launch can ask a moment before the
    /// system counts the app as in the foreground), then on the next change or foregrounding.
    private var retryTask: Task<Void, Never>?
    private var startRetries = 0
    static let startRetryLimit = 5
    var startRetryDelay: Duration = .seconds(1)
    private let measure: any PhoneDayMeasure = NotMeasuredYet()
    private let activity: any FocusActivityControlling
    /// The end time of the Live Activity on show, nil when none is.
    private(set) var activityUntil: Date?

    init(services: PhoneServices, activity: any FocusActivityControlling = NoFocusActivity()) {
        self.services = services
        self.activity = activity
    }

    func start() {
        // An activity left from before this launch: keep it while its end time is ahead (the Mac's
        // word arrives in a moment), end it now if that time has passed.
        activityUntil = activity.adopt()
        if let shown = activityUntil, shown <= Date() { endActivity() }
        Task {
            if let person = await services.auth.currentUser() { signedIn(person) } else { endActivity() }
        }
    }

    /// Back in the foreground: an end time may have passed, or a start may have been refused while
    /// the app was in the background.
    func becameActive() {
        guard heardFromMac else { return }
        startRetries = 0
        reconcileFocus()
    }

    // MARK: Sign-in

    func prepareAppleRequest() -> String {
        nonce = SignInNonce.make()
        return nonce.sha256
    }

    func finishApple(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            signInError = PhoneCopy.signInFailed
            return
        }
        let raw = nonce.raw, name = credential.fullName
        signingIn = true
        Task {
            do { signedIn(try await services.auth.signInWithApple(identityToken: token, rawNonce: raw, fullName: name)) }
            catch { signInError = PhoneCopy.signInFailed }
            signingIn = false
        }
    }

    func signInWithGoogle() {
        signingIn = true
        Task {
            do { signedIn(try await services.auth.signInWithGoogle()) }
            catch { signInError = (error as? AuthError) == .cancelled ? nil : PhoneCopy.signInFailed }
            signingIn = false
        }
    }

    func handle(url: URL) {
        if services.auth.handle(url: url) { return }
        // zenmodeos.com/pair/K4M7QX opened on the phone: ask before approving.
        if url.pathComponents.count >= 3, url.pathComponents[1] == "pair", let code = JoinCode(url.pathComponents[2]) {
            pairing = .confirm(code)
        }
    }

    private func signedIn(_ person: ZenUser) {
        user = person
        signInError = nil
        followScore()
        followFocus()
        Task { await publishToday() }
    }

    func signOut() {
        Task {
            try? await services.auth.signOut()
            scoreTask?.cancel()
            focusTask?.cancel()
            user = nil
            snapshot = nil
            liveFocus = .idle
            heardFromMac = false
            reconcileFocus()
        }
    }

    // MARK: The score

    private func followScore() {
        scoreTask?.cancel()
        let scores = services.scores
        scoreTask = Task { [weak self] in
            for await next in scores.updates() {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { self?.snapshot = next }
            }
        }
    }

    // MARK: The Mac's focus

    /// Follows `live/focus` while signed in. Read only: nothing about focus leaves the phone.
    private func followFocus() {
        focusTask?.cancel()
        let focus = services.focus
        focusTask = Task { [weak self] in
            for await next in focus.liveFocus() {
                guard !Task.isCancelled else { return }
                self?.liveFocus = next
                self?.heardFromMac = true
                self?.reconcileFocus()
            }
        }
    }

    /// Brings the line and the Live Activity in step with `liveFocus`: start when the Mac is
    /// focusing and the end is ahead, move the end time when it changes, end when the Mac stops or
    /// the time passes. Never two activities.
    private func reconcileFocus() {
        let now = Date()
        focusingUntil = liveFocus.isFocusing(at: now) ? liveFocus.until : nil
        switch FocusActivityStep.next(shown: activityUntil, live: liveFocus, now: now) {
        case .keep: break
        case .start(let until):
            if activity.start(until: until) {
                activityUntil = until
                retryTask?.cancel()
                startRetries = 0
            } else {
                retryStartSoon()
            }
        case .update(let until): activity.update(until: until); activityUntil = until
        case .end: endActivity()
        }
        scheduleExpiry()
    }

    private func retryStartSoon() {
        retryTask?.cancel()
        guard startRetries < Self.startRetryLimit else { return }
        startRetries += 1
        let delay = startRetryDelay
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reconcileFocus()
        }
    }

    private func endActivity() {
        guard activityUntil != nil else { return }
        activity.end()
        activityUntil = nil
    }

    /// Checks again when the end time comes, so a Mac that never said "done" doesn't leave the
    /// line or the Island up.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let until = focusingUntil ?? activityUntil else { expiryTask = nil; return }
        let wait = max(until.timeIntervalSinceNow, 0) + 0.05
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.reconcileFocus()
        }
    }

    /// The phone's day, score only: an iPhone never sends minutes.
    func publishToday() async {
        guard user != nil, let score = await measure.scoreToday() else { return }
        let report = PhoneDayReport(platform: .ios, day: DayKeys.key(for: Date(), in: .current), score: score)
        try? await services.days.publish(phone: report)
    }

    // MARK: Pairing a Mac

    /// The code typed (or scanned): ask first, never approve silently.
    func reviewCode() {
        guard let code = JoinCode(codeText) else { pairing = .failed(PhoneCopy.badCode); return }
        pairing = .confirm(code)
    }

    func approve(_ code: JoinCode) {
        pairing = .approving
        Task {
            do {
                try await services.auth.approvePairing(code: code)
                pairing = .approved
                codeText = ""
            } catch {
                pairing = .failed((error as? AuthError) == .codeExpired ? PhoneCopy.codeChanged : PhoneCopy.pairFailed)
            }
        }
    }

    func cancelPairing() {
        pairing = .idle
    }
}

enum PhoneCopy {
    static let hello = "Hi, I'm Zeno."
    static let lede = "Your day counts itself. One score, every screen."
    static let signInFailed = "That didn't finish. Try again."
    static let google = "Continue with Google"
    static let pairTitle = "Bring a Mac along"
    static let pairBody = "Type the six characters your Mac shows under its QR code."
    static let pairConfirmTitle = "A Mac wants to sign in as you"
    static let pairConfirmBody = "Approve only if it's your Mac, in front of you now. It will show the same Zen Score as this iPhone."
    static let approve = "Approve"
    static let notMe = "That's not me"
    static let approved = "Your Mac is in. Zeno's on its way over."
    static let badCode = "Six letters and numbers, as the Mac shows them."
    static let codeChanged = "That code just changed. Use the one on the Mac now."
    static let pairFailed = "Couldn't approve that one. Check the code and try again."
    static let noScore = "No score yet today. Your day counts itself."
    /// "Focusing until 12:00 on your Mac": the end time in the Mac's 24-hour style, never a countdown.
    static func focusing(until: Date, timeZone: TimeZone = .current) -> String {
        "Focusing until \(DayPlanner.text(until, timeZone: timeZone)) on your Mac"
    }
}
