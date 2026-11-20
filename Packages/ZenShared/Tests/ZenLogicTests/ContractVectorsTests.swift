// Replays the shared vectors the Kotlin, the server and this port are all held to.
import Foundation
import Testing
@testable import ZenLogic

struct ContractVectorsTests {
    /// zen_score_v1.json: written by the Kotlin, replayed by every port.
    @Test func zenScoreV1Vectors() throws {
        let vectors = try Vectors.load("zen_score_v1.json")
        #expect(vectors["version"] as? Int == 1)
        let cases = vectors["cases"] as! [[String: Any]]
        #expect(cases.count >= 50)
        for c in cases {
            let got = ZenScoreRule.compute(screenTimeMillis: c["screenTimeMillis"] as! Int, distractedSessions: c["distractedSessions"] as! Int, promiseHours: c["promiseHours"] as! Int)
            #expect(got == c["tenths"] as? Int, "\(c["name"]!)")
        }
    }

    /// Every point of the grid, by the digests the Kotlin wrote: one per promise, so a mismatch
    /// says where, then the whole grid.
    @Test func zenScoreV1Grid() throws {
        let grid = try ZenScoreGrid.shared.get()
        let digests = grid.digests()
        #expect(grid.sha256ByPromiseHours.count == grid.promiseHours.count)
        for (h, hours) in grid.promiseHours.enumerated() {
            #expect(digests.byPromiseHours[h] == grid.sha256ByPromiseHours[h], "every grid point with a \(hours)-hour promise")
        }
        #expect(digests.all == grid.sha256)
    }

    /// name_policy_v1.json: the server's verdict on every case.
    @Test func namePolicyV1Vectors() throws {
        let vectors = try Vectors.load("name_policy_v1.json")
        #expect(vectors["version"] as? Int == 1)
        let cases = (vectors["cases"] as! [[String: Any]]).map { ($0["name"] as! String, $0["expect"] as! String) }
        #expect(cases.count >= 47)
        for verdict in ["ok", "offensive", "contact"] {
            #expect(cases.contains { $0.1 == verdict })
        }
        for (name, expect) in cases {
            #expect(NamePolicy.check(name).rawValue == expect, "\(name)")
        }
    }
}
