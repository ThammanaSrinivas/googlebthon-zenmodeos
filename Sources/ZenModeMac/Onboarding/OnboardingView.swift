import SwiftUI
import Albeit
import ZenAPI

/// Onboarding: the story, three questions, the day counting itself, bringing the iPhone's day
/// over, and the hand-off. Under a minute, and nothing to type except an optional join code.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var storyIndex = 0
    @State private var storyPaused = false
    @State private var storyFeeling = 0

    var body: some View {
        let step = model.step ?? .story
        ZStack {
            ZenBackdrop(tone: tone(step), glowAt: UnitPoint(x: 0.7, y: 0.42))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ZenLockup(size: 17)
                        .padding(.top, 54)
                    Spacer(minLength: ZenSpace.s6)
                    Group {
                        switch step {
                        case .story: storyColumn
                        case .seat: SeatColumn()
                        case .uses: UsesColumn()
                        case .quiet: QuietColumn()
                        case .count: CountColumn()
                        case .bring: BringColumn()
                        case .handoff: HandoffColumn()
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                    Spacer(minLength: ZenSpace.s6)
                    footer(step)
                        .padding(.bottom, 36)
                }
                .frame(width: 430, alignment: .leading)
                .padding(.leading, 56)

                ZStack {
                    switch step {
                    case .story: StoryStage(index: storyIndex, feelingIndex: $storyFeeling, model: model)
                    case .seat, .uses, .quiet: ProfileStage()
                    case .count: CountStage()
                    case .bring: PairStage()
                    case .handoff: HandoffStage()
                    }
                }
                .id(step == .seat || step == .uses || step == .quiet ? AppModel.Step.seat : step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)), removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 44)
            }
        }
        .ignoresSafeArea()
        .animation(ZenMotion.container, value: step)
        .onAppear { storyIndex = model.initialStoryIndex }
        .onKeyPress(.rightArrow) { if step == .story { advanceStory(1) }; return .handled }
        .onKeyPress(.leftArrow) { if step == .story { advanceStory(-1) }; return .handled }
    }

    private func tone(_ step: AppModel.Step) -> BackdropTone {
        switch step {
        case .story: [BackdropTone.zen, .mint, .amber][storyIndex]
        case .quiet: .twilight
        case .handoff: .zen
        default: .mint
        }
    }

    // MARK: The story

    private var storyColumn: some View {
        let card = Copy.Story.cards[storyIndex]
        return VStack(alignment: .leading, spacing: ZenSpace.s5) {
            StoryProgress(index: storyIndex, paused: storyPaused)
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                Eyebrow(card.eyebrow, color: Color.zen.textBrand)
                Text(card.title)
                    .zenType(.display)
                    .foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(card.body)
                    .zenType(.lede)
                    .foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(storyIndex)
            .transition(.opacity.combined(with: .offset(y: 8)))
            HStack(spacing: ZenSpace.s4) {
                Button(Copy.Story.start) { model.go(.seat) }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button(Copy.Story.haveCode) {
                    model.choose(seat: .campus)
                    model.go(.seat)
                }
                .buttonStyle(ZenLinkButtonStyle())
            }
            .padding(.top, ZenSpace.s2)
        }
        .onHover { storyPaused = $0 }
        .task(id: storyIndex) {
            try? await Task.sleep(for: .seconds(storyIndex == 0 ? 11 : 8))
            if !Task.isCancelled && !storyPaused { advanceStory(1) }
        }
        .animation(ZenMotion.calm(ZenMotion.t3), value: storyIndex)
    }

    private func advanceStory(_ d: Int) {
        withAnimation(ZenMotion.container) { storyIndex = (storyIndex + d + 3) % 3 }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ step: AppModel.Step) -> some View {
        if step == .story {
            Text("Use ← → to move through the story.")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption)
        } else {
            HStack(spacing: ZenSpace.s4) {
                let steps = AppModel.Step.allCases.dropFirst()
                CellRow(steps.map { $0.rawValue < step.rawValue ? .on : ($0 == step ? .reward : .empty) })
                    .accessibilityElement()
                    .accessibilityLabel("Step \(step.rawValue) of \(steps.count)")
                if step != .handoff {
                    Button("Back") { model.back() }
                        .buttonStyle(ZenLinkButtonStyle())
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                }
                Spacer()
                if model.isDemo { DemoTag() }
            }
        }
    }
}

/// Three segments of cells; the current one fills as its card plays.
private struct StoryProgress: View {
    let index: Int
    let paused: Bool
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: paused)) { tl in
            let duration: Double = index == 0 ? 11 : 8
            let fraction = min(tl.date.timeIntervalSince(startedAt) / duration, 1)
            HStack(spacing: ZenSpace.s3) {
                ForEach(0..<3, id: \.self) { i in
                    let filled = i < index ? 6 : (i == index ? Int((fraction * 6).rounded(.down)) + 1 : 0)
                    CellRow(filled: min(filled, 6), of: 6, size: 8)
                }
            }
        }
        .onChange(of: index) { _, _ in startedAt = Date() }
        .accessibilityElement()
        .accessibilityLabel("Story card \(index + 1) of 3")
    }
}

// MARK: - Make it yours

private struct QuestionHeader: View {
    let eyebrow: String, title: String
    var body_: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(eyebrow, color: Color.zen.textBrand)
            Text(title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let body_ {
                Text(body_).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A large, glassy choice row. Selected: brand tint and a filled cell.
struct ChoiceRow: View {
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenSpace.s4) {
                RoundedRectangle(cornerRadius: ZenRadius.cell + 1, style: .continuous)
                    .fill(selected ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: ZenRadius.cell + 1, style: .continuous)
                            .strokeBorder(selected ? .clear : Color.zen.borderOutline, lineWidth: 1)
                    }
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(caption).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ZenSpace.s4)
            .padding(.vertical, ZenSpace.s3 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(selected ? .regular.tint(Color.zen.brandSoft.opacity(0.35)).interactive() : .regular.interactive(),
                         in: .rect(cornerRadius: ZenRadius.lg))
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title). \(caption)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct SeatColumn: View {
    @Environment(AppModel.self) private var model
    @FocusState private var codeFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Seat.eyebrow, title: Copy.Seat.title)
            VStack(spacing: ZenSpace.s2) {
                ForEach(Profile.Seat.allCases, id: \.self) { seat in
                    let o = Copy.Seat.option(seat)
                    ChoiceRow(title: o.title, caption: o.caption, selected: model.profile.seat == seat) {
                        withAnimation(ZenMotion.container) { model.choose(seat: seat) }
                        if seat != .personal { codeFocused = true }
                    }
                }
            }
            if model.profile.seat != .personal {
                codeField
                    .transition(.opacity.combined(with: .offset(y: -6)))
            } else {
                Button("Continue") { model.next() }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .animation(ZenMotion.container, value: model.profile.seat)
    }

    @ViewBuilder
    private var codeField: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                TextField(Copy.Seat.codeLabel, text: $model.codeText, prompt: Text("ZEN4HS"))
                    .textFieldStyle(.plain)
                    .font(ZenFont.number(22)).tracking(3)
                    .foregroundStyle(Color.zen.textHeading)
                    .focused($codeFocused)
                    .onSubmit { model.checkCode() }
                    .padding(.horizontal, ZenSpace.s4)
                    .frame(width: 190, height: 48)
                    .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.md))
                    .accessibilityLabel(Copy.Seat.codeLabel)
                    .accessibilityHint(Copy.Seat.codePrompt)
                switch model.codeState {
                case .found(let p):
                    Button("Join \(p.name)") { model.joinCohort() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                case .checking:
                    ProgressView().controlSize(.small).accessibilityLabel("Checking the code")
                default:
                    Button(Copy.Seat.check) { model.checkCode() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(model.codeText.count < JoinCode.length)
                        .keyboardShortcut(.defaultAction)
                }
            }
            switch model.codeState {
            case .found(let p):
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(p.name) · \(p.organisation) · \(p.memberCount) people")
                        .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(Copy.Seat.privacy(p.kind)).zenType(.caption).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZenRadius.md).fill(Color.zen.surfaceTint.opacity(0.8)))
            case .failed(let message):
                Text(message).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
                    .accessibilityAddTraits(.updatesFrequently)
            default:
                Text(Copy.Seat.codePrompt).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            HStack(spacing: ZenSpace.s4) {
                Button(Copy.Seat.skipCode) { model.next() }.buttonStyle(ZenLinkButtonStyle())
                if model.isDemo { Text(Copy.Seat.demoCode).zenType(.caption).foregroundStyle(Color.zen.accentRewardText) }
            }
        }
    }
}

private struct UsesColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Uses.eyebrow, title: Copy.Uses.title, body_: Copy.Uses.body)
            FlowLayout(spacing: ZenSpace.s2, lineSpacing: ZenSpace.s2) {
                ForEach(Profile.Use.allCases, id: \.self) { use in
                    let on = model.profile.uses.contains(use)
                    Button {
                        withAnimation(ZenMotion.container) { model.toggle(use: use) }
                    } label: {
                        Text(Copy.Uses.label(use))
                            .font(ZenFont.text(14, .semibold))
                            .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textHeading)
                            .padding(.horizontal, ZenSpace.s4)
                            .frame(height: 38)
                            .background { if on { Capsule().fill(Color.zen.actionPrimary) } }
                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            Button("Continue") { model.next() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.profile.uses.isEmpty)
        }
    }
}

private struct QuietColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Quiet.eyebrow, title: Copy.Quiet.title, body_: Copy.Quiet.body)
            VStack(spacing: ZenSpace.s2) {
                ForEach(Copy.Quiet.presets, id: \.1) { preset in
                    ChoiceRow(title: preset.1, caption: preset.2, selected: model.profile.quiet == preset.0) {
                        model.choose(quiet: preset.0)
                    }
                }
            }
            Button("Continue") { model.next() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Let it count, bring your day, hand-off

private struct CountColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Count.eyebrow, title: Copy.Count.title, body_: Copy.Count.body)
            HStack(spacing: ZenSpace.s4) {
                if model.accessibilityTrusted {
                    Label(Copy.Count.on, systemImage: "checkmark.circle.fill")
                        .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textBrand)
                    Button("Continue") { model.next() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(Copy.Count.allow) { model.requestAccessibility() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button(Copy.Count.later) { model.next() }.buttonStyle(ZenLinkButtonStyle())
                }
            }
        }
    }
}

private struct BringColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Bring.eyebrow, title: Copy.Bring.title, body_: Copy.Bring.body)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Button(Copy.Bring.google) { model.signInWithGoogle() }
                    .buttonStyle(ZenSecondaryButtonStyle())
                Button(Copy.Bring.explore) { model.finishOnboarding() }
                    .buttonStyle(ZenLinkButtonStyle())
            }
            if case .failed(let message) = model.pairState {
                Text(message).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
            }
            if model.pairState == .approving {
                ProgressView().controlSize(.small).accessibilityLabel("Signing in")
            }
        }
    }
}

private struct HandoffColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Handoff.kicker, title: Copy.Handoff.title,
                           body_: model.snapshot?.week.statusLine)
            Button(Copy.Handoff.open) { model.finishOnboarding() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}
