import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

// MARK: - The steps

/// One step of "Get set up". Each one reads its done state from the real thing (the Keychain, the
/// calendar's permission, the saved work hours …), never from a box the person ticks.
struct SetupStep: Identifiable, Equatable {
    enum ID: String, CaseIterable, Sendable {
        case dnd, slack, calendar, webhook, workHours, team, talk
    }

    let id: ID
    let done: Bool
    /// The line under the title (the step's own words when not done, what's set when done).
    var note: String?

    var isOptional: Bool { id == .webhook }

    var title: String {
        switch id {
        case .dnd: "Turn on Mac Do Not Disturb"
        case .slack: "Connect Slack"
        case .calendar: "Connect your calendar"
        case .webhook: "Add a webhook"
        case .workHours: "Set your work hours"
        case .team: "Join your team"
        case .talk: "Talk to Zeno"
        }
    }

    @MainActor var detail: String {
        switch id {
        case .dnd: "Two Shortcuts, made once, let Focus Mode quiet this Mac."
        case .slack: "Focus Mode pauses it and Zeno catches you up after."
        case .calendar: "Zeno goes quiet in meetings and books focus blocks."
        case .webhook: "A signed post when a block starts and ends."
        case .workHours: "When work ends, Slack says offline and the Mac goes quiet."
        case .team: "Ask Zeno about the team; your admin sees team numbers only."
        case .talk: "Press \(TalkHotKey.display) in any app and say how the day went."
        }
    }

    var symbol: String {
        switch id {
        case .dnd: "moon.fill"
        case .slack: "number"
        case .calendar: "calendar"
        case .webhook: "point.3.connected.trianglepath.dotted"
        case .workHours: "clock"
        case .team: "person.2"
        case .talk: "waveform"
        }
    }

    /// The words on the row's action.
    var action: String {
        switch id {
        case .talk: "Try it"
        case .team: "Join"
        default: "Set up"
        }
    }
}

/// The checklist as a whole: the required steps count toward done; the optional one (the webhook)
/// shows, but never holds the list open.
struct SetupProgress: Equatable {
    let steps: [SetupStep]

    var required: [SetupStep] { steps.filter { !$0.isOptional } }
    var doneCount: Int { required.filter(\.done).count }
    var total: Int { required.count }
    var isComplete: Bool { doneCount == total }
    var fraction: Double { total == 0 ? 1 : Double(doneCount) / Double(total) }
    /// The first required step still to do.
    var next: SetupStep? { required.first { !$0.done } }

    /// "3 of 6 done"
    var label: String { "\(doneCount) of \(total) done" }

    /// The steps in the order the card lists them.
    static func make(dnd: Bool, slack: Bool, calendar: Bool, webhook: Bool, workHours: Bool, team: Bool, talked: Bool,
                     notes: [SetupStep.ID: String] = [:]) -> SetupProgress {
        let done: [SetupStep.ID: Bool] = [.dnd: dnd, .slack: slack, .calendar: calendar, .webhook: webhook,
                                          .workHours: workHours, .team: team, .talk: talked]
        return SetupProgress(steps: SetupStep.ID.allCases.map { SetupStep(id: $0, done: done[$0] ?? false, note: notes[$0]) })
    }
}

/// What the checklist remembers on this Mac.
enum SetupMemory {
    /// The person closed the finished checklist.
    static let dismissedKey = "zen.setup.dismissed"
    /// The person has talked to Zeno at least once (⌃⌥Z, "Hey Zeno" or the row's Try it).
    static let talkedKey = "zen.setup.talkedToZeno"
}

// MARK: - The card

/// "Get set up" on Today: the steps that make ZenMode OS run itself, each with its real state and a
/// link to where it's done, a progress bar, and the month's Bloom opening as the steps get done.
/// Folds to one line when everything required is done, and goes once that line is closed.
struct SetupChecklistCard: View {
    @Environment(AppModel.self) private var model
    /// Scrolls Today to the team card (the join field lives there).
    var showTeam: () -> Void = {}
    @AppStorage(SetupMemory.dismissedKey) private var dismissed = false
    @AppStorage(SetupMemory.talkedKey) private var talked = false
    @AppStorage(FocusSettings.webhookURLKey) private var webhookURL = ""
    @State private var dndReady: Bool?

    var body: some View {
        let progress = current
        Group {
            if dismissed {
                EmptyView()
            } else if progress.isComplete {
                done
            } else {
                full(progress)
            }
        }
        .task { await checkDND() }
        .onChange(of: model.voice?.state) { _, state in
            if let state, [.listening, .thinking, .speaking].contains(state) { talked = true }
        }
    }

    /// Every step's state, read now.
    private var current: SetupProgress {
        let hours = model.afterHours.hours
        let hoursSaved = model.defaults.data(forKey: AfterHoursGuard.hoursKey) != nil
        var notes: [SetupStep.ID: String] = [:]
        if hoursSaved { notes[.workHours] = "\(hours.start)–\(hours.end)" }
        if let team = model.team.team { notes[.team] = team.name }
        if model.team.load == .signedOut { notes[.team] = "Sign in first, then join." }
        if dndReady == nil { notes[.dnd] = "Checking Shortcuts…" }
        return SetupProgress.make(
            dnd: dndReady == true,
            slack: FocusSecrets.shared.value(FocusSecrets.slackToken) != nil,
            calendar: model.calendarLink.state == .connected,
            webhook: !webhookURL.isEmpty && FocusSecrets.shared.value(FocusSecrets.webhookSecret) != nil,
            workHours: hoursSaved,
            team: model.team.team != nil,
            talked: talked,
            notes: notes)
    }

    private func checkDND() async {
        dndReady = await ShortcutsDNDHook(runner: ProcessRunner()).missing().isEmpty
    }

    private func open(_ step: SetupStep.ID) {
        switch step {
        case .dnd, .slack, .webhook, .workHours:
            model.integrationsTab = .focus
            model.navigate = .integrations
        case .calendar:
            model.navigate = .calendar
        case .team:
            showTeam()
        case .talk:
            talked = true
            model.talkToZeno()
        }
    }

    // MARK: Full

    private func full(_ progress: SetupProgress) -> some View {
        HStack(alignment: .top, spacing: ZenSpace.s8) {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    HStack(spacing: ZenSpace.s2) {
                        Eyebrow("Get set up", color: Color.zen.textBrand)
                        Text(progress.label).font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                    }
                    Text("Make ZenMode OS run itself")
                        .font(ZenFont.brand(26)).tracking(-0.6).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text("A minute each. After this, nothing is ever logged by hand.")
                        .zenType(.body).foregroundStyle(Color.zen.textBody)
                }
                ProgressTrack(fraction: progress.fraction)
                    .accessibilityElement()
                    .accessibilityLabel("Setup progress")
                    .accessibilityValue(progress.label)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: ZenSpace.s2, alignment: .top)],
                          alignment: .leading, spacing: ZenSpace.s2) {
                    ForEach(progress.steps) { step in
                        SetupRow(step: step, isNext: step.id == progress.next?.id) { open(step.id) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BloomPreview(fraction: progress.fraction)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxl)
    }

    // MARK: Done

    private var done: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(Color.zen.textBrand)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're set up").font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text("ZenMode OS runs itself now. Change any of it in Integrations.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            Spacer(minLength: ZenSpace.s3)
            Button("Hide") { withAnimation(ZenMotion.exit) { dismissed = true } }
                .buttonStyle(ZenLinkButtonStyle())
                .accessibilityLabel("Hide the setup checklist")
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, ZenSpace.s5).padding(.vertical, ZenSpace.s3)
        .glassCard(radius: ZenRadius.xl)
    }
}

/// A thin green bar on a sunk track.
private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.zen.textHeading.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Color.zen.brandFill, Color.zen.brandSoft], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 420)
        .animation(ZenMotion.container, value: fraction)
    }
}

/// One step: its icon, title and line, and either Done or the way to do it. The whole row is the
/// button, with a hover lift and the system focus ring.
private struct SetupRow: View {
    let step: SetupStep
    let isNext: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenSpace.s3) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(step.done ? Color.zen.textBrand : Color.zen.textHeading)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous)
                            .fill(step.done ? Color.zen.surfaceTint : Color.zen.textHeading.opacity(0.06)))
                    if step.done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white, Color.zen.brandFill)
                            .background(Circle().fill(Color.zen.surfaceRaised).padding(1))
                            .offset(x: 4, y: 4)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(step.title).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                        if step.isOptional {
                            Text("Optional").font(ZenFont.text(11, .medium)).foregroundStyle(Color.zen.textCaption)
                                .padding(.horizontal, 6).frame(height: 18)
                                .background(Capsule().strokeBorder(Color.zen.borderOutline, lineWidth: 1))
                        }
                    }
                    Text(step.done ? (step.note ?? "Done") : (step.note ?? step.detail))
                        .font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ZenSpace.s2)
                if step.done {
                    Text("Done").font(ZenFont.text(12, .semibold)).foregroundStyle(Color.zen.textBrand)
                } else {
                    HStack(spacing: 3) {
                        Text(step.action).font(ZenFont.text(12.5, .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(isNext ? Color.zen.onActionPrimary : Color.zen.textBrand)
                    .padding(.horizontal, isNext ? 10 : 0).frame(height: 26)
                    .background { if isNext { Capsule().fill(Color.zen.actionPrimary) } }
                    .offset(x: hovering && !isNext ? 2 : 0)
                }
            }
            .padding(.horizontal, ZenSpace.s3).padding(.vertical, ZenSpace.s2)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .fill(hovering ? Color.zen.surfaceRaised.opacity(0.9) : Color.zen.surfaceRaised.opacity(0.0)))
            .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .strokeBorder(hovering ? Color.zen.borderOutline : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous))
        }
        .buttonStyle(SetupRowPress())
        .onHover { hovering = $0 }
        .animation(ZenMotion.calm(ZenMotion.t1), value: hovering)
        .pointerStyle(.link)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title)\(step.isOptional ? ", optional" : ""). \(step.done ? "Done" : "Not done")")
        .accessibilityHint(step.done ? "Opens where it's set" : step.detail)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SetupRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
    }
}

/// The month's Bloom on its ink tile, opening from the heart as setup gets done: the eye-catcher
/// for someone new, and a preview of what their own month will look like.
private struct BloomPreview: View {
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                let open = 0.34 + 0.66 * fraction
                PatternTile(month: PersonalMonth.demo.hours, kind: .bloom)
                    .overlay {
                        // The unopened rim, under a veil of the tile's own ink.
                        RadialGradient(colors: [.clear, Color(hex: 0x0C130C, alpha: 0.88)], center: .center,
                                       startRadius: r * open * 0.92, endRadius: r * open * 0.92 + 26)
                            .clipShape(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous))
                            .animation(ZenMotion.calm(ZenMotion.t3), value: fraction)
                    }
                    .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }
            .frame(width: 208, height: 208)
            .modifier(HoverTilt(glow: Color.zen.brandSoft, maxAngle: 8))
            .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text("Your month, as a Bloom").font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                DemoTag("Preview")
            }
            Text("Every seed is an hour. It opens as you set up, then fills with your own days.")
                .font(ZenFont.text(12)).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 208, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
