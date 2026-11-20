import Foundation
import Testing
import ZenAPI
import ZenMock
@testable import ZenPhoneApp

/// A Live Activity stand-in that records every call and checks there's never more than one up.
@MainActor
private final class RecordingActivity: FocusActivityControlling {
    enum Call: Equatable { case adopt, start(Date), update(Date), end }

    private(set) var calls: [Call] = []
    /// What's on show right now, nil when nothing is.
    private(set) var onShow: Date?
    private(set) var mostAtOnce = 0
    /// What an earlier launch left on the Lock Screen.
    var leftover: Date?
    /// The system refusing a start (Live Activities off, app in the background).
    var refuse = false

    init(leftover: Date? = nil) { self.leftover = leftover }

    func adopt() -> Date? {
        calls.append(.adopt)
        onShow = leftover
        return leftover
    }

    func start(until: Date) -> Bool {
        calls.append(.start(until))
        guard !refuse else { return false }
        mostAtOnce = max(mostAtOnce, onShow == nil ? 1 : 2)
        onShow = until
        return true
    }

    func update(until: Date) {
        calls.append(.update(until))
        onShow = until
    }

    func end() {
        calls.append(.end)
        onShow = nil
    }

    var starts: Int { calls.filter { if case .start = $0 { true } else { false } }.count }
    var ends: Int { calls.filter { $0 == .end }.count }
}

/// Focus sync that serves `live/focus` from a fake and fails the test if the phone writes anything.
private final class ReadOnlyFocus: FocusSyncService, @unchecked Sendable {
    let mac = FakeFocusSync()
    private let lock = NSLock()
    private var _writes = 0
    var writes: Int { lock.withLock { _writes } }

    func setLive(_ live: LiveFocus) async throws(FocusSyncError) { lock.withLock { _writes += 1 } }
    func save(_ record: FocusRecord) async throws(FocusSyncError) { lock.withLock { _writes += 1 } }
    func saveDaily(_ daily: DailyFocus, day: String) async throws(FocusSyncError) { lock.withLock { _writes += 1 } }
    func saveWorkHours(_ hours: WorkHours) async throws(FocusSyncError) { lock.withLock { _writes += 1 } }
    func liveFocus() -> AsyncStream<LiveFocus> { mac.liveFocus() }

    /// The Mac writing `live/focus`.
    func macSays(_ live: LiveFocus) async { try? await mac.setLive(live) }
}

private let someone = ZenUser(uid: "fake-uid", displayName: "Fake Person")

@MainActor
private func phone(signedIn: ZenUser? = someone, focus: ReadOnlyFocus = ReadOnlyFocus(),
                   activity: RecordingActivity = RecordingActivity()) -> PhoneModel {
    PhoneModel(services: PhoneServices(auth: ScriptedAuth(signedIn: signedIn), scores: FakeScores(), days: FakeSync.demo(),
                                       voiceTokens: FakeVoiceTokens(), cards: FakeZenCards(), focus: focus, isDemo: true),
               activity: activity)
}

/// Whole seconds from now, so two reads of the "same" time compare equal.
private func minutes(_ m: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate + m * 60).rounded())
}

private let now = Date(timeIntervalSince1970: 1_763_620_200)
private let later = now.addingTimeInterval(50 * 60)
private let later2 = now.addingTimeInterval(80 * 60)
private let earlier = now.addingTimeInterval(-60)

@Suite("iPhone: what the Live Activity does next")
struct FocusActivityStepTests {
    @Test("Each case", arguments: [
        (nil, LiveFocus.idle, FocusActivityStep.keep),
        (nil, LiveFocus(active: true, until: later), .start(later)),
        (later, LiveFocus(active: true, until: later), .keep),
        (later, LiveFocus(active: true, until: later2), .update(later2)),
        (later, LiveFocus.idle, .end),
        // A Mac that crashed mid-block leaves `active` set: past its end, it's over.
        (later, LiveFocus(active: true, until: earlier), .end),
        (nil, LiveFocus(active: true, until: earlier), .keep),
        (nil, LiveFocus(active: true, until: now), .keep),
        (nil, LiveFocus(active: true, until: nil), .keep),
    ] as [(Date?, LiveFocus, FocusActivityStep)])
    func step(shown: Date?, live: LiveFocus, expected: FocusActivityStep) {
        #expect(FocusActivityStep.next(shown: shown, live: live, now: now) == expected)
    }

    @Test("The line reads the end time in the Mac's 24-hour style")
    func copy() {
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        // 1_763_620_200 is 12:00 IST.
        #expect(PhoneCopy.focusing(until: now, timeZone: ist) == "Focusing until 12:00 on your Mac")
        #expect(PhoneCopy.focusing(until: now.addingTimeInterval(6 * 3600 + 5 * 60), timeZone: ist) == "Focusing until 18:05 on your Mac")
    }

    @Test("Without ActivityKit, nothing starts")
    @MainActor
    func none() {
        let none = NoFocusActivity()
        #expect(none.adopt() == nil)
        #expect(!none.start(until: later))
    }
}

@Suite("iPhone: following the Mac's focus")
@MainActor
struct FocusFollowTests {
    @Test("The Mac starts focus: the line and one Live Activity; it ends: both go")
    func startAndEnd() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        let m = phone(focus: focus, activity: activity)
        m.start()
        #expect(await eventually { m.user != nil })
        #expect(m.focusingUntil == nil && activity.starts == 0)

        let until = minutes(50)
        await focus.macSays(LiveFocus(active: true, until: until))
        #expect(await eventually { m.focusingUntil == until })
        #expect(m.liveFocus.active)
        #expect(activity.calls == [.adopt, .start(until)])
        #expect(m.activityUntil == until)

        await focus.macSays(.idle)
        #expect(await eventually { m.focusingUntil == nil })
        #expect(activity.calls == [.adopt, .start(until), .end])
        #expect(activity.onShow == nil && m.activityUntil == nil)
        #expect(focus.writes == 0)
    }

    @Test("A new end time moves the activity; the same one leaves it alone; never two at once")
    func update() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        let m = phone(focus: focus, activity: activity)
        m.start()
        let first = minutes(50), second = minutes(80)
        await focus.macSays(LiveFocus(active: true, until: first))
        #expect(await eventually { m.focusingUntil == first })
        await focus.macSays(LiveFocus(active: true, until: first))
        await focus.macSays(LiveFocus(active: true, until: second))
        #expect(await eventually { m.focusingUntil == second })
        #expect(activity.calls == [.adopt, .start(first), .update(second)])
        #expect(activity.mostAtOnce == 1)
    }

    @Test("A doc left active past its end (a Mac that crashed) shows nothing")
    func stale() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        let m = phone(focus: focus, activity: activity)
        await focus.macSays(LiveFocus(active: true, until: minutes(-5)))
        m.start()
        #expect(await eventually { m.liveFocus.active })
        #expect(m.focusingUntil == nil)
        #expect(activity.calls == [.adopt])
    }

    @Test("When the end time comes, the line and the activity go by themselves")
    func expires() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        let m = phone(focus: focus, activity: activity)
        m.start()
        #expect(await eventually { m.user != nil })
        let until = Date().addingTimeInterval(0.4)
        await focus.macSays(LiveFocus(active: true, until: until))
        #expect(await eventually { m.focusingUntil == until })
        #expect(activity.starts == 1)
        #expect(await eventually { m.focusingUntil == nil && activity.onShow == nil })
        #expect(activity.calls.last == .end)
        #expect(m.liveFocus.active, "the doc still says active; the time is what ended it")
    }

    @Test("A refused start is tried again when the app comes back")
    func refused() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        activity.refuse = true
        let m = phone(focus: focus, activity: activity)
        m.start()
        let until = minutes(50)
        await focus.macSays(LiveFocus(active: true, until: until))
        #expect(await eventually { m.focusingUntil == until })
        #expect(m.activityUntil == nil && activity.onShow == nil)

        activity.refuse = false
        m.becameActive()
        #expect(m.activityUntil == until && activity.onShow == until)
        #expect(activity.calls == [.adopt, .start(until), .start(until)])
        m.becameActive()
        #expect(activity.starts == 2)
    }

    @Test("Signing out ends the activity and the line")
    func signOut() async {
        let focus = ReadOnlyFocus(), activity = RecordingActivity()
        let m = phone(focus: focus, activity: activity)
        m.start()
        await focus.macSays(LiveFocus(active: true, until: minutes(50)))
        #expect(await eventually { activity.onShow != nil })
        m.signOut()
        #expect(await eventually { m.user == nil && m.focusingUntil == nil && activity.onShow == nil })
        #expect(!m.liveFocus.active)

        // The Mac's later word doesn't reach a signed-out phone.
        await focus.macSays(LiveFocus(active: true, until: minutes(90)))
        for _ in 0..<50 { await Task.yield() }
        #expect(activity.onShow == nil && m.focusingUntil == nil)
    }
}

@Suite("iPhone: the activity left from before this launch")
@MainActor
struct FocusAdoptTests {
    @Test("Past its end: ended at once")
    func pastEnd() {
        let activity = RecordingActivity(leftover: minutes(-10))
        let m = phone(signedIn: nil, activity: activity)
        m.start()
        #expect(activity.calls == [.adopt, .end])
        #expect(m.activityUntil == nil)
    }

    @Test("The Mac still focusing to the same time: kept, not started again")
    func kept() async {
        let until = minutes(30)
        let focus = ReadOnlyFocus(), activity = RecordingActivity(leftover: until)
        await focus.macSays(LiveFocus(active: true, until: until))
        let m = phone(focus: focus, activity: activity)
        m.start()
        #expect(m.activityUntil == until)
        #expect(await eventually { m.focusingUntil == until })
        #expect(activity.calls == [.adopt])
    }

    @Test("The Mac stopped while the phone was away: ended")
    func macStopped() async {
        let activity = RecordingActivity(leftover: minutes(30))
        let m = phone(activity: activity)
        m.start()
        #expect(await eventually { activity.onShow == nil })
        #expect(activity.calls == [.adopt, .end])
    }

    @Test("Nobody signed in: ended")
    func signedOut() async {
        let activity = RecordingActivity(leftover: minutes(30))
        let m = phone(signedIn: nil, activity: activity)
        m.start()
        #expect(await eventually { activity.onShow == nil })
        #expect(activity.calls == [.adopt, .end])
        #expect(m.user == nil)
    }
}
