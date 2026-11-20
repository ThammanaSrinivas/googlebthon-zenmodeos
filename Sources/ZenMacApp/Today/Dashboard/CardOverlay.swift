import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Albeit

/// One pattern card, opened: the card turns over into the middle of the window, its story beside it,
/// and Share (primary) and Save image (secondary). ← → walk the deck, Esc puts it back.
struct CardOverlay: View {
    @Environment(AppModel.self) private var model
    let card: PatternCard
    @State private var dealt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dash = model.dashboard
        ZStack {
            Rectangle().fill(.black.opacity(0.46))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { dash.close() }
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: ZenSpace.s6) {
                navButton("chevron.left", label: "Previous card") { dash.step(-1) }
                HStack(alignment: .center, spacing: ZenSpace.s10) {
                    PlayingCard(rank: dash.rank(of: card), suit: card.suit, skin: card.skin, feeling: card.feeling,
                                title: card.title, line: card.face, width: 272, liveZeno: true)
                        .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
                        .rotation3DEffect(.degrees(dealt ? 0 : 80), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .rotationEffect(.degrees(dealt ? -2.5 : -12))
                        .scaleEffect(dealt ? 1 : 0.74)
                        .offset(y: dealt ? 0 : 70)
                        .opacity(dealt ? 1 : 0)
                    CardDetail(card: card)
                        .frame(width: 400)
                        .opacity(dealt ? 1 : 0)
                        .offset(x: dealt ? 0 : 28)
                }
                .id(card.id)
                navButton("chevron.right", label: "Next card") { dash.step(1) }
            }
            .padding(ZenSpace.s8)
        }
        .background {
            // Arrow keys walk the deck.
            Group {
                Button("") { dash.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { dash.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0).accessibilityHidden(true)
        }
        .onAppear { deal() }
        .onChange(of: card.id) { _, _ in
            dealt = false
            Task { @MainActor in deal() }
        }
    }

    private func deal() {
        if reduceMotion { dealt = true; return }
        withAnimation(.spring(response: 0.62, dampingFraction: 0.8)) { dealt = true }
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.zen.textHeading)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The card's story: what the pattern is, three facts, when in the day it shows up, Zeno's one
/// suggestion, and the two actions.
private struct CardDetail: View {
    @Environment(AppModel.self) private var model
    let card: PatternCard

    var body: some View {
        let dash = model.dashboard
        let rank = dash.rank(of: card)
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: 6) {
                Image(systemName: card.suit.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                Eyebrow("\(card.suitMeaning) · \(rank) · card \(dash.position(of: card)) of \(dash.cards.count)")
                Spacer(minLength: 0)
                Button { dash.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.zen.textCaption)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.zen.textHeading.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc)")
            }
            Text(card.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
            Text(card.body).zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: ZenSpace.s3) {
                ForEach(card.facts, id: \.self) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.value).font(ZenFont.number(19)).foregroundStyle(Color.zen.textHeading).lineLimit(1).minimumScaleFactor(0.7)
                        Text(f.label).zenType(.caption).foregroundStyle(Color.zen.textCaption).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, ZenSpace.s1)

            if let hours = card.hours {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("When it shows up")
                    HourStrip(hours: hours, color: accent)
                }
            }

            HStack(spacing: ZenSpace.s3) {
                ZenoView(card.feeling, replay: dash.position(of: card)).frame(width: 46)
                Text(card.tip).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.8)))

            HStack(spacing: ZenSpace.s3) {
                ShareImageButton(fileName: "\(card.title) · ZenMode OS.png") {
                    ImageExport.png(PatternShareImage(card: card, rank: rank))
                } label: {
                    Label("Share card", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ZenPrimaryButtonStyle())

                Button {
                    if let png = ImageExport.png(PatternShareImage(card: card, rank: rank)) {
                        ImageExport.save(png, suggestedName: "\(card.title) · ZenMode OS.png")
                    }
                } label: {
                    Label("Save image", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
            .padding(.top, ZenSpace.s1)
            Text("The card shares its pattern, never your minutes or apps.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s6)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).fill(Color.zen.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 18)
    }

    /// The card's hue, dark enough to read on paper.
    private var accent: Color {
        switch card.skin {
        case .paper, .mint, .zen: Color.zen.brandFill
        case .night: Color.zen.textBrand
        default: card.skin.deep
        }
    }
}

/// 24 cells, one an hour, lit by how often the pattern shows up then.
private struct HourStrip: View {
    let hours: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous)
                        .fill(hours[h] > 0 ? color.opacity(0.18 + 0.82 * hours[h]) : Color.zen.textHeading.opacity(0.05))
                        .frame(height: 14)
                }
            }
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { t in
                    Text(t).font(ZenFont.number(9)).foregroundStyle(Color.zen.textCaption)
                    if t != "24" { Spacer() }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
