import Foundation
import Observation

/// GOLDBEES on the NSE, from Yahoo Finance's public chart endpoint (no key, the same feed the
/// iPhone uses). A public market price: nothing about our backend travels with it.
struct YahooGoldQuotes: GoldQuoteService {
    static let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/GOLDBEES.NS?interval=1m&range=1d")!

    func latest() async -> GoldQuote? {
        var request = URLRequest(url: Self.url, timeoutInterval: 8)
        request.setValue("ZenMode OS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? GoldQuoteParser.parse(data, now: Date())
    }
}

/// The live price for every Gold surface. Polls every 15 s while the market is open, every 60 s
/// after the close, and every 10 s after a failed fetch. Until the first quote lands, Invest waits.
@MainActor
@Observable
final class GoldMarket {
    enum Status: Equatable { case waiting, live, stale }

    static let shared = GoldMarket(service: YahooGoldQuotes())

    private(set) var quote: GoldQuote?
    private(set) var status: Status = .waiting
    @ObservationIgnored private let service: any GoldQuoteService
    @ObservationIgnored private var poller: Task<Void, Never>?

    init(service: any GoldQuoteService) { self.service = service }

    /// Starts polling once; later calls do nothing.
    func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let next = await self.service.latest()
                if let next {
                    self.quote = next
                    self.status = .live
                } else if self.quote != nil {
                    self.status = .stale
                }
                let wait = Self.interval(marketOpen: next?.marketOpen ?? false, failed: next == nil)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// 15 s while the NSE is open, 60 s after the close, 10 s after a failure.
    nonisolated static func interval(marketOpen: Bool, failed: Bool) -> Int {
        failed ? 10 : (marketOpen ? 15 : 60)
    }

    /// "Live · 3:12 PM" while the NSE is open, "Close · 20 Nov" after it.
    nonisolated static func stamp(_ quote: GoldQuote) -> String {
        let ist = TimeZone(identifier: "Asia/Kolkata") ?? .current
        if quote.marketOpen {
            return "Live · " + quote.at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: ist))
        }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.timeZone = ist
        return "Close · " + quote.at.formatted(style)
    }

    /// "▲ ₹2.30 · 2.2%" against the previous close.
    nonisolated static func move(_ quote: GoldQuote) -> String {
        let up = quote.changePaise >= 0
        let pct = abs(quote.changeFraction * 100)
        return "\(up ? "▲" : "▼") \(Rupees.text(paise: abs(quote.changePaise))) · \(String(format: "%.1f", pct))%"
    }
}

/// zenmodeos.com's Gold Invest terms, by section. Every link here was checked to exist.
enum GoldTerms {
    static let base = "https://zenmodeos.com/terms/"
    static let goldInvest = URL(string: base + "gold-invest.html")!
    static let legal = URL(string: base)!
    static let app = URL(string: base + "app.html")!
    static let privacy = URL(string: base + "privacy.html")!

    /// §03 Eligibility · §04 How the hand-off works · §05 We hold no money and no units ·
    /// §06 No investment advice · §08 Prices and quantities are indicative ·
    /// §10 Risks you are accepting · §13 Streaks and scores create no entitlement.
    static func section(_ n: Int) -> URL { URL(string: base + "gold-invest.html#s\(n)")! }
}
