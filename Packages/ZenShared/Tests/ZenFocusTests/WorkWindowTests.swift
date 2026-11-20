import Foundation
import Testing
import ZenAPI
@testable import ZenFocus

@Suite("Work hours and the after-hours window")
struct WorkWindowTests {
    let ist = TimeZone(identifier: "Asia/Kolkata")!

    /// 2026-11-20 is a Friday. `ist("2026-11-20 18:30")`.
    func ist(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = ist
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    let office = WorkWindow(WorkHours(start: "09:30", end: "18:30", days: [1, 2, 3, 4, 5], tz: "Asia/Kolkata"))!
    let night = WorkWindow(WorkHours(start: "22:00", end: "06:00", days: [1, 2, 3, 4, 5], tz: "Asia/Kolkata"))!

    @Test("Office hours: inside, the end minute, before, weekend")
    func office9to6() {
        #expect(office.isoWeekday(ist("2026-11-20 12:00")) == 5)
        #expect(office.isWorkTime(ist("2026-11-20 09:30")))
        #expect(office.isWorkTime(ist("2026-11-20 18:29")))
        #expect(!office.isWorkTime(ist("2026-11-20 18:30")))
        #expect(!office.isWorkTime(ist("2026-11-20 09:29")))
        #expect(!office.isWorkTime(ist("2026-11-21 12:00")))
    }

    @Test("Next start skips the weekend: Friday evening → Monday 09:30")
    func nextStart() {
        #expect(office.nextStart(after: ist("2026-11-20 18:30")) == ist("2026-11-23 09:30"))
        #expect(office.nextStart(after: ist("2026-11-19 20:00")) == ist("2026-11-20 09:30"))
        #expect(office.nextStart(after: ist("2026-11-20 07:00")) == ist("2026-11-20 09:30"))
        #expect(office.currentEnd(at: ist("2026-11-20 10:00")) == ist("2026-11-20 18:30"))
        #expect(office.currentEnd(at: ist("2026-11-20 19:00")) == nil)
    }

    @Test("A night shift crosses midnight and belongs to the day it started")
    func nightShift() {
        #expect(night.crossesMidnight)
        #expect(night.isWorkTime(ist("2026-11-20 23:00")))      // Friday night: a Friday shift
        #expect(night.isWorkTime(ist("2026-11-21 05:59")))      // Saturday early: still Friday's shift
        #expect(!night.isWorkTime(ist("2026-11-21 06:00")))
        #expect(!night.isWorkTime(ist("2026-11-21 23:00")))     // Saturday night: not a workday
        #expect(!night.isWorkTime(ist("2026-11-23 03:00")))     // Monday early: Sunday's shift, off
        #expect(night.currentEnd(at: ist("2026-11-20 23:00")) == ist("2026-11-21 06:00"))
        #expect(night.currentEnd(at: ist("2026-11-21 02:00")) == ist("2026-11-21 06:00"))
        #expect(night.nextStart(after: ist("2026-11-21 06:00")) == ist("2026-11-23 22:00"))
    }

    @Test("After-hours minutes across midnight")
    func minutesAcrossMidnight() {
        #expect(office.afterHoursMinutes(from: ist("2026-11-19 18:00"), to: ist("2026-11-19 19:00")) == 30)
        #expect(office.afterHoursMinutes(from: ist("2026-11-19 23:30"), to: ist("2026-11-20 00:30")) == 60)
        #expect(night.afterHoursMinutes(from: ist("2026-11-20 21:30"), to: ist("2026-11-20 22:30")) == 30)
        #expect(night.afterHoursMinutes(from: ist("2026-11-20 05:30"), to: ist("2026-11-20 06:30")) == 30)
        #expect(office.afterHoursMinutes(from: ist("2026-11-20 10:00"), to: ist("2026-11-20 09:00")) == 0)
    }

    @Test("Bad hours make no window")
    func invalid() {
        #expect(WorkWindow(WorkHours(start: "9:30", end: "18:30", days: [1], tz: "Asia/Kolkata")) == nil)
        #expect(WorkWindow(WorkHours(start: "09:30", end: "09:30", days: [1], tz: "Asia/Kolkata")) == nil)
        #expect(WorkWindow(WorkHours(start: "09:30", end: "18:30", days: [1], tz: "Mars/Olympus")) == nil)
        #expect(WorkWindow(WorkHours(start: "09:30", end: "18:30", days: [], tz: "Asia/Kolkata"))?.nextStart(after: Date()) == nil)
    }
}

@Suite("After-hours guard")
struct AfterHoursTests {
    let ist = TimeZone(identifier: "Asia/Kolkata")!

    @Test("Steps: work ends, work starts, nothing on the first tick")
    func steps() {
        #expect(AfterHours.step(wasWork: true, isWork: false) == .workEnded)
        #expect(AfterHours.step(wasWork: false, isWork: true) == .workStarted)
        #expect(AfterHours.step(wasWork: nil, isWork: false) == .none)
        #expect(AfterHours.step(wasWork: true, isWork: true) == .none)
    }

    @Test("Slack's evening status names the time, and the day when it isn't tomorrow")
    func status() {
        let now = Date(timeIntervalSince1970: 1_795_179_600)            // Fri 20 Nov 18:30 IST
        let tomorrow = Date(timeIntervalSince1970: 1_795_233_600)       // Sat 21 Nov 09:30 IST
        let monday = tomorrow.addingTimeInterval(2 * 86_400)            // Mon 23 Nov 09:30 IST
        #expect(AfterHours.statusText(back: tomorrow, now: now, timeZone: ist) == "Offline, back 9:30 AM")
        #expect(AfterHours.statusText(back: monday, now: now, timeZone: ist) == "Offline, back Monday 9:30 AM")
    }
}
