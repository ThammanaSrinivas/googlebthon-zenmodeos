import Foundation
import Observation
import ZenAPI

/// Zen Gold's rules, the same as the iPhone's: a won week (4 good days) opens gold pay until
/// Sunday midnight, and a won week also keeps it open for the whole week after.
struct GoldGate: Equatable {
    enum State: Equatable {
        case openThisWeek
        case openFromLastWeek
        /// Good days still needed this week.
        case locked(daysToGo: Int)
    }

    let state: State

    init(thisWeek: WeekProgress, lastWeekWon: Bool) {
        if thisWeek.isWon { state = .openThisWeek }
        else if lastWeekWon { state = .openFromLastWeek }
        else { state = .locked(daysToGo: max(WeekProgress.goodDaysToWin - thisWeek.goodDays, 1)) }
    }

    var isOpen: Bool { !isLocked }
    var isLocked: Bool { if case .locked = state { true } else { false } }

    var line: String {
        switch state {
        case .openThisWeek: "Week won. Gold is open until Sunday."
        case .openFromLastWeek: "Last week was won, so gold is open all week."
        case .locked(let n): n == 1 ? "One more good day opens gold." : "\(n) more good days open gold."
        }
    }

    var tab: String {
        switch state {
        case .openThisWeek, .openFromLastWeek: "Open"
        case .locked(let n): "\(n) to go"
        }
    }
}

/// A live GOLDBEES quote. Only ever a real, live price: nothing is shown until one arrives.
struct GoldQuote: Equatable, Sendable {
    /// Rupees in paise, so sums never drift.
    let lastPaise: Int
    let previousClosePaise: Int
    /// When the last trade printed.
    let at: Date
    /// True while the NSE's regular session is open.
    let marketOpen: Bool
    /// Today's one-minute closes, oldest first, for the sparkline.
    var dayPaise: [Int] = []

    /// The move against the previous close, in paise and as a fraction.
    var changePaise: Int { lastPaise - previousClosePaise }
    var changeFraction: Double { previousClosePaise == 0 ? 0 : Double(changePaise) / Double(previousClosePaise) }
}

/// Where quotes come from. `YahooGoldQuotes` reads the public NSE price; `NoQuotes` keeps Invest
/// waiting rather than showing a made-up number.
protocol GoldQuoteService: Sendable {
    func latest() async -> GoldQuote?
}

struct NoQuotes: GoldQuoteService {
    func latest() async -> GoldQuote? { nil }
}

/// Reads Yahoo Finance's public chart response for GOLDBEES.NS. Pure, so it is tested on a
/// captured response; the network lives in `YahooGoldQuotes`.
enum GoldQuoteParser {
    enum Failure: Error, Equatable { case malformed, noPrice }

    static func parse(_ data: Data, now: Date) throws -> GoldQuote {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any] else { throw Failure.malformed }
        guard let price = number(meta["regularMarketPrice"]), price > 0 else { throw Failure.noPrice }
        let previous = number(meta["chartPreviousClose"]) ?? number(meta["previousClose"]) ?? price
        let time = number(meta["regularMarketTime"]).map { Date(timeIntervalSince1970: $0) } ?? now
        var open = false
        if let period = meta["currentTradingPeriod"] as? [String: Any], let regular = period["regular"] as? [String: Any],
           let start = number(regular["start"]), let end = number(regular["end"]) {
            let t = now.timeIntervalSince1970
            open = t >= start && t < end
        }
        let closes = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Any] ?? []
        let day = closes.compactMap(number).filter { $0 > 0 }.map(paise)
        return GoldQuote(lastPaise: paise(price), previousClosePaise: paise(previous), at: time, marketOpen: open, dayPaise: day)
    }

    static func paise(_ rupees: Double) -> Int { Int((rupees * 100).rounded()) }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        return nil
    }
}

/// One week's order, recorded on this Mac at the price handed off at.
struct GoldOrder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// The Monday of the week the order belongs to.
    let week: Date
    let units: Int
    let pricePaise: Int?

    var totalPaise: Int? { pricePaise.map { $0 * units } }
}

/// The gold set aside, on this Mac. One order per week; a retry replaces it.
@MainActor
@Observable
final class GoldLedger {
    private(set) var orders: [GoldOrder]
    /// True while the ledger holds the demo weeks (no real order recorded yet).
    private(set) var isDemo: Bool
    private static let key = "zen.gold.ledger.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([GoldOrder].self, from: data), !saved.isEmpty {
            orders = saved
            isDemo = false
        } else {
            orders = Self.demo()
            isDemo = true
        }
    }

    var units: Int { orders.reduce(0) { $0 + $1.units } }
    var weeks: Int { Set(orders.map(\.week)).count }

    func record(units: Int, pricePaise: Int, week: Date) {
        if isDemo { orders = []; isDemo = false }
        orders.removeAll { $0.week == week }
        orders.insert(GoldOrder(id: UUID().uuidString, week: week, units: units, pricePaise: pricePaise), at: 0)
        if let data = try? JSONEncoder().encode(orders) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Units only: a demo ledger never carries prices.
    private static func demo() -> [GoldOrder] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        return [(1, 2), (2, 1), (3, 3), (5, 2), (6, 1), (8, 5)].map { back, units in
            GoldOrder(id: "demo-\(back)", week: calendar.date(byAdding: .weekOfYear, value: -back, to: monday)!, units: units, pricePaise: nil)
        }
    }
}

/// ₹ with Indian grouping: ₹1,23,456.50.
enum Rupees {
    static func text(paise: Int) -> String {
        let rupees = paise / 100, rest = paise % 100
        var digits = String(rupees)
        var grouped = ""
        if digits.count > 3 {
            let last3 = String(digits.suffix(3))
            digits.removeLast(3)
            var pairs: [String] = []
            while digits.count > 2 { pairs.insert(String(digits.suffix(2)), at: 0); digits.removeLast(2) }
            if !digits.isEmpty { pairs.insert(digits, at: 0) }
            grouped = pairs.joined(separator: ",") + "," + last3
        } else {
            grouped = digits
        }
        return "₹" + grouped + (rest == 0 ? "" : String(format: ".%02d", rest))
    }
}
