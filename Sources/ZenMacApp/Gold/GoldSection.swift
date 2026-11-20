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
    static let invest = "Invest gold"
    static let toranTitle = "This month, as a garland"
    static let toranLine = "A marigold for every good day. A won week ends in a tassel."
    static let ledger = "Orders"
    static let how = ["Win the week: four days above 6.0", "Gold opens till Sunday, and all next week", "Buy 1 to 10 units of GOLDBEES through Kite"]
    static let glanceOpen = "Gold is open this week"
    static let openGold = "Open Zen Gold"
}

/// Zen Gold: the gold set aside, the live price and the week's gate on one ink card with the page's
/// one primary button (Invest gold), the month as a marigold toran, and the orders so far.
struct GoldSection: View {
    @Environment(AppModel.self) private var model
    @State private var investing = false

    var body: some View {
        let gate = model.goldGate
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack(alignment: .bottom) {
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
                    Spacer()
                    ZenoView(gate.isOpen ? .proud : .curious).frame(width: 132)
                }
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
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $investing) { InvestSheet(gate: gate) }
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
                    HStack {
                        GoldCoin().frame(width: 22, height: 22)
                        Text("Week of \(order.week.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        Spacer()
                        Text("\(order.units) unit\(order.units == 1 ? "" : "s")").font(ZenFont.number(13)).foregroundStyle(Color.zen.textHeading)
                        Text(order.totalPaise.map(Rupees.text) ?? "—").font(ZenFont.number(13)).foregroundStyle(Color.zen.textCaption)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.zen.borderHairline).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow("How it works")
            ForEach(Array(GoldCopy.how.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Text("0\(i + 1)").font(ZenFont.number(12)).foregroundStyle(Color.zen.accentRewardText)
                    Text(step).font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.5)))
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

    var body: some View {
        let week = (model.snapshot ?? FakeSnapshot.value).week
        let ledger = model.goldLedger
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GoldCopy.setAside.uppercased()).font(ZenFont.number(10.5)).tracking(1).foregroundStyle(Color(hex: 0xA4A9A0))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(ledger.units)").font(ZenFont.number(52)).foregroundStyle(Color(hex: 0xFFC800))
                        Text("units of gold").font(ZenFont.text(15, .semibold)).foregroundStyle(Color(hex: 0xF2F3EE))
                    }
                    Text("across \(ledger.weeks) won weeks").font(ZenFont.text(12.5)).foregroundStyle(Color(hex: 0x9DA298))
                }
                Spacer()
                GoldCoin().frame(width: 58, height: 58)
                    .shadow(color: Color(hex: 0xFFC800, alpha: 0.35), radius: 16)
            }
            HStack(spacing: ZenSpace.s2) {
                Circle().fill(model.goldQuote == nil ? Color(hex: 0x858A81) : Color(hex: 0x5BDF62)).frame(width: 7, height: 7)
                Text(GoldCopy.ticker).font(ZenFont.number(11)).foregroundStyle(Color(hex: 0xC9CCC4))
                Spacer()
                if let q = model.goldQuote {
                    Text(Rupees.text(paise: q.lastPaise)).font(ZenFont.number(13)).foregroundStyle(Color(hex: 0xF2F3EE))
                } else {
                    Text(GoldCopy.waitingPrice).font(ZenFont.text(12)).foregroundStyle(Color(hex: 0x9DA298))
                }
            }
            .padding(.horizontal, ZenSpace.s3).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
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
            .accessibilityHint(gate.isOpen ? "Choose how many units to buy, then authorise in Kite" : gate.line)
        }
        .padding(ZenSpace.s5)
        .background(InkTable())
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color(hex: 0xFFC800, alpha: 0.22), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
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

    var body: some View {
        let quote = model.goldQuote
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack {
                Eyebrow(reviewing ? "02 · Review" : "01 · How much", color: Color.zen.accentRewardText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Color.zen.textCaption)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }
            Text(reviewing ? "Review your order" : "Units of GOLDBEES this week").zenType(.title).foregroundStyle(Color.zen.textHeading)
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
            } else if let q = quote {
                LabeledContent("Units", value: "\(units)")
                LabeledContent("Price", value: Rupees.text(paise: q.lastPaise))
                LabeledContent("Total", value: Rupees.text(paise: q.lastPaise * units))
                Text("Kite opens in your browser to authorise. One order a week; a retry replaces it.")
                    .zenType(.caption).foregroundStyle(Color.zen.textCaption)
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
        .frame(width: 440)
    }
}

/// Lets a button pick its style at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Zen Gold at a glance, for Today: the gate, this week's four, and a way in.
struct GoldGlanceCard: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        let gate = model.goldGate
        let week = (model.snapshot ?? FakeSnapshot.value).week
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                GoldCoin().frame(width: 34, height: 34)
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
            }
            HStack(spacing: ZenSpace.s2) {
                CellRow((0..<4).map { $0 < week.goodDays ? .reward : .empty }, size: 12)
                Text("\(min(week.goodDays, 4)) of 4 this week").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
            }
            // This month's garland: a marigold for each good day, a tassel for each won week.
            Toran(weeks: model.streak?.weeks ?? [])
                .frame(maxWidth: 300, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            Button(GoldCopy.openGold) { open() }.buttonStyle(ZenLinkButtonStyle())
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color.zen.accentReward.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
