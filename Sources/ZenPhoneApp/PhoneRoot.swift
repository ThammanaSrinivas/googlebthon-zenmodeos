import AuthenticationServices
import SwiftUI
import Albeit
import ZenAPI

/// The iPhone app's root. Signed out: Zeno says hello, with Apple and Google. Signed in: the
/// combined Zen Score, live, the week, and approving a Mac that wants to sign in as you.
public struct ZenPhoneRoot: View {
    @State private var model = PhoneModel(services: ZenPhoneBackend.make())

    public init() {}

    public var body: some View {
        ZStack {
            ZenBackdrop(tone: .zen, glowAt: UnitPoint(x: 0.5, y: 0.3))
                .ignoresSafeArea()
            if let user = model.user {
                SignedInView(model: model, user: user)
                    .transition(.opacity)
            } else {
                HelloView(model: model)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .animation(ZenMotion.container, value: model.user)
        .onOpenURL { model.handle(url: $0) }
        .onAppear { model.start() }
        .sheet(isPresented: Binding(get: { if case .confirm = model.pairing { true } else { false } },
                                    set: { if !$0, case .confirm = model.pairing { model.cancelPairing() } })) {
            if case .confirm(let code) = model.pairing { ApproveSheet(model: model, code: code) }
        }
    }
}

private struct HelloView: View {
    let model: PhoneModel
    @State private var feeling: ZenoFeeling = .happy

    var body: some View {
        VStack(spacing: ZenSpace.s6) {
            Spacer()
            ZenoView(feeling).frame(width: 220)
            VStack(spacing: ZenSpace.s3) {
                Text(PhoneCopy.hello).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                Text(PhoneCopy.lede).zenType(.lede).foregroundStyle(Color.zen.textBody).multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: ZenSpace.s3) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                    request.nonce = model.prepareAppleRequest()
                } onCompletion: { model.finishApple($0) }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())
                Button(PhoneCopy.google) { model.signInWithGoogle() }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                if model.signingIn { ProgressView().accessibilityLabel("Signing in") }
                if let error = model.signInError {
                    Text(error).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
                }
                if model.services.isDemo { DemoTag() }
            }
        }
        .padding(.horizontal, ZenSpace.s6)
        .padding(.bottom, ZenSpace.s6)
        .task {
            let cycle: [ZenoFeeling] = [.happy, .pleasant, .curious, .proud, .sleepy]
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                i = (i + 1) % cycle.count
                feeling = cycle[i]
            }
        }
    }
}

private struct SignedInView: View {
    @Bindable var model: PhoneModel
    let user: ZenUser

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("ZenMode OS · today")
                        Text("Hi, \(user.firstName).").zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    }
                    Spacer()
                    ZenoView(model.snapshot?.score.isGoodDay == true ? .happy : .calm).frame(width: 64)
                }
                scoreCard
                pairCard
                HStack {
                    if model.services.isDemo { DemoTag() }
                    Spacer()
                    Button("Sign out") { model.signOut() }.buttonStyle(ZenLinkButtonStyle())
                }
            }
            .padding(ZenSpace.s5)
        }
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow("Zen Score · every screen")
            if let snap = model.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    ScoreText(snap.score.text, size: 72)
                    Text("/10").font(ZenFont.number(16)).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zen Score \(snap.score.text) out of 10")
                Text(snap.week.statusLine).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                CellRow(snap.week.days.enumerated().map { i, d in
                    guard let d else { return .empty }
                    return snap.week.winningDayIndex == i ? .reward : (d.isGoodDay ? .on : .empty)
                }, size: 14)
                ForEach(snap.devices) { d in
                    HStack {
                        Image(systemName: d.kind == .iPhone ? "iphone" : "laptopcomputer").frame(width: 20)
                        Text(d.name).font(ZenFont.text(14, .semibold))
                        Spacer()
                        Text(d.detail).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                    .foregroundStyle(Color.zen.textHeading)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text(PhoneCopy.noScore).zenType(.body).foregroundStyle(Color.zen.textBody)
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private var pairCard: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Text(PhoneCopy.pairTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(PhoneCopy.pairBody).zenType(.body).foregroundStyle(Color.zen.textBody)
            HStack(spacing: ZenSpace.s3) {
                TextField("K4M7QX", text: $model.codeText)
                    .font(ZenFont.number(22)).tracking(3)
                    .codeKeyboard()
                    .padding(.horizontal, ZenSpace.s4).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: ZenRadius.md).fill(Color.zen.surfaceRaised))
                    .accessibilityLabel("Code from your Mac")
                Button("Next") { model.reviewCode() }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(model.codeText.count < JoinCode.length)
            }
            switch model.pairing {
            case .approving: ProgressView().accessibilityLabel("Approving")
            case .approved: Text(PhoneCopy.approved).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textBrand)
            case .failed(let m): Text(m).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
            default: EmptyView()
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }
}

/// "A Mac wants to sign in as you": the one moment pairing asks for a decision.
private struct ApproveSheet: View {
    let model: PhoneModel
    let code: JoinCode

    var body: some View {
        VStack(spacing: ZenSpace.s5) {
            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 44)).foregroundStyle(Color.zen.textBrand)
                .accessibilityHidden(true)
            Text(PhoneCopy.pairConfirmTitle).zenType(.title).foregroundStyle(Color.zen.textHeading).multilineTextAlignment(.center)
            Text(code.display).font(ZenFont.number(28)).tracking(4).foregroundStyle(Color.zen.textHeading)
            Text(PhoneCopy.pairConfirmBody).zenType(.body).foregroundStyle(Color.zen.textBody).multilineTextAlignment(.center)
            Button(PhoneCopy.approve) { model.approve(code) }
                .buttonStyle(ZenPrimaryButtonStyle())
            Button(PhoneCopy.notMe) { model.cancelPairing() }
                .buttonStyle(ZenLinkButtonStyle())
        }
        .padding(ZenSpace.s6)
        .presentationDetents([.medium])
    }
}

private extension View {
    /// Capitals and no autocorrect for a pairing code; the Mac build of this library has no keyboard.
    func codeKeyboard() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.characters).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}
