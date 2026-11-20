import Foundation
import Testing
@testable import ZenAPI
import ZenMock

@Suite("Join codes and cohorts")
struct CohortTests {
    @Test("People type codes loosely", arguments: ["zen4hs", "ZEN-4HS", "zen 4hs", "ZEN·4HS"])
    func normalises(raw: String) {
        #expect(JoinCode(raw)?.value == "ZEN4HS")
    }

    @Test("Look-alikes and wrong lengths are refused", arguments: ["ZEN0HS", "ZEN1HS", "ZENOHS", "ZENIHS", "ZEN4H", "ZEN4HSX", ""])
    func refuses(raw: String) {
        #expect(JoinCode(raw) == nil)
    }

    @Test("The text field keeps only what a code can hold")
    func sanitize() {
        #expect(JoinCode.sanitize("k4m-7qx-extra") == "K4M7QX")
        #expect(JoinCode.sanitize("o0i1") == "")
    }

    @Test("Codes read as two groups of three")
    func display() {
        #expect(JoinCode("K4M7QX")?.display == "K4M·7QX")
    }

    @Test("A group under 5 shows no score and no rate")
    func underFive() {
        let preview = CohortPreview(id: "x", name: "Room 12", organisation: "IITM", kind: .campus, memberCount: 4)
        let summary = CohortSummary(preview: preview, score: ZenScore(tenths: 74), goodDayRate: 0.5)
        #expect(summary.score == nil)
        #expect(summary.goodDayRate == nil)
    }

    @Test("A group of 5 or more shows its score")
    func fiveOrMore() {
        let preview = CohortPreview(id: "x", name: "Room 12", organisation: "IITM", kind: .campus, memberCount: 5)
        #expect(CohortSummary(preview: preview, score: ZenScore(tenths: 74), goodDayRate: 0.5).score?.text == "7.4")
    }

    @Test("The fake finds the demo cohort and nothing else")
    func fakeCohorts() async throws {
        let fake = FakeCohorts()
        #expect(try await fake.preview(code: ZenMock.demoCohortCode).name == "Hostel 4")
        await #expect(throws: CohortError.notFound) { try await fake.preview(code: JoinCode("ABC234")!) }
    }
}

@Suite("Quiet hours: Zeno rests in class or work hours, and every night")
struct QuietHoursTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func at(_ weekday: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // 16 Nov 2026 is a Monday (weekday 2).
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16 + (weekday - 2), hour: hour, minute: minute))!
    }

    @Test("Night is always quiet, 22:30 to 07:00")
    func night() {
        #expect(QuietHours.none.isQuiet(at: at(2, 22, 30), calendar: calendar))
        #expect(QuietHours.none.isQuiet(at: at(2, 6, 59), calendar: calendar))
        #expect(!QuietHours.none.isQuiet(at: at(2, 7, 0), calendar: calendar))
        #expect(!QuietHours.none.isQuiet(at: at(2, 22, 29), calendar: calendar))
    }

    @Test("Class hours are quiet on weekdays only")
    func classHours() {
        #expect(QuietHours.classHours.isQuiet(at: at(3, 10), calendar: calendar))
        #expect(!QuietHours.classHours.isQuiet(at: at(3, 16), calendar: calendar))
        #expect(!QuietHours.classHours.isQuiet(at: at(7, 10), calendar: calendar)) // Saturday
    }

    @Test("Summaries read plainly")
    func summaries() {
        #expect(QuietHours.classHours.summary == "Weekdays 9–4")
        #expect(QuietHours.workHours.summary == "Weekdays 10–6")
        #expect(QuietHours.none.summary == "Only at night")
    }

    @Test("The hour strip marks night and the block")
    func strip() {
        let q = QuietHours.classHours
        #expect(q.hourIsQuiet(0) && q.hourIsQuiet(6) && q.hourIsQuiet(22) && q.hourIsQuiet(23))
        #expect(!q.hourIsQuiet(7) && !q.hourIsQuiet(8) && !q.hourIsQuiet(16))
        #expect(q.hourIsQuiet(9) && q.hourIsQuiet(15))
    }
}
