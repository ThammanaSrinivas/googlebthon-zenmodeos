import SwiftUI
import Albeit
import ZenAPI

enum GoldCopy {
    static let eyebrow = "Zen Gold"
    static let titleTop = "Good weeks"
    static let titleBottom = "turn to gold."
    static let lede = "Win the week with four good days and Zen Gold opens. It stays open until Sunday midnight, and for the whole week after."
    static let closed = "One more good day opens Gold"
    static let open = "Gold is open until Sunday"
    static let invest = "Invest in gold"
    static let priceSource = "GOLDBEES on the NSE, priced live. Your order goes through at the price you see."
    static let priceWaiting = "The live price arrives through your account once you're signed in. No made-up prices, ever."
    static let ledger = "Weeks that turned to gold"
}

/// Zen Gold: the won-week gate, the weeks already won as coins, and the investing card, which
/// opens on a won week and only ever shows a real, live price.
struct GoldSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = (model.snapshot ?? FakeSnapshot.value).week
        let won = week.isWon
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: ZenSpace.s2) {
                        Eyebrow(GoldCopy.eyebrow, color: Color.zen.accentRewardText)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(GoldCopy.titleTop).foregroundStyle(Color.zen.textHeading)
                            Text(GoldCopy.titleBottom)
                                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xD9A400), Color(hex: 0x7A5A00)], startPoint: .leading, endPoint: .trailing))
                        }
                        .zenType(.display)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        Text(GoldCopy.lede).zenType(.body).foregroundStyle(Color.zen.textBody)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                    Spacer()
                    ZenoView(won ? .proud : .curious).frame(width: 150)
                }
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    gate(week)
                    investCard(open: won)
                        .frame(width: 400)
                }
                ledger
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }

    private func gate(_ week: WeekProgress) -> some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Eyebrow("This week")
                Spacer()
                Text(week.isWon ? GoldCopy.open : GoldCopy.closed).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.accentRewardText)
            }
            HStack(spacing: ZenSpace.s2) {
                ForEach(0..<7, id: \.self) { i in
                    DayTile(name: names[i], score: week.days[i], isToday: i == week.todayIndex,
                            isWinning: week.winningDayIndex == i, isFuture: week.todayIndex.map { i > $0 } ?? false)
                }
            }
            HStack(spacing: ZenSpace.s3) {
                CellRow((0..<4).map { $0 < week.goodDays ? .reward : .empty }, size: 14)
                Text("\(min(week.goodDays, 4)) of 4 good days").font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            Text("A good day is a Zen Score above 6.0, across all your screens.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private func investCard(open: Bool) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                GoldCoin().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GoldCopy.invest).zenType(.title).foregroundStyle(Color(hex: 0xF2F3EE))
                    Text(open ? "Open now" : "Opens on a won week").font(ZenFont.number(10.5)).tracking(0.6)
                        .foregroundStyle(open ? Color(hex: 0xFFC800) : Color(hex: 0xA4A9A0))
                }
            }
            Text(GoldCopy.priceSource).font(ZenFont.text(13.5)).foregroundStyle(Color(hex: 0xC9CCC4))
                .fixedSize(horizontal: false, vertical: true)
            // TODO(buildathon): the live GOLDBEES price through ZenCorePrivate (network stays out of this repo).
            Text(GoldCopy.priceWaiting).font(ZenFont.text(12)).foregroundStyle(Color(hex: 0x9DA298))
                .fixedSize(horizontal: false, vertical: true)
            Button(open ? "Invest" : "Locked until the week is won") {}
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(true)
                .environment(\.colorScheme, .light)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InkTable())
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color(hex: 0xFFC800, alpha: 0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
    }

    private var ledger: some View {
        let weeks = model.streak?.weeks.filter { !$0.isCurrent } ?? []
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Text(GoldCopy.ledger).zenType(.title).foregroundStyle(Color.zen.textHeading)
                DemoTag("Demo history")
                Spacer()
                Text("\(weeks.filter(\.isWon).count) of \(weeks.count) weeks").font(ZenFont.number(12)).foregroundStyle(Color.zen.textCaption)
            }
            HStack(alignment: .bottom, spacing: ZenSpace.s3) {
                ForEach(weeks) { week in
                    VStack(spacing: ZenSpace.s2) {
                        if week.isWon {
                            GoldCoin().frame(width: 34, height: 34)
                        } else {
                            Circle().strokeBorder(Color.zen.borderOutline, lineWidth: 1.5).frame(width: 34, height: 34)
                        }
                        Text(week.id.formatted(.dateTime.day().month(.abbreviated))).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week of \(week.id.formatted(.dateTime.day().month(.wide))): \(week.isWon ? "won" : "not won")")
                }
            }
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
    }
}

/// The reward glyph: an amber coin with an ink ring and a star.
struct GoldCoin: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xFFE59A), Color(hex: 0xFFC800), Color(hex: 0xE2A400)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: s * 0.6))
                Circle().strokeBorder(Color(hex: 0x1E1E1E), lineWidth: s * 0.07).padding(s * 0.18)
                Image(systemName: "star.fill").font(.system(size: s * 0.26, weight: .bold)).foregroundStyle(Color(hex: 0xFFF4D9))
                    .shadow(color: Color(hex: 0x1E1E1E), radius: 0, x: 0.6, y: 0.6)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
