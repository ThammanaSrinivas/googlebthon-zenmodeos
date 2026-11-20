import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Albeit
import ZenAPI

/// Renders views to PNG, hands them to the share menu, and saves them.
@MainActor
enum ImageExport {
    /// A 4:5 picture at 2× (1080 × 1350 for the 540 × 675 cards below).
    static func png<V: View>(_ view: V) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Writes the picture where the share menu can pick it up, under its own name.
    static func temporaryFile(_ png: Data, named name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZenMode OS share", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do { try png.write(to: url, options: .atomic); return url } catch { return nil }
    }

    static func save(_ png: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url, options: .atomic)
    }
}

/// A button that opens macOS's share menu for a rendered picture, anchored on itself.
struct ShareImageButton<Label: View>: View {
    let fileName: String
    let make: @MainActor () -> Data?
    @ViewBuilder var label: () -> Label
    @State private var anchor = ShareAnchor()

    init(fileName: String, make: @escaping @MainActor () -> Data?, @ViewBuilder label: @escaping () -> Label) {
        self.fileName = fileName
        self.make = make
        self.label = label
    }

    var body: some View {
        Button {
            guard let png = make(), let url = ImageExport.temporaryFile(png, named: fileName), let view = anchor.view else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } label: { label() }
        .background(ShareAnchorView(anchor: anchor))
    }
}

@MainActor
final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

/// A pattern card as a picture to share: the card, tilted, in its own light, with the lockup.
/// It carries the pattern, never minutes or apps.
struct PatternShareImage: View {
    let card: PatternCard
    let rank: String

    var body: some View {
        ZStack {
            ZenBackdrop(tone: tone, glowAt: UnitPoint(x: 0.5, y: 0.42))
            VStack(spacing: 30) {
                PlayingCard(rank: rank, suit: card.suit, skin: card.skin, feeling: card.feeling, title: card.title, line: card.face, width: 300)
                    .rotationEffect(.degrees(-3))
                    .shadow(color: Color(hex: 0x12160F, alpha: 0.3), radius: 30, y: 20)
                VStack(spacing: 8) {
                    ZenLockup(size: 18)
                    Eyebrow("Pattern card · \(rank) of \(card.suit.name)")
                }
            }
        }
        .frame(width: 540, height: 675)
    }

    private var tone: BackdropTone {
        switch card.skin {
        case .zen: .zen
        case .mint, .paper: .mint
        case .gold, .ember: .amber
        case .dusk: .dusk
        case .night: .twilight
        }
    }
}

/// Today as a picture to share: the Zen Score and the week. Scores only.
struct TodayShareImage: View {
    let score: ZenScore
    let week: WeekProgress
    let date: Date

    var body: some View {
        ZStack {
            ZenBackdrop(tone: .zen, glowAt: UnitPoint(x: 0.5, y: 0.36))
            VStack(spacing: 0) {
                ZenLockup(size: 20)
                Spacer()
                Eyebrow(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                ScoreText(score.text, size: 150).padding(.top, 6)
                Text("Zen Score · every screen").font(ZenFont.text(17, .semibold)).foregroundStyle(Color.zen.textHeading)
                HStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = week.days[d]
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.map { $0.isGoodDay ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.16) } ?? Color.zen.textHeading.opacity(0.04))
                            .overlay {
                                if day == nil { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.zen.borderOutline, lineWidth: 1.5) }
                            }
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.top, 34)
                Text(Self.streakLine(week)).font(ZenFont.text(16, .semibold)).foregroundStyle(Color.zen.textHeading).padding(.top, 14)
                Spacer()
                ZenoStill(week.isWon ? .proud : .happy).frame(width: 96)
            }
            .padding(.vertical, 44)
        }
        .frame(width: 540, height: 675)
    }
}

extension TodayShareImage {
    /// "9-week streak · one more wins it", or "Week won · 10-week streak".
    static func streakLine(_ week: WeekProgress) -> String {
        if week.isWon { return "Week won · \(week.weeklyStreak)-week streak" }
        let left = WeekProgress.goodDaysToWin - week.goodDays
        return "\(week.streakBefore)-week streak · " + (left == 1 ? "one more wins it" : "\(left) more win it")
    }
}
