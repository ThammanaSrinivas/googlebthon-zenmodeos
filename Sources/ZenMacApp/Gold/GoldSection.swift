import SwiftUI
import Albeit
import ZenAPI

enum GoldCopy {
    static let eyebrow = "Zen Gold"
    static let titleTop = "Good weeks"
    static let titleBottom = "turn to gold."
    static let lede = "Win the week with four good days and gold pay opens until Sunday, and for the whole week after."
    static let setAside = "Set aside"
    static let ticker = "GOLDBEES · NSE"
    static let waitingPrice = "Waiting for the live price"
    static let stalePrice = "Showing the last price we got"
    static let indicative = "Prices are indicative and may be delayed"
    static let invest = "Invest gold"
    static let risk = "Investing in a gold ETF carries risk, and you can lose money."
    static let toranTitle = "This month, as a garland"
    static let toranLine = "A marigold for every good day. A won week ends in a tassel."
    static let ledger = "Orders"
    static let howTitle = "How it works"
    static let how: [(String, Int)] = [
        ("Win the week: four days above 6.0.", 13),
        ("Gold opens till Sunday, and all next week.", 13),
        ("Pick 1 to 10 units of GOLDBEES, then confirm the order yourself in Zerodha Kite.", 4),
    ]
    static let noCustody = "ZenMode OS is not a broker and gives no investment advice. Zerodha executes, settles and holds; ZenMode never takes custody of money or units."
    static let eligibility = "You need to be 18 or older, with an active Zerodha trading and demat account and KYC done."
    static let handOff = "Kite opens in your browser, where you review and confirm the order. The price you get is the price your order executes at."
    static let glanceOpen = "Gold is open this week"
    static let openGold = "Open Zen Gold"
    // Link titles
    static let termsGold = "Gold Invest terms"
    static let termsRisks = "Risks you accept"
    static let termsPrices = "Indicative prices"
    static let termsEligibility = "Eligibility"
    static let termsHandOff = "How the hand-off works"
    static let termsApp = "App terms"
    static let termsPrivacy = "Privacy"
}

/// Zen Gold: the coin, the gold set aside and the live price on one ink card with the page's one
/// primary action (Invest gold), the month as a marigold toran, the orders, and the terms that
/// govern it, linked clause by clause on zenmodeos.com.
struct GoldSection: View {
    @Environment(AppModel.self) private var model
    @State private var investing = false
    private let market = GoldMarket.shared

    var body: some View {
        let gate = model.goldGate
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s6) {
                hero(gate)
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    GoldCard(gate: gate, investing: $investing)
                        .frame(maxWidth: .infinity)
                    toranCard
                        .frame(width: 340)
                }
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    ordersCard
                    howCard.frame(width: 340)
                }
                legalFooter
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $investing) { InvestSheet(gate: gate) }
        .task { market.start() }
    }

    private func hero(_ gate: GoldGate) -> some View {
        HStack(alignment: .center, spacing: ZenSpace.s6) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(GoldCopy.eyebrow, color: Color.zen.accentRewardText)
                VStack(alignment: .leading, spacing: 0) {
                    Text(GoldCopy.titleTop).foregroundStyle(Color.zen.textHeading)
                    Text(GoldCopy.titleBottom).foregroundStyle(GoldInk.gradient)
                }
                .zenType(.display)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Text(GoldCopy.lede).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xFFC800, alpha: 0.35), .clear], center: .center, startRadius: 0, endRadius: 120))
                    .frame(width: 240, height: 240)
                GoldCoin(glint: gate.isOpen)
                    .frame(width: 150, height: 150)
                    .rotation3DEffect(.degrees(-12), axis: (x: 0.2, y: 1, z: 0), perspective: 0.6)
                    .shadow(color: Color(hex: 0x7A4E00, alpha: 0.35), radius: 18, x: 6, y: 14)
            }
            .frame(width: 220, height: 180)
            .accessibilityElement()
            .accessibilityLabel("Zen Gold coin\(gate.isOpen ? ", gold is open" : "")")
        }
    }

    private var toranCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Eyebrow(GoldCopy.toranTitle)
                Spacer()
                DemoTag("Demo history")
            }
            Toran(weeks: model.streak?.weeks ?? [])
                .frame(height: 236)
            Text(GoldCopy.toranLine).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
    }

    private var ordersCard: some View {
        let ledger = model.goldLedger
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Text(GoldCopy.ledger).zenType(.title).foregroundStyle(Color.zen.textHeading)
                if ledger.isDemo { DemoTag("Demo ledger") }
                Spacer()
                Text("\(ledger.units) units · \(ledger.weeks) weeks").font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption)
            }
            VStack(spacing: 0) {
                ForEach(ledger.orders) { order in
                    HStack(spacing: ZenSpace.s3) {
                        GoldCoin().frame(width: 24, height: 24)
                        Text("Week of \(order.week.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        Spacer()
                        Text("\(order.units) unit\(order.units == 1 ? "" : "s")").font(ZenFont.number(13)).foregroundStyle(Color.zen.textHeading)
                        Group {
                            if let total = order.totalPaise {
                                Text(Rupees.text(paise: total)).foregroundStyle(Color.zen.textHeading)
                            } else {
                                Text("—").foregroundStyle(Color.zen.textCaption)
                            }
                        }
                        .font(ZenFont.number(13))
                        .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.zen.borderHairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            if ledger.isDemo {
                Text("Your real orders show here with the price they were handed off at.")
                    .zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(GoldCopy.howTitle)
            ForEach(Array(GoldCopy.how.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Text("0\(i + 1)").font(ZenFont.number(12)).foregroundStyle(Color.zen.accentRewardText)
                    Text(step.0).font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: ZenSpace.s4) {
                TermsLink(title: GoldCopy.termsHandOff, url: GoldTerms.section(4), color: Color.zen.accentRewardText)
                TermsLink(title: GoldCopy.termsEligibility, url: GoldTerms.section(3), color: Color.zen.accentRewardText)
            }
            .padding(.top, ZenSpace.s1)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.5)))
    }

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Rectangle().fill(Color.zen.borderHairline).frame(height: 1)
            Text(GoldCopy.noCustody).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
            HStack(spacing: ZenSpace.s5) {
                TermsLink(title: GoldCopy.termsGold, url: GoldTerms.goldInvest)
                TermsLink(title: GoldCopy.termsRisks, url: GoldTerms.section(10))
                TermsLink(title: GoldCopy.termsApp, url: GoldTerms.app)
                TermsLink(title: GoldCopy.termsPrivacy, url: GoldTerms.privacy)
            }
        }
    }
}

/// The amber words, legible on paper and on ink.
enum GoldInk {
    static let gradient = LinearGradient(colors: [Color(light: 0xC99A00, dark: 0xFFD86B), Color(light: 0x7A5A00, dark: 0xFFC800)],
                                         startPoint: .leading, endPoint: .trailing)
}

/// The ink card: gold set aside, the live price, this week's four, and Invest gold.
struct GoldCard: View {
    @Environment(AppModel.self) private var model
    let gate: GoldGate
    @Binding var investing: Bool
    private let market = GoldMarket.shared

    var body: some View {
        let week = (model.snapshot ?? FakeSnapshot.value).week
        let ledger = model.goldLedger
        let quote = market.quote
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GoldCopy.setAside.uppercased()).font(ZenFont.number(10.5)).tracking(1).foregroundStyle(Color(hex: 0xA4A9A0))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(ledger.units)").font(ZenFont.number(52)).foregroundStyle(Color(hex: 0xFFC800))
                        Text("units of gold").font(ZenFont.text(15, .semibold)).foregroundStyle(Color(hex: 0xF2F3EE))
                    }
                    // A rupee value only for real orders: demo units never get a price.
                    if let quote, !ledger.isDemo {
                        Text("≈ \(Rupees.text(paise: quote.lastPaise * ledger.units)) at today's price")
                            .font(ZenFont.text(12.5)).foregroundStyle(Color(hex: 0xC9CCC4))
                    } else {
                        Text("across \(ledger.weeks) won weeks").font(ZenFont.text(12.5)).foregroundStyle(Color(hex: 0x9DA298))
                    }
                }
                Spacer()
                GoldCoin(glint: gate.isOpen).frame(width: 64, height: 64)
                    .shadow(color: Color(hex: 0xFFC800, alpha: 0.35), radius: 16)
            }
            ticker(quote)
            HStack(spacing: ZenSpace.s3) {
                CellRow((0..<4).map { $0 < week.goodDays ? .reward : .empty }, size: 14)
                Text(gate.line).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color(hex: 0xF2F3EE))
                Spacer()
                Text(gate.tab.uppercased()).font(ZenFont.number(10)).tracking(0.8)
                    .foregroundStyle(gate.isOpen ? Color(hex: 0x1A1003) : Color(hex: 0xC9CCC4))
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(gate.isOpen ? Color(hex: 0xFFC800) : .white.opacity(0.1)))
            }
            Button {
                investing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: gate.isOpen ? "sparkles" : "lock.fill").font(.system(size: 12, weight: .semibold))
                    Text(gate.isOpen ? GoldCopy.invest : "\(GoldCopy.invest) · \(gate.tab)")
                }
                .font(ZenFont.text(14, .semibold))
                .foregroundStyle(Color(hex: 0x1A1003))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFD86B), Color(hex: 0xFFC800)], startPoint: .top, endPoint: .bottom)))
                .opacity(gate.isOpen ? 1 : 0.45)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!gate.isOpen)
            .accessibilityHint(gate.isOpen ? "Choose how many units to buy, then confirm in Kite" : gate.line)
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                Text(GoldCopy.risk).font(ZenFont.text(11.5)).foregroundStyle(Color(hex: 0x9DA298))
                TermsLink(title: GoldCopy.termsGold, url: GoldTerms.section(10), color: Color(hex: 0xFFD86B))
            }
        }
        .padding(ZenSpace.s5)
        .background(InkTable())
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color(hex: 0xFFC800, alpha: 0.22), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
    }

    /// GOLDBEES now: the price, the move, today's line and when it was last traded.
    private func ticker(_ quote: GoldQuote?) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Circle().fill(quote == nil ? Color(hex: 0x858A81) : (quote!.marketOpen ? Color(hex: 0x5BDF62) : Color(hex: 0xC9CCC4)))
                    .frame(width: 7, height: 7)
                Text(GoldCopy.ticker).font(ZenFont.number(11)).foregroundStyle(Color(hex: 0xC9CCC4))
                Spacer()
                if let q = quote {
                    Text(Rupees.text(paise: q.lastPaise)).font(ZenFont.number(17)).foregroundStyle(Color(hex: 0xF2F3EE))
                    Text(GoldMarket.move(q)).font(ZenFont.number(11.5))
                        .foregroundStyle(q.changePaise >= 0 ? Color(hex: 0x5BDF62) : Color(hex: 0xFF8A3D))
                } else {
                    ProgressView().controlSize(.mini)
                    Text(GoldCopy.waitingPrice).font(ZenFont.text(12)).foregroundStyle(Color(hex: 0x9DA298))
                }
            }
            if let q = quote, q.dayPaise.count > 1 {
                GoldSparkline(points: q.dayPaise, previousClose: q.previousClosePaise)
                    .frame(height: 46)
            }
            if let q = quote {
                HStack(spacing: ZenSpace.s2) {
                    Text(market.status == .stale ? GoldCopy.stalePrice : "\(GoldMarket.stamp(q)) · Prev close \(Rupees.text(paise: q.previousClosePaise))")
                        .font(ZenFont.number(10.5)).foregroundStyle(Color(hex: 0x9DA298))
                    Spacer()
                    TermsLink(title: GoldCopy.indicative, url: GoldTerms.section(8), color: Color(hex: 0x9DA298))
                }
            }
        }
        .padding(ZenSpace.s3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(quote.map { "GOLDBEES \(Rupees.text(paise: $0.lastPaise)), \($0.changePaise >= 0 ? "up" : "down") \(Rupees.text(paise: abs($0.changePaise))) on the previous close, \(GoldMarket.stamp($0))" }
                            ?? GoldCopy.waitingPrice)
    }
}

/// Invest gold, two steps: how many units, then review and hand off to Kite. The order is recorded
/// at the price handed off at, so it waits for a real live price.
private struct InvestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let gate: GoldGate
    @State private var units = 1
    @State private var reviewing = false
    private let market = GoldMarket.shared

    var body: some View {
        let quote = market.quote
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack {
                Eyebrow(reviewing ? "02 · Review" : "01 · How much", color: Color.zen.accentRewardText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Color.zen.textCaption)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }
            HStack(spacing: ZenSpace.s3) {
                GoldCoin().frame(width: 40, height: 40)
                Text(reviewing ? "Review your order" : "Units of GOLDBEES this week").zenType(.title).foregroundStyle(Color.zen.textHeading)
            }
            if !reviewing {
                HStack(spacing: ZenSpace.s3) {
                    ForEach([1, 3, 5], id: \.self) { n in
                        Button("\(n)") { units = n }
                            .buttonStyle(units == n ? AnyButtonStyle(ZenPrimaryButtonStyle()) : AnyButtonStyle(ZenSecondaryButtonStyle()))
                    }
                    Spacer()
                    Stepper(value: $units, in: 1...10) {
                        Text("\(units)").font(ZenFont.number(28)).foregroundStyle(Color.zen.textHeading)
                    }
                }
                if let q = quote {
                    LabeledContent("At today's price", value: "≈ \(Rupees.text(paise: q.lastPaise * units))")
                        .font(ZenFont.text(13.5))
                }
                Text(GoldCopy.eligibility).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
                TermsLink(title: GoldCopy.termsEligibility, url: GoldTerms.section(3))
            } else if let q = quote {
                LabeledContent("Units", value: "\(units)")
                LabeledContent("Price", value: "\(Rupees.text(paise: q.lastPaise)) · \(GoldMarket.stamp(q))")
                LabeledContent("Estimated total", value: Rupees.text(paise: q.lastPaise * units))
                Text(GoldCopy.handOff).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: ZenSpace.s4) {
                    TermsLink(title: GoldCopy.termsHandOff, url: GoldTerms.section(4))
                    TermsLink(title: GoldCopy.termsPrices, url: GoldTerms.section(8))
                    TermsLink(title: GoldCopy.termsRisks, url: GoldTerms.section(10))
                }
            }
            if quote == nil {
                Label(GoldCopy.waitingPrice, systemImage: "clock").font(ZenFont.text(13)).foregroundStyle(Color.zen.textCaption)
            }
            HStack {
                if reviewing { Button("Back") { reviewing = false }.buttonStyle(ZenLinkButtonStyle()) }
                Spacer()
                Button(reviewing ? "Open Kite to authorise" : "Review order") {
                    if reviewing, let q = quote {
                        model.recordGoldOrder(units: units, quote: q)
                        if let url = URL(string: "https://kite.zerodha.com/") { NSWorkspace.shared.open(url) }
                        dismiss()
                    } else {
                        reviewing = true
                    }
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(quote == nil || !gate.isOpen)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ZenSpace.s6)
        .frame(width: 460)
        .task { market.start() }
    }
}

/// Lets a button pick its style at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Zen Gold at a glance, for Today: the coin, the gate, the live price, this week as seven
/// marigolds, and a way in. Calm: Today's primary action is Share today, so this card only links.
struct GoldGlanceCard: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void
    private let market = GoldMarket.shared

    var body: some View {
        let gate = model.goldGate
        let week = (model.snapshot ?? FakeSnapshot.value).week
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                GoldCoin(glint: gate.isOpen).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(GoldCopy.eyebrow).font(ZenFont.brand(20)).foregroundStyle(Color.zen.textHeading)
                    Text(gate.isOpen ? GoldCopy.glanceOpen : gate.line).font(ZenFont.text(12.5)).foregroundStyle(Color.zen.accentRewardText)
                }
                Spacer()
                Text(gate.tab.uppercased()).font(ZenFont.number(10)).tracking(0.8)
                    .foregroundStyle(gate.isOpen ? Color(hex: 0x1A1003) : Color.zen.textCaption)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(gate.isOpen ? Color.zen.accentReward : Color.zen.surfaceSunk))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(model.goldLedger.units)").font(ZenFont.number(40)).foregroundStyle(GoldInk.gradient)
                Text("units set aside").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                Spacer()
                if let q = market.quote {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Rupees.text(paise: q.lastPaise)).font(ZenFont.number(13)).foregroundStyle(Color.zen.textHeading)
                        Text(GoldMarket.move(q)).font(ZenFont.number(10))
                            .foregroundStyle(q.changePaise >= 0 ? Color.zen.scoreGain : Color.zen.scoreDeduct)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            // This week as seven marigolds: one for each good day, today lit, a ring where there's no data.
            WeekMarigolds(week: week)
            Text("\(min(week.goodDays, 4)) of 4 good days this week").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
            Spacer(minLength: 0)
            Button(GoldCopy.openGold) { open() }.buttonStyle(ZenLinkButtonStyle())
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color.zen.accentReward.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .task { market.start() }
    }
}

/// Monday to Sunday as marigolds, with the day's initial under each. Reads at any card height.
struct WeekMarigolds: View {
    let week: WeekProgress
    private let initials = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: ZenSpace.s2) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Marigold(state: state(i), lit: i == week.todayIndex)
                        .frame(width: 26, height: 26)
                    Text(initials[i]).font(ZenFont.number(9.5))
                        .foregroundStyle(i == week.todayIndex ? Color.zen.textHeading : Color.zen.textCaption)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(week.statusLine)")
    }

    private func state(_ i: Int) -> Marigold.State {
        if let today = week.todayIndex, i > today { return .future }
        guard let score = week.days[i] else { return .noData }
        return score.isGoodDay ? .good : .under
    }
}
