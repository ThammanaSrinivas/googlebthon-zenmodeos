import SwiftUI
import Albeit
import ZenAPI

// The Today dashboard's front end: what each card shows, as plain values. Everything here is demo
// data until the sync contract lands; the screen says so with a Demo data tag.
//
// Privacy shapes the model: a screen whose minutes never leave it (an iPhone) has no sessions and
// shows its Zen Score only. The Mac's minutes are measured here and stay here.

/// How a stretch of time felt. The same three on every visual.
enum Feel: String, CaseIterable, Identifiable, Sendable {
    case focus = "Focus", intentional = "Intentional", unintentional = "Unintentional"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .focus: Color.zen.feelFocus
        case .intentional: Color.zen.feelIntentional
        case .unintentional: Color.zen.feelUnintentional
        }
    }
}

/// What kind of app the time went to. A browser's window title tells these apart; it's read, never stored.
enum AppKind: String, CaseIterable, Identifiable, Sendable {
    case work = "Work", reading = "Reading", messaging = "Messaging", video = "Video", social = "Social"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .work: "hammer"
        case .reading: "book"
        case .messaging: "bubble.left.and.bubble.right"
        case .video: "play.rectangle"
        case .social: "person.2.wave.2"
        }
    }
}

/// One stretch of one app in front, in minutes since midnight.
struct UsageSession: Identifiable, Hashable, Sendable {
    let id: Int
    let start: Int
    let minutes: Int
    let kind: AppKind
    let feel: Feel
    let app: String

    var end: Int { start + minutes }
}

/// One screen's day. `sessions == nil` is a screen whose minutes stay on it: it shows its score only.
struct ScreenDay: Identifiable, Sendable {
    let id: String
    let kind: DeviceLine.Kind
    let name: String
    let sessions: [UsageSession]?
    let score: ZenScore

    var isSealed: Bool { sessions == nil }
    var minutes: Int { sessions?.reduce(0) { $0 + $1.minutes } ?? 0 }
    var symbol: String { kind == .iPhone ? "iphone" : "laptopcomputer" }
}

/// A line Zeno said, where, and whether a pull-back followed (you went back to something on purpose).
struct NudgeMoment: Identifiable, Sendable {
    let id: Int
    let minute: Int
    let device: DeviceLine.Kind
    let feeling: ZenoFeeling
    let line: String
    /// The minute the pull-back landed on this Mac, if one did.
    let pullBackAt: Int?
}

/// One day of the dashboard.
struct DayInsight: Identifiable, Sendable {
    /// 0 is today, 1 yesterday, and so on.
    let id: Int
    let date: Date
    /// The minute the day is measured to: now for today, midnight for a finished day.
    let now: Int
    /// The account's Zen Score: the lower of the screens' scores.
    let score: ZenScore
    /// Change on the day before, in tenths.
    let delta: Int
    let screens: [ScreenDay]
    let nudges: [NudgeMoment]

    var isToday: Bool { id == 0 }
    /// The screen measured here.
    var mac: ScreenDay? { screens.first { !$0.isSealed } }
    var sessions: [UsageSession] { screens.flatMap { $0.sessions ?? [] } }
    var minutes: Int { sessions.reduce(0) { $0 + $1.minutes } }

    func minutes(_ feel: Feel) -> Int { sessions.filter { $0.feel == feel }.reduce(0) { $0 + $1.minutes } }
    func minutes(_ kind: AppKind) -> Int { sessions.filter { $0.kind == kind }.reduce(0) { $0 + $1.minutes } }
    func minutes(_ kind: AppKind, _ feel: Feel) -> Int {
        sessions.filter { $0.kind == kind && $0.feel == feel }.reduce(0) { $0 + $1.minutes }
    }

    /// Kinds with any time, most first.
    var kinds: [AppKind] { AppKind.allCases.filter { minutes($0) > 0 }.sorted { minutes($0) > minutes($1) } }
    /// Focus and intentional, as a share of the Mac's minutes.
    var onPurpose: Double { minutes == 0 ? 0 : Double(minutes - minutes(.unintentional)) / Double(minutes) }
    var longestFocus: UsageSession? { sessions.filter { $0.feel == .focus }.max { $0.minutes < $1.minutes } }
    var pullBacks: Int { nudges.filter { $0.pullBackAt != nil }.count }

    /// "Today", or "Thu 19 Nov".
    var label: String {
        if isToday { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// A pattern the week shows, dealt as a card. Ranked by how strongly it shows up in the person's own
/// use: the strongest leads the deck. The face carries the pattern, never minutes, so it can be shared.
struct PatternCard: Identifiable, Hashable, Sendable {
    let id: String
    let suit: CardSuit
    let skin: CardSkin
    let feeling: ZenoFeeling
    let title: String
    /// One line on the face.
    let face: String
    let body: String
    let facts: [Fact]
    /// 24 values, 0…1: when in the day it shows up (nil for a pattern that isn't about the hour).
    let hours: [Double]?
    /// Zeno's one suggestion.
    let tip: String
    /// How strongly it shows up, 0…1. Orders the deck.
    let strength: Double

    struct Fact: Hashable, Sendable {
        let value: String
        let label: String
    }

    /// What the suit stands for.
    var suitMeaning: String {
        switch suit {
        case .spade: "Focus"
        case .heart: "On purpose"
        case .diamond: "Reward"
        case .club: "Worth a look"
        }
    }
}

/// The dashboard's state: which day, which card is open, what's being searched.
@MainActor
@Observable
final class DashboardModel {
    private(set) var days: [DayInsight]
    /// Strongest first.
    private(set) var cards: [PatternCard]
    /// The last seven days' Zen Scores, oldest first, ending today.
    let lastSeven: [ZenScore]
    var dayIndex = 0
    private(set) var openCardID: PatternCard.ID?
    var query = ""
    /// A kind picked from search, held lit in the flow until the pointer moves over it.
    var litKind: AppKind?

    init(now: Date = Date()) {
        let demo = DashboardDemo(now: now)
        days = demo.days
        cards = demo.cards.sorted { $0.strength > $1.strength }
        lastSeven = demo.lastSeven
    }

    var day: DayInsight { days[dayIndex] }
    var openCard: PatternCard? { cards.first { $0.id == openCardID } }

    /// The rank a card is dealt at, from its place in the deck: A, K, Q, J, 10, 9 …
    func rank(of card: PatternCard) -> String {
        let ranks = ["A", "K", "Q", "J", "10", "9", "8", "7", "6"]
        let i = cards.firstIndex(of: card) ?? 0
        return ranks[min(i, ranks.count - 1)]
    }

    func position(of card: PatternCard) -> Int { (cards.firstIndex(of: card) ?? 0) + 1 }

    func open(_ card: PatternCard) {
        withAnimation(ZenMotion.container) { openCardID = card.id }
    }

    func close() {
        withAnimation(ZenMotion.exit) { openCardID = nil }
    }

    /// The next or previous card in the deck, wrapping.
    func step(_ by: Int) {
        guard let open = openCard, let i = cards.firstIndex(of: open) else { return }
        let next = cards[(i + by + cards.count) % cards.count]
        withAnimation(ZenMotion.container) { openCardID = next.id }
    }
}
