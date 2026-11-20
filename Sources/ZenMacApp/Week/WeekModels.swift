// Week and streak models, app-side until ZenAPI and ZenMock move into Packages/ZenShared.
// TODO(buildathon): move the pure types into ZenShared (with tests) after that push.
import Foundation
import ZenAPI
import ZenMock

// MARK: - The streak calendar

/// One day's combined Zen Score. `score == nil` is a day with no data: not good, and not a zero.
struct DayRecord: Equatable, Sendable {
    let date: Date
    let score: ZenScore?
}

/// Days laid out as weeks, Monday to Sunday in the home time zone, with the weekly streak worked
/// out the one way it's worked out everywhere: 4 good days win a week, won weeks in a row make the
/// streak, the week in progress never breaks it.
struct StreakCalendar: Sendable {
    struct Week: Identifiable, Sendable {
        /// The Monday that starts the week.
        let id: Date
        /// Seven slots, Monday first. nil is a day after today (not lived yet).
        let days: [DayRecord?]
        let isCurrent: Bool

        var progress: WeekProgress {
            WeekProgress(days: days.map { $0?.score }, todayIndex: isCurrent ? days.lastIndex { $0 != nil } : nil, streakBefore: 0)
        }
        var goodDays: Int { progress.goodDays }
        var isWon: Bool { progress.isWon }
    }

    let weeks: [Week]
    /// Won weeks in a row, up to and including this week if it's already won.
    let currentStreak: Int
    let bestStreak: Int
    /// The streak before this week: the number the week in progress can add one to.
    let streakBeforeThisWeek: Int

    /// `records` may come in any order and may have gaps; `today` decides which week is current.
    init(records: [DayRecord], today: Date, calendar base: Calendar) {
        var calendar = base
        calendar.firstWeekday = 2
        let byDay = Dictionary(records.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let todayStart = calendar.startOfDay(for: today)
        let thisMonday = Self.monday(of: todayStart, calendar)
        let earliest = byDay.keys.min().map { Self.monday(of: $0, calendar) } ?? thisMonday

        var weeks: [Week] = []
        var monday = earliest
        while monday <= thisMonday {
            let start = monday
            let days: [DayRecord?] = (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                if day > todayStart { return nil }
                return byDay[day] ?? DayRecord(date: day, score: nil)
            }
            weeks.append(Week(id: monday, days: days, isCurrent: monday == thisMonday))
            monday = calendar.date(byAdding: .weekOfYear, value: 1, to: monday)!
        }
        self.weeks = weeks

        var streak = 0, best = 0
        for week in weeks where !week.isCurrent {
            streak = week.isWon ? streak + 1 : 0
            best = max(best, streak)
        }
        streakBeforeThisWeek = streak
        let thisWeekWon = weeks.last.map { $0.isCurrent && $0.isWon } ?? false
        currentStreak = thisWeekWon ? streak + 1 : streak
        bestStreak = max(best, currentStreak)
    }

    var thisWeek: Week? { weeks.last { $0.isCurrent } }

    static func monday(of day: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)!.start
    }
}

// MARK: - A week's pattern

/// How a finished week went, in one short line drawn from its seven scores: when it was won, or the
/// shape it took if it wasn't. Only what the day scores can tell; never a guess about hours or apps.
enum WeekPattern {
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Two halves or two parts of the week this far apart (in tenths) make a shape worth naming.
    static let gap = 10

    static func headline(days: [ZenScore?], wonOn: Int?) -> String {
        let scored = days.prefix(7).enumerated().compactMap { i, s in s.map { (i, $0.tenths) } }
        let good = scored.filter { ZenScore(tenths: $0.1).isGoodDay }.count
        if scored.count < 3 { return "A quiet week on record" }
        if good == 7 { return "Seven good days of seven" }
        if let wonOn, dayNames.indices.contains(wonOn) {
            switch wonOn {
            case ...3: return "Won by \(dayNames[wonOn])"
            case 4: return "Won on Friday"
            default: return "Sealed on \(dayNames[wonOn])"
            }
        }
        if good == 3 { return "One good day short" }
        func mean(_ part: [(Int, Int)]) -> Int? { part.isEmpty ? nil : part.map(\.1).reduce(0, +) / part.count }
        if let start = mean(scored.filter { $0.0 <= 2 }), let finish = mean(scored.filter { $0.0 >= 4 }) {
            if start - finish >= gap { return "Strong start, slow finish" }
            if finish - start >= gap { return "Slow start, strong finish" }
        }
        if let weekdays = mean(scored.filter { $0.0 < 5 }), let weekend = mean(scored.filter { $0.0 >= 5 }) {
            if weekend - weekdays >= gap { return "Busy weekdays, calm weekend" }
            if weekdays - weekend >= gap { return "Calm weekdays, busy weekend" }
        }
        let values = scored.map(\.1)
        if let hi = values.max(), let lo = values.min(), hi - lo <= gap { return "Steady all week" }
        let low = scored.min { $0.1 < $1.1 }!
        return "\(dayNames[low.0]) pulled it down"
    }
}

// MARK: - The weekly review

/// What the weekly review may be written from: outcomes only. The iPhone contributes its score and
/// nothing else; a computer may add its distracting minutes and pull-backs.
struct WeekRecap: Codable, Equatable, Sendable {
    struct Device: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case iPhone, mac, windows, linux, android }
        let kind: Kind
        let daysCounted: Int
        /// nil on an iPhone: its minutes never leave it.
        let distractingMinutes: Int?
        let pullBacks: Int?

        init(kind: Kind, daysCounted: Int, distractingMinutes: Int?, pullBacks: Int?) {
            self.kind = kind
            self.daysCounted = daysCounted
            self.distractingMinutes = kind == .iPhone ? nil : distractingMinutes
            self.pullBacks = kind == .iPhone ? nil : pullBacks
        }
    }

    /// Monday first, in tenths; nil is a day with no data.
    let dayScores: [Int?]
    let weeklyStreak: Int
    let devices: [Device]

    var progress: WeekProgress {
        WeekProgress(days: dayScores.map { $0.map(ZenScore.init(tenths:)) }, todayIndex: dayScores.lastIndex { $0 != nil },
                     streakBefore: weeklyStreak)
    }
}

/// The Sunday review: a headline, a short read of the week, and one small experiment for the next.
/// Gemini Pro writes it on the server; the app shows it only after `validated()`.
struct WeeklyReview: Codable, Equatable, Sendable {
    let headline: String
    let body: String
    let experiment: String

    static let headlineLimit = 60
    static let bodyLimit = 320
    static let experimentLimit = 120

    func validated() throws(ReviewRejection) -> WeeklyReview {
        let h = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = experiment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, !b.isEmpty, !e.isEmpty else { throw .empty }
        guard h.count <= Self.headlineLimit, b.count <= Self.bodyLimit, e.count <= Self.experimentLimit else { throw .tooLong }
        let lower = (h + " " + b + " " + e).lowercased()
        if Self.clinicalWords.contains(where: lower.contains) { throw .clinical }
        return WeeklyReview(headline: h, body: b, experiment: e)
    }

    /// The review stays a friend's read of a week, never a diagnosis.
    static let clinicalWords = ["addict", "disorder", "diagnos", "adhd", "depress", "anxiety", "therapy"]

    /// Written here from the numbers alone, when Gemini can't answer.
    static func fallback(for recap: WeekRecap) -> WeeklyReview {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let p = recap.progress
        let scored = recap.dayScores.enumerated().compactMap { i, s in s.map { (i, $0) } }
        let headline = p.isWon ? "Week won · \(p.weeklyStreak)-week streak" : "\(p.goodDays) of 4 good days this week"
        var body = "No scores yet this week."
        if let best = scored.max(by: { $0.1 < $1.1 }), let low = scored.min(by: { $0.1 < $1.1 }) {
            let bestText = ZenScore(tenths: best.1).text, lowText = ZenScore(tenths: low.1).text
            body = best.0 == low.0
                ? "\(names[best.0]) came in at \(bestText)."
                : "\(names[best.0]) was your calmest day at \(bestText). \(names[low.0]) dipped to \(lowText)."
        }
        let experiment = p.isWon
            ? "Keep the evenings that worked. Pick one and protect it again."
            : "Pick the day that dipped and plan one phone-free hour into it."
        return WeeklyReview(headline: headline, body: body, experiment: experiment)
    }
}

enum ReviewRejection: Error, Equatable, Sendable {
    case empty, tooLong, clinical
}

protocol WeeklyReviewService: Sendable {
    func review(for recap: WeekRecap) async throws -> WeeklyReview
    /// Who wrote the review: `.gemini` for the live model (the default), `.fallback` for anything canned.
    var source: NudgeSource { get }
}

extension WeeklyReviewService {
    var source: NudgeSource { .gemini }
}

/// Timeout, validation and the local fallback around any review service.
struct ResilientReviews: Sendable {
    let service: any WeeklyReviewService
    var timeout: Duration = .seconds(8)

    func review(for recap: WeekRecap) async -> (WeeklyReview, NudgeSource) {
        let service = self.service, timeout = self.timeout
        let live: WeeklyReview? = await withTaskGroup(of: WeeklyReview?.self) { group in
            group.addTask { try? await service.review(for: recap).validated() }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let live { return (live, service.source) }
        return (.fallback(for: recap), .fallback)
    }
}

// MARK: - Demo data

/// A review in the voice Gemini is asked for, for the offline demo.
struct FakeReviews: WeeklyReviewService {
    /// A canned review: never credited to Gemini.
    var source: NudgeSource { .fallback }

    func review(for recap: WeekRecap) async throws -> WeeklyReview {
        try await Task.sleep(for: .milliseconds(1200))
        return WeeklyReview(
            headline: "Wednesdays are your calm day",
            body: "Three good days so far, with Wednesday at 8.1 leading. Thursday dipped to 5.4, mostly after 9 pm on the Mac. You pulled back 23 times this week, which is how good days get made.",
            experiment: "This Thursday, close the laptop at 9 and leave the phone outside the room.")
    }
}

enum WeekDemo {
    /// Twelve weeks ending today, matching `FakeScores.snapshot(now:)` for this week: nine won weeks
    /// before it, a short week before those, and earlier weeks that come and go.
    static func history(today: Date, calendar base: Calendar) -> [DayRecord] {
        var calendar = base
        calendar.firstWeekday = 2
        let todayStart = calendar.startOfDay(for: today)
        let monday = calendar.dateInterval(of: .weekOfYear, for: todayStart)!.start
        let thisWeek: [Int?] = [72, 58, 81, 54, 81, nil, nil]
        var seed: UInt64 = 46
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % 1000)
        }
        var records: [DayRecord] = []
        for weeksBack in (0..<12).reversed() {
            let start = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: monday)!
            for d in 0..<7 {
                let day = calendar.date(byAdding: .day, value: d, to: start)!
                guard day <= todayStart else { continue }
                let score: Int?
                if weeksBack == 0 {
                    score = thisWeek[d]
                } else if weeksBack <= 9 {
                    // A won week: four or more good weekdays, the rest anywhere.
                    score = d < 5 && d != weeksBack % 5 ? 62 + next() % 26 : (next() % 4 == 0 ? nil : 45 + next() % 40)
                } else if weeksBack == 10 {
                    score = d < 2 ? 64 + next() % 10 : 40 + next() % 20
                } else {
                    score = next() % 6 == 0 ? nil : 48 + next() % 40
                }
                records.append(DayRecord(date: day, score: score.map(ZenScore.init(tenths:))))
            }
        }
        return records
    }

    /// This week, for the review: outcomes only.
    static let recap = WeekRecap(dayScores: [72, 58, 81, 54, 81, nil, nil], weeklyStreak: 9, devices: [
        .init(kind: .iPhone, daysCounted: 5, distractingMinutes: nil, pullBacks: nil),
        .init(kind: .mac, daysCounted: 5, distractingMinutes: 252, pullBacks: 23),
    ])
}
