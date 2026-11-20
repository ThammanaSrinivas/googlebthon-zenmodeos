// The on-device ledger, on a clock the tests move by hand: intent timers, overruns, focus, pauses,
// pickups, persistence and the event stream.
import Foundation
import Testing
@testable import ZenVoice

@Suite("On-device ledger")
struct OnDeviceLedgerTests {
    @Test("An intent runs for its minutes; a new one replaces the open one")
    func intents() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        let first = await ledger.startIntent(app: "Instagram", purpose: "Reel", minutes: 2)
        #expect(first.session.endsAt == T.now.addingTimeInterval(120))
        #expect(first.replaced == nil)
        clock.advance(by: 30)
        let second = await ledger.startIntent(app: "YouTube", purpose: "", minutes: 10)
        #expect(second.replaced?.id == first.session.id)
        #expect(second.replaced?.endReason == .replaced)
        #expect(await ledger.activeIntent?.id == second.session.id)
        #expect(await ledger.intents.filter(\.isOpen).count == 1)
    }

    @Test("Ending on time records no overrun; the clock measures one the model left out")
    func overruns() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2)
        clock.advance(by: 120)
        let onTime = await ledger.endIntent()
        #expect(onTime?.onTime == true)
        #expect(onTime?.overrunMinutes == 0)

        await ledger.startIntent(app: "YouTube", purpose: "", minutes: 5)
        clock.advance(by: 5 * 60 + 3 * 60 + 40) // 3 min 40 s past
        let late = await ledger.endIntent(overrunMinutes: 1)
        #expect(late?.overrunMinutes == 3)
        #expect(late?.onTime == false)

        await ledger.startIntent(app: "Chrome", purpose: "", minutes: 5)
        let told = await ledger.endIntent(overrunMinutes: 9)
        #expect(told?.overrunMinutes == 9)
        #expect(await ledger.endIntent() == nil)
    }

    @Test("An unknown session id ends the open session, as the prototype did")
    func unknownIdFallsBack() async {
        let ledger = T.ledger(ManualVoiceClock(T.now))
        let open = await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2).session
        #expect(await ledger.endIntent(id: "s999")?.id == open.id)
    }

    @Test("The ledger clamps minutes, focus length and pause seconds itself too")
    func clamps() async {
        let ledger = T.ledger(ManualVoiceClock(T.now))
        #expect(await ledger.startIntent(app: "X", purpose: "", minutes: 999).session.minutes == 180)
        #expect(await ledger.startIntent(app: "X", purpose: "", minutes: -4).session.minutes == 1)
        #expect(await ledger.startFocus(minutes: 1, label: "L", quietApps: []).minutes == 5)
        #expect(await ledger.pause(app: "X", seconds: 99).seconds == 30)
    }

    @Test("Time's up fires once per session; focus ends at its end time")
    func timers() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        let session = await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2).session
        let focus = await ledger.startFocus(minutes: 45, label: "Client demo prep", quietApps: ["WhatsApp"])
        clock.advance(by: 119)
        #expect(await ledger.checkTimers().isEmpty)
        clock.advance(by: 1)
        let fired = await ledger.checkTimers()
        #expect(fired.count == 1)
        guard case .intentTimeUp(let up) = fired.first else { Issue.record("expected time's up"); return }
        #expect(up.id == session.id)
        #expect(await ledger.checkTimers().isEmpty)
        #expect(await ledger.activeIntent?.id == session.id) // still open: the person ends it

        clock.advance(by: 45 * 60)
        let ended = await ledger.checkTimers()
        #expect(ended == [.focusEnded(FocusSession(id: focus.id, label: focus.label, minutes: 45, quietApps: ["WhatsApp"],
                                                   startedAt: focus.startedAt, endsAt: focus.endsAt, endedAt: focus.endsAt))])
        #expect(await ledger.activeFocus == nil)
    }

    @Test("A new focus replaces the running one; ending early stops it")
    func focusReplace() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        await ledger.startFocus(minutes: 60, label: "A", quietApps: [])
        clock.advance(by: 60)
        let second = await ledger.startFocus(minutes: 45, label: "B", quietApps: [])
        #expect(await ledger.activeFocus?.id == second.id)
        clock.advance(by: 60)
        let ended = await ledger.endFocus()
        #expect(ended?.endedAt == clock.now)
        #expect(await ledger.endFocus() == nil)
    }

    @Test("Pauses match apps without case and keep the first spelling")
    func pauses() async {
        let ledger = T.ledger(ManualVoiceClock(T.now))
        await ledger.pause(app: "WhatsApp", seconds: 7)
        let updated = await ledger.pause(app: "whatsapp", seconds: 12)
        #expect(updated.app == "WhatsApp")
        #expect(updated.seconds == 12)
        #expect(await ledger.pauses.count == 1)
        #expect(await ledger.pauseSeconds(for: "WHATSAPP") == 12)
        await ledger.unpause(app: "Whatsapp")
        #expect(await ledger.pauses.isEmpty)
    }

    @Test("Pickups count per day; an intent marks its pickup once")
    func pickups() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        await ledger.recordPickup()
        await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2)
        await ledger.startIntent(app: "YouTube", purpose: "", minutes: 2) // same pickup
        #expect(await ledger.today() == PickupTally(day: "2026-11-20", total: 1, withIntent: 1))
        await ledger.recordPickup()
        #expect(await ledger.today() == PickupTally(day: "2026-11-20", total: 2, withIntent: 1))
        clock.advance(by: 2 * 3_600) // past midnight in India
        #expect(await ledger.today() == PickupTally(day: "2026-11-21", total: 0, withIntent: 0))
        await ledger.startIntent(app: "Chrome", purpose: "", minutes: 2) // no pickup today yet
        #expect(await ledger.today().withIntent == 0)
    }

    @Test("State survives a relaunch through the key-value store")
    func persistence() async {
        let clock = ManualVoiceClock(T.now)
        let store = InMemoryKeyValueStore()
        let ledger = T.ledger(clock, store: store)
        await ledger.recordPickup()
        let session = await ledger.startIntent(app: "Instagram", purpose: "Reel", minutes: 2).session
        await ledger.pause(app: "WhatsApp", seconds: 7)
        await ledger.setLastCard(id: "card-1")

        let relaunched = T.ledger(clock, store: store)
        #expect(await relaunched.activeIntent == session)
        #expect(await relaunched.pauses.map(\.app) == ["WhatsApp"])
        #expect(await relaunched.lastCardId == "card-1")
        #expect(await relaunched.today().total == 1)
        // Ids keep counting, so a new session never reuses an old id.
        #expect(await relaunched.startIntent(app: "X", purpose: "", minutes: 1).session.id != session.id)
    }

    @Test("Listeners get every change")
    func events() async {
        let clock = ManualVoiceClock(T.now)
        let ledger = T.ledger(clock)
        let stream = await ledger.events()
        let collected = Task { () -> [LedgerEvent] in
            var events: [LedgerEvent] = []
            for await event in stream {
                events.append(event)
                if events.count == 4 { break }
            }
            return events
        }
        let session = await ledger.startIntent(app: "Instagram", purpose: "", minutes: 2).session
        let pause = await ledger.pause(app: "WhatsApp", seconds: 7)
        clock.advance(by: 120)
        await ledger.checkTimers()
        let ended = await ledger.endIntent()!
        var timeUp = session
        timeUp.timeUpNotified = true
        #expect(await collected.value == [.intentStarted(session), .paused(pause), .intentTimeUp(timeUp), .intentEnded(ended)])
    }
}
