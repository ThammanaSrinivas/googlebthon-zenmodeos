import Foundation
import Testing
import Albeit
import ZenAPI
import ZenMock
import ZenVoice
@testable import ZenMacApp

// Functional tests: the Mac app's model on the fakes (Services.fakes(), the default backend), driven
// through its intents the way the views drive it. Not covered here: signing in (pairing approval,
// Apple, Google). Every sign-in starts MacDaySync on UserDefaults.standard
// (AppModel.startDaySync), so a test would write a device id and sequence into the real defaults;
// it needs an injectable store first.

@MainActor
private func appModel() -> AppModel {
    let m = AppModel()
    m.notch.reduceMotion = true
    return m
}

@Suite("App: onboarding, step by step")
@MainActor
struct OnboardingFlowTests {
    @Test("Next walks the seven steps in order; back walks them back")
    func steps() {
        let m = appModel()
        #expect(m.stage == .onboarding(.story) && m.step == .story)
        m.back() // nothing before the story
        #expect(m.step == .story)
        m.next()
        #expect(m.step == .seat)
        m.next()
        #expect(m.step == .uses)
        m.back()
        #expect(m.step == .seat)
        #expect(AppModel.Step.allCases == [.story, .seat, .uses, .quiet, .count, .bring, .handoff])
    }

    @Test("Campus seat, a typed code, the demo cohort: joined, then on to uses")
    func joinCohort() async {
        let m = appModel()
        m.go(.seat)
        m.choose(seat: .campus)
        #expect(m.profile.seat == .campus)
        m.codeText = "zen-4hs"
        #expect(m.codeText == "ZEN4HS") // typed loosely, kept clean
        m.checkCode()
        #expect(m.codeState == .checking)
        #expect(await eventually { m.codeState == .found(FakeCohorts.demo) })
        m.joinCohort()
        #expect(await eventually { m.step == .uses })
        guard case .joined(let summary) = m.codeState else { Issue.record("not joined: \(m.codeState)"); return }
        #expect(summary.preview == FakeCohorts.demo)
        #expect(m.cohort == summary && m.profile.cohortCode == "ZEN4HS")
        #expect(m.notch.moment.kicker == FakeCohorts.demo.name)
        #expect(m.notch.moment.line == "You're in. 23 people, one score.")
    }

    @Test("A half-typed code fails at once; an unknown one after the check")
    func badCodes() async {
        let m = appModel()
        m.codeText = "ZEN"
        m.checkCode()
        #expect(m.codeState == .failed(Copy.Seat.notFound))
        m.codeText = "AAAAAA"
        m.checkCode()
        #expect(await eventually { m.codeState == .failed(Copy.Seat.notFound) })
        #expect(m.cohort == nil)
    }

    @Test("Choosing just me clears a code in progress")
    func personal() async {
        let m = appModel()
        m.codeText = "ZEN"
        m.checkCode()
        m.choose(seat: .personal)
        #expect(m.codeState == .idle && m.cohort == nil && m.profile.seat == .personal)
        #expect(await eventually { m.notch.moment.line == "Just us, then. I like it." })
    }

    @Test("Uses toggle on and off")
    func uses() {
        let m = appModel()
        m.toggle(use: .build)
        m.toggle(use: .study)
        m.toggle(use: .build)
        #expect(m.profile.uses == [.study])
    }

    @Test("Quiet hours chosen in onboarding are what Zeno says back")
    func quiet() async {
        let m = appModel()
        m.choose(quiet: .classHours)
        #expect(m.profile.quiet == .classHours)
        #expect(await eventually { m.notch.moment.line == "I'll keep quiet weekdays 9–4." })
        m.choose(quiet: .none)
        #expect(await eventually { m.notch.moment.line == "Got it. Nights only." })
    }

    @Test("Bring your day (QR pairing on): the Mac shows a fresh pairing code and waits")
    func bring() async {
        let m = appModel()
        m.qrPairing = true
        m.go(.bring)
        #expect(m.pairState == .waiting)
        #expect(await eventually { m.pairing != nil })
        #expect(m.pairing?.code.value == "K4M7QX")
        #expect(m.pairing?.url.absoluteString == "https://zenmodeos.com/pair/K4M7QX")
        #expect(m.user == nil)
    }

    @Test("Sign in with Apple without a token fails kindly, and nobody is signed in")
    func appleWithoutToken() {
        let m = appModel()
        m.signInWithApple(identityToken: nil, fullName: nil)
        #expect(m.pairState == .failed(AppModel.qrPairingEnabled ? Copy.Bring.appleFailed : Copy.Bring.appleFailedNoCode))
        #expect(m.user == nil)
    }

    @Test("The hand-off loads today's score; then onboarding finishes on Today")
    func handoffToToday() async {
        let m = appModel()
        m.profile.quiet = m.preferences.values.quiet // finishing saves only a change: keep it unchanged
        m.go(.handoff)
        #expect(await eventually { m.snapshot != nil })
        #expect(m.snapshot?.score.tenths == 81)
        #expect(await eventually { m.notch.moment.line == Copy.Handoff.line("there") })
        m.next()
        #expect(m.stage == .today && m.step == nil)
        #expect(m.notch.quiet == m.profile.quiet)
        #expect(await eventually { m.lastNudge != nil })
        #expect(FakeNudges.lines.contains(m.lastNudge!.0))
    }

    @Test("The story's feelings row: each tap shows the next feeling in the notch, wrapping both ways")
    func feelings() async {
        let m = appModel()
        m.showFeeling(3)
        #expect(await eventually { m.notch.moment.feeling == .proud })
        #expect(m.notch.moment.line == Copy.feelingLines[3].line)
        m.showFeeling(-1)
        #expect(await eventually { m.notch.moment.feeling == .sleepy })
        m.showFeeling(5)
        #expect(await eventually { m.notch.moment.feeling == .happy })
    }

    @Test("Settings › Test speaks with the full brand name")
    func testZenoBrand() async {
        let m = appModel()
        m.testZeno(.happy)
        #expect(await eventually { m.notch.moment.line == "Good day locked in. Nice." })
        #expect(usesFullBrandName(m.notch.moment.kicker))
    }

    @Test("Settings › Test speaks whatever the hour")
    func testZeno() async {
        let m = appModel()
        m.notch.quiet = alwaysQuiet
        m.testZeno(.sleepy)
        #expect(await eventually { m.notch.moment.line == "Bedtime soon. Last scroll?" })
        #expect(m.notch.moment.feeling == .sleepy)
    }
}

@Suite("App: Today on the fakes, end to end")
@MainActor
struct TodayFlowTests {
    @Test("Launch: the live score arrives, the week and its streak load, gold opens from last week")
    func launch() async {
        let m = appModel()
        #expect(m.isDemo)
        m.start()
        #expect(await eventually { m.snapshot != nil })
        let snap = m.snapshot!
        // The combined score: the phone's 8.1 is the lower one, and the week is 3 of 4.
        #expect(snap.score.tenths == 81)
        #expect(snap.week.statusLine == "3 of 4 good days · one more wins the week")
        #expect(snap.devices.contains { $0.kind == .iPhone } && snap.devices.contains { $0.isThisDevice })
        // The streak calendar: nine won weeks before this one.
        #expect(m.streak?.streakBeforeThisWeek == 9)
        #expect(m.goldGate.state == .openFromLastWeek)
        #expect(m.goldGate.isOpen)
        // The dashboard agrees with the live number.
        #expect(m.dashboard.days[0].score == snap.score)
        #expect(m.dashboard.lastSeven.last == snap.score)
        // The weekly review loads (the offline one, after its pause).
        #expect(await eventually(.seconds(10)) { m.review != nil && !m.reviewLoading })
        let validated = try? m.review?.0.validated()
        #expect(m.review?.0 == validated)
    }

    @Test("Launch on the fakes wires Zeno's voice as the demo, with a ledger of its own")
    func voice() async {
        let m = appModel()
        let ledger = m.voiceLedger
        m.start()
        let voice = m.voice
        #expect(voice?.isDemo == true)
        #expect(voice?.ledger !== m.voiceLedger) // the demo never writes the Mac's ledger
        #expect(m.voiceLedger === ledger)        // one ledger for the app's life
        #expect(voice?.state == .idle)
    }

    @Test("Before any score loads, gold reads the demo week")
    func goldBeforeScore() {
        let m = appModel()
        #expect(m.snapshot == nil && m.streak == nil)
        #expect(m.goldGate.state == .locked(daysToGo: 1)) // 3 good days, and no finished week known yet
    }

    @Test("Ask Zeno: a check-in spends the day's budget and shows a line")
    func refresh() async throws {
        let m = appModel()
        await m.refreshNudge(trigger: .hello)
        let (nudge, _) = try #require(m.lastNudge)
        #expect(FakeNudges.lines.contains(nudge))
        #expect(m.snapshot?.score.tenths == 81)
    }

    @Test("Replaying onboarding goes back to the story")
    func replay() {
        let m = appModel()
        m.go(.uses)
        m.replayOnboarding()
        #expect(m.stage == .onboarding(.story))
    }
}
