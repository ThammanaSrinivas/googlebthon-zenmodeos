// The contract types on the wire: every Codable type round-trips, the raw values other code (the
// backend, stored settings) depends on are pinned, and the defaults are what the app expects.
// A renamed case or field fails here before it breaks a device or a stored profile.
import Foundation
import Testing
import ZenAPI

private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(Value.self, from: encoder.encode(value))
}

private func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let when = Date(timeIntervalSince1970: 1_795_156_200)

struct CodableRoundTripTests {
    @Test func syncReportsRoundTrip() throws {
        let android = PhoneDayReport(platform: .android, day: "2026-11-20", score: ZenScore(tenths: 72), minutes: 95)
        let iPhone = PhoneDayReport(platform: .ios, day: "2026-11-20", score: ZenScore(tenths: 81))
        let mac = ComputerDayReport(deviceId: String(repeating: "a", count: 32), day: "2026-11-20", countedMinutes: 38,
                                    pullBacks: 4, promiseMinutes: 240, sequence: 7)
        #expect(try roundTrip(android) == android)
        #expect(try roundTrip(iPhone) == iPhone)
        #expect(try roundTrip(mac) == mac)
    }

    @Test func anIPhoneReportNeverEncodesMinutes() throws {
        for platform in [DevicePlatform.ios, .ipados] {
            let report = PhoneDayReport(platform: platform, day: "2026-11-20", score: ZenScore(tenths: 81), minutes: 300)
            #expect(report.minutes == nil)
            #expect(try object(report)["minutes"] == nil)
        }
        let android = PhoneDayReport(platform: .android, day: "2026-11-20", score: ZenScore(tenths: 81), minutes: 300)
        #expect(try object(android)["minutes"] as? Int == 300)
    }

    @Test func aComputerReportDefaultsToTheMac() {
        let report = ComputerDayReport(deviceId: "x", day: "2026-11-20", countedMinutes: 0, pullBacks: 0, promiseMinutes: 60, sequence: 0)
        #expect(report.platform == .macos)
    }

    @Test func voiceAndCardTypesRoundTrip() throws {
        let token = LiveToken(token: "auth_tokens/x", model: "gemini-3.8-live", voice: "Kore",
                              expiresAt: when.addingTimeInterval(1_800), connectBy: when.addingTimeInterval(60))
        let card = ZenCard(id: "c1", summary: "நல்ல நாள்", mood: .happy, language: "ta", earnedBack: "an hour",
                           drift: nil, createdAt: when, sharedAt: when.addingTimeInterval(5))
        let draft = ZenCardDraft(summary: "  Long walk  ", mood: .tired, language: "en-IN", earnedBack: "", drift: "news")
        #expect(try roundTrip(token) == token)
        #expect(try roundTrip(card) == card)
        #expect(try roundTrip(draft) == draft)
        #expect(draft.summary == "Long walk")
        #expect(draft.earnedBack == nil)
    }

    @Test func aTokenNeverAsksToConnectAfterItExpires() {
        let token = LiveToken(token: "t", model: "m", voice: "v", expiresAt: when, connectBy: when.addingTimeInterval(60))
        #expect(token.connectBy == when)
        #expect(token.canConnect(at: when.addingTimeInterval(-1)))
        #expect(!token.canConnect(at: when))
        #expect(token.isExpired(at: when))
    }

    @Test func nudgesRoundTripWithTheirWireNames() throws {
        for action in ZenoNudge.Action.allCases {
            let nudge = ZenoNudge(feeling: .curious, line: "Back again?", action: action)
            #expect(try roundTrip(nudge) == nudge)
        }
        let context = NudgeContext(scoreTenths: 64, goodDaysThisWeek: 2, weeklyStreak: 1, hourOfDay: 21, trigger: .goodDay)
        #expect(try roundTrip(context) == context)
        #expect(try object(context)["trigger"] as? String == "good_day")
    }

    @Test func profilesRoundTripAndDefaultToAPersonalSeatWithNoQuietBlock() throws {
        let profile = Profile()
        #expect(profile.seat == .personal)
        #expect(profile.uses.isEmpty)
        #expect(profile.quiet == .none)
        #expect(profile.cohortCode == nil)
        let full = Profile(seat: .campus, uses: [.study, .build], quiet: .classHours, cohortCode: "ZEN4HS")
        #expect(try roundTrip(profile) == profile)
        #expect(try roundTrip(full) == full)
    }

    @Test func aStoredProfileWithoutACohortCodeStillLoads() throws {
        let json = #"{"seat":"team","uses":["work"],"quiet":{"weekdays":[2,3],"start":600,"end":1080}}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile == Profile(seat: .team, uses: [.work], quiet: QuietHours(weekdays: [2, 3], start: 600, end: 1_080)))
    }

    @Test func aZenScoreIsStoredAsTenths() throws {
        #expect(try object(ZenScore(tenths: 81)) as? [String: Int] == ["tenths": 81])
        #expect(try roundTrip(ZenScore(tenths: 100)) == ZenScore(tenths: 100))
    }
}

/// Raw values other code stores or sends. Changing one is a contract change on both sides.
struct WireValueTests {
    @Test func platforms() {
        #expect(DevicePlatform.allCases.map(\.rawValue) == ["ios", "ipados", "macos", "android", "windows", "linux"])
        #expect(DevicePlatform.allCases.filter(\.isPhone) == [.ios, .android])
        #expect(DevicePlatform.allCases.filter(\.scoreOnly) == [.ios, .ipados])
    }

    @Test func moodsFeelingsAndActions() {
        #expect(ZenCard.Mood.allCases.map(\.rawValue) == ["happy", "pleasant", "neutral", "tired", "sad"])
        #expect(ZenoNudge.Feeling.allCases.map(\.rawValue) == ["happy", "pleasant", "curious", "sad"])
        #expect(ZenoNudge.Action.allCases.map(\.rawValue) == ["none", "start_focus", "open_review", "react_circle"])
    }

    @Test func profileValues() {
        #expect(Profile.Seat.allCases.map(\.rawValue) == ["personal", "campus", "team"])
        #expect(Profile.Use.allCases.map(\.rawValue) == ["study", "work", "build", "create", "everything"])
    }

    @Test func triggers() throws {
        let triggers: [NudgeContext.Trigger] = [.pickup, .goodDay, .checkIn, .hello]
        #expect(triggers.map(\.rawValue) == ["pickup", "good_day", "check_in", "hello"])
    }

    @Test func cardLimitsMatchTheBackend() {
        #expect(ZenCardDraft.maxSummaryLength == 280)
        #expect(ZenCardDraft.maxEarnedBackLength == 40)
        #expect(ZenCardDraft.maxDriftLength == 80)
        #expect(ZenCardDraft.maxNoteLength == 120)
        #expect(ZenoNudge.maxLineLength == 40)
        #expect(CohortSummary.minimumGroupSize == 5)
        #expect(JoinCode.length == 6)
    }
}

struct QuietHoursEdgeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        // 2026-11-16 is a Monday.
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theBlockStartsOnItsMinuteAndEndsBeforeItsEnd() {
        let quiet = QuietHours.classHours
        #expect(!quiet.isQuiet(at: date(16, 8, 59), calendar: calendar))
        #expect(quiet.isQuiet(at: date(16, 9, 0), calendar: calendar))
        #expect(quiet.isQuiet(at: date(16, 15, 59), calendar: calendar))
        #expect(!quiet.isQuiet(at: date(16, 16, 0), calendar: calendar))
        // Saturday at 10 is not in a weekday block.
        #expect(!quiet.isQuiet(at: date(21, 10, 0), calendar: calendar))
    }

    @Test func theNightEdges() {
        #expect(!QuietHours.none.isQuiet(at: date(16, 22, 29), calendar: calendar))
        #expect(QuietHours.none.isQuiet(at: date(16, 22, 30), calendar: calendar))
        #expect(QuietHours.none.isQuiet(at: date(17, 6, 59), calendar: calendar))
        #expect(!QuietHours.none.isQuiet(at: date(17, 7, 0), calendar: calendar))
    }

    @Test func summariesForOddBlocks() {
        #expect(QuietHours(weekdays: [2], start: 600, end: 600).summary == "Only at night")
        #expect(QuietHours(weekdays: [1, 7, 4], start: 12 * 60 + 30, end: 13 * 60 + 5).summary == "3 days a week 12:30–1:05")
        #expect(QuietHours(weekdays: [2, 3, 4, 5, 6], start: 0, end: 60).summary == "Weekdays 12–1")
    }

    @Test func theHourStripWithoutABlockMarksOnlyTheNight() {
        let quiet = (0..<24).filter(QuietHours.none.hourIsQuiet)
        #expect(quiet == [0, 1, 2, 3, 4, 5, 6, 22, 23])
    }
}
