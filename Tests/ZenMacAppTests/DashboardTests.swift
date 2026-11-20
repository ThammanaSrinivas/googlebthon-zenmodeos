import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("Today: the dashboard's demo days")
struct DashboardDemoTests {
    private let evening = DashboardDemo(now: nov(20, 23, 30), calendar: india)

    @Test("Three days, today first, each the day before the last")
    func days() {
        let d = evening.days
        #expect(d.map(\.id) == [0, 1, 2])
        #expect(d[0].isToday && !d[1].isToday)
        #expect(d[0].label == "Today")
        #expect(d[0].date == india.startOfDay(for: nov(20)))
        #expect(d[1].date == india.startOfDay(for: nov(19)) && d[2].date == india.startOfDay(for: nov(18)))
        #expect(d[1].now == 1440 && d[2].now == 1440)
    }

    @Test("The day's score is the lower of the screens', as the combine rule says")
    func combined() {
        for day in evening.days {
            #expect(day.score == day.screens.map(\.score).min())
        }
        #expect(evening.days.map(\.score.tenths) == [81, 54, 81])
    }

    @Test("The week strip matches the fakes and the three days; the deltas add up")
    func lastSeven() {
        let seven = evening.lastSeven.map(\.tenths)
        #expect(seven == [66, 74, 72, 58, 81, 54, 81])
        #expect(Array(seven.suffix(4)) == [58] + evening.days.reversed().map(\.score.tenths))
        for (i, day) in evening.days.enumerated() {
            #expect(day.delta == seven[6 - i] - seven[5 - i], "day \(i)")
        }
        #expect(seven.suffix(3).map { $0 } == [81, 54, 81])
        #expect(evening.days[0].score == FakeSnapshotWeek.value.days[4])
    }

    @Test("The iPhone is sealed: a score and no sessions. The Mac carries the minutes")
    func sealedPhone() throws {
        for day in evening.days {
            let phone = try #require(day.screens.first { $0.kind == .iPhone })
            #expect(phone.isSealed && phone.sessions == nil && phone.minutes == 0)
            #expect(day.mac?.kind == .mac)
            #expect(day.minutes == day.mac?.minutes)
        }
    }

    @Test("Sessions never overlap, stay inside the day, and run in order")
    func sessions() {
        for day in evening.days {
            let s = day.sessions
            #expect(!s.isEmpty)
            #expect(s.allSatisfy { $0.minutes > 0 && $0.start >= 0 && $0.end <= day.now })
            for (a, b) in zip(s, s.dropFirst()) { #expect(a.end <= b.start, "\(a.app) runs into \(b.app)") }
            #expect(Set(s.map(\.id)).count == s.count)
        }
    }

    @Test("Feel and kind split the same minutes")
    func splits() {
        for day in evening.days {
            #expect(Feel.allCases.map(day.minutes).reduce(0, +) == day.minutes)
            #expect(AppKind.allCases.map(day.minutes).reduce(0, +) == day.minutes)
            let kinds = day.kinds
            #expect(kinds == kinds.sorted { day.minutes($0) > day.minutes($1) })
            #expect(kinds.allSatisfy { day.minutes($0) > 0 })
            #expect((0...1).contains(day.onPurpose))
            for k in AppKind.allCases {
                #expect(Feel.allCases.map { day.minutes(k, $0) }.reduce(0, +) == day.minutes(k))
            }
        }
    }

    @Test("Today's numbers the cards quote: a 52 m longest run, three pull-backs")
    func todayFacts() {
        let today = evening.days[0]
        #expect(today.longestFocus?.minutes == 52 && today.longestFocus?.app == "Xcode")
        #expect(today.pullBacks == 3)
        #expect(today.nudges.allSatisfy { n in n.pullBackAt.map { $0 > n.minute } ?? true })
    }

    @Test("Before noon the demo day reads as early evening; after noon it runs to now")
    func todayNow() {
        #expect(DashboardDemo(now: nov(20, 9), calendar: india).days[0].now == 18 * 60 + 20)
        #expect(DashboardDemo(now: nov(20, 14, 40), calendar: india).days[0].now == 14 * 60 + 40)
    }

    @Test("A session running at 'now' is cut there, and later ones wait")
    func cutAtNow() throws {
        let day = DashboardDemo(now: nov(20, 15, 10), calendar: india).days[0]
        let last = try #require(day.sessions.last)
        #expect(last.app == "Xcode" && last.start == 15 * 60 && last.minutes == 10)
        #expect(day.nudges.allSatisfy { $0.minute < 15 * 60 + 10 })
        #expect(day.pullBacks == 3)
    }

    @Test("Seven cards, each with its own id and a strength in 0…1")
    func deck() {
        let deck = DashboardDemo.deck
        #expect(deck.count == 7)
        #expect(Set(deck.map(\.id)).count == 7)
        for card in deck {
            #expect((0...1).contains(card.strength), "\(card.id)")
            #expect(!card.title.isEmpty && !card.face.isEmpty && !card.tip.isEmpty && !card.suitMeaning.isEmpty)
            if let hours = card.hours { #expect(hours.count == 24 && hours.allSatisfy { (0...1).contains($0) }, "\(card.id)") }
            #expect(!card.facts.isEmpty)
        }
    }

    @Test("A shareable card face never carries minutes")
    func faces() {
        for card in DashboardDemo.deck {
            #expect(!card.face.contains(" m") && !card.face.lowercased().contains("minute"), "\(card.face)")
        }
    }

    @Test("Durations and clock times the way the cards write them", arguments: [
        (0, "0 m"), (52, "52 m"), (59, "59 m"), (60, "1h"), (263, "4h 23m"), (400, "6h 40m"), (1440, "24h"),
    ])
    func duration(minutes: Int, text: String) {
        #expect(durationText(minutes) == text)
    }

    @Test("Clock text clamps to the day", arguments: [(0, "00:00"), (570, "09:30"), (1439, "23:59"), (1500, "23:59"), (-5, "00:00")])
    func clock(minute: Int, text: String) {
        #expect(clockText(minute) == text)
    }
}

@Suite("Today: the dashboard model")
@MainActor
struct DashboardModelTests {
    @Test("Cards are dealt strongest first and ranked A, K, Q, J, 10, 9, 8")
    func ranks() {
        let m = DashboardModel(now: nov(20, 20))
        #expect(m.cards.map(\.strength) == m.cards.map(\.strength).sorted(by: >))
        #expect(m.cards.map(m.rank) == ["A", "K", "Q", "J", "10", "9", "8"])
        #expect(m.cards.map(m.position) == Array(1...7))
        #expect(m.cards.first?.id == "deep-work")
    }

    @Test("Open, step both ways with wrapping, close")
    func stepping() {
        let m = DashboardModel(now: nov(20, 20))
        #expect(m.openCard == nil)
        m.step(1) // nothing open: nothing happens
        #expect(m.openCard == nil)
        m.open(m.cards[0])
        #expect(m.openCard == m.cards[0])
        m.step(-1)
        #expect(m.openCard == m.cards[6])
        m.step(1)
        #expect(m.openCard == m.cards[0])
        m.step(3)
        #expect(m.openCard == m.cards[3])
        m.close()
        #expect(m.openCard == nil)
    }

    @Test("Starts on today; the week strip has seven days")
    func start() {
        let m = DashboardModel(now: nov(20, 20))
        #expect(m.dayIndex == 0 && m.day.isToday)
        #expect(m.lastSeven.count == 7)
        m.dayIndex = 2
        #expect(m.day.id == 2)
    }
}
