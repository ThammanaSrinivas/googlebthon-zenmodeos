import SwiftUI
import AppKit
import Albeit
import ZenAPI

/// A friend in a Zen circle, as the circle sees them: a first name, the Zen Score and the weekly
/// streak. Never apps, minutes or when they were on; an iPhone seat is a score and nothing else.
struct Buddy: Identifiable, Equatable {
    enum Device: String { case iPhone, android, mac }

    let id: String
    let name: String
    let isYou: Bool
    /// The week's average so far, in tenths.
    let weekTenths: Int
    /// Today's score so far; nil when the day isn't counting yet.
    let todayTenths: Int?
    let streak: Int
    /// Monday first; nil for a day with no data, missing entries are days to come.
    let week: [Int?]
    let device: Device
    /// Reactions they've had today.
    let received: Int

    var goodDays: Int { week.compactMap { $0 }.filter { $0 > ZenScore.goodDayThresholdTenths }.count }

    /// The week in words: won as soon as the 4th good day lands, never "5 of 4".
    var weekLine: String { goodDays >= 4 ? "Week won" : "\(goodDays) of 4 good days" }

    /// Zeno's face for this seat: proud on a long streak, happy on a great day, sleepy when the day
    /// hasn't started counting. Never sad: a low day is information, not a punishment.
    var feeling: ZenoFeeling {
        guard let today = todayTenths else { return .sleepy }
        if streak >= 10 && today > 60 { return .proud }
        if today >= 80 { return .happy }
        if today > 60 { return .pleasant }
        return .calm
    }

    func score(_ period: BuddyPeriod) -> Int? { period == .today ? todayTenths : weekTenths }

    /// The seat's horizon seed, the same on every launch (Swift's hashValue isn't).
    var seed: UInt64 { id.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 } }
}

enum BuddyPeriod: String, CaseIterable { case today, week }

/// The four reactions, four a day in all (Flow 06).
enum Reaction: String, CaseIterable, Identifiable {
    case love = "Love", melt = "Melt", cheer = "Cheer", fire = "Fire"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .love: "heart.fill"
        case .melt: "drop.fill"
        case .cheer: "hands.clap.fill"
        case .fire: "flame.fill"
        }
    }
    var hue: Color {
        switch self {
        case .love: Color(hex: 0xFF5C7A)
        case .melt: Color(hex: 0x6FA8FF)
        case .cheer: Color(hex: 0xFFC800)
        case .fire: Color(hex: 0xFF6600)
        }
    }
    static let perDay = 4
}

enum BuddyDemo {
    static let circle: [Buddy] = [
        Buddy(id: "asha", name: "Asha", isYou: false, weekTenths: 78, todayTenths: 84, streak: 12, week: [79, 74, 82, 71, 84], device: .iPhone, received: 3),
        Buddy(id: "you", name: "You", isYou: true, weekTenths: 69, todayTenths: 81, streak: 9, week: [72, 58, 81, 54, 81], device: .mac, received: 2),
        Buddy(id: "ravi", name: "Ravi", isYou: false, weekTenths: 68, todayTenths: 62, streak: 4, week: [66, 71, 72, 70, 62], device: .android, received: 1),
        Buddy(id: "meera", name: "Meera", isYou: false, weekTenths: 64, todayTenths: nil, streak: 2, week: [61, 68, nil, 63, nil], device: .iPhone, received: 0),
        Buddy(id: "arjun", name: "Arjun", isYou: false, weekTenths: 57, todayTenths: 51, streak: 0, week: [55, 62, 49, 66, 51], device: .iPhone, received: 1),
    ]
    static let seats = 7
    static let feed: [(feeling: ZenoFeeling, line: String)] = [
        (.proud, "Asha won the week on Thursday. That's 12 in a row."),
        (.happy, "Ravi sent you Cheer for Wednesday's good day."),
        (.pleasant, "You're one good day from winning the week."),
        (.sleepy, "Meera's day isn't counting yet. Her seat waits."),
    ]
}

/// Zen Bros: the friends' circle, ranked by Zen Score, with streaks and reactions.
struct BuddiesTab: View {
    @State private var period: BuddyPeriod = .week
    @State private var reactionsLeft = Reaction.perDay
    @State private var sent: [String: Reaction] = [:]
    @State private var toast: String?
    @State private var width: CGFloat = 1000

    /// Five seats sit in one row when there's room, else three to a row.
    private var columns: Int { width >= 840 ? 5 : 3 }

    private var ranked: [Buddy] {
        BuddyDemo.circle.sorted { ($0.score(period) ?? -1) > ($1.score(period) ?? -1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s6) {
            header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZenSpace.s3, alignment: .top), count: columns),
                      alignment: .leading, spacing: ZenSpace.s3) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { i, buddy in
                    BuddyCard(buddy: buddy, rank: i + 1, period: period, sent: sent[buddy.id], canReact: reactionsLeft > 0) { reaction in
                        react(reaction, to: buddy)
                    }
                }
            }
            .animation(ZenMotion.container, value: period)
            HStack(alignment: .top, spacing: ZenSpace.s5) {
                feed.frame(maxHeight: .infinity)
                privacyNote.frame(width: 320).frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .id("feed")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // MARK: The circle's header

    private var header: some View {
        HStack(alignment: .center, spacing: ZenSpace.s6) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow("\(CircleCopy.inviteCode) · \(CircleCopy.brosCode)")
                    DemoTag()
                }
                Text(CircleCopy.brosName).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                HStack(spacing: ZenSpace.s3) {
                    faces
                    Text("\(BuddyDemo.circle.count) of \(BuddyDemo.seats) seats · \(CircleCopy.ranksReset)")
                        .font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                }
            }
            Spacer(minLength: ZenSpace.s4)
            VStack(alignment: .trailing, spacing: ZenSpace.s3) {
                HStack(spacing: ZenSpace.s3) {
                    periodSwitch
                    Button { copyInvite() } label: { Label(CircleCopy.invite, systemImage: "person.badge.plus") }
                        .buttonStyle(ZenPrimaryButtonStyle())
                }
                HStack(spacing: 6) {
                    ForEach(0..<Reaction.perDay, id: \.self) { i in
                        Circle().fill(i < reactionsLeft ? Color(hex: 0xFF5C7A) : Color.zen.borderOutline.opacity(0.6)).frame(width: 7, height: 7)
                    }
                    Text("\(reactionsLeft) \(CircleCopy.reactionsLeft)").font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(reactionsLeft) reactions left today")
                if let toast {
                    Text(toast).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textBrand)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
        }
        .padding(ZenSpace.s6)
        .glassCard(radius: ZenRadius.xxxl)
        .animation(ZenMotion.calm(ZenMotion.t2), value: toast)
    }

    /// Everyone's Zeno, overlapping, like faces at a table.
    private var faces: some View {
        HStack(spacing: -10) {
            ForEach(BuddyDemo.circle) { b in
                ZenoStill(b.feeling)
                    .frame(width: 44)
                    .offset(y: 6)
                    .frame(width: 36, height: 36)
                    .background(Color.zen.surfaceTint)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(b.isYou ? Color.zen.accentReward : Color.zen.surfaceRaised, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    private var periodSwitch: some View {
        HStack(spacing: 2) {
            ForEach(BuddyPeriod.allCases, id: \.self) { p in
                let on = p == period
                Button { period = p } label: {
                    Text(p == .today ? CircleCopy.daily : CircleCopy.weekly)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 30)
                }
                .buttonStyle(SegmentStyle(on: on))
                .focusEffectDisabled()
                .accessibilityLabel(p == .today ? "Rank by today" : "Rank by this week")
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.zen.surfaceSunk))
    }

    // MARK: The week, as a feed

    private var feed: some View {
        CirclePanel(title: CircleCopy.feedTitle) {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                ForEach(Array(BuddyDemo.feed.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: ZenSpace.s3) {
                        ZenoStill(item.feeling).frame(width: 34)
                        Text(item.line).font(ZenFont.text(14)).foregroundStyle(Color.zen.textHeading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                Text(CircleCopy.scoresOnly).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            Text(CircleCopy.brosPrivacy).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).strokeBorder(Color.zen.brandFill.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func react(_ reaction: Reaction, to buddy: Buddy) {
        guard reactionsLeft > 0, sent[buddy.id] == nil else { return }
        reactionsLeft -= 1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.52)) { sent[buddy.id] = reaction }
        flash("Sent \(reaction.rawValue) to \(buddy.name)")
    }

    private func copyInvite() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://zenmodeos.com/c/\(CircleCopy.brosCode)", forType: .string)
        flash(CircleCopy.inviteCopied)
    }

    private func flash(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { toast = nil }
        }
    }
}

/// One seat: a horizon in their hue with Zeno on it, the rank, the score, the week as cells, the
/// streak, and (for anyone but you) the four reactions.
private struct BuddyCard: View {
    let buddy: Buddy
    let rank: Int
    let period: BuddyPeriod
    let sent: Reaction?
    let canReact: Bool
    let react: (Reaction) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let score = buddy.score(period)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                HorizonStrip(tone: buddy.feeling == .proud ? .amber : .zen, seed: buddy.seed)
                ZenoStill(buddy.feeling).frame(width: 104).offset(y: 18)
            }
            .frame(height: 112)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text("#\(rank)").font(ZenFont.number(11)).foregroundStyle(Color(hex: 0x12160F))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background(Capsule().fill(.white.opacity(0.85)))
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if let sent {
                        Image(systemName: sent.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(sent.hue))
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("You sent \(sent.rawValue)")
                    }
                    if buddy.received > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.system(size: 9, weight: .bold))
                            Text("\(buddy.received)").font(ZenFont.number(11))
                        }
                        .foregroundStyle(Color(hex: 0xB0213F))
                        .padding(.horizontal, 7).frame(height: 20)
                        .background(Capsule().fill(.white.opacity(0.85)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(buddy.received) reactions today")
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(buddy.name).font(ZenFont.brand(20)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    // The weekly streak; it drops "wk" before the name would ever truncate.
                    ViewThatFits(in: .horizontal) {
                        streakChip("◆ \(buddy.streak) wk")
                        streakChip("◆ \(buddy.streak)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(buddy.streak)-week streak")
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(score.map { ZenScore(tenths: $0).text } ?? "–").font(ZenFont.number(30))
                        .foregroundStyle(score.map { $0 > ZenScore.goodDayThresholdTenths } == true ? Color.zen.textHeading : Color.zen.textCaption)
                        .fixedSize()
                    Text(period == .today ? "today" : "this week").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    CellRow((0..<7).map { i in
                        guard i < buddy.week.count, let t = buddy.week[i] else { return .empty }
                        return t > ZenScore.goodDayThresholdTenths ? .on : .empty
                    }, size: 10)
                    .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        if buddy.goodDays >= 4 {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                        }
                        Text(buddy.weekLine).font(ZenFont.text(12, buddy.goodDays >= 4 ? .semibold : .medium)).lineLimit(1)
                    }
                    .foregroundStyle(buddy.goodDays >= 4 ? Color.zen.textBrand : Color.zen.textBody)
                }
                Text(buddy.isYou ? CircleCopy.youSeat : (buddy.device == .iPhone ? CircleCopy.iPhoneSeat : "Counted on their \(buddy.device == .mac ? "Mac" : "phone")."))
                    .font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 32, alignment: .topLeading)
                if buddy.isYou {
                    // Your seat has no buttons: what's come your way today instead.
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xE0445F))
                        Text("\(buddy.received) for you today").font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textBody)
                    }
                    .frame(height: 30, alignment: .leading)
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Reaction.allCases) { r in
                            Button { react(r) } label: {
                                Image(systemName: r.symbol).font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(ReactionStyle(hue: r.hue, chosen: sent == r))
                            .focusEffectDisabled()
                            .disabled(sent != nil || !canReact)
                            .opacity(sent != nil && sent != r ? 0.35 : 1)
                            .help("\(r.rawValue) \(buddy.name)")
                            .accessibilityLabel("Send \(r.rawValue) to \(buddy.name)")
                        }
                    }
                    .frame(height: 30, alignment: .leading)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, ZenSpace.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zen.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous)
            .strokeBorder(buddy.isYou ? Color.zen.accentReward : Color.zen.borderHairline, lineWidth: buddy.isYou ? 1.5 : 1))
        .modifier(ZenLift())
        .offset(y: hovering && !reduceMotion ? -3 : 0)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t2), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(rank). \(buddy.name), Zen Score \(score.map { ZenScore(tenths: $0).text } ?? "not counting yet"), \(buddy.streak)-week streak, \(buddy.weekLine)")
    }
}

extension BuddyCard {
    fileprivate func streakChip(_ text: String) -> some View {
        Text(text).font(ZenFont.number(10.5)).foregroundStyle(Color.zen.accentRewardText)
            .padding(.horizontal, 6).frame(height: 20)
            .background(Capsule().fill(Color.zen.accentRewardTint))
            .fixedSize()
    }
}

/// A reaction: a tinted circle that deepens on hover, fills when sent, rings for the keyboard.
private struct ReactionStyle: ButtonStyle {
    let hue: Color
    let chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        ReactionBody(configuration: configuration, hue: hue, chosen: chosen)
    }

    private struct ReactionBody: View {
        let configuration: Configuration
        let hue: Color
        let chosen: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(chosen ? .white : hue)
                .frame(width: 30, height: 30)
                .background(Circle().fill(chosen ? hue : hue.opacity(hovering && enabled ? 0.26 : 0.13)))
                .overlay { if focused { Circle().strokeBorder(Color.zen.textBrand, lineWidth: 2).padding(-3) } }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : (hovering && enabled && !reduceMotion ? 1.06 : 1))
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: hovering)
                .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
        }
    }
}

/// One option in a small segmented pill: raised when on, a wash on hover, a ring for the keyboard.
struct SegmentStyle: ButtonStyle {
    let on: Bool
    var size: CGFloat = 12.5

    func makeBody(configuration: Configuration) -> some View {
        SegmentBody(configuration: configuration, on: on, size: size)
    }

    private struct SegmentBody: View {
        let configuration: Configuration
        let on: Bool
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(ZenFont.text(size, on ? .semibold : .medium))
                .foregroundStyle(on || hovering ? Color.zen.textHeading : Color.zen.textBody)
                .background {
                    if on { Capsule().fill(Color.zen.surfaceRaised).modifier(ZenLift()) }
                    else if hovering { Capsule().fill(Color.zen.surfaceRaised.opacity(0.5)) }
                }
                .overlay { if focused { Capsule().strokeBorder(Color.zen.textBrand, lineWidth: 2) } }
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}
