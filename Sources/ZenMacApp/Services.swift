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
    /// True when the fakes are wired; every surface showing their data says "Demo data".
    public let isDemo: Bool

    public init(auth: any AuthService, nudges: any ZenoNudgeService, cohorts: any CohortService,
                scores: any ScoreService, days: any DaySyncService, isDemo: Bool) {
        self.auth = auth
        self.nudges = ResilientNudges(nudges)
        self.cohorts = cohorts
        self.scores = scores
        self.days = days
        self.isDemo = isDemo
    }

    /// The fakes: the open-source build, `swift run`, and ZEN_USE_MOCK=1.
    public static func fakes() -> Services {
        Services(auth: FakeAuth(approvalDelay: .seconds(30)), nudges: FakeNudges(), cohorts: FakeCohorts(),
                 scores: FakeScores(), days: FakeSync.demo(), isDemo: true)
    }
}

/// The backend the app target picked. Set it before the app finishes launching:
///
///     init() { ZenMacBackend.make = { /* live services, or .fakes() */ } }
@MainActor
public enum ZenMacBackend {
    public static var make: @MainActor () -> Services = { .fakes() }
}
