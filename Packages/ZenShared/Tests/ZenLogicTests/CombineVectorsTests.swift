// Replays Vectors/combine_v1.json: the cases the server's combine is held to, generated from the
// server's implementation and kept byte-identical here. This test FAILS while the file is missing.
//
// The file's keys follow the wire shapes the server writes: `phone.report` is a phone report with a
// `zenScore` in tenths, `computers[].report` a ComputerDayReport (same keys as ZenAPI's), each with
// the `writtenAt` the backend stamped, and `expected` the exact combined day (null for none), its
// devices without pull-backs. The decoder below maps those shapes onto ZenAPI and ZenLogic types;
// the file itself is never adapted. Dates are ISO-8601.
import Foundation
import Testing
import ZenAPI
@testable import ZenLogic

struct CombineVectorsTests {
    static let file = "combine_v1.json"

    /// The phone report as the vectors spell it.
    struct WirePhone: Decodable {
        let platform: DevicePlatform
        let day: DayKey
        let zenScore: Int
        let minutes: Int?

        var report: PhoneDayReport {
            PhoneDayReport(platform: platform, day: day, score: ZenScore(tenths: zenScore), minutes: minutes)
        }
    }

    /// A device's part as the vectors spell it; `init(_:)` projects ours onto it to compare.
    struct WireDevice: Decodable, Equatable {
        let kind: DeviceContribution.Kind
        let platform: DevicePlatform
        let deviceId: String?
        let counted: Bool
        let zenScore: Int?
        let minutes: Int?
        let lastSeen: Date?

        init(_ d: DeviceContribution) {
            kind = d.kind
            platform = d.platform
            deviceId = d.deviceId
            counted = d.counted
            zenScore = d.score?.tenths
            minutes = d.minutes
            lastSeen = d.lastSeen
        }
    }

    struct WireDay: Decodable, Equatable {
        let day: DayKey
        let zenScore: Int
        let minutes: Int?
        let scoreOnly: Bool
        let devices: [WireDevice]
        let updatedAt: Date

        init(_ c: CombinedDay) {
            day = c.day
            zenScore = c.score.tenths
            minutes = c.minutes
            scoreOnly = c.scoreOnly
            devices = c.devices.map(WireDevice.init)
            updatedAt = c.updatedAt
        }
    }

    struct File: Decodable {
        struct Rules: Decodable {
            let phoneFreshHours: Double
            let placeHeldDays: Double
            let furthestZoneAheadHours: Double
            let defaultDeviceLimit: Int
        }

        struct Stamped<Report: Decodable>: Decodable {
            let report: Report
            let writtenAt: Date
        }

        struct Case: Decodable {
            let name: String
            let now: Date
            let deviceLimit: Int?
            let phone: Stamped<WirePhone>?
            let computers: [Stamped<ComputerDayReport>]
            let expected: WireDay?
        }

        let version: Int
        let combineVersion: Int
        let rules: Rules
        let cases: [Case]
    }

    static func load() throws -> File? {
        guard let url = Vectors.url(file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(File.self, from: Data(contentsOf: url))
    }

    @Test func theFileIsThere() throws {
        #expect(try Self.load() != nil, "Tests/ZenLogicTests/Vectors/\(Self.file) is missing: copy it byte-identical from the backend's contract vectors")
    }

    @Test func theRulesMatchThisPort() throws {
        let vectors = try #require(try Self.load())
        #expect(vectors.version == 1)
        #expect(vectors.combineVersion == CombineRule.version)
        #expect(vectors.rules.phoneFreshHours * 3_600 == CombineRule.phoneFresh)
        #expect(vectors.rules.placeHeldDays * 86_400 == CombineRule.placeHeld)
        #expect(vectors.rules.furthestZoneAheadHours * 3_600 == DayKeys.furthestZoneAhead)
        #expect(vectors.rules.defaultDeviceLimit == CombineRule.defaultDeviceLimit)
    }

    @Test func everyCaseCombinesExactlyAsTheServerDoes() throws {
        let vectors = try #require(try Self.load())
        #expect(vectors.cases.count == 36)
        for c in vectors.cases {
            let got = CombineRule.combine(
                phone: c.phone.map { PhoneDayInput(report: $0.report.report, writtenAt: $0.writtenAt) },
                computers: c.computers.map { ComputerDayInput(report: $0.report, writtenAt: $0.writtenAt) },
                deviceLimit: c.deviceLimit ?? CombineRule.defaultDeviceLimit, now: c.now)
            #expect(got.map(WireDay.init) == c.expected, "\(c.name)")
        }
    }

    /// Every computer the combine lists carries the pull-backs it reported (the vectors don't
    /// spell them, so this checks them against the inputs).
    @Test func computersCarryTheirOwnPullBacks() throws {
        let vectors = try #require(try Self.load())
        for c in vectors.cases {
            let got = CombineRule.combine(
                phone: c.phone.map { PhoneDayInput(report: $0.report.report, writtenAt: $0.writtenAt) },
                computers: c.computers.map { ComputerDayInput(report: $0.report, writtenAt: $0.writtenAt) },
                deviceLimit: c.deviceLimit ?? CombineRule.defaultDeviceLimit, now: c.now)
            let reported = Dictionary(c.computers.map { ($0.report.deviceId, $0.report.pullBacks) }, uniquingKeysWith: max)
            for device in got?.devices ?? [] where device.kind == .computer {
                #expect(device.pullBacks == reported[device.deviceId ?? ""], "\(c.name)")
            }
        }
    }
}
