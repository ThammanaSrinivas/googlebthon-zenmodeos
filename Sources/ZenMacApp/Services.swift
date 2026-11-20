import Foundation
import ZenAPI
import ZenMock

/// Every backend the app talks to, behind the contracts in ZenAPI. The app never sees an
/// implementation type: the private repo provides the live ones, the fakes stand in otherwise.
struct Services: Sendable {
    let auth: any AuthService
    let nudges: ResilientNudges
    let cohorts: any CohortService
    let scores: any ScoreService
    /// True when the fakes are wired; every surface showing their data says "Demo data".
    let isDemo: Bool

    static func make() -> Services {
        // TODO(buildathon): when ZenCorePrivate lands (private repo), build these from it under
        // `#if canImport(ZenCorePrivate)`: Firebase sign-in, sync and the zenoNudge callable.
        return Services(auth: FakeAuth(approvalDelay: .seconds(30)), nudges: ResilientNudges(FakeNudges()),
                        cohorts: FakeCohorts(), scores: FakeScores(), isDemo: true)
    }
}
