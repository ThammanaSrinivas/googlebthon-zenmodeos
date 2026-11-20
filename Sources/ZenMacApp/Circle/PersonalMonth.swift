import Foundation

/// The person's own month, and what it says about them. Demo until day history is wired: a builder
/// who is mostly a Deep worker, with a few late nights. The facts are read from the hours, never
/// typed, so the hero, the cards and Today all agree.
struct PersonalMonth: Sendable {
    let hours: MonthHours

    /// The hour of the day with the most focus across the month.
    var calmestHour: Int { hours.mindfulHour }
    var focusHours: Int { hours.focusHours }
    var unplannedHours: Int { hours.unplannedHours }

    /// Hours on a screen that went to something on purpose (focus or intentional), as a share.
    var onPurposeShare: Double {
        let active = hours.cells.filter { $0 != .rest }.count
        guard active > 0 else { return 0 }
        return Double(hours.cells.filter { $0 == .focus || $0 == .intentional }.count) / Double(active)
    }

    /// The archetype whose day-shape is closest to this month's: cosine over, for each hour of the
    /// day, how often a screen was on and how often it was focus.
    var closest: Archetype {
        let mine = Self.profile(hours)
        return Archetype.allCases.max { a, b in
            Self.similarity(mine, Self.profile(a.month(seed: 2026))) < Self.similarity(mine, Self.profile(b.month(seed: 2026)))
        } ?? .deepWorker
    }

    /// "Mid-afternoon", "Early morning": the calmest hour in words.
    var calmestPart: String {
        switch calmestHour {
        case 5..<9: "Early morning"
        case 9..<12: "Late morning"
        case 12..<14: "Around lunch"
        case 14..<17: "Mid-afternoon"
        case 17..<21: "Early evening"
        default: "Late at night"
        }
    }

    static let demo = PersonalMonth.make(seed: 0x5EED_2026)

    /// Deep afternoons, focused mornings, a little drift in the evenings, and late Thursdays.
    static func make(seed: UInt64) -> PersonalMonth {
        var s = seed
        func rand() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double(s >> 11) / Double(1 << 53)
        }
        var cells: [MonthHours.Feel] = []
        cells.reserveCapacity(720)
        var focusByHour = [Int](repeating: 0, count: 24)
        for day in 0..<30 {
            let weekday = day % 7          // 0 = Monday
            let lateNight = weekday == 3   // Thursdays run late
            let weekend = weekday >= 5
            for hour in 0..<24 {
                let (active, focus, unplanned): (Double, Double, Double)
                switch hour {
                case 0..<1 where lateNight: (active, focus, unplanned) = (0.8, 0.1, 0.65)
                case 0..<7: (active, focus, unplanned) = (0.03, 0.1, 0.4)
                case 7..<9: (active, focus, unplanned) = (0.45, 0.2, 0.25)
                case 9..<13: (active, focus, unplanned) = (weekend ? 0.4 : 0.75, weekend ? 0.15 : 0.5, 0.12)
                case 13..<18: (active, focus, unplanned) = (weekend ? 0.45 : 0.93, weekend ? 0.2 : 0.78, 0.04)
                case 18..<21: (active, focus, unplanned) = (0.5, 0.12, 0.32)
                case 21..<23: (active, focus, unplanned) = (lateNight ? 0.85 : 0.45, 0.05, lateNight ? 0.6 : 0.4)
                default: (active, focus, unplanned) = (lateNight ? 0.7 : 0.08, 0.05, 0.55)
                }
                if rand() > active { cells.append(.rest); continue }
                let r = rand()
                let feel: MonthHours.Feel = r < focus ? .focus : (r < focus + unplanned ? .unplanned : .intentional)
                if feel == .focus { focusByHour[hour] += 1 }
                cells.append(feel)
            }
        }
        let calmest = focusByHour.indices.max { focusByHour[$0] < focusByHour[$1] } ?? 14
        // The day that hour shone brightest: the first focused one after mid-month.
        let day = (15..<30).first { cells[$0 * 24 + calmest] == .focus } ?? 17
        return PersonalMonth(hours: MonthHours(cells: cells, mindfulHour: calmest, mindfulDay: day))
    }

    /// For each hour of the day: the share of days on a screen, then the share of days in focus.
    static func profile(_ m: MonthHours) -> [Double] {
        let active = (0..<24).map { h in Double((0..<30).filter { m.feel(day: $0, hour: h) != .rest }.count) / 30 }
        let focus = (0..<24).map { h in Double((0..<30).filter { m.feel(day: $0, hour: h) == .focus }.count) / 30 }
        return active + focus.map { $0 * 2 }
    }

    static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let na = sqrt(a.reduce(0) { $0 + $1 * $1 }), nb = sqrt(b.reduce(0) { $0 + $1 * $1 })
        return na == 0 || nb == 0 ? 0 : dot / (na * nb)
    }
}
