import SwiftUI
import Albeit

/// Where the minutes went: this Mac → the kind of app → how it felt. Point at a kind or a feel to
/// follow just its threads. The iPhone isn't in it: its minutes stay on the phone.
struct MinutesFlowCard: View {
    let day: DayInsight
    /// A kind lit from search.
    @Binding var lit: AppKind?
    @State private var hovered: FlowNode.ID?

    var body: some View {
        DashCard("Where the minutes went", eyebrow: "Screen · kind of app · how it felt") {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                if day.minutes == 0 {
                    Text("Nothing measured yet. The day counts itself.").zenType(.body).foregroundStyle(Color.zen.textCaption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Sankey(day: day, focus: hovered ?? lit.map { .kind($0) }, hovered: $hovered)
                        .id(day.id)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: hovered) { _, h in if h != nil { lit = nil } }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Color.zen.textCaption)
                    Text("From this Mac. Your iPhone's minutes stay on your iPhone.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
        }
    }
}

struct FlowNode: Identifiable {
    enum ID: Hashable { case screen, kind(AppKind), feel(Feel) }

    let id: ID
    let rect: CGRect
    let minutes: Int
    let name: String
    let color: Color
    /// The node and its label, for pointing at.
    let hitRect: CGRect
}

/// The flow's geometry: three columns of bars and the ribbons between them, scaled to one minute height.
private struct SankeyLayout {
    struct Ribbon {
        let from: FlowNode.ID, to: FlowNode.ID
        let x0: CGFloat, x1: CGFloat
        let top0: CGFloat, top1: CGFloat, height0: CGFloat, height1: CGFloat
        let color: Color
        let isFeel: Bool
    }

    var nodes: [FlowNode] = []
    var ribbons: [Ribbon] = []

    init(day: DayInsight, size: CGSize) {
        let total = max(day.minutes, 1)
        let bar: CGFloat = 8
        let x0: CGFloat = 76, x1 = size.width * 0.42, x2 = size.width - 104
        // Kinds ordered by how they felt (focus at the top, drift at the bottom), so threads cross least.
        let kinds = day.kinds.sorted { lean(day, $0) < lean(day, $1) }
        let feels = Feel.allCases.filter { day.minutes($0) > 0 }
        let gapK: CGFloat = 10, gapF: CGFloat = 16
        let usable = size.height - 6
        let k = min((usable - gapK * CGFloat(max(kinds.count - 1, 0))) / CGFloat(total),
                    (usable - gapF * CGFloat(max(feels.count - 1, 0))) / CGFloat(total))
        func h(_ m: Int) -> CGFloat { max(2, CGFloat(m) * k) }

        let screenH = h(total)
        let screenRect = CGRect(x: x0, y: (size.height - screenH) / 2, width: bar, height: screenH)
        nodes.append(FlowNode(id: .screen, rect: screenRect, minutes: day.minutes, name: "This Mac", color: Color.zen.textHeading.opacity(0.62),
                              hitRect: CGRect(x: 0, y: screenRect.minY, width: x0 + bar, height: screenH)))

        let kindsH = kinds.reduce(0) { $0 + h(day.minutes($1)) } + gapK * CGFloat(max(kinds.count - 1, 0))
        var y = (size.height - kindsH) / 2
        var kindRects: [AppKind: CGRect] = [:]
        for kind in kinds {
            let r = CGRect(x: x1, y: y, width: bar, height: h(day.minutes(kind)))
            kindRects[kind] = r
            nodes.append(FlowNode(id: .kind(kind), rect: r, minutes: day.minutes(kind), name: kind.rawValue, color: Color.zen.textHeading.opacity(0.62),
                                  hitRect: CGRect(x: x1 - 6, y: r.minY - 4, width: 130, height: max(r.height, 14) + 8)))
            y += r.height + gapK
        }

        let feelsH = feels.reduce(0) { $0 + h(day.minutes($1)) } + gapF * CGFloat(max(feels.count - 1, 0))
        y = (size.height - feelsH) / 2
        var feelRects: [Feel: CGRect] = [:]
        for feel in feels {
            let r = CGRect(x: x2, y: y, width: bar, height: h(day.minutes(feel)))
            feelRects[feel] = r
            nodes.append(FlowNode(id: .feel(feel), rect: r, minutes: day.minutes(feel), name: feel.rawValue, color: feel.color,
                                  hitRect: CGRect(x: x2 - 6, y: r.minY - 4, width: size.width - x2 + 6, height: max(r.height, 14) + 8)))
            y += r.height + gapF
        }

        // Screen → kind: one grey thread per kind, stacked down the screen's bar.
        var screenY = screenRect.minY
        for kind in kinds {
            guard let r = kindRects[kind] else { continue }
            ribbons.append(Ribbon(from: .screen, to: .kind(kind), x0: screenRect.maxX, x1: r.minX, top0: screenY, top1: r.minY,
                                  height0: r.height, height1: r.height, color: Color.zen.textHeading.opacity(0.09), isFeel: false))
            screenY += r.height
        }

        // Kind → feel: one thread per pair, coloured by the feel.
        var feelY = feelRects.mapValues(\.minY)
        for kind in kinds {
            guard let kr = kindRects[kind] else { continue }
            var kindY = kr.minY
            for feel in feels {
                let m = day.minutes(kind, feel)
                guard m > 0, let fr = feelRects[feel], let fy = feelY[feel] else { continue }
                let hh = CGFloat(m) * k
                ribbons.append(Ribbon(from: .kind(kind), to: .feel(feel), x0: kr.maxX, x1: fr.minX, top0: kindY, top1: fy,
                                      height0: hh, height1: hh, color: feel.color.opacity(0.32), isFeel: true))
                kindY += hh
                feelY[feel] = fy + hh
            }
        }
    }

    /// 0 for all focus, 2 for all drift.
    private func lean(_ day: DayInsight, _ kind: AppKind) -> Double {
        let m = Double(max(day.minutes(kind), 1))
        return (Double(day.minutes(kind, .intentional)) + 2 * Double(day.minutes(kind, .unintentional))) / m
    }

    func node(at p: CGPoint) -> FlowNode.ID? { nodes.first { $0.hitRect.contains(p) }?.id }
}

private struct Sankey: View {
    let day: DayInsight
    let focus: FlowNode.ID?
    @Binding var hovered: FlowNode.ID?

    var body: some View {
        GeometryReader { geo in
            let layout = SankeyLayout(day: day, size: geo.size)
            Canvas { ctx, _ in draw(&ctx, layout) }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): let n = layout.node(at: p); if n != hovered { hovered = n }
                    case .ended: hovered = nil
                    }
                }
                .animation(ZenMotion.calm(ZenMotion.t1), value: focus)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(day))
    }

    private func touches(_ r: SankeyLayout.Ribbon) -> Bool {
        guard let focus else { return true }
        if r.from == focus || r.to == focus { return true }
        // A kind's grey thread from the screen lights with any of its feels.
        if case .feel(let f) = focus, case .kind(let k) = r.to { return day.minutes(k, f) > 0 }
        if case .kind = focus, r.from == .screen { return false }
        return false
    }

    private func draw(_ ctx: inout GraphicsContext, _ layout: SankeyLayout) {
        for r in layout.ribbons {
            var p = Path()
            let mid = (r.x0 + r.x1) / 2
            p.move(to: CGPoint(x: r.x0, y: r.top0))
            p.addCurve(to: CGPoint(x: r.x1, y: r.top1), control1: CGPoint(x: mid, y: r.top0), control2: CGPoint(x: mid, y: r.top1))
            p.addLine(to: CGPoint(x: r.x1, y: r.top1 + r.height1))
            p.addCurve(to: CGPoint(x: r.x0, y: r.top0 + r.height0), control1: CGPoint(x: mid, y: r.top1 + r.height1), control2: CGPoint(x: mid, y: r.top0 + r.height0))
            p.closeSubpath()
            let on = touches(r)
            ctx.fill(p, with: .color(r.color.opacity(focus == nil ? 1 : (on ? 1.6 : 0.3))))
        }

        for n in layout.nodes {
            let dim = focus != nil && focus != n.id && !connected(n.id, layout)
            ctx.fill(Path(roundedRect: n.rect, cornerRadius: 2), with: .color(n.color.opacity(dim ? 0.35 : 1)))
            let name = Text(n.name).font(ZenFont.text(12, .semibold)).foregroundStyle(Color.zen.textHeading.opacity(dim ? 0.4 : 1))
            let minutes = Text(durationText(n.minutes)).font(ZenFont.number(10.5)).foregroundStyle(Color.zen.textCaption.opacity(dim ? 0.5 : 1))
            switch n.id {
            case .screen:
                ctx.draw(name, at: CGPoint(x: n.rect.minX - 8, y: n.rect.midY - 7), anchor: .trailing)
                ctx.draw(minutes, at: CGPoint(x: n.rect.minX - 8, y: n.rect.midY + 8), anchor: .trailing)
            case .feel:
                // Name over minutes: the right edge is narrow.
                ctx.draw(name, at: CGPoint(x: n.rect.maxX + 7, y: n.rect.midY - 7), anchor: .leading)
                ctx.draw(minutes, at: CGPoint(x: n.rect.maxX + 7, y: n.rect.midY + 8), anchor: .leading)
            case .kind:
                let nameSize = ctx.resolve(name).measure(in: CGSize(width: 200, height: 40))
                ctx.draw(name, at: CGPoint(x: n.rect.maxX + 7, y: n.rect.midY), anchor: .leading)
                ctx.draw(minutes, at: CGPoint(x: n.rect.maxX + 7 + nameSize.width + 6, y: n.rect.midY + 0.5), anchor: .leading)
            }
        }
    }

    private func connected(_ id: FlowNode.ID, _ layout: SankeyLayout) -> Bool {
        layout.ribbons.contains { touches($0) && ($0.from == id || $0.to == id) && focus != nil && ($0.from == focus || $0.to == focus || isFeelFocus($0)) }
    }

    private func isFeelFocus(_ r: SankeyLayout.Ribbon) -> Bool {
        if case .feel = focus { return true }
        return false
    }

    static func summary(_ day: DayInsight) -> String {
        let kinds = day.kinds.map { "\($0.rawValue) \(durationText(day.minutes($0)))" }.joined(separator: ", ")
        let feels = Feel.allCases.map { "\($0.rawValue) \(durationText(day.minutes($0)))" }.joined(separator: ", ")
        return "Where the minutes went on this Mac. By kind: \(kinds). By feel: \(feels)."
    }
}
