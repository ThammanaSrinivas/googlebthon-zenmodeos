// The on-device ledger across relaunches and days: the stored format, broken storage, timers that
// ran out while the app was closed, an intent left open overnight, pickups on a new day, the kept
// history, and listeners that go away.
import Foundation
import Testing
@testable import ZenVoice

@Suite("On-device ledger: storage and days")
struct OnDeviceLedgerPersistenceTests {
    /// 2026-11-20T16:32:00Z in milliseconds.
    static let nowMs = 1_795_192_320_000

    @Test("A ledger stored in today's format loads")
    func storedFormatLoads() async throws {
        let store = InMemoryKeyValueStore()
        let json = """
        {"intents":[{"id":"s1","app":"Instagram","purpose":"Reel","minutes":2,"startedAt":\(Self.nowMs - 60_000),\
        "endsAt":\(Self.nowMs + 60_000),"timeUpNotified":false}],\
        "pauses":[{"app":"WhatsApp","seconds":7,"since":\(Self.nowMs - 5_000)}],\
        "pickups":{"day":"2026-11-20","total":3,"withIntent":1},"latestPickupHasIntent":true,\
        "lastCardId":"card-2","nextId":4}
        """
        store.set(Data(json.utf8), forKey: OnDeviceLedger.storageKey)
        let ledger = T.ledger(ManualVoiceClock(T.now), store: store)
        let intent = try #require(await ledger.activeIntent)
        #expect(intent.id == "s1" && intent.app == "Instagram" && intent.minutes == 2)
        #expect(intent.endsAt == T.now.addingTimeInterval(60))
        #expect(await ledger.pauseSeconds(for: "whatsapp") == 7)
        #expect(await ledger.today() == PickupTally(day: "2026-11-20", total: 3, withIntent: 1))
        #expect(await ledger.lastCardId == "card-2")
        #expect(await ledger.startIntent(app: "YouTube", purpose: "", minutes: 5).session.id == "s4")
    }

    @Test("What the ledger saves is the format it loads: sorted keys, dates in milliseconds")
    func savedFormat() async throws {
        let store = InMemoryKeyValueStore()
        let ledger = T.ledger(ManualVoiceClock(T.now), store: store)
        await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2)
        let data = try #require(store.data(forKey: OnDeviceLedger.storageKey))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let intents = try #require(object["intents"] as? [[String: Any]])
        #expect((intents.first?["startedAt"] as? NSNumber)?.int64Value == Int64(Self.nowMs))
        #expect(Set(object.keys).isSuperset(of: ["intents", "pauses", "latestPickupHasIntent", "nextId"]))
    }

    @Test("Broken storage starts an empty ledger, and the next change replaces it")
    func brokenStorage() async {
        let clock = ManualVoiceClock(T.now)
        for broken in ["", "not json", "{\"intents\": 5}", "[]", "{\"nextId\": \"x\"}"] {
            let store = InMemoryKeyValueStore()
            store.set(Data(broken.utf8), forKey: OnDeviceLedger.storageKey)
            let ledger = T.ledger(clock, store: store)
            #expect(await ledger.intents.isEmpty, "\(broken)")
            #expect(await ledger.lastCardId == nil, "\(broken)")
            let session = await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2).session
            #expect(session.id == "s1", "\(broken)")
            #expect(await T.ledger(clock, store: store).activeIntent == session, "\(broken)")
        }
    }

    @Test("A focus that ran out while the app was closed ends once, at its own end time")
    func focusEndsWhileClosed() async {
        let clock = ManualVoiceClock(T.now)
        let store = InMemoryKeyValueStore()
        let focus = await T.ledger(clock, store: store).startFocus(minutes: 25, label: "Essay", quietApps: ["Instagram"])
        clock.advance(by: 3 * 3_600)
        let relaunched = T.ledger(clock, store: store)
        #expect(await relaunched.activeFocus == nil)
        var ended = focus
        ended.endedAt = focus.endsAt
        #expect(await relaunched.checkTimers() == [.focusEnded(ended)])
        #expect(await relaunched.checkTimers().isEmpty)
        #expect(await T.ledger(clock, store: store).checkTimers().isEmpty) // the end was saved
    }

    @Test("Time's up fires once, even across a relaunch")
    func timeUpOnceAcrossRelaunch() async {
        let clock = ManualVoiceClock(T.now)
        let store = InMemoryKeyValueStore()
        await T.ledger(clock, store: store).startIntent(app: "Instagram", purpose: "", minutes: 2)
        clock.advance(by: 180)
        #expect(await T.ledger(clock, store: store).checkTimers().count == 1)
        #expect(await T.ledger(clock, store: store).checkTimers().isEmpty)
    }

    @Test("An intent left open overnight ends with the overrun capped at 12 hours")
    func intentLeftOpenOvernight() async throws {
        let clock = ManualVoiceClock(T.now)
        let store = InMemoryKeyValueStore()
        await T.ledger(clock, store: store).startIntent(app: "YouTube", purpose: "One video", minutes: 10)
        clock.advance(by: 20 * 3_600)
        let relaunched = T.ledger(clock, store: store)
        let ended = try #require(await relaunched.endIntent())
        #expect(ended.overrunMinutes == 720)
        #expect(ended.onTime == false)
        #expect(await relaunched.endIntent() == nil)
    }

    @Test("Pickups start again on a new day, after a relaunch too; the first intent marks the first pickup")
    func pickupsOnANewDay() async {
        let clock = ManualVoiceClock(T.now) // 22:02 in India
        let store = InMemoryKeyValueStore()
        let ledger = T.ledger(clock, store: store)
        await ledger.recordPickup()
        await ledger.recordPickup()
        clock.advance(by: 3 * 3_600) // 01:02 on the 21st
        let relaunched = T.ledger(clock, store: store)
        #expect(await relaunched.today() == PickupTally(day: "2026-11-21"))
        #expect(await relaunched.status().pickups.total == 0)
        await relaunched.recordPickup()
        await relaunched.startIntent(app: "Instagram", purpose: "", minutes: 2)
        #expect(await relaunched.today() == PickupTally(day: "2026-11-21", total: 1, withIntent: 1))
    }

    @Test("The day is the ledger's own time zone's")
    func pickupsFollowTheTimeZone() async {
        let clock = ManualVoiceClock(T.now) // 16:32 UTC, 22:02 in India, 08:32 in Los Angeles
        let india = T.ledger(clock)
        let losAngeles = OnDeviceLedger(clock: clock, store: InMemoryKeyValueStore(),
                                        timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        clock.advance(by: 2 * 3_600)
        #expect(await india.recordPickup().day == "2026-11-21")
        #expect(await losAngeles.recordPickup().day == "2026-11-20")
    }

    @Test("Only the latest 50 intents are kept, and ids never repeat")
    func keptHistory() async {
        let clock = ManualVoiceClock(T.now)
        let store = InMemoryKeyValueStore()
        let ledger = T.ledger(clock, store: store)
        for i in 0..<60 { await ledger.startIntent(app: "App \(i)", purpose: "", minutes: 1) }
        let kept = await T.ledger(clock, store: store).intents
        #expect(kept.count == ZenoLimits.keptIntents)
        #expect(kept.first?.id == "s11" && kept.last?.id == "s60")
        #expect(kept.filter(\.isOpen).map(\.id) == ["s60"])
        #expect(Set(kept.map(\.id)).count == kept.count)
    }

    @Test("Ending a session that was already replaced ends the open one instead")
    func endingAReplacedSession() async throws {
        let ledger = T.ledger(ManualVoiceClock(T.now))
        let first = await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2).session
        let second = await ledger.startIntent(app: "YouTube", purpose: "", minutes: 2).session
        let ended = try #require(await ledger.endIntent(id: first.id))
        #expect(ended.id == second.id)
        #expect(await ledger.intents.first?.endReason == .replaced)
    }

    @Test("Unpausing an app that isn't paused changes nothing and tells nobody")
    func unpauseUnknown() async {
        let store = InMemoryKeyValueStore()
        let ledger = T.ledger(ManualVoiceClock(T.now), store: store)
        let stream = await ledger.events()
        await ledger.unpause(app: "Instagram")
        #expect(store.data(forKey: OnDeviceLedger.storageKey) == nil)
        await ledger.pause(app: "Instagram", seconds: 100)
        let first = await stream.first { _ in true }
        #expect(first == .paused(AppPause(app: "Instagram", seconds: 30, since: T.now)))
    }

    @Test("A listener that goes away is dropped; the others keep hearing")
    func listenersGoAway() async {
        let ledger = T.ledger(ManualVoiceClock(T.now))
        let gone = Task { for await _ in await ledger.events() {} }
        let kept = await ledger.events()
        gone.cancel()
        await gone.value
        await ledger.recordPickup()
        let event = await kept.first { _ in true }
        #expect(event == .pickup(PickupTally(day: "2026-11-20", total: 1, withIntent: 0)))
    }

    @Test("The app's UserDefaults store keeps the ledger and forgets it on nil")
    func userDefaultsStore() async throws {
        let suite = "zen.tests.ledger.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsKeyValueStore(defaults)
        let clock = ManualVoiceClock(T.now)
        await OnDeviceLedger(clock: clock, store: store, timeZone: T.india).setLastCard(id: "card-7")
        #expect(await OnDeviceLedger(clock: clock, store: store, timeZone: T.india).lastCardId == "card-7")
        store.set(nil, forKey: OnDeviceLedger.storageKey)
        #expect(store.data(forKey: OnDeviceLedger.storageKey) == nil)
        #expect(abs(SystemVoiceClock().now.timeIntervalSinceNow) < 1)
    }

    @Test("The timer loop stops when its task is cancelled")
    func timerLoopStops() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        await ledger.startIntent(app: "Instagram", purpose: "", minutes: 1)
        let loop = Task { await ledger.runTimers(every: .milliseconds(5)) }
        clock.advance(by: 61)
        await eventually("time's up") { await ledger.activeIntent?.timeUpNotified == true }
        loop.cancel()
        await loop.value
    }
}
