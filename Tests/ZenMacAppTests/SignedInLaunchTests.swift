import Testing
import ZenAPI
@testable import ZenMacApp

@Suite("App: opening again when already signed in")
@MainActor
struct SignedInLaunchTests {
    // resume(signedIn:) itself starts the day sync on the real defaults (see AppModelFlowTests),
    // so it's covered through the decision it makes.
    @Test("Signed in on the first card: Today. Signed out, or past the first card: it stays")
    func stays() {
        #expect(AppModel.launchStage(.onboarding(.story), signedIn: true) == .today)
        #expect(AppModel.launchStage(.onboarding(.story), signedIn: false) == .onboarding(.story))
        #expect(AppModel.launchStage(.onboarding(.seat), signedIn: true) == .onboarding(.seat))
        #expect(AppModel.launchStage(.today, signedIn: true) == .today)
    }

    @Test("Welcome back, by first name")
    func welcomeBack() {
        #expect(Copy.Hello.back("Kamal") == "Welcome back, Kamal.")
        #expect(Copy.Hello.back("") == "Welcome back.")
    }
}
