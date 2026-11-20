// An exact port of the ZenMode OS Zen Score formula (the Kotlin original in the Android app).
// The value it produces is ZenAPI's `ZenScore`; this file only computes it.
import Foundation
import ZenAPI

/// The Zen Score formula: 2.5–10.0, computed as whole tenths (25–100).
///
/// Must stay identical to the Kotlin original, the same Double operations in the same order: the
/// phone sends this number, every device shows it, and the server scores a combined day with its
/// own port. All of them replay `Tests/ZenLogicTests/Vectors/zen_score_v1.json`, which the Kotlin
/// writes.
///
/// Rewarding, not punishing: keeping the promise is worth 8.0 and nothing on a kept day takes
/// that away. Only time left unused lifts it toward 10, and distracted sessions only eat into that
/// lift. Going over the promise costs a penalty that saturates (2.8 at most), so even a bad day
/// reads ~5, and nothing reads below 2.5.
public enum ZenScoreRule {
    public static let MAX_TENTHS = 100

    /// Share of the promise left unused at which the unused-time bonus is full.
    private static let BONUS_FULL_AT_UNUSED = 0.5

    /// Past this many, a further distracted session costs effectively nothing (the sum has converged).
    private static let MAX_COUNTED_DISTRACTIONS = 1_000

    /// The score in whole tenths.
    /// - Parameter distractedSessions: the day's distracted sessions (pull-backs). The iPhone has no
    ///   session log, so it passes 0; a computer's come from its tracker.
    public static func compute(screenTimeMillis: Int, distractedSessions: Int, promiseHours: Int) -> Int {
        let promiseMillis = Double(max(promiseHours, 1)) * 3_600_000.0
        let used = Double(max(screenTimeMillis, 0)) / promiseMillis
        let kept = Double(CoreConstants.SCORE_KEPT_TENTHS) / 10.0
        let distraction = distractionPenalty(distractedSessions)
        let points: Double
        if used <= 1.0 {
            let unusedBonus = CoreConstants.SCORE_UNUSED_BONUS_MAX *
                min(max((1.0 - used) / BONUS_FULL_AT_UNUSED, 0.0), 1.0)
            points = kept + max(unusedBonus - distraction, 0.0)
        } else {
            let overPenalty = CoreConstants.SCORE_OVER_PENALTY_MAX *
                (1.0 - exp(-CoreConstants.SCORE_OVER_PENALTY_RATE * (used - 1.0)))
            points = kept - overPenalty - distraction
        }
        return min(max(roundToInt(points * 10), CoreConstants.SCORE_FLOOR_TENTHS), MAX_TENTHS)
    }

    /// The score of a computer-style day: distracting minutes and pull-backs against a promise in
    /// minutes (whole hours, as the contract keeps it).
    public static func score(minutes: Int, pullBacks: Int, promiseMinutes: Int) -> ZenScore {
        ZenScore(tenths: compute(screenTimeMillis: millis(ofMinutes: minutes), distractedSessions: pullBacks,
                                 promiseHours: promiseMinutes / 60))
    }

    /// A day that hasn't used any of its promise yet: what a fresh morning reads (10.0).
    public static var untouchedDay: ZenScore {
        score(minutes: 0, pullBacks: 0, promiseMinutes: CoreConstants.PLACEHOLDER_PROMISE_HOURS * 60)
    }

    /// `minutes` in milliseconds, saturating instead of trapping (the score saturated long before).
    public static func millis(ofMinutes minutes: Int) -> Int {
        let (product, overflow) = minutes.multipliedReportingOverflow(by: 60_000)
        return overflow ? .max : product
    }

    /// 0.3 for the first, then 0.3 / i^1.3 for the i-th, summed from the first: a texture that
    /// stays under ~1.2 points.
    private static func distractionPenalty(_ count: Int) -> Double {
        stride(from: 1, through: min(max(count, 0), MAX_COUNTED_DISTRACTIONS), by: 1).reduce(0.0) { sum, i in
            sum + CoreConstants.SCORE_DISTRACTION_COST / pow(Double(i), CoreConstants.SCORE_DISTRACTION_DECAY)
        }
    }

    /// Kotlin's `Double.roundToInt()` (Math.round): nearest, ties toward positive infinity. Taking
    /// the fraction off is exact, so a tie is a tie (adding 0.5 first can round 0.49999999999999994 up).
    static func roundToInt(_ x: Double) -> Int {
        let whole = x.rounded(.down)
        return Int(x - whole >= 0.5 ? whole + 1 : whole)
    }
}
