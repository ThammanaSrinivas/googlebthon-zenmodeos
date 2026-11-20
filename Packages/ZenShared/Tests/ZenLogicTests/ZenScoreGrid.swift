// zen_score_v1.json's grid (every minute from 0 to 6000, 13 pull-back counts, promises of 1 to 12 h),
// scored once by ZenScore.compute for the tests that check it: the digests the Kotlin wrote
// (ContractVectorsTests) and the promises the formula makes (ZenScoreTests).
@testable import ZenLogic

struct ZenScoreGrid: Sendable {
    static let shared = Result { try ZenScoreGrid() }

    let minutes: [Int]
    let distractedSessions: [Int]
    let promiseHours: [Int]
    /// [promise hours][pull-back count][minutes], in the vectors' order.
    let tenths: [[[Int]]]
    let sha256ByPromiseHours: [String]
    let sha256: String

    private init() throws {
        let grid = try Vectors.load("zen_score_v1.json")["grid"] as! [String: Any]
        func span(_ range: Any?) -> [Int] {
            let bounds = range as! [String: Any]
            return Array((bounds["from"] as! Int)...(bounds["to"] as! Int))
        }
        let minutes = span(grid["minutes"])
        let distractedSessions = grid["distractedSessions"] as! [Int]
        let promiseHours = span(grid["promiseHours"])
        tenths = promiseHours.map { hours in
            distractedSessions.map { distracted in
                minutes.map { ZenScoreRule.compute(screenTimeMillis: $0 * 60_000, distractedSessions: distracted, promiseHours: hours) }
            }
        }
        self.minutes = minutes
        self.distractedSessions = distractedSessions
        self.promiseHours = promiseHours
        sha256ByPromiseHours = grid["sha256ByPromiseHours"] as! [String]
        sha256 = grid["sha256"] as! String
    }

    /// SHA-256 of each promise's lines and of all of them, as the Kotlin hashes them: one ASCII line
    /// `minutes,distractedSessions,promiseHours,tenths\n` per point, in the grid's order.
    func digests() -> (byPromiseHours: [String], all: String) {
        var all = SHA256()
        let byPromiseHours = promiseHours.indices.map { h in
            var one = SHA256()
            for (d, distracted) in distractedSessions.enumerated() {
                for (m, minute) in minutes.enumerated() {
                    let line = Array("\(minute),\(distracted),\(promiseHours[h]),\(tenths[h][d][m])\n".utf8)
                    one.update(line)
                    all.update(line)
                }
            }
            return one.hexDigest()
        }
        return (byPromiseHours, all.hexDigest())
    }
}
