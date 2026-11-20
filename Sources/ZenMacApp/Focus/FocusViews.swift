import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

enum FocusCopy {
    static let eyebrow = "Focus Mode"
    static let idleTitle = "Lock in. Log off."
    static let idleBody = "One switch: Do Not Disturb, Slack, your calendar and your webhooks. Zeno catches you up after."
    static let starting = "Switching everything off…"
    static let ending = "Switching everything back on…"
    static let end = "End focus"
    static let earlyTitle = "End this block early?"
    static let earlyBody = "Everything switches back on. This block won't count as kept."
    static let earlyConfirm = "End early"
    static let keepGoing = "Keep focusing"
    static let setUp = "Set up hooks"
    static func untilLabel(_ date: Date) -> String { "Until \(FocusClock.text(date))" }
}

/// Today's Focus card: four lengths when idle; while focusing, the end time and a chip per hook.
struct FocusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let focus = model.focus
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s2) {
                Eyebrow(FocusCopy.eyebrow, color: Color.zen.textBrand)
                if model.isDemo { DemoTag() }
                Spacer(minLength: 0)
                Button(FocusCopy.setUp) { model.integrationsTab = .focus; model.navigate = .integrations }
                    .buttonStyle(ZenLinkButtonStyle())
            }
            switch focus.phase {
            case .idle: idle
            case .starting: progress(FocusCopy.starting)
            case .focusing, .ending: focusing
            }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl, tint: focus.isFocusing ? Color.zen.brandFill.opacity(0.10) : nil)
        .confirmationDialog(FocusCopy.earlyTitle, isPresented: Binding(get: { focus.confirmingEarlyEnd }, set: { focus.confirmingEarlyEnd = $0 })) {
            Button(FocusCopy.earlyConfirm, role: .destructive) { focus.end() }
            Button(FocusCopy.keepGoing, role: .cancel) {}
        } message: {
            Text(FocusCopy.earlyBody)
        }
    }

    private var idle: some View {
        let until = FocusModel.suggestedUntil()
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Text(FocusCopy.idleTitle).font(ZenFont.brand(26)).foregroundStyle(Color.zen.textHeading)
                .accessibilityAddTraits(.isHeader)
            Text(FocusCopy.idleBody).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ZenSpace.s2) {
                ForEach(FocusModel.lengths, id: \.self) { m in
                    Button("\(m) min") { model.startFocus(minutes: m) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .accessibilityLabel("Focus for \(m) minutes")
                }
                Button(FocusCopy.untilLabel(until)) { model.startFocus(until: until) }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .accessibilityLabel("Focus until \(FocusClock.text(until))")
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: ZenSpace.s3) {
            ProgressView().controlSize(.small)
            Text(text).zenType(.body).foregroundStyle(Color.zen.textBody)
        }
        .accessibilityElement(children: .combine)
    }

    private var focusing: some View {
        let focus = model.focus
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text(focus.untilText ?? "").font(ZenFont.brand(30)).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: ZenSpace.s3)
                if focus.phase == .ending {
                    progress(FocusCopy.ending)
                } else {
                    Button(FocusCopy.end) { focus.requestEnd() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .keyboardShortcut(.escape, modifiers: [.command])
                }
            }
            HookChips(chips: focus.chips)
        }
    }
}

/// One chip per hook: on, failed (focus went on anyway) or skipped (not set up).
struct HookChips: View {
    let chips: [HookOutcome]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ZenSpace.s2) { ForEach(chips) { HookChip(outcome: $0) } }
            VStack(alignment: .leading, spacing: ZenSpace.s2) { ForEach(chips) { HookChip(outcome: $0) } }
        }
    }
}

struct HookChip: View {
    let outcome: HookOutcome

    private var symbol: String {
        switch outcome.state {
        case .on: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "minus.circle"
        }
    }

    private var tint: Color {
        switch outcome.state {
        case .on: Color.zen.textBrand
        case .failed: Color.zen.scoreDeduct
        case .skipped: Color.zen.textCaption
        }
    }

    private var stateWord: String {
        switch outcome.state {
        case .on: "on"
        case .failed: "failed"
        case .skipped: "skipped"
        }
    }

    var body: some View {
        let name = FocusModel.name(outcome.id)
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            Text(name).font(ZenFont.text(12.5, .medium)).foregroundStyle(Color.zen.textHeading)
            if outcome.state != .on, let note = outcome.note {
                Text(note).font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(Color.zen.surfaceCard.opacity(0.85)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(stateWord)" + (outcome.note.map { ", \($0)" } ?? ""))
        .help(outcome.note ?? "\(name) \(stateWord)")
    }
}
