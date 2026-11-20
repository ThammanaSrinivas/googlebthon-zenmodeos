import Foundation
import ZenAPI
import ZenMock
#if canImport(ZenPrivate)
import ZenPrivate
#endif

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
        #if canImport(ZenPrivate)
        let live = ZenPrivate.services()
        return Services(auth: live.auth, nudges: ResilientNudges(live.nudges), cohorts: live.cohorts, scores: live.scores, isDemo: false)
        #else
        // TODO(buildathon): the private repo wires Firebase sign-in, sync and the zenoNudge callable.
        return Services(auth: FakeAuth(approvalDelay: .seconds(30)), nudges: ResilientNudges(FakeNudges()),
                        cohorts: FakeCohorts(), scores: FakeScores(), isDemo: true)
        #endif
    }
}
