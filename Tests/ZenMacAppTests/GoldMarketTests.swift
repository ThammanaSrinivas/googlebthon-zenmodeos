import Foundation
import Testing
@testable import ZenMacApp

@Suite("GOLDBEES: the live price")
struct GoldMarketTests {
    /// Trimmed from a real response of Yahoo's chart endpoint for GOLDBEES.NS (20 Nov 2026).
    static let sample = """
    {"chart":{"result":[{"meta":{"currency":"INR","symbol":"GOLDBEES.NS","exchangeTimezoneName":"Asia/Kolkata",
    "regularMarketPrice":101.43,"chartPreviousClose":106.3,"previousClose":106.3,"regularMarketTime":1795167458,
    "currentTradingPeriod":{"pre":{"start":1795146300,"end":1795146300},"regular":{"timezone":"IST","start":1795146300,"end":1795168800},
    "post":{"start":1795168800,"end":1795168800}}},
    "timestamp":[1795146300,1795146360,1795146420,1795146480],
    "indicators":{"quote":[{"close":[101.7300033569336,null,101.62999725341797,101.43000030517578]}]}}],"error":null}}
    """

    private var data: Data { Data(Self.sample.utf8) }

    @Test("Reads the price, the previous close and today's line in paise")
    func parses() throws {
        let q = try GoldQuoteParser.parse(data, now: Date(timeIntervalSince1970: 1_795_160_000))
        #expect(q.lastPaise == 10_143)
        #expect(q.previousClosePaise == 10_630)
        #expect(q.dayPaise == [10_173, 10_163, 10_143])
        #expect(q.at == Date(timeIntervalSince1970: 1_795_167_458))
    }

    @Test("Open inside the regular session, closed outside it")
    func session() throws {
        #expect(try GoldQuoteParser.parse(data, now: Date(timeIntervalSince1970: 1_795_160_000)).marketOpen)
        #expect(try !GoldQuoteParser.parse(data, now: Date(timeIntervalSince1970: 1_795_168_800)).marketOpen)
        #expect(try !GoldQuoteParser.parse(data, now: Date(timeIntervalSince1970: 1_795_140_000)).marketOpen)
    }

    @Test("The move against the previous close")
    func move() throws {
        let q = try GoldQuoteParser.parse(data, now: Date(timeIntervalSince1970: 1_795_160_000))
        #expect(q.changePaise == -487)
        #expect(GoldMarket.move(q) == "▼ ₹4.87 · 4.6%")
    }

    @Test("A response without a price is refused, never guessed")
    func noPrice() {
        let broken = Data(#"{"chart":{"result":[{"meta":{"symbol":"GOLDBEES.NS"}}]}}"#.utf8)
        #expect(throws: GoldQuoteParser.Failure.noPrice) { try GoldQuoteParser.parse(broken, now: Date()) }
        #expect(throws: GoldQuoteParser.Failure.malformed) { try GoldQuoteParser.parse(Data("nope".utf8), now: Date()) }
    }

    @Test("Polls every 15 s while open, 60 s after the close, 10 s after a failure")
    func cadence() {
        #expect(GoldMarket.interval(marketOpen: true, failed: false) == 15)
        #expect(GoldMarket.interval(marketOpen: false, failed: false) == 60)
        #expect(GoldMarket.interval(marketOpen: true, failed: true) == 10)
    }

    @Test("The stamp says Live with a time, or Close with a date")
    func stamp() {
        let open = GoldQuote(lastPaise: 10_143, previousClosePaise: 10_630, at: Date(timeIntervalSince1970: 1_795_167_458), marketOpen: true)
        let closed = GoldQuote(lastPaise: 10_143, previousClosePaise: 10_630, at: Date(timeIntervalSince1970: 1_795_167_458), marketOpen: false)
        #expect(GoldMarket.stamp(open).hasPrefix("Live · "))
        #expect(GoldMarket.stamp(closed).hasPrefix("Close · "))
    }

    @Test("A real order carries rupees with Indian grouping; a demo order carries none")
    func ledgerMoney() {
        let real = GoldOrder(id: "x", week: Date(), units: 3, pricePaise: 10_143)
        #expect(real.totalPaise.map(Rupees.text) == "₹304.29")
        #expect(GoldOrder(id: "d", week: Date(), units: 2, pricePaise: nil).totalPaise == nil)
    }

    @Test("Every terms link points at zenmodeos.com's Gold Invest terms")
    func terms() {
        #expect(GoldTerms.goldInvest.absoluteString == "https://zenmodeos.com/terms/gold-invest.html")
        #expect(GoldTerms.section(10).absoluteString == "https://zenmodeos.com/terms/gold-invest.html#s10")
        #expect(GoldTerms.privacy.host == "zenmodeos.com")
    }
}
