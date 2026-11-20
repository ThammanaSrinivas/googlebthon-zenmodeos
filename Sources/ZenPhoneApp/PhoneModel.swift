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
    public let isDemo: Bool

    public init(auth: any AuthService, scores: any ScoreService, days: any DaySyncService,
                voiceTokens: any VoiceTokenService, cards: any ZenCardService, isDemo: Bool) {
        self.auth = auth
        self.scores = scores
        self.days = days
        self.voiceTokens = voiceTokens
        self.cards = cards
        self.isDemo = isDemo
    }

    public static func fakes() -> PhoneServices {
        PhoneServices(auth: FakeAuth(), scores: FakeScores(), days: FakeSync.demo(),
                      voiceTokens: FakeVoiceTokens(), cards: FakeZenCards(), isDemo: true)
    }
}

@MainActor
public enum ZenPhoneBackend {
    public static var make: @MainActor () -> PhoneServices = { .fakes() }
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

    private var nonce = SignInNonce.make()
    private var scoreTask: Task<Void, Never>?
    private let measure: any PhoneDayMeasure = NotMeasuredYet()

    init(services: PhoneServices) {
        self.services = services
    }

    func start() {
        Task {
            if let person = await services.auth.currentUser() { signedIn(person) }
        }
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
        Task { await publishToday() }
    }

    func signOut() {
        Task {
            try? await services.auth.signOut()
            scoreTask?.cancel()
            user = nil
            snapshot = nil
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
}
