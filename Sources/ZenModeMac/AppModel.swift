import SwiftUI
import Albeit
import ZenAPI

/// The app's state. Views read this and call its intents; they never see a service.
@MainActor
@Observable
final class AppModel {
    enum Step: Int, CaseIterable { case story, seat, uses, quiet, count, bring, handoff }
    enum Stage: Equatable { case onboarding(Step), today }

    enum CodeState: Equatable {
        case idle, checking, found(CohortPreview), joined(CohortSummary), failed(String)
    }

    enum PairState: Equatable { case waiting, approving, paired, failed(String) }

    var stage: Stage = .onboarding(.story)
    /// Which story card opens first (debug tours start mid-story).
    var initialStoryIndex = 0
    var profile = Profile()
    var codeText = "" { didSet { let clean = JoinCode.sanitize(codeText); if clean != codeText { codeText = clean } } }
    private(set) var codeState: CodeState = .idle
    private(set) var cohort: CohortSummary?
    private(set) var user: ZenUser?
    private(set) var pairing: PairingCode?
    private(set) var pairState: PairState = .waiting
    private(set) var snapshot: ScoreSnapshot?
    private(set) var accessibilityTrusted = AccessibilityAccess.isTrusted
    private(set) var lastNudge: (ZenoNudge, NudgeSource)?

    let notch = NotchModel()
    let frontmost = FrontmostTracker()
    let services = Services.make()
    var isDemo: Bool { services.isDemo }

    private var pairTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    func start() {
        AppNap.holdOff()
        frontmost.start()
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            notch.speak(.init(feeling: .happy, kicker: Copy.Hello.kicker, line: Copy.Hello.line), hold: .seconds(3.2), respectQuiet: false)
        }
        Task { snapshot = try? await services.scores.today() }
    }

    // MARK: Onboarding

    var step: Step? { if case .onboarding(let s) = stage { s } else { nil } }

    func go(_ step: Step) {
        withAnimation(ZenMotion.container) { stage = .onboarding(step) }
        if step == .bring { startPairing() }
        if step == .count { startPermissionPolling() }
        if step == .handoff { playHandoff() }
    }

    func next() {
        guard let s = step else { return }
        if let n = Step(rawValue: s.rawValue + 1) { go(n) } else { finishOnboarding() }
    }

    func back() {
        guard let s = step, let p = Step(rawValue: s.rawValue - 1) else { return }
        go(p)
    }

    func finishOnboarding() {
        notch.quiet = profile.quiet
        withAnimation(ZenMotion.container) { stage = .today }
        Task { await refreshNudge(trigger: .hello) }
    }

    /// Zeno shows a feeling in the notch (the story's feelings row). Onboarding ignores quiet hours.
    func showFeeling(_ index: Int) {
        let feelings: [ZenoFeeling] = [.happy, .pleasant, .curious, .proud, .sleepy]
        let i = (index % feelings.count + feelings.count) % feelings.count
        let line = Copy.feelingLines[i]
        notch.speak(.init(feeling: feelings[i], kicker: line.kicker, line: line.line), hold: .seconds(3.4), respectQuiet: false)
    }

    func choose(seat: Profile.Seat) {
        profile.seat = seat
        if seat == .personal { codeState = .idle; cohort = nil }
        let line: (ZenoFeeling, String) = switch seat {
        case .personal: (.pleasant, "Just us, then. I like it.")
        case .campus: (.happy, "A campus! Got your code?")
        case .team: (.curious, "A team. Which one?")
        }
        notch.speak(.init(feeling: line.0, kicker: "Make it yours", line: line.1), hold: .seconds(2.8), respectQuiet: false)
    }

    func checkCode() {
        guard let code = JoinCode(codeText) else { codeState = .failed(Copy.Seat.notFound); return }
        codeState = .checking
        Task {
            do {
                let preview = try await services.cohorts.preview(code: code)
                withAnimation(ZenMotion.container) { codeState = .found(preview) }
            } catch {
                withAnimation(ZenMotion.container) { codeState = .failed((error as? CohortError) == .offline ? Copy.Seat.offline : Copy.Seat.notFound) }
            }
        }
    }

    func joinCohort() {
        guard let code = JoinCode(codeText) else { return }
        codeState = .checking
        Task {
            do {
                let summary = try await services.cohorts.join(code: code)
                cohort = summary
                profile.cohortCode = code.value
                withAnimation(ZenMotion.container) { codeState = .joined(summary) }
                notch.speak(.init(feeling: .happy, kicker: summary.preview.name, line: "You're in. \(summary.preview.memberCount) people, one score."),
                            hold: .seconds(3), respectQuiet: false)
                try? await Task.sleep(for: .milliseconds(900))
                next()
            } catch {
                withAnimation(ZenMotion.container) { codeState = .failed((error as? CohortError) == .offline ? Copy.Seat.offline : Copy.Seat.notFound) }
            }
        }
    }

    func toggle(use: Profile.Use) {
        if profile.uses.contains(use) { profile.uses.remove(use) } else { profile.uses.insert(use) }
    }

    func choose(quiet: QuietHours) {
        withAnimation(ZenMotion.container) { profile.quiet = quiet }
        let line = quiet == .none ? "Got it. Nights only." : "I'll keep quiet \(quiet.summary.lowercased())."
        notch.speak(.init(feeling: .sleepy, kicker: "Quiet hours", line: line), hold: .seconds(2.8), respectQuiet: false)
    }

    func requestAccessibility() {
        AccessibilityAccess.request()
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let trusted = AccessibilityAccess.isTrusted
                if trusted != accessibilityTrusted { withAnimation(ZenMotion.container) { accessibilityTrusted = trusted } }
                if trusted { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startPairing() {
        pairTask?.cancel()
        pairState = .waiting
        pairTask = Task {
            do {
                let code = try await services.auth.newPairingCode()
                pairing = code
                let person = try await services.auth.waitForApproval(of: code)
                paired(person)
            } catch {
                if !Task.isCancelled { pairState = .failed((error as? AuthError) == .codeExpired ? Copy.Bring.expired : Copy.Seat.offline) }
            }
        }
    }

    /// Mock only: stands in for the iPhone approving the code.
    func simulateApproval() {
        pairTask?.cancel()
        paired(ZenUser(uid: "demo-kamal", displayName: "Kamal"))
    }

    func signInWithGoogle() {
        pairTask?.cancel()
        pairState = .approving
        Task {
            do { paired(try await services.auth.signInWithGoogle()) } catch { pairState = .failed(Copy.Seat.offline) }
        }
    }

    private func paired(_ person: ZenUser) {
        user = person
        pairState = .paired
        go(.handoff)
    }

    private func playHandoff() {
        let name = user?.firstName ?? "there"
        Task {
            snapshot = try? await services.scores.today()
            try? await Task.sleep(for: .milliseconds(760))
            notch.speak(.init(feeling: .happy, kicker: Copy.Handoff.kicker, line: Copy.Handoff.line(name)), hold: .seconds(3.4), respectQuiet: false)
        }
    }

    // MARK: Today

    func refreshNudge(trigger: NudgeContext.Trigger) async {
        let snap: ScoreSnapshot? = if let snapshot { snapshot } else { try? await services.scores.today() }
        snapshot = snap
        let hour = Calendar.current.component(.hour, from: Date())
        let context = NudgeContext(scoreTenths: snap?.score.tenths ?? 0, goodDaysThisWeek: snap?.week.goodDays ?? 0,
                                   weeklyStreak: snap?.week.weeklyStreak ?? 0, hourOfDay: hour, trigger: trigger)
        let result = await services.nudges.nudge(for: context)
        lastNudge = result
        notch.speak(result.0, kicker: result.1 == .gemini ? "Zeno · Gemini" : "Zeno")
    }
}
