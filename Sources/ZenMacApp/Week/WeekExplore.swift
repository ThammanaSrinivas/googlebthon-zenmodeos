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

/// Zeno's read of the week: Gemini's review beside a picture of the week, then the set questions.
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
            ReviewCard()
            AskCard(ask: ask)
        }
    }
}

/// Who wrote the words, said plainly: Gemini only when Gemini wrote them.
private struct SourceCredit: View {
    let source: NudgeSource

    var body: some View {
        HStack(spacing: 6) {
            if source == .gemini {
                GeminiSpark(size: 11)
            } else {
                Image(systemName: "number").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.zen.textCaption)
                    .accessibilityHidden(true)
            }
            Text(source == .gemini ? WeekCopy.fromGemini : WeekCopy.fromNumbers)
                .font(ZenFont.text(12, .medium)).foregroundStyle(Color.zen.textCaption)
        }
    }
}

/// Set questions as chips that look and act like secondary buttons, the answer typing in below.
private struct AskCard: View {
    let ask: WeekAskModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: ZenSpace.s1) {
                Eyebrow(WeekCopy.askEyebrow)
                Text(WeekCopy.askLede).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: ZenSpace.s2 + 2, lineSpacing: ZenSpace.s2 + 2) {
                ForEach(WeekPrompt.all) { prompt in
                    let on = ask.selected == prompt
                    Button { ask.ask(prompt, recap: WeekDemo.recap, reduceMotion: reduceMotion) } label: {
                        Text(prompt.label)
                    }
                    .buttonStyle(AskChipStyle(selected: on))
                    .focusEffectDisabled()
                    .accessibilityHint(WeekCopy.askHint)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            answerArea
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WeekPaper())
        .animation(ZenMotion.container, value: ask.loading)
        .animation(ZenMotion.container, value: ask.selected)
    }

    @ViewBuilder
    private var answerArea: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
        if ask.loading {
            HStack(spacing: ZenSpace.s3) {
                LoadingCells()
                Text(WeekCopy.askThinking).zenType(.body).foregroundStyle(Color.zen.textBody)
            }
            .padding(ZenSpace.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.zen.surfaceRaised.opacity(0.8)))
            .accessibilityElement(children: .combine)
        } else if let answer = ask.answer, let question = ask.selected {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text("\(WeekCopy.youAsked) · \(question.label)").font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textCaption)
                Text(String(answer.text.prefix(ask.typed)))
                    .font(ZenFont.text(15.5)).lineSpacing(6).foregroundStyle(Color.zen.textHeading)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(answer.text)
                SourceCredit(source: answer.source)
            }
            .padding(ZenSpace.s5)
            .padding(.leading, ZenSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.zen.surfaceRaised))
            .overlay(shape.strokeBorder(Color.zen.borderHairline, lineWidth: 1))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.zen.brandFill).frame(width: 3).padding(.vertical, ZenSpace.s4)
            }
            .transition(.opacity.combined(with: .offset(y: 6)))
        } else {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "arrow.turn.left.up").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                Text(WeekCopy.askEmpty)
            }
            .font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
            .padding(ZenSpace.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(Color.zen.borderOutline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }
}

/// A question chip: a secondary button you can see at rest (raised paper, a firm outline), a
/// green wash and outline on hover, a sink on press, a brand ring on keyboard focus, green when
/// it's the question asked.
struct AskChipStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, selected: selected) }

    private struct Styled: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let active = selected || hovering
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark" : "bubble.left").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zen.textBrand)
                    .accessibilityHidden(true)
                configuration.label
            }
            .font(ZenFont.text(13.5, .semibold))
            .foregroundStyle(selected ? Color.zen.textBrand : Color.zen.textHeading)
            .padding(.horizontal, ZenSpace.s4)
            .frame(minHeight: 36)
            .background(Capsule().fill(active ? Color.zen.surfaceTint : Color.zen.surfaceRaised))
            .overlay(Capsule().strokeBorder(active ? Color.zen.textBrand.opacity(selected ? 0.9 : 0.7) : Color.zen.textCaption.opacity(0.6),
                                            lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 6 : 2, y: hovering ? 3 : 1)
            .overlay { if focused { Capsule().strokeBorder(Color.zen.textBrand, lineWidth: 2.5).padding(-4) } }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
            .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Capsule())
        }
    }
}

/// Gemini's weekly review: this week drawn as light on the left, Zeno in it; the read on the right
/// (a headline, a short read, one thing to try) with Regenerate.
struct ReviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = (model.snapshot ?? FakeSnapshot.value).week
        HStack(alignment: .top, spacing: 0) {
            ReviewArt(week: week)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.28 }
                .frame(maxHeight: .infinity)
            read
                .padding(ZenSpace.s8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(WeekPaper())
        .animation(ZenMotion.container, value: model.reviewLoading)
    }

    @ViewBuilder
    private var read: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s3) {
                Eyebrow(WeekCopy.reviewEyebrow)
                Spacer()
                if let (_, source) = model.review, !model.reviewLoading { SourceCredit(source: source) }
            }
            if let (review, _) = model.review, !model.reviewLoading {
                Text(review.headline).font(ZenFont.brand(30)).tracking(-0.7).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(review.body).font(ZenFont.text(15)).lineSpacing(6).foregroundStyle(Color.zen.textBody)
                    .frame(maxWidth: 640, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Image(systemName: "leaf").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.zen.surfaceRaised))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(WeekCopy.tryThis, color: Color.zen.textBrand)
                        Text(review.experiment).font(ZenFont.text(14.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(ZenSpace.s4)
                .frame(maxWidth: 640, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceTint))
                .accessibilityElement(children: .combine)
                regenerate
            } else {
                VStack(alignment: .leading, spacing: ZenSpace.s3) {
                    Text(WeekCopy.reviewLoading).font(ZenFont.brand(24)).foregroundStyle(Color.zen.textHeading)
                    LoadingCells()
                }
                .padding(.vertical, ZenSpace.s4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WeekCopy.reviewLoading)
                regenerate
            }
        }
    }

    private var regenerate: some View {
        Button { Task { await model.loadReview() } } label: {
            Label(WeekCopy.regenerate, systemImage: "arrow.clockwise")
        }
        .buttonStyle(ZenSecondaryButtonStyle())
        .disabled(model.reviewLoading)
        .accessibilityHint(WeekCopy.regenerateHint)
        .padding(.top, ZenSpace.s1)
    }
}

/// The review's picture: this week as light, lettered by day, with Zeno sitting in it wearing the
/// week's feeling and the week's count on a tag.
private struct ReviewArt: View {
    let week: WeekProgress

    var body: some View {
        let state = WeekState(week)
        WeekLight(days: week.days, wonOn: week.winningDayIndex, lastDay: week.todayIndex, seed: 47, showsDays: true)
            .overlay(alignment: .topLeading) {
                Text("THIS WEEK · \(week.goodDays) OF 4")
                    .font(ZenFont.number(10)).tracking(0.9).foregroundStyle(Color.zen.textHeading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.zen.surfaceRaised.opacity(0.9)))
                    .padding(ZenSpace.s4)
            }
            .overlay(alignment: .topTrailing) {
                ZenoView(state.feeling).frame(width: 76).padding(ZenSpace.s4)
            }
            .frame(minHeight: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week so far: \(week.goodDays) of 4 good days")
    }
}

/// The paper Zeno's read sits on: raised, opaque enough that every line reads the same over any
/// backdrop, a hairline, Albeit's lift.
struct WeekPaper: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        content
            .background(shape.fill(Color.zen.surfaceRaised.opacity(0.94)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.zen.borderHairline, lineWidth: 1))
            .modifier(ZenLift())
    }
}
