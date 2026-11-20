import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenMacApp

@Suite("Services: the fake set the open-source build runs on")
struct ServicesTests {
    private let context = NudgeContext(scoreTenths: 81, goodDaysThisWeek: 3, weeklyStreak: 9, hourOfDay: 14, trigger: .checkIn)

    @Test("The fakes say they're the demo")
    func demo() async throws {
        let s = Services.fakes()
        #expect(s.isDemo)
        #expect(await s.auth.currentUser() == nil)
        let today = try await s.scores.today()
        #expect(today.score.tenths == 81)
        #expect(today.week == FakeSnapshotWeek.value)
    }

    @Test("The default backend is the fakes")
    @MainActor
    func defaultBackend() {
        #expect(ZenMacBackend.make().isDemo)
    }

    @Test("The live feed starts with today's snapshot at once")
    func feed() async {
        var it = Services.fakes().scores.updates().makeAsyncIterator()
        let first = await it.next()
        #expect(first?.score.tenths == 81)
        #expect(first?.devices.contains { $0.kind == .iPhone && $0.detail.contains(" m ") } == false)
    }

    @Test("The demo cohort answers to its code only")
    func cohorts() async throws {
        let s = Services.fakes()
        let preview = try await s.cohorts.preview(code: ZenMock.demoCohortCode)
        #expect(preview.memberCount >= CohortSummary.minimumGroupSize)
        await #expect(throws: CohortError.notFound) { try await s.cohorts.preview(code: JoinCode("AAAAAA")!) }
    }

    @Test("Sign in with Apple: a token signs in, an empty one is a cancel")
    func apple() async throws {
        let auth = Services.fakes().auth
        var name = PersonNameComponents()
        name.givenName = "Fake"
        let user = try await auth.signInWithApple(identityToken: "fake-token", rawNonce: "fake-nonce", fullName: name)
        #expect(user.displayName == "Fake")
        await #expect(throws: AuthError.cancelled) {
            try await auth.signInWithApple(identityToken: "", rawNonce: "fake-nonce", fullName: nil)
        }
    }

    @Test("A fake nudge is a valid line Zeno can say")
    func nudgeLine() async {
        let (nudge, _) = await Services.fakes().nudges.nudge(for: context)
        #expect(FakeNudges.lines.contains(nudge))
        #expect(nudge.line.count <= ZenoNudge.maxLineLength)
    }

    @Test("A fake nudge is never labelled as written by Gemini",
          .disabled("bug: ZenAPI ResilientNudges (Packages/ZenShared/Sources/ZenAPI/Nudge.swift:114) returns .gemini for any service that answers, so on the fakes AppModel.refreshNudge (Sources/ZenMacApp/AppModel.swift:259) shows the kicker \"Zeno · Gemini\" for FakeNudges' lines; expected a demo/fallback source when Services.isDemo"))
    func nudgeSource() async {
        let (_, source) = await Services.fakes().nudges.nudge(for: context)
        #expect(source != .gemini)
    }

    @Test("The offline weekly review is never labelled as written by Gemini",
          .disabled("bug: Sources/ZenMacApp/Week/WeekModels.swift:180, ResilientReviews returns .gemini for FakeReviews' text (AppModel.reviews uses FakeReviews on every build); expected a demo/fallback source"))
    func reviewSource() async {
        let (_, source) = await ResilientReviews(service: FakeReviews()).review(for: WeekDemo.recap)
        #expect(source != .gemini)
    }
}
