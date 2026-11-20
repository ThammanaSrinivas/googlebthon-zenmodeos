import Foundation
import Testing
@testable import ZenLogic

struct DayKeysTests {
    let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    let kiribati = TimeZone(identifier: "Pacific/Kiritimati")!
    /// 2026-11-20T20:00:00Z
    let lateUTC = Date(timeIntervalSince1970: 1_795_204_800)

    @Test func theKeyIsTheDayInTheZoneItWasLivedIn() {
        #expect(DayKeys.key(for: lateUTC, in: kolkata) == "2026-11-21") // 01:30 next day
        #expect(DayKeys.key(for: lateUTC, in: losAngeles) == "2026-11-20") // 12:00
        #expect(DayKeys.key(for: lateUTC, in: TimeZone(secondsFromGMT: 0)!) == "2026-11-20")
    }

    @Test func theKeyIsASCIIWhateverTheDate() {
        let key = DayKeys.key(for: Date(timeIntervalSince1970: 0), in: TimeZone(secondsFromGMT: 0)!)
        #expect(key == "1970-01-01")
        #expect(key.utf8.allSatisfy { $0 < 128 })
    }

    @Test func theLatestAllowedDayIsUTCPlusFourteen() {
        // 20:00 UTC on the 20th is 10:00 on the 21st in Kiribati.
        #expect(DayKeys.latestAllowed(now: lateUTC) == "2026-11-21")
        #expect(DayKeys.key(for: lateUTC, in: kiribati) == DayKeys.latestAllowed(now: lateUTC))
        // 06:30 UTC is 20:30 the same day there.
        #expect(DayKeys.latestAllowed(now: Date(timeIntervalSince1970: 1_795_156_200)) == "2026-11-20")
    }

    @Test func validKeysAreRealDatesInASCIIDigits() {
        #expect(DayKeys.isValid("2026-02-28"))
        #expect(DayKeys.isValid("2028-02-29"))
        #expect(!DayKeys.isValid("2026-02-29"))
        #expect(!DayKeys.isValid("2026-13-01"))
        #expect(!DayKeys.isValid("2026-1-01"))
        #expect(!DayKeys.isValid("٢٠٢٦-١١-٢٠"))
        #expect(!DayKeys.isValid("2026/11/20"))
        #expect(!DayKeys.isValid(""))
    }

    @Test func keysStepAcrossMonthsAndYears() {
        #expect(DayKeys.adding(1, to: "2026-12-31") == "2027-01-01")
        #expect(DayKeys.adding(-1, to: "2028-03-01") == "2028-02-29")
        #expect(DayKeys.adding(1, to: "nonsense") == nil)
    }

    @Test func weeksStartOnMonday() {
        #expect(DayKeys.weekStart(of: "2026-11-20") == "2026-11-16") // a Friday
        #expect(DayKeys.weekStart(of: "2026-11-16") == "2026-11-16")
        #expect(DayKeys.weekStart(of: "2026-11-22") == "2026-11-16") // Sunday
        #expect(LocalDate.parse("2026-11-20")?.dayOfWeek == .friday)
        #expect(LocalDate(year: 1970, month: 1, day: 1).dayOfWeek == .thursday)
    }

    @Test func civilMathsRoundTrips() {
        for epochDay in stride(from: -800_000, through: 800_000, by: 997) {
            let date = LocalDate(epochDay: epochDay)
            #expect(LocalDate(year: date.year, month: date.month, day: date.dayOfMonth) == date)
        }
        #expect(LocalDate(year: 2026, month: 11, day: 20).daysUntil(LocalDate(year: 2027, month: 1, day: 1)) == 42)
    }

    @Test func aDayStartsAtLocalMidnightAcrossDST() {
        // 2026-03-08: Los Angeles springs forward; the day is 23 hours long.
        let day = LocalDate(year: 2026, month: 3, day: 8)
        let length = day.plusDays(1).startOfDay(in: losAngeles).timeIntervalSince(day.startOfDay(in: losAngeles))
        #expect(length == 23 * 3_600)
        #expect(DayKeys.key(for: day.startOfDay(in: losAngeles), in: losAngeles) == "2026-03-08")
    }
}
