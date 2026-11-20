import Foundation
import ZenAPI
import ZenMock

/// Every backend the app talks to, behind the contracts in ZenAPI. The app never sees an
/// implementation type. This package never imports the private backend either: the app target
/// chooses it at launch (`ZenMacBackend.make`, set in Apps/Mac) and the fakes stand in otherwise.
public struct Services: Sendable {
    public let auth: any AuthService
    public let nudges: ResilientNudges
    public let cohorts: any CohortService
    /// A live feed: the same number on every device within seconds of any of them publishing.
    public let scores: any ScoreService
    /// Where this Mac's day goes once someone is signed in.
    public let days: any DaySyncService
    /// Single-use Live tokens for Zeno's voice (Gemini Live); the key never reaches the app.
    public let voiceTokens: any VoiceTokenService
    /// Zen Cards Zeno makes in conversation.
    public let cards: any ZenCardService
    /// Focus Mode's writes (focus_sessions, daily, live/focus). Nil: this Mac keeps them for later.
    public let focus: (any FocusSyncService)?
    /// zenoCatchUp, zenoPlanDay, zenoWrapUp, zenoAsk.
    public let work: any ZenoWorkService
    /// The team: sponsor, Focus Report link, the Zen Gold claim.
    public let team: any TeamService
    /// The team admin's view (adminDashboard, cohortReport).
    public let admin: any AdminService
    /// True when the fakes are wired; every surface showing their data says "Demo data".
    public let isDemo: Bool

    public init(auth: any AuthService, nudges: any ZenoNudgeService, cohorts: any CohortService,
                scores: any ScoreService, days: any DaySyncService,
                voiceTokens: any VoiceTokenService, cards: any ZenCardService,
                focus: (any FocusSyncService)? = nil, work: any ZenoWorkService = FakeZenoWork(),
                team: any TeamService = FakeTeam(), admin: any AdminService = FakeAdmin(), isDemo: Bool) {
        self.auth = auth
        self.nudges = ResilientNudges(nudges)
        self.cohorts = cohorts
        self.scores = scores
        self.days = days
        self.voiceTokens = voiceTokens
        self.cards = cards
        self.focus = focus
        self.work = work
        self.team = team
        self.admin = admin
        self.isDemo = isDemo
    }

    /// The fakes: the open-source build, `swift run`, and ZEN_USE_MOCK=1.
    public static func fakes() -> Services {
        Services(auth: FakeAuth(approvalDelay: .seconds(30)), nudges: FakeNudges(), cohorts: FakeCohorts(),
                 scores: FakeScores(), days: FakeSync.demo(), voiceTokens: FakeVoiceTokens(), cards: FakeZenCards(),
                 focus: FakeFocusSync(), work: FakeZenoWork(), team: FakeTeam(), admin: FakeAdmin(), isDemo: true)
    }
}

/// The backend the app target picked. Set it before the app finishes launching:
///
///     init() { ZenMacBackend.make = { /* live services, or .fakes() */ } }
@MainActor
public enum ZenMacBackend {
    public static var make: @MainActor () -> Services = { .fakes() }
}
