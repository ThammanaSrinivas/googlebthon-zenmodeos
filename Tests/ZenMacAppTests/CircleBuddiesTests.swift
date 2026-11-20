import Foundation
import Testing
import Albeit
import ZenAPI
@testable import ZenMacApp

@Suite("Zen Circle · Zen Bros: the seats")
struct BuddiesTests {
    private func buddy(today: Int?, streak: Int = 0, week: [Int?] = []) -> Buddy {
        Buddy(id: "fake", name: "Fake", isYou: false, weekTenths: 60, todayTenths: today, streak: streak,
              week: week, device: .iPhone, received: 0)
    }

    @Test("Zeno's face per seat, and never sad", arguments: [
        (Int?.none, 0, ZenoFeeling.sleepy), (84, 12, .proud), (61, 10, .proud), (60, 10, .calm),
        (80, 2, .happy), (79, 2, .pleasant), (61, 0, .pleasant), (60, 0, .calm), (0, 0, .calm),
    ])
    func feeling(today: Int?, streak: Int, face: ZenoFeeling) {
        let f = buddy(today: today, streak: streak).feeling
        #expect(f == face)
        #expect(f != .sad)
    }

    @Test("Good days are above 6.0; days with no data don't count")
    func goodDays() {
        #expect(buddy(today: nil, week: [61, 60, nil, 75]).goodDays == 2)
        #expect(buddy(today: nil).goodDays == 0)
    }

    @Test("Today ranks by today's score, the week by the week's")
    func periods() {
        let b = Buddy(id: "x", name: "X", isYou: false, weekTenths: 70, todayTenths: nil, streak: 0, week: [], device: .mac, received: 0)
        #expect(b.score(.week) == 70 && b.score(.today) == nil)
    }

    @Test("A seat's seed is stable across launches and differs between seats")
    func seed() {
        let ids = BuddyDemo.circle.map(\.seed)
        #expect(Set(ids).count == ids.count)
        #expect(buddy(today: nil).seed == buddy(today: 50).seed)
    }

    @Test("The demo circle: five people, one of them you, in seven seats")
    func demoCircle() {
        let c = BuddyDemo.circle
        #expect(c.count == 5 && c.count <= BuddyDemo.seats)
        #expect(c.filter { $0.isYou }.count == 1)
        #expect(Set(c.map(\.id)).count == c.count)
        #expect(c.allSatisfy { $0.week.count <= 7 && $0.received <= Reaction.perDay })
    }

    @Test("Your seat matches your own week everywhere else: 8.1 today, 3 good days, a 9-week streak")
    func yourSeat() throws {
        let you = try #require(BuddyDemo.circle.first { $0.isYou })
        #expect(you.todayTenths == FakeSnapshotWeek.value.days[4]?.tenths)
        #expect(you.week == FakeSnapshotWeek.value.days.prefix(5).map { $0?.tenths })
        #expect(you.goodDays == FakeSnapshotWeek.value.goodDays)
        #expect(you.streak == FakeSnapshotWeek.value.streakBefore)
    }

    @Test("Every friend's week average is the average of their days so far")
    func othersAverages() {
        for b in BuddyDemo.circle where !b.isYou {
            let days = b.week.compactMap { $0 }
            let mean = Double(days.reduce(0, +)) / Double(days.count)
            #expect(Int(mean.rounded()) == b.weekTenths, "\(b.name)")
        }
    }

    @Test("Your week average is the average of your days so far")
    func yourAverage() throws {
        let you = try #require(BuddyDemo.circle.first { $0.isYou })
        let days = you.week.compactMap { $0 }
        #expect(Int((Double(days.reduce(0, +)) / Double(days.count)).rounded()) == you.weekTenths)
    }

    @Test("The feed agrees with the seats")
    func feed() throws {
        let asha = try #require(BuddyDemo.circle.first { $0.id == "asha" })
        let won = WeekProgress(days: (asha.week + Array(repeating: nil, count: 7 - asha.week.count)).map { $0.map(ZenScore.init(tenths:)) },
                               todayIndex: 4, streakBefore: asha.streak - 1)
        #expect(won.winningDayIndex == 3) // Thursday
        #expect(BuddyDemo.feed[0].line.contains("Thursday") && BuddyDemo.feed[0].line.contains("\(asha.streak) in a row"))
        let meera = try #require(BuddyDemo.circle.first { $0.id == "meera" })
        #expect(meera.todayTenths == nil && meera.feeling == .sleepy)
    }

    @Test("Four reactions, four a day, each its own symbol")
    func reactions() {
        #expect(Reaction.allCases.count == 4 && Reaction.perDay == 4)
        #expect(Set(Reaction.allCases.map(\.symbol)).count == 4)
    }
}
