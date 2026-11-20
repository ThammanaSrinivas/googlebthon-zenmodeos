// ZenScoreRule (the Zen Score formula), ported with the Kotlin original's tests, then the promises the formula makes over
// zen_score_v1.json's whole grid, as the server's port checks them.
import Testing
import ZenAPI
@testable import ZenLogic

struct ZenScoreTests {
    private let hour = 3_600_000
    private let promise = 4

    private func score(_ screenTimeMillis: Int, distracted: Int = 0) -> Int {
        ZenScoreRule.compute(screenTimeMillis: screenTimeMillis, distractedSessions: distracted, promiseHours: promise)
    }

    @Test func keepingThePromiseExactlyIsWorthEight() {
        #expect(score(promise * hour) == 80)
    }

    @Test func aKeptDayNeverDropsBelowEightHoweverDistracted() {
        for h in 0...4 {
            #expect(score(h * hour, distracted: 500) >= CoreConstants.SCORE_KEPT_TENTHS)
        }
    }

    @Test func halfThePromiseOrLessUndistractedIsAFullTen() {
        #expect(score(promise * hour / 2) == ZenScoreRule.MAX_TENTHS)
        #expect(score(0) == ZenScoreRule.MAX_TENTHS)
    }

    @Test func threeQuartersOfThePromiseLandsAtNine() {
        #expect(score(promise * hour * 3 / 4) == 90)
    }

    @Test func distractionsOnlyEatIntoTheUnusedTimeBonus() {
        // 0.3 + 0.3/2^1.3 + 0.3/3^1.3 = 0.49 off a 9.0 day.
        #expect(score(promise * hour * 3 / 4, distracted: 3) == 85)
    }

    @Test func goingOverCostsAGentleSaturatingPenalty() {
        #expect(score(promise * hour * 11 / 10) == 76) // 10% over
        #expect(score(promise * hour * 3 / 2) == 65) // 50% over
        #expect(score(2 * promise * hour) == 58) // twice the promise
        #expect(score(100 * promise * hour) == 52) // wildly over: the penalty caps at 2.8
    }

    @Test func theWorstPossibleDayStillReadsAboveTheFloor() {
        let worst = score(100 * promise * hour, distracted: Int(Int32.max))
        #expect(worst >= CoreConstants.SCORE_FLOOR_TENTHS)
        #expect((38...42).contains(worst)) // 8 - 2.8 - ~1.2
    }

    @Test func moreScreenTimeNeverRaisesTheScore() {
        let scores = (0...40).map { score($0 * hour / 4, distracted: 2) }
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $1 <= $0 })
    }

    @Test func anotherDistractionNeverRaisesTheScore() {
        let scores = (0...30).map { score(5 * hour, distracted: $0) }
        #expect(zip(scores, scores.dropFirst()).allSatisfy { $1 <= $0 })
    }

    @Test func scoreNeverLeavesTheFloorTo10Range() {
        let range = CoreConstants.SCORE_FLOOR_TENTHS...ZenScoreRule.MAX_TENTHS
        #expect(range.contains(ZenScoreRule.compute(screenTimeMillis: -5, distractedSessions: -3, promiseHours: 0)))
        #expect(range.contains(ZenScoreRule.compute(screenTimeMillis: Int.max / 2, distractedSessions: Int(Int32.max), promiseHours: 1)))
    }

    @Test func theConvenienceScoresMinutesAgainstAPromiseInMinutes() {
        #expect(ZenScoreRule.score(minutes: 180, pullBacks: 3, promiseMinutes: 240).tenths
                == ZenScoreRule.compute(screenTimeMillis: 180 * 60_000, distractedSessions: 3, promiseHours: 4))
        #expect(ZenScoreRule.untouchedDay == ZenScore(tenths: 100))
        #expect(ZenScoreRule.millis(ofMinutes: Int.max) == Int.max)
    }

    // ── Beyond the Kotlin test ────────────────────────────────────

    @Test func roundingSendsATieUpAndNothingElse() {
        #expect(ZenScoreRule.roundToInt(97.5) == 98)
        #expect(ZenScoreRule.roundToInt(80.49999999999999) == 80)
        #expect(ZenScoreRule.roundToInt(0.49999999999999994) == 0)
        #expect(ZenScoreRule.roundToInt(-2.5) == -2)
    }

    /// Eight hours on a four-hour promise: the pre-783ad23 formula wrote 2.5, the kinder one 5.8.
    @Test func eightHoursOnAFourHourPromiseScoresFivePointEight() {
        #expect(ZenScoreRule.compute(screenTimeMillis: 8 * hour, distractedSessions: 0, promiseHours: 4) == 58)
    }

    // ── Over the whole grid (zenScore.test.ts) ────────────────────

    /// The grid points `breaks` is true for, as "minutes/pull-backs/hours"; none when kept.
    private func pointsWhere(_ breaks: (_ h: Int, _ d: Int, _ m: Int, _ tenths: Int) -> Bool) throws -> [String] {
        let grid = try ZenScoreGrid.shared.get()
        var found: [String] = []
        for h in grid.promiseHours.indices {
            for d in grid.distractedSessions.indices {
                for m in grid.minutes.indices where breaks(h, d, m, grid.tenths[h][d][m]) {
                    found.append("\(grid.minutes[m])/\(grid.distractedSessions[d])/\(grid.promiseHours[h])")
                }
            }
        }
        return found
    }

    @Test func itStaysBetween2Point5And10() throws {
        #expect(try pointsWhere { _, _, _, tenths in !(CoreConstants.SCORE_FLOOR_TENTHS...ZenScoreRule.MAX_TENTHS).contains(tenths) } == [])
    }

    @Test func moreTimeNeverRaisesItAnywhereOnTheGrid() throws {
        let grid = try ZenScoreGrid.shared.get()
        #expect(try pointsWhere { h, d, m, tenths in m > 0 && tenths > grid.tenths[h][d][m - 1] } == [])
    }

    @Test func anotherPullBackNeverRaisesItAnywhereOnTheGrid() throws {
        let grid = try ZenScoreGrid.shared.get()
        #expect(try pointsWhere { h, d, m, tenths in d > 0 && tenths > grid.tenths[h][d - 1][m] } == [])
    }

    @Test func aKeptPromiseIsWorthEightOrMoreGoingOverEightOrLess() throws {
        let grid = try ZenScoreGrid.shared.get()
        #expect(try pointsWhere { h, _, m, tenths in
            grid.minutes[m] <= grid.promiseHours[h] * 60 ? tenths < CoreConstants.SCORE_KEPT_TENTHS : tenths > CoreConstants.SCORE_KEPT_TENTHS
        } == [])
    }
}
