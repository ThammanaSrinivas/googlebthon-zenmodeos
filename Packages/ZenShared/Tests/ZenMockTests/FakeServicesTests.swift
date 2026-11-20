// The fakes the demo runs on must behave like the real backend: sign-in and pairing answer the way
// the real AuthService does, a cohort's numbers only show at 5 members or more, the demo score
// moves live for every subscriber, the default polling stream polls, and a Zen Card never carries
// a score.
import Foundation
import Testing
import ZenAPI
import ZenLogic
@testable import ZenMock

struct FakeAuthContractTests {
    @Test func nobodyIsSignedInUntilTheyAsk() async throws {
        let auth = FakeAuth()
        #expect(await auth.currentUser() == nil)
        #expect(try await auth.signInWithGoogle() == ZenMock.demoUser)
    }

    @Test func appleSignInTakesTheGivenNameOrTheDemoName() async throws {
        let auth = FakeAuth()
        var name = PersonNameComponents()
        name.givenName = "Asha"
        name.familyName = "Raman"
        #expect(try await auth.signInWithApple(identityToken: "token", rawNonce: "nonce", fullName: name)
            == ZenUser(uid: "demo-apple", displayName: "Asha"))
        // Apple only sends the name the first time: later sign-ins carry none.
        #expect(try await auth.signInWithApple(identityToken: "token", rawNonce: "nonce", fullName: nil).displayName
            == ZenMock.demoUser.displayName)
    }

    @Test func anEmptyAppleTokenIsACancelledSheet() async {
        await #expect(throws: AuthError.cancelled) {
            try await FakeAuth().signInWithApple(identityToken: "", rawNonce: "nonce", fullName: nil)
        }
    }

    @MainActor @Test func noURLBelongsToTheFakesSignIn() {
        #expect(FakeAuth().handle(url: URL(string: "com.googleusercontent.apps.123:/oauth?code=x")!) == false)
    }

    @Test func aFreshPairingCodeIsAValidJoinCodeThatExpiresInFiveMinutes() async throws {
        let before = Date()
        let code = try await FakeAuth().newPairingCode()
        #expect(JoinCode(code.code.value) == code.code)
        let lifetime = code.expiresAt.timeIntervalSince(before)
        #expect(lifetime > 299 && lifetime <= 301)
        #expect(code.url.absoluteString == "https://zenmodeos.com/pair/\(code.code.value)")
    }

    @Test func aCodeThatExpiresDuringTheWaitIsRefused() async {
        let auth = FakeAuth(approvalDelay: .milliseconds(50))
        let code = PairingCode(code: JoinCode("K4M7QX")!, expiresAt: Date().addingTimeInterval(0.01))
        await #expect(throws: AuthError.codeExpired) { try await auth.waitForApproval(of: code) }
    }

    @Test func cancellingTheWaitReadsAsCancelled() async throws {
        let auth = FakeAuth(approvalDelay: .seconds(60))
        let code = try await auth.newPairingCode()
        let wait = Task { try await auth.waitForApproval(of: code) }
        try await Task.sleep(for: .milliseconds(20))
        wait.cancel()
        await #expect(throws: AuthError.cancelled) { try await wait.value }
    }

    @Test func cancellingThePhonesApprovalReadsAsCancelled() async throws {
        let approve = Task { try await FakeAuth().approvePairing(code: JoinCode("K4M7QX")!) }
        approve.cancel()
        await #expect(throws: AuthError.cancelled) { try await approve.value }
    }
}

/// An AuthService that implements only what it must: the contract's defaults fill the rest.
private struct MinimalAuth: AuthService {
    func currentUser() async -> ZenUser? { nil }
    func signInWithGoogle() async throws(AuthError) -> ZenUser { throw .unavailable }
    func signInWithApple(identityToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws(AuthError) -> ZenUser {
        throw .unavailable
    }
    @MainActor func handle(url: URL) -> Bool { false }
    func newPairingCode() async throws(AuthError) -> PairingCode { throw .unavailable }
    func waitForApproval(of code: PairingCode) async throws(AuthError) -> ZenUser { throw .unavailable }
}

struct AuthContractDefaultsTests {
    @Test func aServiceWithoutPhoneApprovalSaysItIsUnavailable() async throws {
        await #expect(throws: AuthError.unavailable) { try await MinimalAuth().approvePairing(code: JoinCode("K4M7QX")!) }
        try await MinimalAuth().signOut() // the default sign-out never throws
    }

    @Test(arguments: [("Kamal Senthilkumar", "Kamal"), ("Asha", "Asha"), ("  Ravi  Kumar", "Ravi"), ("", "")])
    func theFirstNameIsTheFirstWord(display: String, first: String) {
        #expect(ZenUser(uid: "u", displayName: display).firstName == first)
    }
}

struct FakeCohortsContractTests {
    @Test func joiningTheDemoCohortShowsItsNumbers() async throws {
        let summary = try await FakeCohorts().join(code: JoinCode("zen-4hs")!)
        #expect(summary.preview == FakeCohorts.demo)
        #expect(summary.preview.memberCount >= CohortSummary.minimumGroupSize)
        #expect(summary.score == ZenScore(tenths: 74))
        #expect(summary.goodDayRate == 0.62)
    }

    @Test func joiningAnyOtherCodeIsNotFound() async {
        await #expect(throws: CohortError.notFound) { try await FakeCohorts().join(code: JoinCode("ABC234")!) }
        await #expect(throws: CohortError.notFound) { try await FakeCohorts().preview(code: JoinCode("ABC234")!) }
    }

    @Test("Aggregates show from exactly 5 members", arguments: [0, 1, 4, 5, 6, 23])
    func theFiveMemberThreshold(members: Int) {
        let preview = CohortPreview(id: "c", name: "Lab", organisation: "Org", kind: .team, memberCount: members)
        let summary = CohortSummary(preview: preview, score: ZenScore(tenths: 70), goodDayRate: 0.5)
        #expect((summary.score != nil) == (members >= 5))
        #expect((summary.goodDayRate != nil) == (members >= 5))
        #expect(summary.preview == preview) // the preview itself is never hidden
    }

    @Test func aJoinCodeDescribesItselfInGroupsOfThree() {
        #expect("\(JoinCode("zen4hs")!)" == "ZEN·4HS")
    }
}

struct FakeNudgesContractTests {
    @Test func everyDemoLinePassesTheAppsOwnGuardrails() throws {
        for line in FakeNudges.lines { #expect(try line.validated() == line) }
        #expect(Set(FakeNudges.lines.map(\.feeling)).isSubset(of: Set(ZenoNudge.Feeling.allCases)))
    }

    @Test func theLineRotatesWithTheHourAndTheOffset() async throws {
        let context = { (hour: Int) in
            NudgeContext(scoreTenths: 81, goodDaysThisWeek: 3, weeklyStreak: 9, hourOfDay: hour, trigger: .pickup)
        }
        #expect(try await FakeNudges().nudge(for: context(0)) == FakeNudges.lines[0])
        #expect(try await FakeNudges().nudge(for: context(5)) == FakeNudges.lines[1])
        #expect(try await FakeNudges(index: 2).nudge(for: context(23)) == FakeNudges.lines[1])
    }

    /// A canned line passes through ResilientNudges untouched but is never credited to Gemini, so the
    /// notch doesn't say "Zeno · Gemini" on the fakes.
    @Test func throughResilientNudgesTheDemoLineIsNeverCreditedToGemini() async {
        let context = NudgeContext(scoreTenths: 81, goodDaysThisWeek: 3, weeklyStreak: 9, hourOfDay: 2, trigger: .hello)
        let (nudge, source) = await ResilientNudges(FakeNudges()).nudge(for: context)
        #expect(nudge == FakeNudges.lines[2])
        #expect(FakeNudges().source == .fallback)
        #expect(source == .fallback)
    }
}

struct FakeScoresLiveTests {
    @Test func everySubscriberSeesTheSecondDeviceAtOnce() async {
        let scores = FakeScores()
        let first = Collected(scores.updates())
        let second = Collected(scores.updates())
        _ = await first.wait(for: 1)
        _ = await second.wait(for: 1)
        scores.simulateSecondDevice()
        #expect(await first.wait(for: 2).map(\.score.tenths) == [81, 65])
        #expect(await second.wait(for: 2).map(\.score.tenths) == [81, 65])
        first.cancel()
        second.cancel()
    }

    @Test func copiesOfOneFakeShareTheirDevicesButNewFakesDoNot() async throws {
        let scores = FakeScores()
        let copy = scores
        copy.simulateSecondDevice()
        #expect(try await scores.today().score == ZenScore(tenths: 65))
        #expect(try await FakeScores().today().score == ZenScore(tenths: 81))
    }

    @Test func aFinishedSubscriberIsForgotten() async throws {
        let scores = FakeScores()
        let live = try #require(Mirror(reflecting: scores).children.first { $0.label == "live" }?.value as? LiveDemo)
        let updates = Collected(scores.updates())
        _ = await updates.wait(for: 1)
        #expect(live.subscriberCount == 1)
        updates.cancel()
        let deadline = ContinuousClock.now + .seconds(2)
        while live.subscriberCount > 0, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(live.subscriberCount == 0)
        scores.simulateSecondDevice() // nobody to tell, and nothing breaks
    }

    @Test func negativeNumbersFromTheSimulatorCountAsZero() {
        let snapshot = FakeScores().simulateSecondDevice(minutes: -30, pullBacks: -2)
        #expect(snapshot.score == ZenScore(tenths: 81))
        #expect(snapshot.devices.last?.detail == "0 m distracting · 0 pull-backs")
    }

    @Test func aHeavySecondDeviceTakesTheScoreDownButNeverBelowTheFloor() {
        let snapshot = FakeScores().simulateSecondDevice(minutes: 1_500, pullBacks: 1_000)
        let computers = ZenScoreRule.score(minutes: 38 + 1_500, pullBacks: 4 + 1_000, promiseMinutes: 240)
        #expect(snapshot.score == computers)
        #expect(snapshot.score >= ZenScore(tenths: 0))
        #expect(snapshot.week.days[4] == snapshot.score)
    }

    @Test func theDemoPhoneLineNeverShowsMinutes() async throws {
        for snapshot in [try await FakeScores().today(), FakeScores().simulateSecondDevice()] {
            let phone = try #require(snapshot.devices.first { $0.kind == .iPhone })
            #expect(phone.detail == "Counted on the phone")
            #expect(snapshot.devices.filter(\.isThisDevice).count == 1)
        }
    }
}

/// A ScoreService that only knows `today()`: it gets the contract's polling `updates()`.
private actor CountingScores: ScoreService {
    private(set) var calls = 0
    private let failEvery: Int

    init(failEvery: Int = 0) { self.failEvery = failEvery }

    func today() async throws -> ScoreSnapshot {
        calls += 1
        if failEvery > 0, calls % failEvery == 0 { throw SyncError.offline }
        return ScoreSnapshot(score: ZenScore(tenths: min(calls * 10, 100)),
                             week: WeekProgress(days: Array(repeating: nil, count: 7), todayIndex: 0, streakBefore: 0),
                             devices: [], updatedAt: Date(timeIntervalSince1970: 0))
    }
}

struct PollingUpdatesTests {
    @Test func pollingYieldsEachAnswerAndSkipsFailures() async {
        let scores = CountingScores(failEvery: 2)
        let updates = Collected(scores.pollingUpdates(every: .milliseconds(5)))
        let values = await updates.wait(for: 3)
        updates.cancel()
        // Calls 2, 4, … failed: only the odd calls' scores arrive, in order.
        #expect(Array(values.prefix(3)).map(\.score.tenths) == [10, 30, 50])
    }

    @Test func cancellingTheStreamStopsThePolling() async {
        let scores = CountingScores()
        let updates = Collected(scores.pollingUpdates(every: .milliseconds(5)))
        _ = await updates.wait(for: 2)
        updates.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        let stopped = await scores.calls
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await scores.calls <= stopped + 1)
    }

    @Test func theDefaultUpdatesStartWithTheCurrentDay() async {
        let scores = CountingScores()
        let updates = Collected(scores.updates())
        #expect(await updates.wait(for: 1).first?.score.tenths == 10)
        updates.cancel()
    }
}

struct FakeZenCardsNeverCarryAScoreTests {
    static let allowedKeys: Set<String> = ["id", "summary", "mood", "language", "earnedBack", "drift", "createdAt", "sharedAt"]

    private func keys(_ card: ZenCard) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        return Set(try #require(object).keys)
    }

    @Test func savedAndSharedCardsHoldOnlyTheNoteMoodAndLanguage() async throws {
        let cards = FakeZenCards(now: { Date(timeIntervalSince1970: 1_795_156_200) })
        let saved = try await cards.save(ZenCardDraft(summary: "Walked instead of scrolling", mood: .happy, language: "en-IN",
                                                      earnedBack: "an hour", drift: "reels after lunch"))
        let shared = try await cards.share(cardId: saved.id, note: "Day 3!")
        for card in [saved, shared] {
            let keys = try keys(card)
            #expect(keys.isSubset(of: Self.allowedKeys))
            #expect(!keys.contains { $0.lowercased().contains("score") || $0.lowercased().contains("minute") })
        }
        #expect(Set(Mirror(reflecting: saved).children.compactMap(\.label)) == Self.allowedKeys)
    }

    @Test func idsAreUniqueAndTheNewestComesFirst() async throws {
        let cards = FakeZenCards()
        var ids: [String] = []
        for i in 0..<5 { ids.append(try await cards.save(ZenCardDraft(summary: "note \(i)", mood: .neutral, language: "ta")).id) }
        #expect(Set(ids).count == 5)
        #expect(try await cards.recent().map(\.id) == ids.reversed())
    }

    @Test func sharingAnUnknownCardIsNotFound() async {
        await #expect(throws: FakeZenCards.Failure.notFound) { try await FakeZenCards().share(cardId: "card-9", note: nil) }
    }

    @Test func sharingTwiceKeepsTheFirstShareTimeAndABlankNoteIsNoNote() async throws {
        let clock = TestNow(Demo.now)
        let cards = FakeZenCards(now: { clock.now })
        let saved = try await cards.save(ZenCardDraft(summary: "Quiet evening", mood: .pleasant, language: "hi-Latn"))
        let first = try await cards.share(cardId: saved.id, note: "   ")
        clock.advance(60)
        let again = try await cards.share(cardId: saved.id, note: "  hello  ")
        #expect(first.sharedAt == Demo.now)
        #expect(again.sharedAt == Demo.now)
        #expect(cards.notes == [saved.id: "hello"])
        #expect(try await cards.recent().first?.sharedAt == Demo.now)
    }
}
