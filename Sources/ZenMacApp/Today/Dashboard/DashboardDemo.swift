import Foundation
import Albeit
import ZenAPI

/// Demo data for the dashboard, until the day sync lands. Three days of a builder's Mac, an iPhone
/// that shares its score only, Zeno's lines, and seven pattern cards. The week matches `FakeScores`
/// (Wednesday 8.1, Thursday 5.4, today 8.1, a 9-week streak).
struct DashboardDemo {
    let days: [DayInsight]
    let cards: [PatternCard]
    let lastSeven: [ZenScore]

    init(now: Date, calendar: Calendar = .current) {
        let midnight = calendar.startOfDay(for: now)
        let realMinute = Int(now.timeIntervalSince(midnight) / 60)
        // Before noon the demo day would be nearly empty, so it reads as early evening instead.
        let todayNow = realMinute >= 12 * 60 ? realMinute : 18 * 60 + 20

        func day(_ offset: Int, now: Int, mac: Int, phone: Int, delta: Int, sessions: [Raw], nudges: [RawNudge]) -> DayInsight {
            let date = calendar.date(byAdding: .day, value: -offset, to: midnight) ?? midnight
            let kept = sessions.enumerated().compactMap { i, r -> UsageSession? in
                guard r.start < now else { return nil }
                return UsageSession(id: offset * 100 + i, start: r.start, minutes: min(r.minutes, now - r.start), kind: r.kind, feel: r.feel, app: r.app)
            }
            let lines = nudges.enumerated().compactMap { i, n -> NudgeMoment? in
                guard n.minute < now else { return nil }
                return NudgeMoment(id: offset * 100 + i, minute: n.minute, device: n.device, feeling: n.feeling, line: n.line,
                                   pullBackAt: n.pullBack.flatMap { $0 < now ? $0 : nil })
            }
            let screens = [
                ScreenDay(id: "mac", kind: .mac, name: "This Mac", sessions: kept, score: ZenScore(tenths: mac)),
                ScreenDay(id: "iphone", kind: .iPhone, name: "iPhone", sessions: nil, score: ZenScore(tenths: phone)),
            ]
            return DayInsight(id: offset, date: date, now: now, score: ZenScore(tenths: min(mac, phone)), delta: delta,
                              screens: screens, nudges: lines)
        }

        days = [
            day(0, now: todayNow, mac: 84, phone: 81, delta: 27, sessions: Self.today, nudges: Self.todayNudges),
            day(1, now: 1440, mac: 54, phone: 63, delta: -27, sessions: Self.yesterday, nudges: Self.yesterdayNudges),
            day(2, now: 1440, mac: 86, phone: 81, delta: 23, sessions: Self.dayBefore, nudges: Self.dayBeforeNudges),
        ]
        lastSeven = [66, 74, 72, 58, 81, 54, 81].map { ZenScore(tenths: $0) }
        cards = Self.deck
    }

    private struct Raw {
        let start: Int, minutes: Int, kind: AppKind, feel: Feel, app: String
        init(_ h: Int, _ m: Int, _ minutes: Int, _ kind: AppKind, _ feel: Feel, _ app: String) {
            self.start = h * 60 + m; self.minutes = minutes; self.kind = kind; self.feel = feel; self.app = app
        }
    }

    private struct RawNudge {
        let minute: Int, device: DeviceLine.Kind, feeling: ZenoFeeling, line: String, pullBack: Int?
        init(_ h: Int, _ m: Int, _ device: DeviceLine.Kind, _ feeling: ZenoFeeling, _ line: String, pullBack: (Int, Int)? = nil) {
            self.minute = h * 60 + m; self.device = device; self.feeling = feeling; self.line = line
            self.pullBack = pullBack.map { $0.0 * 60 + $0.1 }
        }
    }

    private static let today: [Raw] = [
        Raw(8, 40, 25, .work, .intentional, "Mail"),
        Raw(9, 8, 12, .video, .unintentional, "YouTube"),
        Raw(9, 30, 52, .work, .focus, "Xcode"),
        Raw(10, 26, 14, .reading, .intentional, "Safari · docs"),
        Raw(10, 42, 9, .social, .unintentional, "X"),
        Raw(11, 5, 44, .work, .focus, "Figma"),
        Raw(12, 10, 13, .messaging, .intentional, "WhatsApp"),
        Raw(14, 35, 17, .social, .unintentional, "Reddit"),
        Raw(15, 0, 48, .work, .focus, "Xcode"),
        Raw(16, 5, 18, .reading, .intentional, "Notion"),
        Raw(17, 10, 11, .messaging, .intentional, "Messages"),
        Raw(18, 40, 16, .reading, .intentional, "Safari · articles"),
        Raw(21, 25, 22, .video, .unintentional, "YouTube"),
        Raw(22, 5, 12, .messaging, .intentional, "Messages"),
    ]

    private static let todayNudges: [RawNudge] = [
        RawNudge(9, 18, .mac, .curious, "Back again. Something on purpose?", pullBack: (9, 30)),
        RawNudge(10, 49, .mac, .pleasant, "Stretch? You've earned a slow minute.", pullBack: (11, 5)),
        RawNudge(13, 5, .iPhone, .happy, "Halfway there, and it's a good day."),
        RawNudge(14, 50, .mac, .curious, "The 3 pm dip again. Walk first?", pullBack: (15, 0)),
        RawNudge(21, 40, .mac, .sleepy, "Bedtime soon. Last scroll?"),
    ]

    private static let yesterday: [Raw] = [
        Raw(9, 15, 20, .video, .unintentional, "YouTube"),
        Raw(9, 40, 35, .work, .focus, "Xcode"),
        Raw(10, 20, 25, .social, .unintentional, "Reddit"),
        Raw(11, 0, 30, .work, .intentional, "Mail"),
        Raw(13, 50, 40, .video, .unintentional, "YouTube"),
        Raw(14, 40, 22, .social, .unintentional, "X"),
        Raw(15, 20, 45, .work, .focus, "Figma"),
        Raw(17, 0, 15, .messaging, .intentional, "WhatsApp"),
        Raw(20, 30, 18, .reading, .intentional, "Safari · articles"),
        Raw(22, 0, 48, .video, .unintentional, "YouTube"),
        Raw(23, 0, 20, .social, .unintentional, "Instagram"),
    ]

    private static let yesterdayNudges: [RawNudge] = [
        RawNudge(9, 28, .mac, .curious, "Back again. Something on purpose?", pullBack: (9, 40)),
        RawNudge(10, 40, .mac, .pleasant, "Stretch? You've earned a slow minute."),
        RawNudge(14, 20, .iPhone, .pleasant, "Slow afternoon. Still counts."),
        RawNudge(22, 25, .mac, .sleepy, "Bedtime soon. Last scroll?"),
    ]

    private static let dayBefore: [Raw] = [
        Raw(8, 30, 20, .reading, .intentional, "Safari · docs"),
        Raw(9, 30, 62, .work, .focus, "Xcode"),
        Raw(10, 40, 10, .social, .unintentional, "X"),
        Raw(11, 0, 50, .work, .focus, "Figma"),
        Raw(12, 30, 15, .messaging, .intentional, "WhatsApp"),
        Raw(14, 20, 14, .video, .unintentional, "YouTube"),
        Raw(15, 0, 55, .work, .focus, "Xcode"),
        Raw(16, 20, 20, .reading, .intentional, "Notion"),
        Raw(18, 0, 12, .messaging, .intentional, "Messages"),
        Raw(21, 10, 25, .reading, .intentional, "Books"),
    ]

    private static let dayBeforeNudges: [RawNudge] = [
        RawNudge(10, 48, .mac, .happy, "Two big runs before noon. Nice.", pullBack: (11, 0)),
        RawNudge(13, 0, .iPhone, .happy, "Good day locked in. Keep it easy."),
        RawNudge(21, 5, .mac, .sleepy, "Books at night. Zeno approves."),
    ]

    private static func hours(_ peaks: [Int: Double]) -> [Double] { (0..<24).map { peaks[$0] ?? 0 } }

    static let deck: [PatternCard] = [
        PatternCard(id: "deep-work", suit: .spade, skin: .zen, feeling: .happy,
                    title: "Deep work", face: "Your best focus starts at 9:30.",
                    body: "Three of your four longest focus runs this week began between 9:30 and 10:00, in Xcode and Figma.",
                    facts: [.init(value: "52 m", label: "Longest run"), .init(value: "6h 40m", label: "Focus this week"), .init(value: "Wed", label: "Best day")],
                    hours: hours([8: 0.1, 9: 0.9, 10: 1, 11: 0.6, 12: 0.1, 14: 0.2, 15: 0.7, 16: 0.4, 17: 0.1]),
                    tip: "Keep 9:30 to 11 clear. It's your best stretch.", strength: 0.94),
        PatternCard(id: "week-winner", suit: .diamond, skin: .gold, feeling: .proud,
                    title: "Week winner", face: "Nine won weeks in a row.",
                    body: "Four good days win a week, and you've won every one since the middle of September.",
                    facts: [.init(value: "9", label: "Weekly streak"), .init(value: "3 of 4", label: "This week"), .init(value: "8.1", label: "Today's score")],
                    hours: nil,
                    tip: "One more good day wins week ten.", strength: 0.9),
        PatternCard(id: "pull-backs", suit: .heart, skin: .paper, feeling: .pleasant,
                    title: "Pull-backs", face: "When Zeno asks, you come back.",
                    body: "Three of this week's four nudges on this Mac ended with you back on something you meant to do, a few minutes later.",
                    facts: [.init(value: "3 of 4", label: "Nudges answered"), .init(value: "3", label: "Pull-backs today"), .init(value: "Xcode", label: "Where you go back")],
                    hours: hours([9: 0.8, 10: 0.7, 14: 1, 21: 0.3]),
                    tip: "One calm line seems to be enough. Zeno will keep it that way.", strength: 0.82),
        PatternCard(id: "afternoon-dip", suit: .club, skin: .ember, feeling: .curious,
                    title: "The 3 pm dip", face: "After lunch, scrolling sneaks in.",
                    body: "Most of this week's unplanned minutes on this Mac landed between 14:00 and 15:30, on Reddit and YouTube.",
                    facts: [.init(value: "41%", label: "Of unplanned time"), .init(value: "Reddit", label: "Usual app"), .init(value: "14:35", label: "Usual start")],
                    hours: hours([13: 0.3, 14: 1, 15: 0.7, 16: 0.2]),
                    tip: "A short walk at 14:30 tends to beat the dip.", strength: 0.74),
        PatternCard(id: "clear-start", suit: .heart, skin: .mint, feeling: .calm,
                    title: "Clear start", face: "Your first hour is on purpose.",
                    body: "On five of the last seven days, your first hour on this Mac went to mail, docs and plans.",
                    facts: [.init(value: "5 of 7", label: "Clear mornings"), .init(value: "Mail", label: "First app"), .init(value: "8:40", label: "Usual start")],
                    hours: hours([8: 1, 9: 0.5]),
                    tip: "Nothing to change. Your mornings are working.", strength: 0.66),
        PatternCard(id: "quick-replies", suit: .heart, skin: .dusk, feeling: .pleasant,
                    title: "Quick replies", face: "Messages, short and kind.",
                    body: "Messaging comes in short visits, and after each one you head back to work.",
                    facts: [.init(value: "3", label: "Visits today"), .init(value: "12 m", label: "Usual visit"), .init(value: "Every time", label: "Back to work")],
                    hours: hours([12: 0.8, 17: 0.7, 22: 0.5]),
                    tip: "Batched replies suit you. Keep them batched.", strength: 0.55),
        PatternCard(id: "night-owl", suit: .club, skin: .night, feeling: .sleepy,
                    title: "Night owl", face: "Late videos on weeknights.",
                    body: "On weeknights, YouTube after 21:30 tends to run past 22:00, and those days end a little lower.",
                    facts: [.init(value: "3", label: "Nights this week"), .init(value: "21:30", label: "Usual start"), .init(value: "−0.8", label: "Score on those days")],
                    hours: hours([21: 0.8, 22: 1, 23: 0.6]),
                    tip: "Zeno can say goodnight at 22:15, once.", strength: 0.48),
    ]
}

/// "4h 23m", "52 m", "0 m": minutes the way every card writes them.
func durationText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) m" }
    let m = minutes % 60
    return m == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(m)m"
}

/// "09:30": a minute since midnight on the 24-hour clock.
func clockText(_ minute: Int) -> String {
    let m = min(max(minute, 0), 1439)
    return String(format: "%02d:%02d", m / 60, m % 60)
}
