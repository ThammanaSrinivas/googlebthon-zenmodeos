import SwiftUI
import AuthenticationServices
import Albeit
import ZenAPI

/// Onboarding: the story, three questions, the day counting itself, signing in (as a team member or
/// the person who runs the team), and the hand-off. Under a minute, and nothing to type except an
/// optional join code. Return continues, Escape or ⌘[ goes back.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var storyIndex = 0
    @State private var storyPaused = false
    @State private var storyFeeling = 0
    /// The step on screen. It follows the model's one update later, so the leaving step already
    /// knows which way to slide.
    @State private var shown: AppModel.Step = .story
    @State private var forward = true

    var body: some View {
        let step = shown
        ZStack {
            ZenBackdrop(tone: tone(step), glowAt: UnitPoint(x: 0.7, y: 0.42))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ZenLockup(size: 17)
                        .padding(.top, 54)
                        .accessibilityLabel(Copy.product)
                    Spacer(minLength: ZenSpace.s6)
                    column(step)
                        .id(step)
                        .transition(columnTransition)
                    Spacer(minLength: ZenSpace.s6)
                    footer(step)
                        .padding(.bottom, 36)
                }
                .frame(width: 430, alignment: .leading)
                .padding(.leading, 56)

                stage(step)
                    .id(stageKey(step))
                    .transition(stageTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 44)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t3), value: storyIndex)
        .onAppear {
            storyIndex = model.initialStoryIndex
            shown = model.step ?? .story
            #if DEBUG
            // Debug renders: ZEN_SIGNIN_ROLE=admin picks "I run a team" on the sign-in step.
            if ProcessInfo.processInfo.environment["ZEN_SIGNIN_ROLE"] == "admin" { model.choose(role: .admin) }
            #endif
        }
        .onChange(of: model.step) { old, new in
            guard let new, new != shown else { return }
            forward = new.rawValue >= (old?.rawValue ?? shown.rawValue)
            Task { @MainActor in
                withAnimation(reduceMotion ? nil : ZenMotion.container) { shown = new }
            }
        }
        .onKeyPress(.rightArrow) { if step == .story { advanceStory(1) }; return step == .story ? .handled : .ignored }
        .onKeyPress(.leftArrow) { if step == .story { advanceStory(-1) }; return step == .story ? .handled : .ignored }
        // Escape and ⌘[ go back a step (not from the story, nor once signed in).
        .background {
            Group {
                Button("") { goBack() }.keyboardShortcut(.cancelAction)
                Button("") { goBack() }.keyboardShortcut("[", modifiers: .command)
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }

    private func goBack() {
        guard let s = model.step, s != .story, s != .handoff else { return }
        model.back()
    }

    // MARK: Steps

    @ViewBuilder
    private func column(_ step: AppModel.Step) -> some View {
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

    @ViewBuilder
    private func stage(_ step: AppModel.Step) -> some View {
        switch step {
        case .story: StoryStage(index: storyIndex, feelingIndex: $storyFeeling, model: model)
        case .seat, .uses, .quiet: ProfileStage()
        case .count: CountStage()
        case .bring where model.qrPairing: PairStage()
        case .bring, .handoff: DeviceDuoStage(handoff: step == .handoff)
        }
    }

    /// Stages that stay put between steps: the profile preview across the three questions, and the
    /// two devices from signing in to the hand-off (where Zeno makes the trip).
    private func stageKey(_ step: AppModel.Step) -> Int {
        switch step {
        case .seat, .uses, .quiet: 1
        case .bring where !model.qrPairing: 2
        case .handoff: 2
        default: 10 + step.rawValue
        }
    }

    /// A short, direction-aware slide: forward comes in from the right, back from the left.
    private var columnTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let d: CGFloat = forward ? 40 : -40
        return .asymmetric(
            insertion: .modifier(active: SoftEntry(x: d, blur: 6), identity: SoftEntry(x: 0, blur: 0)),
            removal: .modifier(active: SoftEntry(x: -d * 0.6, blur: 4), identity: SoftEntry(x: 0, blur: 0)))
    }

    private var stageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let d: CGFloat = forward ? 60 : -60
        return .asymmetric(
            insertion: .modifier(active: SoftEntry(x: d, blur: 10, scale: 0.97), identity: SoftEntry(x: 0, blur: 0)),
            removal: .modifier(active: SoftEntry(x: -d * 0.5, blur: 8, scale: 0.98), identity: SoftEntry(x: 0, blur: 0)))
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
            StoryProgress(index: storyIndex, paused: storyPaused || reduceMotion)
                .rise(0)
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
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .modifier(active: SoftEntry(x: 0, y: 10, blur: 6), identity: SoftEntry(x: 0, blur: 0)),
                removal: .opacity))
            .rise(1)
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
            .rise(2)
        }
        .onHover { storyPaused = $0 }
        .task(id: storyIndex) {
            try? await Task.sleep(for: .seconds(storyIndex == 0 ? 11 : 8))
            if !Task.isCancelled && !storyPaused { advanceStory(1) }
        }
    }

    private func advanceStory(_ d: Int) {
        withAnimation(reduceMotion ? nil : ZenMotion.container) { storyIndex = (storyIndex + d + 3) % 3 }
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(_ step: AppModel.Step) -> some View {
        if step == .story {
            HStack(spacing: ZenSpace.s2) {
                KeyCap("←")
                KeyCap("→")
                Text("move through the story").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                Text("·").foregroundStyle(Color.zen.textCaption)
                KeyCap("return")
                Text("starts").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Use the left and right arrow keys to move through the story. Return starts.")
        } else {
            HStack(spacing: ZenSpace.s5) {
                StepTrack(current: step.rawValue, total: AppModel.Step.allCases.count - 1, label: stepLabel(step))
                Spacer(minLength: 0)
                if step != .handoff {
                    Button {
                        model.back()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(ZenLinkButtonStyle())
                    .help("Back (Esc or ⌘[)")
                    .accessibilityHint("Goes to the previous step")
                }
                if model.isDemo { DemoTag() }
            }
        }
    }

    private func stepLabel(_ step: AppModel.Step) -> String {
        switch step {
        case .story: ""
        case .seat: Copy.Seat.step
        case .uses: Copy.Uses.step
        case .quiet: Copy.Quiet.step
        case .count: Copy.Count.step
        case .bring: Copy.Bring.step
        case .handoff: Copy.Handoff.step
        }
    }
}

// MARK: - Motion

/// Offset, blur and scale together: the soft way things arrive and leave in onboarding.
struct SoftEntry: ViewModifier {
    var x: CGFloat
    var y: CGFloat = 0
    var blur: CGFloat
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .offset(x: x, y: y)
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(blur == 0 ? 1 : 0)
    }
}

/// Staggered entrances: each part of a step rises into place a beat after the one before.
private struct Rise: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        let done = up || reduceMotion
        content
            .opacity(done ? 1 : 0)
            .offset(y: done ? 0 : 12)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(ZenMotion.settle(ZenMotion.t3).delay(0.08 + 0.07 * Double(order))) { up = true }
            }
    }
}

extension View {
    fileprivate func rise(_ order: Int) -> some View { modifier(Rise(order: order)) }
}

// MARK: - Progress

/// Where you are: a capsule track with the current step drawn long and lit, its number in Departure
/// Mono and its name beside it. VoiceOver reads "Step 3 of 6: Quiet hours".
struct StepTrack: View {
    let current: Int
    let total: Int
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ZenSpace.s3) {
            HStack(spacing: 5) {
                ForEach(1...total, id: \.self) { i in
                    segment(i)
                }
            }
            HStack(spacing: 6) {
                Text(verbatim: "\(current)/\(total)")
                    .font(ZenFont.number(11.5))
                    .foregroundStyle(Color.zen.textHeading)
                    .fixedSize()
                Text(label)
                    .font(ZenFont.text(12.5, .medium))
                    .foregroundStyle(Color.zen.textCaption)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize()
        .animation(reduceMotion ? nil : ZenMotion.container, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total): \(label)")
    }

    @ViewBuilder
    private func segment(_ i: Int) -> some View {
        let done = i < current, now = i == current
        Capsule()
            .fill(now ? AnyShapeStyle(LinearGradient(colors: [Color.zen.brandFill, Color.zen.brandSoft], startPoint: .leading, endPoint: .trailing))
                  : AnyShapeStyle(done ? Color.zen.brandFill : Color.zen.textHeading.opacity(0.14)))
            .frame(width: now ? 34 : (done ? 14 : 10), height: 6)
            .overlay(alignment: .trailing) {
                if now {
                    // The glowing head of the line.
                    Circle().fill(Color.zen.brandSoft).frame(width: 6, height: 6)
                        .shadow(color: Color.zen.brandSoft.opacity(0.9), radius: 5)
                }
            }
            .shadow(color: now ? Color.zen.brandSoft.opacity(0.45) : .clear, radius: 6, y: 0)
    }
}

/// Three thin lines that fill as each story card plays, with a lit head on the one playing.
private struct StoryProgress: View {
    let index: Int
    let paused: Bool
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { tl in
            let duration: Double = index == 0 ? 11 : 8
            let fraction = progress(at: tl.date, duration: duration)
            HStack(spacing: ZenSpace.s2) {
                ForEach(0..<3, id: \.self) { i in
                    let f: Double = i < index ? 1 : (i == index ? fraction : 0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.zen.textHeading.opacity(0.14))
                            Capsule()
                                .fill(LinearGradient(colors: [Color.zen.brandFill, Color.zen.brandSoft], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(5, geo.size.width * f))
                                .shadow(color: i == index ? Color.zen.brandSoft.opacity(0.6) : .clear, radius: 5)
                                .opacity(f > 0 ? 1 : 0)
                        }
                    }
                    .frame(width: 44, height: 5)
                }
            }
        }
        .onChange(of: index) { _, _ in startedAt = Date() }
        .accessibilityElement()
        .accessibilityLabel("Story card \(index + 1) of 3")
    }

    private func progress(at date: Date, duration: Double) -> Double {
        min(date.timeIntervalSince(startedAt) / duration, 1)
    }
}

/// A key, drawn small: for the keyboard hints.
private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(ZenFont.text(11, .semibold))
            .foregroundStyle(Color.zen.textBody)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.zen.borderOutline, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 0, y: 1)
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

/// A large, glassy choice: a lit symbol, a title and a caption, and a radio that fills with a check
/// when picked (never colour alone). Hover lifts it, pressing sinks it, keyboard focus rings it.
struct ChoiceRow: View {
    let title: String
    let caption: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenSpace.s4) {
                if let symbol { SymbolBadge(symbol: symbol, lit: selected) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(caption).zenType(.caption).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Radio(on: selected)
            }
            .padding(.horizontal, ZenSpace.s4)
            .padding(.vertical, ZenSpace.s3)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .buttonStyle(ChoiceButtonStyle(selected: selected, radius: ZenRadius.lg))
        .accessibilityLabel("\(title). \(caption)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The look of every choice in onboarding: glass, tinted green when picked, with hover, press and focus.
struct ChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    var radius: CGFloat = ZenRadius.lg

    func makeBody(configuration: Configuration) -> some View {
        ChoiceBody(configuration: configuration, selected: selected, radius: radius)
    }

    private struct ChoiceBody: View {
        let configuration: Configuration
        let selected: Bool
        let radius: CGFloat
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var scheme
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let sheen = scheme == .dark ? 0.07 : (selected ? 0.16 : 0.22)
            configuration.label
                .background {
                    ZStack {
                        shape.fill(selected ? Color.zen.surfaceTint.opacity(0.9) : Color.zen.surfaceRaised.opacity(hovering ? 0.75 : 0.5))
                        // A key light along the top edge: lit, never a flat fill.
                        shape.fill(LinearGradient(colors: [.white.opacity(sheen), .clear], startPoint: .top, endPoint: .center))
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
                .overlay {
                    shape.strokeBorder(selected ? Color.zen.brandFill : Color.zen.borderOutline.opacity(hovering ? 1 : 0.7),
                                       lineWidth: selected ? 1.5 : 1)
                }
                .overlay {
                    // Keyboard focus: a clear ring outside the edge.
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .strokeBorder(Color.zen.textBrand, lineWidth: 2)
                        .padding(-4)
                        .opacity(focused ? 1 : 0)
                }
                .shadow(color: .black.opacity(hovering ? 0.08 : 0.03), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
                .scaleEffect(configuration.isPressed ? 0.985 : (hovering && !reduceMotion ? 1.008 : 1))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 && enabled }
                .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
                .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
                .animation(ZenMotion.container, value: selected)
                .focusEffectDisabled()
        }
    }
}

/// A symbol in a small lit tile: green and glowing when its choice is picked.
private struct SymbolBadge: View {
    let symbol: String
    let lit: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(lit ? AnyShapeStyle(LinearGradient(colors: [Color.zen.brandSoft, Color.zen.brandFill], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.zen.textHeading.opacity(0.06)))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(lit ? 0.35 : 0), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lit ? Color(hex: 0x0B2410) : Color.zen.textBody)
        }
        .frame(width: 34, height: 34)
        .shadow(color: lit ? Color.zen.brandSoft.opacity(0.45) : .clear, radius: 8, y: 2)
        .accessibilityHidden(true)
    }
}

/// A radio that fills green with a check when on.
private struct Radio: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Color.zen.brandFill : Color.zen.textCaption.opacity(0.8), lineWidth: 1.5)
            if on {
                Circle().fill(Color.zen.brandFill)
                Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct SeatColumn: View {
    @Environment(AppModel.self) private var model
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Seat.eyebrow, title: Copy.Seat.title)
                .rise(0)
            VStack(spacing: ZenSpace.s2) {
                ForEach(Array(Profile.Seat.allCases.enumerated()), id: \.element) { i, seat in
                    let o = Copy.Seat.option(seat)
                    ChoiceRow(title: o.title, caption: o.caption, symbol: Self.symbol(seat), selected: model.profile.seat == seat) {
                        withAnimation(ZenMotion.container) { model.choose(seat: seat) }
                        if seat != .personal { codeFocused = true }
                    }
                    .rise(1 + i)
                }
            }
            Group {
                if model.profile.seat != .personal {
                    codeField
                        .transition(.opacity.combined(with: .offset(y: -6)))
                } else {
                    Button("Continue") { model.next() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .rise(4)
        }
        .animation(ZenMotion.container, value: model.profile.seat)
    }

    static func symbol(_ seat: Profile.Seat) -> String {
        switch seat {
        case .personal: "person.fill"
        case .campus: "graduationcap.fill"
        case .team: "person.3.fill"
        }
    }

    @ViewBuilder
    private var codeField: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                CodeField(text: $model.codeText, focused: $codeFocused) { model.checkCode() }
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
                Label(message, systemImage: "exclamationmark.circle")
                    .zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
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

/// The six-character join code, in Departure Mono on glass, with a focus ring.
private struct CodeField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        TextField(Copy.Seat.codeLabel, text: $text, prompt: Text("ZEN4HS").foregroundStyle(Color.zen.textCaption))
            .textFieldStyle(.plain)
            .font(ZenFont.number(22)).tracking(3)
            .foregroundStyle(Color.zen.textHeading)
            .focused(focused)
            .onSubmit(submit)
            .padding(.horizontal, ZenSpace.s4)
            .frame(width: 190, height: 48)
            .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceRaised.opacity(0.7)))
            .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                    .strokeBorder(focused.wrappedValue ? Color.zen.textBrand : Color.zen.borderOutline, lineWidth: focused.wrappedValue ? 2 : 1)
            }
            .accessibilityLabel(Copy.Seat.codeLabel)
            .accessibilityHint(Copy.Seat.codePrompt)
    }
}

private struct UsesColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Uses.eyebrow, title: Copy.Uses.title, body_: Copy.Uses.body)
                .rise(0)
            FlowLayout(spacing: ZenSpace.s2, lineSpacing: ZenSpace.s2) {
                ForEach(Profile.Use.allCases, id: \.self) { use in
                    let on = model.profile.uses.contains(use)
                    Button {
                        withAnimation(ZenMotion.container) { model.toggle(use: use) }
                    } label: {
                        HStack(spacing: 6) {
                            if on {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                            }
                            Text(Copy.Uses.label(use)).font(ZenFont.text(14, .semibold))
                        }
                        .foregroundStyle(Color.zen.textHeading)
                        .padding(.horizontal, ZenSpace.s4)
                        .frame(height: 38)
                    }
                    .buttonStyle(ChoiceButtonStyle(selected: on, radius: 19))
                    .accessibilityLabel(Copy.Uses.label(use))
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .rise(1)
            Button("Continue") { model.next() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.profile.uses.isEmpty)
                .rise(2)
        }
    }
}

private struct QuietColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Quiet.eyebrow, title: Copy.Quiet.title, body_: Copy.Quiet.body)
                .rise(0)
            VStack(spacing: ZenSpace.s2) {
                ForEach(Array(Copy.Quiet.presets.enumerated()), id: \.element.1) { i, preset in
                    ChoiceRow(title: preset.1, caption: preset.2, symbol: Self.symbol(preset.0),
                              selected: model.profile.quiet == preset.0) {
                        model.choose(quiet: preset.0)
                    }
                    .rise(1 + i)
                }
            }
            Button("Continue") { model.next() }
                .buttonStyle(ZenPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .rise(4)
        }
    }

    static func symbol(_ q: QuietHours) -> String {
        switch q {
        case .classHours: "book.closed.fill"
        case .workHours: "briefcase.fill"
        default: "moon.stars.fill"
        }
    }
}

// MARK: - Let it count, sign in, hand-off

private struct CountColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Count.eyebrow, title: Copy.Count.title, body_: Copy.Count.body)
                .rise(0)
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
            .rise(1)
        }
    }
}

/// Sign in: first who you are (the employee or the employer), then Apple or Google.
private struct BringColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Bring.eyebrow,
                           title: model.qrPairing ? Copy.Bring.title : Copy.Bring.signInTitle,
                           body_: model.qrPairing ? Copy.Bring.body : Copy.Bring.signInBody)
                .rise(0)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(Copy.Bring.roleQuestion)
                HStack(alignment: .top, spacing: ZenSpace.s2) {
                    ForEach(AppModel.SignInRole.allCases, id: \.self) { role in
                        RoleCard(role: role, selected: model.signInRole == role) { model.choose(role: role) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .rise(1)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                    request.nonce = model.prepareAppleRequest()
                } onCompletion: { result in
                    if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                        model.signInWithApple(identityToken: credential.identityToken, fullName: credential.fullName)
                    }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(width: 260, height: 40)
                .clipShape(Capsule())
                .id(scheme)
                .accessibilityHint(model.signInRole == .admin ? "Signs you in as the team's admin" : "Signs you in as a team member")
                HStack(spacing: ZenSpace.s4) {
                    Button(Copy.Bring.google) { model.signInWithGoogle() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .accessibilityHint(model.signInRole == .admin ? "Signs you in as the team's admin" : "Signs you in as a team member")
                    Button(Copy.Bring.explore) { model.finishOnboarding() }
                        .buttonStyle(ZenLinkButtonStyle())
                }
            }
            .rise(2)
            if case .failed(let message) = model.pairState {
                Label(message, systemImage: "exclamationmark.circle")
                    .zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
            }
            if model.pairState == .approving {
                HStack(spacing: ZenSpace.s2) {
                    ProgressView().controlSize(.small)
                    Text("Signing in…").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One way in: a tall glass card with a lit symbol, the role and what it means.
private struct RoleCard: View {
    let role: AppModel.SignInRole
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let copy = Copy.Bring.role(role)
        Button(action: action) {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(alignment: .top) {
                    SymbolBadge(symbol: copy.symbol, lit: selected)
                    Spacer(minLength: 0)
                    Radio(on: selected)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(copy.caption).zenType(.caption).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ZenSpace.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(ChoiceButtonStyle(selected: selected, radius: ZenRadius.xl))
        .accessibilityLabel("\(copy.title). \(copy.caption)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct HandoffColumn: View {
    @Environment(AppModel.self) private var model
    @FocusState private var codeFocused: Bool

    var body: some View {
        let path = model.handoffPath
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            QuestionHeader(eyebrow: Copy.Handoff.kicker, title: Copy.Handoff.title,
                           body_: model.snapshot?.week.statusLine)
                .rise(0)
            Group {
                switch path {
                case .member(joined: false): joinPanel
                case .member(joined: true): EmptyView()
                case .adminTeam(let name): adminPanel(name)
                case .adminCreate: createPanel
                }
            }
            .rise(1)
            HStack(spacing: ZenSpace.s4) {
                if case .adminTeam = path {
                    Button(Copy.Handoff.openAdmin) { model.finishOnboarding() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(codeFocused ? nil : .defaultAction)
                } else {
                    Button(Copy.Handoff.open) { model.finishOnboarding() }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .keyboardShortcut(codeFocused ? nil : .defaultAction)
                }
            }
            .rise(2)
        }
        .animation(ZenMotion.container, value: path)
    }

    private var joinPanel: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.Handoff.joinTitle).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(Copy.Handoff.joinBody).zenType(.caption).foregroundStyle(Color.zen.textBody)
            }
            HStack(spacing: ZenSpace.s3) {
                CodeField(text: $model.codeText, focused: $codeFocused) {
                    if JoinCode(model.codeText) != nil { model.joinCohort() } else { model.finishOnboarding() }
                }
                if model.codeState == .checking {
                    ProgressView().controlSize(.small).accessibilityLabel("Joining")
                } else {
                    Button(Copy.Handoff.join) { model.joinCohort() }
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .disabled(model.codeText.count < JoinCode.length)
                }
            }
            if case .failed(let message) = model.codeState {
                Label(message, systemImage: "exclamationmark.circle").zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
            } else if model.isDemo {
                Text(Copy.Seat.demoCode).zenType(.caption).foregroundStyle(Color.zen.accentRewardText)
            }
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
    }

    private func adminPanel(_ name: String) -> some View {
        HStack(alignment: .top, spacing: ZenSpace.s3) {
            SymbolBadge(symbol: "person.3.fill", lit: true)
            Text(Copy.Handoff.adminReady(name)).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous).strokeBorder(Color.zen.brandFill.opacity(0.45), lineWidth: 1))
    }

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(alignment: .top, spacing: ZenSpace.s3) {
                SymbolBadge(symbol: "globe", lit: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Copy.Handoff.createTitle).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(TeamWeb.base == nil ? Copy.Handoff.createLater : Copy.Handoff.createBody)
                        .zenType(.caption).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let base = TeamWeb.base {
                Button {
                    NSWorkspace.shared.open(base.appending(path: "admin"))
                } label: {
                    Label(Copy.Handoff.createTitle, systemImage: "arrow.up.right")
                }
                .buttonStyle(ZenSecondaryButtonStyle())
                .accessibilityHint("Opens in your browser")
            }
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
    }
}
