import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// "What did I miss?" after a focus block: Slack mentions and DMs since the start, read on this
/// Mac; on the person's tap, Gemini (zenoCatchUp) sorts them into at most 3 cards with a draft
/// reply. Nothing sends until they approve that card.
@MainActor
@Observable
final class CatchUpModel {
    enum State: Equatable {
        case idle
        /// No Slack token: the card offers to connect.
        case notConnected
        case fetching
        /// Messages are in; waiting for the person's tap.
        case waiting(Int)
        case empty
        case thinking
        case ready
        case failed(String)
    }

    struct Card: Identifiable, Equatable {
        enum Status: Equatable { case pending, sending, sent, scheduled(Date), skipped, failed(String) }
        let id: Int
        let message: InboxMessage
        let summary: String
        let urgency: CatchUpCard.Urgency
        var draft: String
        var status: Status = .pending
    }

    private(set) var state: State = .idle
    private(set) var cards: [Card] = []
    private(set) var line = ""
    /// The cards came from Gemini (not the fixed fallback).
    private(set) var fromGemini = false
    @ObservationIgnored private var messages: [InboxMessage] = []
    @ObservationIgnored private let token: () -> String?
    @ObservationIgnored private let sender: any HTTPSending

    init(token: @escaping () -> String? = { FocusSecrets.shared.value(FocusSecrets.slackToken) }, sender: any HTTPSending = URLSessionSender()) {
        self.token = token
        self.sender = sender
    }

    /// A block ended: read what came in since it started (on this Mac only).
    func focusEnded(since: Date) async {
        cards = []
        guard let t = token() else { state = .notConnected; return }
        state = .fetching
        do {
            messages = try await SlackInbox(token: t, sender: sender).messages(since: since)
            state = messages.isEmpty ? .empty : .waiting(messages.count)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// The tap: send the messages to zenoCatchUp. If the call can't be made, the app's own fallback
    /// shows the first three with no draft.
    func catchMeUp(with work: any ZenoWorkService) async {
        guard !messages.isEmpty else { return }
        state = .thinking
        let items = messages.map(\.item)
        let result: CatchUpResult
        do {
            result = try await work.catchUp(items)
        } catch {
            result = Self.localFallback(items)
        }
        fromGemini = !result.fallback
        line = result.line
        var used = Set<Int>()
        cards = result.items.prefix(3).compactMap { c in
            guard messages.indices.contains(c.ref), used.insert(c.ref).inserted else { return nil }
            return Card(id: c.ref, message: messages[c.ref], summary: c.summary, urgency: c.urgency, draft: c.draftReply)
        }
        state = cards.isEmpty ? .empty : .ready
    }

    func setDraft(_ id: Int, _ text: String) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].draft = String(text.prefix(1000))
    }

    /// Sends now, or at `at` (Slack schedules it), after the person approved this card.
    func approve(_ id: Int, at: Date? = nil) async {
        guard let i = cards.firstIndex(where: { $0.id == id }), let t = token() else { return }
        let text = cards[i].draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cards[i].status = .sending
        do {
            try await SlackInbox(token: t, sender: sender).reply(to: cards[i].message, text: text, at: at)
            cards[i].status = at.map { .scheduled($0) } ?? .sent
        } catch {
            cards[i].status = .failed(Self.describe(error))
        }
    }

    func skip(_ id: Int) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].status = .skipped
    }

    func dismiss() {
        state = .idle
        cards = []
        messages = []
    }

    static func localFallback(_ items: [CatchUpItem]) -> CatchUpResult {
        CatchUpResult(items: items.prefix(3).enumerated().map { i, item in
            CatchUpCard(ref: i, summary: String("\(item.fromLabel) sent you a message".prefix(80)), urgency: .today, draftReply: "")
        }, line: "Here's what came in.", fallback: true)
    }

    static func describe(_ error: any Error) -> String {
        if let f = error as? HookFailure { return f.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Try again when you're back." }
        return "Couldn't reach Slack."
    }
}

enum CatchUpCopy {
    static let eyebrow = "What did I miss?"
    static func waiting(_ n: Int) -> String { n == 1 ? "1 message came in while you focused." : "\(n) messages came in while you focused." }
    static let catchMeUp = "Catch me up"
    static let thinking = "Zeno is reading them…"
    static let empty = "Nothing needs you. Quiet block."
    static let notConnected = "Connect Slack to see what came in while you focused."
    static let privacy = "Read on this Mac. Sent to Gemini only when you tap, never stored."
    static func needYou(_ n: Int) -> String { n == 1 ? "1 thing needs you" : "\(n) things need you" }
    static let send = "Send"
    static let skip = "Skip"
    static func sendAt(_ time: String) -> String { "Send at \(time)" }
}

/// The catch-up card on Today, under Focus.
struct CatchUpCardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = model.catchUp
        if c.state != .idle {
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                HStack(spacing: ZenSpace.s2) {
                    Eyebrow(CatchUpCopy.eyebrow, color: Color.zen.textBrand)
                    if c.state == .ready { Text(c.fromGemini ? "Zeno · Gemini" : "Zeno").zenType(.caption).foregroundStyle(Color.zen.textCaption) }
                    Spacer(minLength: 0)
                    Button { c.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.zen.textCaption)
                        .accessibilityLabel("Close catch-up")
                }
                content(c)
            }
            .padding(ZenSpace.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: ZenRadius.xl)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    @ViewBuilder
    private func content(_ c: CatchUpModel) -> some View {
        switch c.state {
        case .idle: EmptyView()
        case .notConnected:
            HStack {
                Text(CatchUpCopy.notConnected).zenType(.body).foregroundStyle(Color.zen.textBody)
                Spacer(minLength: 0)
                Button("Connect Slack") { model.integrationsTab = .focus; model.navigate = .integrations }.buttonStyle(ZenSecondaryButtonStyle())
            }
        case .fetching, .thinking:
            HStack(spacing: ZenSpace.s3) {
                ProgressView().controlSize(.small)
                Text(c.state == .thinking ? CatchUpCopy.thinking : "Checking Slack…").zenType(.body).foregroundStyle(Color.zen.textBody)
            }
            .accessibilityElement(children: .combine)
        case .waiting(let n):
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text(CatchUpCopy.waiting(n)).font(ZenFont.brand(24)).foregroundStyle(Color.zen.textHeading)
                HStack(spacing: ZenSpace.s3) {
                    Button(CatchUpCopy.catchMeUp) { Task { await c.catchMeUp(with: model.services.work) } }
                        .buttonStyle(ZenPrimaryButtonStyle())
                    Text(CatchUpCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
            }
        case .empty:
            Text(CatchUpCopy.empty).zenType(.body).foregroundStyle(Color.zen.textBody)
        case .failed(let why):
            Text(why).zenType(.body).foregroundStyle(Color.zen.scoreDeduct)
        case .ready:
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Text(CatchUpCopy.needYou(c.cards.count)).font(ZenFont.brand(24)).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                if !c.line.isEmpty { Text(c.line).zenType(.body).foregroundStyle(Color.zen.textBody) }
                ForEach(c.cards) { card in CatchUpRow(card: card) }
            }
        }
    }
}

private struct CatchUpRow: View {
    @Environment(AppModel.self) private var model
    let card: CatchUpModel.Card

    private var urgencyText: String {
        switch card.urgency {
        case .now: "Now"
        case .today: "Today"
        case .later: "Later"
        }
    }

    var body: some View {
        let c = model.catchUp
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Text(urgencyText).font(ZenFont.text(11, .semibold))
                    .foregroundStyle(card.urgency == .now ? Color.zen.accentRewardText : Color.zen.textCaption)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(card.urgency == .now ? Color.zen.accentRewardTint : Color.zen.surfaceSunk.opacity(0.6)))
                Text(card.message.isDM ? "DM · \(card.message.fromLabel)" : card.message.fromLabel)
                    .zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            Text(card.summary).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                .fixedSize(horizontal: false, vertical: true)
            switch card.status {
            case .sent: Label("Sent", systemImage: "checkmark.circle.fill").zenType(.caption).foregroundStyle(Color.zen.textBrand)
            case .scheduled(let d): Label("Scheduled for \(FocusClock.text(d))", systemImage: "clock").zenType(.caption).foregroundStyle(Color.zen.textBrand)
            case .skipped: Text("Skipped").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            default:
                TextField("Reply", text: Binding(get: { card.draft }, set: { c.setDraft(card.id, $0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                    .accessibilityLabel("Draft reply to \(card.message.fromLabel)")
                HStack(spacing: ZenSpace.s2) {
                    Button(card.status == .sending ? "Sending…" : CatchUpCopy.send) { Task { await c.approve(card.id) } }
                        .buttonStyle(ZenPrimaryButtonStyle())
                        .disabled(card.status == .sending || card.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let next = model.afterHours.nextWorkStart(), model.afterHours.isAfterHours() {
                        Button(CatchUpCopy.sendAt(FocusClock.text(next))) { Task { await c.approve(card.id, at: next) } }
                            .buttonStyle(ZenSecondaryButtonStyle())
                    }
                    Button(CatchUpCopy.skip) { c.skip(card.id) }.buttonStyle(ZenLinkButtonStyle())
                    if case .failed(let why) = card.status { Text(why).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct) }
                }
            }
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.7)))
    }
}
