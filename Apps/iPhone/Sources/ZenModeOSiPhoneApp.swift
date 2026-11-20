import SwiftUI
import AuthenticationServices
import Albeit
import ZenAPI
import ZenMock

/// The iPhone app, first cut: Zeno says hello and Sign in with Apple runs for real, so the
/// capability and the backend hand-off can be checked on a device. Onboarding, the Island and
/// Today follow on this shell.
@main
struct ZenModeOSiPhoneApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            PhoneHelloView(model: model)
                // Google sign-in returns through the REVERSED_CLIENT_ID URL scheme.
                .onOpenURL { url in _ = model.auth.handle(url: url) }
        }
    }
}

@MainActor
@Observable
final class PhoneModel {
    // TODO(buildathon): ZenCorePrivate's AuthService once the private package lands.
    let auth: any AuthService = FakeAuth()
    private(set) var nonce = SignInNonce.make()
    private(set) var user: ZenUser?
    private(set) var failed = false

    func prepareAppleRequest() -> String {
        nonce = SignInNonce.make()
        return nonce.sha256
    }

    func finishApple(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            failed = true
            return
        }
        let raw = nonce.raw
        Task {
            do { user = try await self.auth.signInWithApple(identityToken: token, rawNonce: raw, fullName: credential.fullName) }
            catch { failed = true }
        }
    }
}

struct PhoneHelloView: View {
    let model: PhoneModel
    @State private var feeling: ZenoFeeling = .happy

    var body: some View {
        ZStack {
            ZenBackdrop(tone: .for(feeling), glowAt: UnitPoint(x: 0.5, y: 0.32))
                .ignoresSafeArea()
            VStack(spacing: ZenSpace.s6) {
                Spacer()
                ZenoView(feeling).frame(width: 220)
                VStack(spacing: ZenSpace.s3) {
                    Text(model.user.map { "Hi, \($0.firstName). Your day is here." } ?? "Hi, I'm Zeno.")
                        .zenType(.headline)
                        .foregroundStyle(Color.zen.textHeading)
                        .multilineTextAlignment(.center)
                    Text("Your day counts itself. One score, every screen.")
                        .zenType(.lede)
                        .foregroundStyle(Color.zen.textBody)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                if model.user == nil {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName]
                        request.nonce = model.prepareAppleRequest()
                    } onCompletion: { result in
                        model.finishApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    if model.failed {
                        Text("Sign in with Apple didn't finish. Try again.")
                            .zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
                    }
                }
                DemoTag()
            }
            .padding(.horizontal, ZenSpace.s6)
            .padding(.bottom, ZenSpace.s6)
        }
        .preferredColorScheme(.light)
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
