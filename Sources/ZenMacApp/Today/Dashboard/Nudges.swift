import SwiftUI
import Albeit
import ZenAPI

/// Nudges and pull-backs: when Zeno spoke, on which screen, and whether you went back to something you
/// meant to do. The iPhone's lane holds Zeno's lines only; its minutes stay on the phone.
struct NudgesCard: View {
    @Environment(AppModel.self) private var model
    let day: DayInsight

    var body: some View {
        DashCard("Nudges and pull-backs", eyebrow: day.isToday ? "07:00 to now" : "07:00 to midnight") {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                NudgeTimeline(day: day)
                    .id(day.id)
                    .transition(.opacity)
                    .frame(height: 100)
                HStack(spacing: 6) {
                    Capsule().fill(Color.zen.brandFill).frame(width: 14, height: 2)
                    Text("Green line: a pull-back to something you meant to do")
                        .zenType(.caption).foregroundStyle(Color.zen.textCaption).lineLimit(1)
                }
                .help("A pull-back is going back to something on purpose within a few minutes of Zeno's line.")
                Eyebrow("What Zeno said").padding(.top, ZenSpace.s1)
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    ForEach(lines, id: \.id) { NudgeRow(minute: $0.minute, device: $0.device, feeling: $0.feeling, line: $0.line) }
                }
                Spacer(minLength: 0)
                HStack(spacing: ZenSpace.s3) {
                    Button { Task { await model.refreshNudge(trigger: .checkIn) } } label: {
                        Label("Ask Zeno", systemImage: "bubble.left")
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    Text("Quiet: \(model.profile.quiet.summary)").zenType(.caption).foregroundStyle(Color.zen.textCaption).lineLimit(1)
                }
            }
        }
    }

    /// The two latest lines, newest first, with Zeno's live line on top today.
    private var lines: [NudgeMoment] {
        var all = day.nudges.sorted { $0.minute > $1.minute }
        if day.isToday, let (nudge, _) = model.lastNudge {
            all.insert(NudgeMoment(id: -1, minute: day.now, device: .mac, feeling: NotchModel.feeling(for: nudge.notchFeeling),
                                   line: nudge.line, pullBackAt: nil), at: 0)
        }
        return Array(all.prefix(2))
    }
}

private struct NudgeRow: View {
    let minute: Int
    let device: DeviceLine.Kind
    let feeling: ZenoFeeling
    let line: String

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            ZenoStill(feeling)
                .frame(width: 28)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.zen.island))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(clockText(minute)) · \(device == .iPhone ? "IPHONE" : "MAC")")
                    .font(ZenFont.number(9.5)).tracking(0.8).foregroundStyle(Color.zen.textCaption)
                Text("“\(line)”").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Two lanes from 07:00 to midnight: this Mac's sessions, and the iPhone (score only). Zeno sits
/// above the lane where it spoke; its line turns green when a pull-back followed.
private struct NudgeTimeline: View {
    let day: DayInsight
    private let start = 7 * 60, end = 24 * 60
    private let lead: CGFloat = 50
    private let macY: CGFloat = 50, phoneY: CGFloat = 76, laneH: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in draw(&ctx, size) }
                ForEach(day.nudges) { n in
                    ZenoStill(n.feeling)
                        .frame(width: 15)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.zen.island))
                        .position(x: x(n.minute, w), y: 11)
                        .help("\(clockText(n.minute)) · \(n.line)")
                }
                Label("MAC", systemImage: "laptopcomputer").labelStyle(LaneLabel()).position(x: 20, y: macY)
                Label("IPHONE", systemImage: "iphone").labelStyle(LaneLabel()).position(x: 20, y: phoneY)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.nudges.count) nudges, \(day.pullBacks) pull-backs.")
    }

    private func x(_ minute: Int, _ width: CGFloat) -> CGFloat {
        lead + CGFloat(min(max(minute, start), end) - start) / CGFloat(end - start) * (width - lead - 4)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width
        let ink = Color.zen.textHeading
        let nowX = x(day.now, w)

        // The Mac's lane: a track, then one block per session.
        let mac = CGRect(x: lead, y: macY - laneH / 2, width: w - lead - 4, height: laneH)
        ctx.fill(Path(roundedRect: mac, cornerRadius: 4), with: .color(ink.opacity(0.05)))
        for s in day.sessions where s.end > start {
            let x0 = x(s.start, w), x1 = max(x(s.end, w), x0 + 2)
            ctx.fill(Path(roundedRect: CGRect(x: x0, y: mac.minY + 1, width: x1 - x0, height: laneH - 2), cornerRadius: 2), with: .color(s.feel.color))
        }

        // The iPhone's lane: sealed, with the words "score only" in it.
        let phone = CGRect(x: lead, y: phoneY - laneH / 2, width: w - lead - 4, height: laneH)
        ctx.stroke(Path(roundedRect: phone, cornerRadius: 4), with: .color(Color.zen.textCaption.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        ctx.draw(Text("score only · minutes stay on the phone").font(ZenFont.text(9.5)).foregroundStyle(Color.zen.textCaption),
                 at: CGPoint(x: phone.maxX - 8, y: phoneY), anchor: .trailing)

        // Zeno's lines: from the mark down to the lane it spoke on. Green when a pull-back followed.
        for n in day.nudges {
            let nx = x(n.minute, w)
            let laneTop = (n.device == .iPhone ? phoneY : macY) - laneH / 2
            var stem = Path()
            stem.move(to: CGPoint(x: nx, y: 22))
            if let back = n.pullBackAt {
                let bx = x(back, w)
                stem.addCurve(to: CGPoint(x: bx, y: laneTop), control1: CGPoint(x: nx, y: laneTop - 6), control2: CGPoint(x: bx, y: 26))
                ctx.stroke(stem, with: .color(Color.zen.brandFill), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: bx - 2.5, y: laneTop - 2.5, width: 5, height: 5)), with: .color(Color.zen.brandFill))
            } else {
                stem.addLine(to: CGPoint(x: nx, y: laneTop))
                ctx.stroke(stem, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }

        // The hours to come, hushed; now, as a hairline.
        if day.isToday, nowX < w - 4 {
            ctx.fill(Path(CGRect(x: nowX, y: macY - laneH, width: w - 4 - nowX, height: phoneY - macY + laneH * 2)),
                     with: .color(Color.zen.surfaceCard.opacity(0.55)))
            var now = Path()
            now.move(to: CGPoint(x: nowX, y: macY - laneH))
            now.addLine(to: CGPoint(x: nowX, y: phoneY + laneH))
            ctx.stroke(now, with: .color(ink.opacity(0.7)), lineWidth: 1)
        }

        for h in stride(from: 8, through: 20, by: 4) {
            ctx.draw(Text(String(format: "%02d:00", h)).font(ZenFont.number(9)).foregroundStyle(Color.zen.textCaption),
                     at: CGPoint(x: x(h * 60, w), y: size.height - 5), anchor: .center)
        }
    }
}

private struct LaneLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9))
            configuration.title.font(ZenFont.number(8.5)).tracking(0.6)
        }
        .foregroundStyle(Color.zen.textCaption)
    }
}
