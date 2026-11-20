import Foundation
import Observation
import ZenAPI

/// What the person chose about Zeno, saved on this Mac. The Island choices travel to the iPhone
/// with the account once sync carries them.
struct PreferenceValues: Codable, Equatable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Sendable {
        case gentle, balanced, chatty

        /// Lines a day outside onboarding, reactions and the hand-off (Flow 05: two by default).
        var perDay: Int {
            switch self {
            case .gentle: 2
            case .balanced: 4
            case .chatty: 6
            }
        }

        var label: String {
            switch self {
            case .gentle: "Gentle"
            case .balanced: "Balanced"
            case .chatty: "Chatty"
            }
        }
    }

    /// The moments Zeno may speak for.
    enum Moment: String, Codable, CaseIterable, Sendable {
        case goodDay, pickup, checkIn, calendar, weeklyReview

        var title: String {
            switch self {
            case .goodDay: "A good day lands"
            case .pickup: "Back again"
            case .checkIn: "Gentle check-ins"
            case .calendar: "Calendar heads-ups"
            case .weeklyReview: "Weekly review is ready"
            }
        }

        var example: String {
            switch self {
            case .goodDay: "\"Good day locked in. Nice.\""
            case .pickup: "\"Back again. Something on purpose?\""
            case .checkIn: "\"Stretch? You've been at it a while.\""
            case .calendar: "\"Busy at 2:00. I'll keep quiet then.\""
            case .weeklyReview: "\"Your week, read. It's on Today.\""
            }
        }
    }

    var zenoInNotch = true
    var frequency: Frequency = .gentle
    var moments: Set<Moment> = Set(Moment.allCases)
    var quietInCalendarEvents = true
    var quiet: QuietHours = .none
    // The iPhone's Dynamic Island
    var islandScore = true
    var islandGoodDay = true
    var islandFocus = true
    var islandReactions = true
}

@MainActor
@Observable
final class ZenPreferences {
    var values: PreferenceValues { didSet { if values != oldValue { save() } } }
    /// Lines Zeno has spent today, by day, against the budget.
    private var spent: (day: Date, count: Int) = (.distantPast, 0)

    private static let key = "zen.preferences.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(PreferenceValues.self, from: data) {
            values = saved
        } else {
            values = PreferenceValues()
        }
    }

    /// Whether Zeno may speak for `moment` now, and if so, counts it against today's budget.
    func spend(_ moment: PreferenceValues.Moment, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard values.zenoInNotch, values.moments.contains(moment) else { return false }
        if !calendar.isDate(spent.day, inSameDayAs: now) { spent = (now, 0) }
        guard spent.count < values.frequency.perDay else { return false }
        spent.count += 1
        return true
    }

    var spentToday: Int { Calendar.current.isDateInToday(spent.day) ? spent.count : 0 }

    private func save() {
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: Self.key) }
    }
}
