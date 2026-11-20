// The tuning constants the shared rules need (ported from the ZenMode OS core logic, the same
// values the Android app, the desktop app and the server use).

/// Constants shared by `ZenScore`, the promise and the Mac's pull-back rule.
public enum CoreConstants {
    // My Promise: the day's allowance of distracting time, in whole hours.
    public static let PROMISE_MIN_DAILY_HOURS = 1
    public static let PROMISE_MAX_DAILY_HOURS = 12
    /// The promise before the person has chosen one.
    public static let PLACEHOLDER_PROMISE_HOURS = 4

    /// Coming back to a distraction this soon after leaving it is a pull-back (5 minutes).
    public static let RAPID_REOPEN_GAP_MS = 5 * 60_000

    // Zen Score formula (see ZenScore): a kept promise holds 8, going over costs a saturating
    // penalty, distracted sessions are a light texture, and only time left unused reaches 9–10.
    /// What a kept promise is worth, in whole tenths.
    public static let SCORE_KEPT_TENTHS = 80
    /// Nothing reads lower than this: "you've drifted, come back", never "you failed".
    public static let SCORE_FLOOR_TENTHS = 25
    /// Ceiling of the over-promise penalty, in points, and how fast it gets there.
    public static let SCORE_OVER_PENALTY_MAX = 2.8
    public static let SCORE_OVER_PENALTY_RATE = 1.5
    /// Cost of the first distracted session, in points; each later one costs less (÷ i^decay),
    /// so the whole sum stays near one point however many there are.
    public static let SCORE_DISTRACTION_COST = 0.3
    public static let SCORE_DISTRACTION_DECAY = 1.3
    /// The most the unused part of the promise adds, in points; reached at half the promise.
    public static let SCORE_UNUSED_BONUS_MAX = 2.0
}
