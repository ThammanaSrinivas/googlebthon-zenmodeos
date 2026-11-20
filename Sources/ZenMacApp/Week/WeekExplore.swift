import SwiftUI
import Albeit
import ZenAPI

// MARK: - Asking about the week

/// A question with a set wording. Free text comes later; set questions keep answers on outcomes.
struct WeekPrompt: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case hardDay, calmDay, plan, screens }
    let kind: Kind
    let label: String
    var id: String { kind.rawValue }

    static let all = [
        WeekPrompt(kind: .hardDay, label: "Why was Thursday hard?"),
        WeekPrompt(kind: .calmDay, label: "What made Wednesday calm?"),
        WeekPrompt(kind: .plan, label: "Plan a calmer Thursday"),
        WeekPrompt(kind: .screens, label: "iPhone vs this Mac this week"),
    ]
}

/// Answers questions about the week from outcomes only: scores, good days, a computer's minutes and
/// pull-backs. Never app names, never an iPhone's minutes. Gemini on the server; the fake here.
protocol WeekAskService: Sendable {
    func answer(_ prompt: WeekPrompt, recap: WeekRecap) async throws -> String
    /// Who writes the answers: `.gemini` for the live model (the default), `.fallback` for anything canned.
    var source: NudgeSource { get }
}

extension WeekAskService {
    var source: NudgeSource { .gemini }
}

/// The demo voice, built from the same numbers the server would get.
struct FakeWeekAsk: WeekAskService {
    /// Answers worked out on this Mac from the week's numbers: never credited to Gemini.
    var source: NudgeSource { .fallback }

    func answer(_ prompt: WeekPrompt, recap: WeekRecap) async throws -> String {
        try await Task.sleep(for: .milliseconds(900))
        let p = recap.progress
        let left = max(0, WeekProgress.goodDaysToWin - p.goodDays)
        let mac = recap.devices.first { $0.kind == .mac }
        switch prompt.kind {
        case .hardDay:
            return "Thursday came in at 5.4, the week's low. Most of the dip landed after 9 pm on this Mac, and it was the one evening without a pull-back. The day itself was fine until then."
        case .calmDay:
            return "Wednesday reached 8.1. It started with a long focus block before lunch and closed early: nothing distracting after 8 pm. That shape, an early close, is your best lever."
        case .plan:
            return left == 0
                ? "The week's already won. Keep Thursday light anyway: close the laptop at 9 and leave the phone outside the room."
                : "\(left == 1 ? "One more good day" : "\(left) more good days") \(left == 1 ? "wins" : "win") the week. For Thursday: one focus block before noon, the laptop closed at 9, the phone charging outside the room. Above 6.0 does it."
        case .screens:
            let minutes = mac?.distractingMinutes ?? 0
            return "Your iPhone shared only its score, as it always does, and it held steady. This Mac carried \(minutes / 60) h \(minutes % 60) m of distracting time across \(mac?.daysCounted ?? 0) days, with \(mac?.pullBacks ?? 0) pull-backs. Each day, your score is the lower of the two."
        }
    }
}

/// Timeout, checks and a fixed line around any answer service.
struct ResilientWeekAsk: Sendable {
    let service: any WeekAskService
    var timeout: Duration = .seconds(8)
    static let limit = 420

    func answer(_ prompt: WeekPrompt, recap: WeekRecap) async -> (String, NudgeSource) {
        let service = self.service, timeout = self.timeout
        let live: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let text = try? await service.answer(prompt, recap: recap) else { return nil }
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = clean.lowercased()
                guard !clean.isEmpty, clean.count <= Self.limit, !WeeklyReview.clinicalWords.contains(where: lower.contains) else { return nil }
                return clean
            }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let live { return (live, service.source) }
        return (WeekCopy.askFallback, .fallback)
    }
}

/// The asking state: which question, the answer as it types in.
@MainActor
@Observable
final class WeekAskModel {
    private(set) var selected: WeekPrompt?
    private(set) var answer: (text: String, source: NudgeSource)?
    private(set) var loading = false
    private(set) var typed = 0
    private let asker = ResilientWeekAsk(service: FakeWeekAsk())
    private var task: Task<Void, Never>?

    func ask(_ prompt: WeekPrompt, recap: WeekRecap, reduceMotion: Bool) {
        task?.cancel()
        selected = prompt
        answer = nil
        typed = 0
        loading = true
        task = Task { [weak self, asker] in
            let result = await asker.answer(prompt, recap: recap)
            guard let self, !Task.isCancelled else { return }
            self.loading = false
            self.answer = result
            if reduceMotion { self.typed = result.0.count; return }
            for i in stride(from: 0, through: result.0.count, by: 2) {
                guard !Task.isCancelled else { return }
                self.typed = i
                try? await Task.sleep(for: .milliseconds(14))
            }
            self.typed = result.0.count
        }
    }
}

// MARK: - The section

/// Zeno's read of the week, one card: Gemini's review on the left, set questions on the right.
struct ExploreSection: View {
    let ask: WeekAskModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s3) {
                Text(WeekCopy.exploreTitle).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                DemoTag()
            }
            HStack(alignment: .top, spacing: ZenSpace.s6) {
                ReviewCard()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(Color.zen.borderHairline).frame(width: 1)
                AskCard(ask: ask)
                    .frame(width: 400, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(ZenSpace.s6)
            .glassCard(radius: ZenRadius.xxxl)
        }
    }
}

/// Set questions as chips, the answer typing in below.
private struct AskCard: View {
    let ask: WeekAskModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(WeekCopy.askEyebrow)
            }
            FlowLayout(spacing: ZenSpace.s2, lineSpacing: ZenSpace.s2) {
                ForEach(WeekPrompt.all) { prompt in
                    let on = ask.selected == prompt
                    Button { ask.ask(prompt, recap: WeekDemo.recap, reduceMotion: reduceMotion) } label: {
                        Text(prompt.label)
                            .font(ZenFont.text(13, .semibold))
                            .foregroundStyle(on ? Color.zen.textBrand : Color.zen.textHeading)
                            .padding(.horizontal, ZenSpace.s3 + 2).frame(height: 34)
                            .background(Capsule().fill(on ? Color.zen.surfaceTint : Color.zen.surfaceCard.opacity(0.7)))
                            .overlay(Capsule().strokeBorder(on ? Color.zen.textBrand.opacity(0.45) : Color.zen.borderHairline, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityHint(WeekCopy.askHint)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            answerArea
        }
        .animation(ZenMotion.container, value: ask.loading)
        .animation(ZenMotion.container, value: ask.selected)
    }

    @ViewBuilder
    private var answerArea: some View {
        if ask.loading {
            HStack(spacing: ZenSpace.s3) {
                LoadingCells()
                Text(WeekCopy.askThinking).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .padding(.top, ZenSpace.s1)
            .accessibilityElement(children: .combine)
        } else if let answer = ask.answer {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text(String(answer.text.prefix(ask.typed)))
                    .font(ZenFont.text(14.5)).lineSpacing(5).foregroundStyle(Color.zen.textHeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(answer.text)
                Text(answer.source == .gemini ? WeekCopy.askFromGemini : WeekCopy.askFromHere)
                    .zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            .padding(ZenSpace.s4)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.65)))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.zen.brandFill).frame(width: 3).padding(.vertical, ZenSpace.s3)
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        } else {
            Text(WeekCopy.askEmpty).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Gemini's weekly review: one headline, a short read, one thing to try. Sits inside Explore's card.
struct ReviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s2) {
                GeminiSpark()
                Eyebrow(WeekCopy.reviewEyebrow)
                Spacer()
                if let (_, source) = model.review, !model.reviewLoading {
                    Text(source == .gemini ? WeekCopy.reviewSourceGemini : WeekCopy.reviewSourceHere)
                        .font(ZenFont.number(9.5)).tracking(0.8).foregroundStyle(Color.zen.textCaption)
                }
            }
            if let (review, _) = model.review, !model.reviewLoading {
                Text(review.headline).font(ZenFont.brand(26)).tracking(-0.6).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(review.body).font(ZenFont.text(14.5)).lineSpacing(5).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Image(systemName: "leaf").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.zen.surfaceTint))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(WeekCopy.tryThis, color: Color.zen.textBrand)
                        Text(review.experiment).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(ZenSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.75)))
                Button(WeekCopy.askAgain) { Task { await model.loadReview() } }.buttonStyle(ZenLinkButtonStyle())
            } else {
                HStack(spacing: ZenSpace.s3) {
                    ZenoView(.curious).frame(width: 56)
                    VStack(alignment: .leading, spacing: ZenSpace.s2) {
                        Text(WeekCopy.reviewLoading).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        LoadingCells()
                    }
                }
                .padding(.vertical, ZenSpace.s4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WeekCopy.reviewLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(ZenMotion.container, value: model.reviewLoading)
    }
}

/// A press sinks a control a touch; nothing else moves.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
    }
}
