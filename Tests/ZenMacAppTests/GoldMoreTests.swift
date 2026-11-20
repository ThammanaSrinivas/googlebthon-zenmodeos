import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("Zen Gold: the gate, edge by edge")
struct GoldGateEdgeTests {
    private func week(_ tenths: [Int?], today: Int? = 4) -> WeekProgress {
        WeekProgress(days: tenths.map { $0.map(ZenScore.init(tenths:)) }, todayIndex: today, streakBefore: 0)
    }

    @Test("6.0 is not a good day; 6.1 is")
    func threshold() {
        #expect(GoldGate(thisWeek: week([60, 60, 60, 60, nil, nil, nil]), lastWeekWon: false).state == .locked(daysToGo: 4))
        #expect(GoldGate(thisWeek: week([61, 61, 61, 61, nil, nil, nil]), lastWeekWon: false).state == .openThisWeek)
    }

    @Test("A day with no data is not a good day")
    func gaps() {
        #expect(GoldGate(thisWeek: week([nil, 70, nil, 70, nil, nil, nil]), lastWeekWon: false).state == .locked(daysToGo: 2))
    }

    @Test("Winning this week beats last week's win")
    func thisWeekFirst() {
        #expect(GoldGate(thisWeek: week([70, 70, 70, 70, nil, nil, nil]), lastWeekWon: true).state == .openThisWeek)
    }

    @Test("The lines and the tab, for each state")
    func words() {
        let open = GoldGate(thisWeek: week([70, 70, 70, 70, nil, nil, nil]), lastWeekWon: false)
        let carried = GoldGate(thisWeek: week([50, nil, nil, nil, nil, nil, nil]), lastWeekWon: true)
        let one = GoldGate(thisWeek: week([70, 70, 70, 50, nil, nil, nil]), lastWeekWon: false)
        let three = GoldGate(thisWeek: week([70, nil, nil, nil, nil, nil, nil]), lastWeekWon: false)
        #expect(open.line == "Week won. Gold is open until Sunday." && open.tab == "Open")
        #expect(carried.line == "Last week was won, so gold is open all week." && carried.tab == "Open")
        #expect(one.line == "One more good day opens gold." && one.tab == "1 to go")
        #expect(three.line == "3 more good days open gold." && three.tab == "3 to go")
        #expect(one.isLocked && !one.isOpen && carried.isOpen && !carried.isLocked)
    }

    @Test("The demo week (3 of 4) after nine won weeks: open, from last week")
    func demoWeek() {
        let gate = GoldGate(thisWeek: FakeSnapshotWeek.value, lastWeekWon: true)
        #expect(gate.state == .openFromLastWeek)
    }
}

/// The demo week every fake shows: Monday 7.2 · 5.8 · 8.1 · 5.4 · Friday 8.1.
enum FakeSnapshotWeek {
    static let value = WeekProgress(days: [72, 58, 81, 54, 81, nil, nil].map { $0.map(ZenScore.init(tenths:)) },
                                    todayIndex: 4, streakBefore: 9)
}

@Suite("GOLDBEES: what the parser does with odd responses")
struct GoldParserEdgeTests {
    private func json(_ meta: String, closes: String = "[]") -> Data {
        Data(#"{"chart":{"result":[{"meta":{\#(meta)},"indicators":{"quote":[{"close":\#(closes)}]}}]}}"#.utf8)
    }

    @Test("A zero or negative price is no price")
    func zeroPrice() {
        #expect(throws: GoldQuoteParser.Failure.noPrice) { try GoldQuoteParser.parse(json(#""regularMarketPrice":0"#), now: Date()) }
        #expect(throws: GoldQuoteParser.Failure.noPrice) { try GoldQuoteParser.parse(json(#""regularMarketPrice":-3.5"#), now: Date()) }
    }

    @Test("Without a previous close the move is zero, not a guess")
    func noPrevious() throws {
        let q = try GoldQuoteParser.parse(json(#""regularMarketPrice":100.5"#), now: Date(timeIntervalSince1970: 5))
        #expect(q.lastPaise == 10_050 && q.previousClosePaise == 10_050)
        #expect(q.changePaise == 0 && q.changeFraction == 0)
        #expect(q.at == Date(timeIntervalSince1970: 5)) // no trade time: the time asked
        #expect(!q.marketOpen) // no session given: closed
    }

    @Test("previousClose stands in for chartPreviousClose")
    func previousCloseFallback() throws {
        let q = try GoldQuoteParser.parse(json(#""regularMarketPrice":100,"previousClose":98"#), now: Date())
        #expect(q.previousClosePaise == 9_800 && q.changePaise == 200)
    }

    @Test("Whole-number prices and gaps in the day's line")
    func integersAndGaps() throws {
        let q = try GoldQuoteParser.parse(json(#""regularMarketPrice":101,"chartPreviousClose":100"#, closes: "[100, null, 0, 101.5]"),
                                          now: Date())
        #expect(q.lastPaise == 10_100)
        #expect(q.dayPaise == [10_000, 10_150])
    }

    @Test("A response with no result at all is malformed")
    func emptyResult() {
        #expect(throws: GoldQuoteParser.Failure.malformed) {
            try GoldQuoteParser.parse(Data(#"{"chart":{"result":[]}}"#.utf8), now: Date())
        }
    }

    @Test("Paise round to the nearest", arguments: [(101.43, 10_143), (0.004, 0), (0.006, 1), (1.0, 100)])
    func paise(rupees: Double, paise: Int) {
        #expect(GoldQuoteParser.paise(rupees) == paise)
    }

    @Test("The move upward, and a flat day")
    func moveUp() {
        let up = GoldQuote(lastPaise: 10_860, previousClosePaise: 10_630, at: Date(), marketOpen: true)
        #expect(GoldMarket.move(up) == "▲ ₹2.30 · 2.2%")
        let flat = GoldQuote(lastPaise: 10_630, previousClosePaise: 10_630, at: Date(), marketOpen: true)
        #expect(GoldMarket.move(flat) == "▲ ₹0 · 0.0%")
    }

    @Test("The stamp is in India's time, wherever the Mac is")
    func stampInIST() {
        // 1_795_167_458 is 20 Nov 2026, 15:07:38 IST.
        let closed = GoldQuote(lastPaise: 1, previousClosePaise: 1, at: Date(timeIntervalSince1970: 1_795_167_458), marketOpen: false)
        #expect(GoldMarket.stamp(closed).contains("20"))
        #expect(GoldMarket.stamp(closed).contains("Nov"))
    }
}

@Suite("Rupees")
struct RupeeTests {
    @Test("Small amounts and paise", arguments: [(0, "₹0"), (5, "₹0.05"), (99, "₹0.99"), (100, "₹1"), (99_999, "₹999.99"),
                                                (1_000_00, "₹1,000"), (10_000_00, "₹10,000"), (1_00_000_00, "₹1,00,000")])
    func amounts(paise: Int, text: String) {
        #expect(Rupees.text(paise: paise) == text)
    }

    @Test("A negative amount reads with a minus sign")
    func negative() {
        #expect(Rupees.text(paise: -50) == "-₹0.50")
        #expect(Rupees.text(paise: -12_345) == "-₹123.45")
    }
}

/// A quote service under the test's control: answers each call with the next value, then waits.
private final class ScriptedQuotes: GoldQuoteService, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [GoldQuote?]
    private(set) var calls = 0

    init(_ answers: [GoldQuote?]) { self.answers = answers }

    func latest() async -> GoldQuote? {
        lock.withLock {
            calls += 1
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }
}

@Suite("GoldMarket: Invest waits for a real price")
@MainActor
struct GoldMarketModelTests {
    private let quote = GoldQuote(lastPaise: 10_143, previousClosePaise: 10_630, at: Date(timeIntervalSince1970: 1), marketOpen: true)

    @Test("Nothing is shown until a quote lands")
    func waiting() async {
        let service = ScriptedQuotes([nil])
        let market = GoldMarket(service: service)
        #expect(market.status == .waiting && market.quote == nil)
        market.start()
        #expect(await eventually { service.calls == 1 })
        // A failure before any quote keeps it waiting: never a made-up number.
        #expect(market.status == .waiting && market.quote == nil)
    }

    @Test("The first quote makes it live; start is idempotent")
    func live() async {
        let service = ScriptedQuotes([quote])
        let market = GoldMarket(service: service)
        market.start()
        market.start()
        #expect(await eventually { market.status == .live })
        #expect(market.quote == quote)
        #expect(service.calls == 1)
    }

    @Test("NoQuotes never answers with a price")
    func noQuotes() async {
        #expect(await NoQuotes().latest() == nil)
    }
}
