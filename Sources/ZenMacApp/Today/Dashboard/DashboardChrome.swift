import SwiftUI
import Albeit

/// A dashboard card: a Clash title, one quiet eyebrow on the right, and the content. Glass over the light.
struct DashCard<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, eyebrow: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.eyebrow = eyebrow
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text(title).font(ZenFont.brand(20)).tracking(-0.4).foregroundStyle(Color.zen.textHeading)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Eyebrow(eyebrow).lineLimit(1)
            }
            content()
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(radius: ZenRadius.widget)
    }
}

/// One number on raised paper, inside the usual stats.
struct StatTile<Content: View>: View {
    let eyebrow: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Eyebrow(eyebrow).lineLimit(1)
            content()
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderHairline.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Today and the two days before, as one pill that slides.
struct DayPicker: View {
    let days: [DayInsight]
    @Binding var selection: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days.reversed()) { d in
                let on = d.id == selection
                Button { withAnimation(ZenMotion.container) { selection = d.id } } label: {
                    Text(d.label)
                        .font(ZenFont.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textCaption)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 28)
                        .background {
                            if on {
                                Capsule().fill(Color.zen.surfaceRaised)
                                    .shadow(color: Color(hex: 0x12160F, alpha: 0.1), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.zen.textHeading.opacity(0.06)))
    }
}

/// Focus · Intentional · Unintentional, the key to every chart on the page.
struct FeelLegend: View {
    var body: some View {
        HStack(spacing: ZenSpace.s4) {
            ForEach(Feel.allCases) { f in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: ZenRadius.cell, style: .continuous).fill(f.color).frame(width: 9, height: 9)
                    Text(f.rawValue).zenType(.caption).foregroundStyle(Color.zen.textBody)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "▲ 2.7" or "▼ 2.7", against the day before.
struct DeltaText: View {
    let tenths: Int

    var body: some View {
        let up = tenths >= 0
        Text("\(up ? "▲" : "▼") \(abs(tenths) / 10).\(abs(tenths) % 10)")
            .font(ZenFont.number(11.5))
            .foregroundStyle(up ? Color.zen.scoreGain : Color.zen.scoreDeduct)
            .accessibilityLabel("\(up ? "up" : "down") \(abs(tenths) / 10).\(abs(tenths) % 10) on the day before")
    }
}
