import SwiftUI
import Albeit
import ZenAPI

// MARK: - Words and mapping

/// How a Zen Card is labelled on Today.
enum ZenCardLabels {
    /// The language a card was spoken in, by name: "Tamil", "Hinglish", "English".
    static func language(_ tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespaces)
        if t.lowercased() == "hi-latn" { return "Hinglish" }
        if t.isEmpty || t == ZenCardDraft.unknownLanguage { return "Any language" }
        let base = String(t.split(separator: "-").first ?? Substring(t))
        return Locale(identifier: "en").localizedString(forLanguageCode: base) ?? t
    }

    static func mood(_ mood: ZenAPI.ZenCard.Mood) -> String { mood.rawValue.capitalized }

    /// Zeno's face for the card's mood.
    static func feeling(_ mood: ZenAPI.ZenCard.Mood) -> ZenoFeeling {
        switch mood {
        case .happy: .happy
        case .pleasant: .pleasant
        case .neutral: .calm
        case .tired: .sleepy
        case .sad: .sad
        }
    }

    /// The tilt of each card in the stack, back to front would read −6°, 3°, −2°; index 0 is the top.
    static let angles: [Double] = [-2, 3, -6, 5]
    /// Fanned on hover: the same leans, opened up.
    static let fanAngles: [Double] = [-1, 8, -10, 12]

    /// The stack's order when `front` is on top: front, then the ones after it, wrapping.
    static func order(count: Int, front: Int) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).map { (front + $0) % count }
    }

    /// Samples for the demo build, labelled as samples wherever they show.
    static func samples(now: Date = Date()) -> [ZenAPI.ZenCard] {
        let day: TimeInterval = 86_400
        return [
            ZenAPI.ZenCard(id: "sample-1", summary: "இன்று மதியம் நீண்ட நடை போனேன், போனைத் தொடவே இல்லை.", mood: .pleasant, language: "ta",
                    earnedBack: "A long walk", createdAt: now.addingTimeInterval(-day * 0.2), sharedAt: now.addingTimeInterval(-day * 0.1)),
            ZenAPI.ZenCard(id: "sample-2", summary: "Aaj subah focus solid tha. Shaam ko reels mein thoda kho gaya, par jaldi nikal aaya.",
                    mood: .happy, language: "hi-Latn", earnedBack: "Morning focus", drift: "Reels after 9", createdAt: now.addingTimeInterval(-day * 1.2)),
            ZenAPI.ZenCard(id: "sample-3", summary: "Finished the deck before lunch, then called Amma instead of scrolling.", mood: .neutral,
                    language: "en-IN", earnedBack: "A call home", createdAt: now.addingTimeInterval(-day * 2.2)),
        ]
    }
}

// MARK: - The stack

/// Zen Cards on Today: the latest few, stacked and tilted like notes on a desk, each with a soft
/// shadow. Click (or press Space) for the next one; point at the stack and it fans out. The top card
/// is the one read aloud.
struct ZenCardStackCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cards: [ZenAPI.ZenCard]?
    @State private var front = 0
    @State private var hovering = false

    static let shown = 3

    private var isSample: Bool { model.isDemo && (cards?.isEmpty ?? true) && !Self.forceEmpty }

    var body: some View {
        let showing = isSample ? ZenCardLabels.samples() : Array((cards ?? []).prefix(Self.shown))
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text("Zen Cards").font(ZenFont.brand(20)).tracking(-0.4).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                if isSample { DemoTag("Samples") }
                Spacer(minLength: 0)
                Eyebrow("Made with Zeno").lineLimit(1)
            }
            if cards == nil && !isSample {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showing.isEmpty {
                empty
            } else {
                stack(showing)
                footer(showing)
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
        .task(id: model.voice?.state) { await load() }
    }

    #if DEBUG
    /// Debug renders: ZEN_CARDS=empty shows the empty state.
    static var forceEmpty: Bool { ProcessInfo.processInfo.environment["ZEN_CARDS"] == "empty" }
    #else
    static let forceEmpty = false
    #endif

    private func load() async {
        if Self.forceEmpty { cards = []; return }
        let latest = (try? await model.services.cards.recent()) ?? []
        cards = latest
        if front >= max(latest.count, 1) { front = 0 }
    }

    private func step(_ count: Int) {
        guard count > 1 else { return }
        withAnimation(reduceMotion ? ZenMotion.calm(ZenMotion.t1) : .spring(response: 0.46, dampingFraction: 0.74)) {
            front = (front + 1) % count
        }
    }

    private func stack(_ showing: [ZenAPI.ZenCard]) -> some View {
        let order = ZenCardLabels.order(count: showing.count, front: front % max(showing.count, 1))
        let top = showing[order[0]]
        return Button { step(showing.count) } label: {
            ZStack {
                ForEach(Array(order.enumerated()).reversed(), id: \.element) { depth, i in
                    let fan = hovering && !reduceMotion
                    let angle = (fan ? ZenCardLabels.fanAngles : ZenCardLabels.angles)[min(depth, 3)]
                    // The cards behind peek out above the top one, each its own way.
                    let dx: CGFloat = fan ? [0, 62, -62, 84][min(depth, 3)] : [0, 18, -16, 24][min(depth, 3)]
                    let dy: CGFloat = fan ? [14, -8, -4, -12][min(depth, 3)] : [10, -8, -20, -26][min(depth, 3)]
                    ZenCardFace(card: showing[i], isTop: depth == 0)
                        .rotationEffect(.degrees(angle))
                        .offset(x: dx, y: dy)
                        .zIndex(Double(showing.count - depth))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StackPress())
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.72)) { hovering = inside }
        }
        .pointerStyle(.link)
        .help(showing.count > 1 ? "Next card" : top.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zen Card \(order[0] + 1) of \(showing.count). \(ZenCardLabels.mood(top.mood)), in \(ZenCardLabels.language(top.language)). \(top.summary)")
        .accessibilityHint(showing.count > 1 ? "Shows the next card" : "")
        .accessibilityAddTraits(.isButton)
    }

    private func footer(_ showing: [ZenAPI.ZenCard]) -> some View {
        let order = ZenCardLabels.order(count: showing.count, front: front % max(showing.count, 1))
        return HStack(spacing: ZenSpace.s2) {
            HStack(spacing: 5) {
                ForEach(0..<showing.count, id: \.self) { i in
                    Capsule().fill(i == order[0] ? Color.zen.textHeading : Color.zen.textHeading.opacity(0.18))
                        .frame(width: i == order[0] ? 14 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Text(showing.count > 1 ? "Click the stack for the next" : "Your latest card")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption)
            Spacer(minLength: 0)
            Button("Talk to Zeno · \(TalkHotKey.display)") { model.talkToZeno() }
                .buttonStyle(ZenLinkButtonStyle())
                .help("Tell Zeno about your evening; it makes the card.")
        }
    }

    private var empty: some View {
        VStack(spacing: ZenSpace.s4) {
            ZStack {
                ForEach(0..<3, id: \.self) { d in
                    RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
                        .strokeBorder(Color.zen.borderOutline, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                        .background(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.35)))
                        .frame(width: 200, height: 128)
                        .rotationEffect(.degrees(ZenCardLabels.angles[2 - d]))
                        .offset(x: [-6, 8, 0][d], y: [10, 6, 0][d])
                }
                ZenoStill(.curious).frame(width: 46)
            }
            .frame(height: 170)
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("No Zen Cards yet").font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text("Tell Zeno about your evening, in any language, and it makes one. Only you see it until you share it.")
                    .font(ZenFont.text(12.5)).foregroundStyle(Color.zen.textCaption)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Talk to Zeno · \(TalkHotKey.display)") { model.talkToZeno() }
                .buttonStyle(ZenSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StackPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
    }
}

/// One Zen Card, as paper: Zeno's face for the mood, the language, the note in the person's own
/// words, and what they earned back. Never a score, never a name.
struct ZenCardFace: View {
    let card: ZenAPI.ZenCard
    let isTop: Bool
    @Environment(\.colorScheme) private var scheme

    private var glow: Color {
        switch card.mood {
        case .happy, .pleasant: Color.zen.brandSoft
        case .neutral: Color(hex: 0x9FB7A0)
        case .tired, .sad: Color(hex: 0x8C9BB0)
        }
    }

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                ZenoStill(ZenCardLabels.feeling(card.mood)).frame(width: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ZenCardLabels.mood(card.mood)).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(card.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
                }
                Spacer(minLength: 0)
                Text(ZenCardLabels.language(card.language))
                    .font(ZenFont.text(11, .semibold)).foregroundStyle(Color.zen.textBody)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Color.zen.textHeading.opacity(0.07)))
            }
            Text(card.summary)
                .font(ZenFont.text(15.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                .lineSpacing(2)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let earned = card.earnedBack {
                    Image(systemName: "leaf.fill").font(.system(size: 10)).foregroundStyle(Color.zen.textBrand)
                    Text(earned).font(ZenFont.text(11.5, .medium)).foregroundStyle(Color.zen.textBody).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: card.isShared ? "person.2.fill" : "lock.fill").font(.system(size: 9))
                Text(card.isShared ? "Shared" : "Only you").font(ZenFont.text(11, .medium)).lineLimit(1)
            }
            .foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s4)
        .frame(width: 290, height: 196, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).fill(Color.zen.surfaceRaised)
                RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
                    .fill(RadialGradient(colors: [glow.opacity(dark ? 0.16 : 0.2), .clear], center: .topLeading, startRadius: 0, endRadius: 220))
            }
        }
        // The cards underneath read as paper, not as a second note to read.
        .overlay {
            if !isTop {
                RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.62))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
            .strokeBorder(dark ? Color.white.opacity(0.08) : Color.zen.borderHairline, lineWidth: 1))
        // The drop shadow that tells the cards apart: a close one and a soft, wide one.
        .shadow(color: .black.opacity(dark ? 0.4 : 0.1), radius: 2, y: 1)
        .shadow(color: .black.opacity(dark ? 0.45 : (isTop ? 0.16 : 0.12)), radius: isTop ? 18 : 12, y: isTop ? 12 : 8)
    }
}
