import SwiftUI
import CoreImage.CIFilterBuiltins
import Albeit
import ZenAPI

// MARK: - Story

struct StoryStage: View {
    let index: Int
    @Binding var feelingIndex: Int
    let model: AppModel

    var body: some View {
        Group {
            switch index {
            case 0: ZenoStage(feelingIndex: $feelingIndex, model: model)
            case 1: OneScoreStage(snapshot: model.snapshot ?? FakeSnapshot.value)
            default: GoldStage()
            }
        }
        .id(index)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
        .animation(ZenMotion.container, value: index)
    }
}

/// Demo numbers for the story when no snapshot has loaded yet.
enum FakeSnapshot {
    static let value = ScoreSnapshot(
        score: ZenScore(tenths: 81),
        week: WeekProgress(days: [ZenScore(tenths: 72), ZenScore(tenths: 58), ZenScore(tenths: 81), ZenScore(tenths: 54), ZenScore(tenths: 81), nil, nil],
                           todayIndex: 4, streakBefore: 9),
        devices: [], updatedAt: Date())
}

private let storyFeelings: [ZenoFeeling] = [.happy, .pleasant, .curious, .proud, .sleepy]

/// Card 1: a hero notch with Zeno trying on feelings, in step with the real notch.
// TODO(imagery): a generated (Imagen) MacBook-at-dusk scene could sit behind this stage, lit in the feeling's hue.
private struct ZenoStage: View {
    @Binding var feelingIndex: Int
    let model: AppModel

    var body: some View {
        let feeling = storyFeelings[feelingIndex % storyFeelings.count]
        let line = Copy.feelingLines[feelingIndex % storyFeelings.count]
        VStack(spacing: ZenSpace.s5) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 56, bottomTrailingRadius: 56, style: .continuous)
                    .fill(Color.zen.island)
                    .overlay {
                        RadialGradient(colors: [feeling.skin.glow.opacity(0.4), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: 220)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 56, bottomTrailingRadius: 56, style: .continuous))
                            .animation(ZenMotion.calm(ZenMotion.t3), value: feeling)
                    }
                ZenoView(feeling)
                    .frame(width: 210)
                    .padding(.top, 34)
            }
            .frame(width: 440, height: 240)
            .shadow(color: .black.opacity(0.28), radius: 30, y: 18)

            VStack(spacing: ZenSpace.s2) {
                Text(line.kicker.uppercased())
                    .font(ZenFont.number(10.5)).tracking(1.1)
                    .foregroundStyle(feeling.skin.kickerOnLight)
                Text(line.line)
                    .font(ZenFont.text(19, .semibold)).tracking(-0.3)
                    .foregroundStyle(Color.zen.textHeading)
            }
            .id(feelingIndex)
            .transition(.opacity.combined(with: .offset(y: 6)))

            HStack(spacing: ZenSpace.s2) {
                ForEach(storyFeelings.indices, id: \.self) { i in
                    let f = storyFeelings[i]
                    let on = i == feelingIndex % storyFeelings.count
                    Button {
                        feelingIndex = i
                        model.showFeeling(i)
                    } label: {
                        Text(f.rawValue.capitalized)
                            .font(ZenFont.text(13, .semibold))
                            .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textHeading)
                            .padding(.horizontal, ZenSpace.s3 + 2)
                            .frame(height: 32)
                            .background { if on { Capsule().fill(Color.zen.actionPrimary) } }
                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show Zeno \(f.rawValue)")
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            Text(Copy.Story.feelingsHint).zenType(.caption).foregroundStyle(Color.zen.textCaption)

            HStack(spacing: ZenSpace.s3) {
                IslandPill(feeling: feeling, score: "8.1")
                Text(Copy.Story.sameOnIsland).zenType(.caption).foregroundStyle(Color.zen.textBody)
            }
            .padding(.top, ZenSpace.s2)
        }
        .animation(ZenMotion.container, value: feelingIndex)
        .task {
            model.showFeeling(feelingIndex)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.6))
                if Task.isCancelled { break }
                feelingIndex = (feelingIndex + 1) % storyFeelings.count
                model.showFeeling(feelingIndex)
            }
        }
    }
}

/// The iPhone's compact Dynamic Island: Zeno on the left, the score on the right.
struct IslandPill: View {
    let feeling: ZenoFeeling
    let score: String

    var body: some View {
        HStack(spacing: 8) {
            ZenoView(feeling).frame(width: 34)
            Spacer(minLength: 0)
            Text(score).font(ZenFont.number(14)).foregroundStyle(Color.zen.brandSoft)
        }
        .padding(.leading, 6).padding(.trailing, 14)
        .frame(width: 136, height: 38)
        .background(Capsule().fill(Color.zen.island))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dynamic Island: Zen Score \(score)")
    }
}

/// Card 2: one number on every screen, the devices it came from, and the week in cells.
struct OneScoreStage: View {
    let snapshot: ScoreSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack {
                Eyebrow("Zen Score · today")
                Spacer()
                DemoTag()
            }
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                ScoreText(snapshot.score.text, size: 96)
                Text("/10").font(ZenFont.number(18)).foregroundStyle(Color.zen.textCaption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zen Score \(snapshot.score.text) out of 10")
            Text("Same on Kamal's iPhone and this Mac · synced 4 s ago")
                .zenType(.body).foregroundStyle(Color.zen.textBody)

            VStack(spacing: ZenSpace.s2) {
                DeviceRow(symbol: "iphone", name: "Kamal's iPhone", detail: "Counted on the phone · score only")
                DeviceRow(symbol: "laptopcomputer", name: "This Mac", detail: "38 m distracting · 4 pull-backs")
            }

            WeekCells(week: snapshot.week)
            Text(Copy.Story.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s8)
        .frame(width: 500)
        .glassCard(radius: ZenRadius.xxxl)
    }
}

struct DeviceRow: View {
    let symbol: String, name: String, detail: String

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.zen.textHeading)
                .frame(width: 22)
            Text(name).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            Spacer()
            Text(detail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(.horizontal, ZenSpace.s4).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.55)))
        .accessibilityElement(children: .combine)
    }
}

/// Seven columns of ten cells: one cell per point. Good days are green, a day with no data is an outline.
struct WeekCells: View {
    let week: WeekProgress
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(alignment: .bottom, spacing: ZenSpace.s4) {
            ForEach(0..<7, id: \.self) { d in
                let day = week.days[d]
                VStack(spacing: 3) {
                    ForEach((0..<10).reversed(), id: \.self) { row in
                        let filled = day.map { row < Int(($0.tenths + 5) / 10) } ?? false
                        RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                            .fill(filled ? (day!.isGoodDay ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.22)) : Color.zen.textHeading.opacity(0.04))
                            .overlay {
                                if row == 6 {
                                    RoundedRectangle(cornerRadius: ZenRadius.cell).strokeBorder(Color.zen.textBrand.opacity(0.5), lineWidth: 1)
                                }
                            }
                            .frame(width: 12, height: 8)
                    }
                    Text(labels[d])
                        .font(ZenFont.number(10))
                        .foregroundStyle(d == week.todayIndex ? Color.zen.textHeading : Color.zen.textCaption)
                        .padding(.top, 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("6.0").font(ZenFont.number(11)).foregroundStyle(Color.zen.textBrand)
                Text("a good day is above").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                Spacer()
                Text(week.statusLine).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 118)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(week.statusLine)")
    }
}

/// Card 3: the week fills, the fourth good day lands, gold opens, and Gemini says one line.
// TODO(imagery): a generated gold-toran texture for the won-week moment.
private struct GoldStage: View {
    @State private var landed = 0
    @State private var typed = 0
    private let scores: [Int?] = [72, 58, 81, 66, 74, nil, nil]
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let good = scores.prefix(landed).compactMap { $0 }.filter { $0 > 60 }.count
        let won = good >= 4
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Eyebrow(won ? "Week won · 10-week streak" : "\(good) of 4 good days", color: won ? Color.zen.accentRewardText : Color.zen.textBrand)
                    Text(won ? "Zen Gold is open." : "One more wins the week.")
                        .zenType(.title).foregroundStyle(Color.zen.textHeading)
                        .contentTransition(.opacity)
                }
                Spacer()
                ZenoView(won ? .proud : .curious).frame(width: 92)
            }
            HStack(spacing: ZenSpace.s2) {
                ForEach(0..<7, id: \.self) { i in
                    dayTile(i, landed: i < landed, winning: won && i == 4)
                }
            }
            HStack(alignment: .top, spacing: ZenSpace.s3) {
                ZStack {
                    Circle().fill(Color.zen.surfaceRaised)
                    Image(systemName: "sparkle").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x4F8DF7), Color(hex: 0xA77BF3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(Copy.Story.geminiLine.prefix(typed)))
                        .font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Copy.Story.geminiCaption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
            .padding(ZenSpace.s4)
            .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.lg))
            .opacity(won ? 1 : 0.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zeno: \(Copy.Story.geminiLine)")
        }
        .padding(ZenSpace.s8)
        .frame(width: 520)
        .glassCard(radius: ZenRadius.xxxl, tint: won ? Color.zen.accentReward.opacity(0.08) : nil)
        .animation(ZenMotion.container, value: landed)
        .task {
            for i in 1...5 {
                try? await Task.sleep(for: .milliseconds(i == 5 ? 900 : 420))
                landed = i
            }
            try? await Task.sleep(for: .milliseconds(700))
            for i in 0...Copy.Story.geminiLine.count {
                typed = i
                try? await Task.sleep(for: .milliseconds(26))
            }
        }
    }

    private func dayTile(_ i: Int, landed: Bool, winning: Bool) -> some View {
        let score = landed ? scores[i] : nil
        let good = (score ?? 0) > 60
        return VStack(spacing: 4) {
            Text(names[i]).font(ZenFont.number(9.5)).foregroundStyle(winning ? Color.zen.accentRewardText : Color.zen.textCaption)
            Text(score.map { "\($0 / 10).\($0 % 10)" } ?? "–")
                .font(ZenFont.number(17)).foregroundStyle(Color.zen.textHeading)
        }
        .frame(maxWidth: .infinity).frame(height: 62)
        .background {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .fill(winning ? Color.zen.accentRewardTint : (good ? Color.zen.surfaceTint : Color.zen.surfaceSunk.opacity(0.6)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .strokeBorder(winning ? Color.zen.accentReward : (score == nil ? Color.zen.borderOutline : .clear), lineWidth: 1.5)
        }
        .scaleEffect(winning ? 1.06 : 1)
    }
}

// MARK: - Make it yours: a live preview of the answers

struct ProfileStage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.profile
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack {
                Eyebrow("Your ZenMode OS")
                Spacer()
                Text(model.step == .seat ? "1 of 3" : model.step == .uses ? "2 of 3" : "3 of 3")
                    .font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
            }
            row("Seat") {
                if case .joined(let c) = model.codeState {
                    Text("\(c.preview.name) · \(c.preview.organisation)")
                } else if case .found(let c) = model.codeState {
                    Text("\(c.name) · \(c.organisation)")
                } else {
                    Text(Copy.Seat.option(p.seat).title)
                }
            }
            row("For") {
                Text(p.uses.isEmpty ? "–" : Profile.Use.allCases.filter(p.uses.contains).map(Copy.Uses.label).joined(separator: " · "))
            }
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack {
                    Text("Zeno is quiet").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                    Text(p.quiet.summary).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                }
                QuietStrip(quiet: p.quiet)
            }
            if p.seat != .personal {
                CohortPreviewCard(state: model.codeState)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(ZenSpace.s8)
        .frame(width: 480)
        .glassCard(radius: ZenRadius.xxxl)
        // Zeno perches on the card and reacts to each answer.
        .overlay(alignment: .topTrailing) {
            ZenoView(perchFeeling)
                .frame(width: 92)
                .shadow(color: perchFeeling.skin.glow.opacity(0.45), radius: 16, y: 6)
                .offset(x: -28, y: -58)
                .animation(ZenMotion.zenoHappy, value: perchFeeling)
                .accessibilityHidden(true)
        }
        .padding(.top, 58)
        .animation(ZenMotion.container, value: p)
        .animation(ZenMotion.container, value: model.codeState)
    }

    private var perchFeeling: ZenoFeeling {
        switch model.step {
        case .uses: model.profile.uses.isEmpty ? .curious : .happy
        case .quiet: .sleepy
        default: model.profile.seat == .personal ? .pleasant : .curious
        }
    }

    private func row(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack {
            Text(label).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            Spacer()
            value().font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, ZenSpace.s1)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.zen.borderHairline).frame(height: 1).offset(y: ZenSpace.s2) }
    }
}

/// 24 cells, one per hour of a weekday: dusk where Zeno rests, green where it may speak.
struct QuietStrip: View {
    let quiet: QuietHours

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                        .fill(quiet.hourIsQuiet(h) ? Color(hex: 0x93A88F).opacity(0.55) : Color.zen.brandFill.opacity(0.85))
                        .frame(height: 14)
                }
            }
            HStack {
                ForEach(["12a", "6a", "12p", "6p", ""], id: \.self) { t in
                    Text(t).font(ZenFont.number(9.5)).foregroundStyle(Color.zen.textCaption)
                    if !t.isEmpty { Spacer() }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zeno is quiet: \(quiet.summary), and every night 10:30 pm to 7 am")
    }
}

/// The group, as a member sees it: seats as cells and one score, only for 5 or more.
private struct CohortPreviewCard: View {
    let state: AppModel.CodeState

    var body: some View {
        let preview: CohortPreview? = switch state {
        case .found(let p): p
        case .joined(let s): s.preview
        default: nil
        }
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Eyebrow(preview.map { "\($0.name) · \($0.memberCount) people" } ?? "Your group", color: Color.zen.textBrand)
                Spacer()
                if let preview, preview.memberCount >= CohortSummary.minimumGroupSize {
                    Text("7.4").font(ZenFont.number(22)).foregroundStyle(Color.zen.textHeading)
                        .accessibilityLabel("Group score 7.4")
                }
            }
            let seats = preview?.memberCount ?? 0
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 4), count: 16), alignment: .leading, spacing: 4) {
                ForEach(0..<max(seats, 16), id: \.self) { i in
                    RoundedRectangle(cornerRadius: ZenRadius.cell)
                        .fill(i < seats ? (i == 0 ? Color.zen.accentReward : Color.zen.brandFill.opacity(i % 3 == 0 ? 0.5 : 0.85)) : Color.zen.textHeading.opacity(0.05))
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityHidden(true)
            Text("One group score, never a name next to a number.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.7)))
    }
}

// MARK: - Let it count

/// This Mac's screen, lit: Zeno watching from the notch, the app in front right now, and how three
/// familiar apps count (an icon and words for each, never colour alone).
struct CountStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        let front = model.frontmost.current
        VStack(spacing: ZenSpace.s5) {
            ZStack(alignment: .top) {
                ScreenGlow(tilt: 0.1)
                VStack(spacing: ZenSpace.s3) {
                    Spacer().frame(height: 62)
                    HStack(spacing: 6) {
                        Circle().fill(Color.zen.brandSoft).frame(width: 7, height: 7)
                            .shadow(color: Color.zen.brandSoft, radius: breathe ? 6 : 1)
                            .scaleEffect(breathe ? 1.15 : 0.9)
                        Text(Copy.Count.nowInFront.uppercased()).font(ZenFont.number(9.5)).tracking(1.1)
                            .foregroundStyle(Color.zen.islandDetail)
                    }
                    Text(front?.name ?? "–")
                        .font(ZenFont.text(30, .semibold)).tracking(-0.6)
                        .foregroundStyle(Color.zen.islandText)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                    if let kind = front?.kind.rawValue {
                        Text(kind).font(ZenFont.text(12.5, .semibold))
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color.zen.brandSoft.opacity(0.16)))
                            .overlay(Capsule().strokeBorder(Color.zen.brandSoft.opacity(0.5), lineWidth: 1))
                            .foregroundStyle(Color.zen.brandSoft)
                    }
                    Text(model.accessibilityTrusted ? Copy.Count.titleNote : "Allow Accessibility to tell browser tabs apart.")
                        .font(ZenFont.text(12, .medium)).foregroundStyle(Color.zen.islandText.opacity(0.78))
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ZenSpace.s6)
                // The notch, with Zeno watching.
                ZStack {
                    UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous).fill(Color.zen.island)
                    ZenoView(.curious).frame(width: 40).offset(y: 2)
                }
                .frame(width: 150, height: 40)
            }
            .frame(width: 480, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x050605)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 30, y: 18)
            .shadow(color: Color.zen.brandSoft.opacity(0.18), radius: 40, y: 20)

            VStack(spacing: ZenSpace.s2) {
                example("hammer.fill", "Xcode", counts: false)
                example("doc.text.fill", "Docs in Chrome", counts: false)
                example("play.rectangle.fill", "YouTube in Chrome", counts: true)
            }
            .frame(width: 498)
        }
        .animation(ZenMotion.container, value: front)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement(children: .contain)
    }

    private func example(_ symbol: String, _ name: String, counts: Bool) -> some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.zen.textBody).frame(width: 22)
            Text(name).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            Spacer()
            Label(counts ? "Counts toward the day" : "Work · doesn't count",
                  systemImage: counts ? "minus.circle.fill" : "checkmark.circle.fill")
                .font(ZenFont.text(12.5, .medium))
                .foregroundStyle(counts ? Color.zen.scoreDeduct : Color.zen.textBrand)
        }
        .padding(.horizontal, ZenSpace.s4).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bring your day

struct PairStage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: ZenSpace.s5) {
            if !model.qrPairing {
                // The demo build: no code to scan, just who you are on every screen.
                ZenMark().fill(Color.zen.textHeading, style: FillStyle(eoFill: true)).frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                Text(Copy.Bring.signInCard).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .multilineTextAlignment(.center)
            } else if let pairing = model.pairing {
                QRCode(text: pairing.url.absoluteString)
                    .frame(width: 196, height: 196)
                    .padding(ZenSpace.s4)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.xxl, style: .continuous).fill(.white))
                    .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
                    .accessibilityLabel("QR code to pair your iPhone")
                Text(pairing.code.display)
                    .font(ZenFont.number(30)).tracking(4)
                    .foregroundStyle(Color.zen.textHeading)
                    .accessibilityLabel("Code \(pairing.code.value.map(String.init).joined(separator: " "))")
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = max(0, pairing.expiresAt.timeIntervalSince(tl.date))
                    CellRow(filled: Int((left / 30).rounded(.up)), of: 10, size: 9)
                }
                Text(Copy.Bring.rotates).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                if model.isDemo {
                    Button(Copy.Bring.simulate) { model.simulateApproval() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
            } else {
                ProgressView().accessibilityLabel("Making a pairing code")
            }
        }
        .padding(ZenSpace.s8)
        .frame(width: 420)
        .glassCard(radius: ZenRadius.xxxl)
    }
}

/// A real QR code for the pairing link, drawn with Core Image.
struct QRCode: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable()
        }
    }

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

