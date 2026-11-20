import Foundation
import Testing
@testable import ZenFocus

@Suite("“Zeno, focus N min”")
struct FocusCommandTests {
    @Test("Lengths, said or typed")
    func lengths() {
        #expect(FocusCommand.parse("Zeno, focus 40 min") == .minutes(40))
        #expect(FocusCommand.parse("focus 25") == .minutes(25))
        #expect(FocusCommand.parse("focus for 90 minutes") == .minutes(90))
        #expect(FocusCommand.parse("Focus 2h") == .minutes(120))
        #expect(FocusCommand.parse("focus 1 hour") == .minutes(60))
    }

    @Test("Until a clock time")
    func until() {
        #expect(FocusCommand.parse("zeno focus until 12") == .until(hour: 12, minute: 0))
        #expect(FocusCommand.parse("focus until 18:30") == .until(hour: 18, minute: 30))
        #expect(FocusCommand.parse("focus until 25") == nil)
    }

    @Test("Not a focus command, or out of range")
    func rejects() {
        #expect(FocusCommand.parse("plan my day") == nil)
        #expect(FocusCommand.parse("focus") == nil)
        #expect(FocusCommand.parse("focus 2") == nil)
        #expect(FocusCommand.parse("focus 900") == nil)
        #expect(FocusCommand.parse("focus abc") == nil)
    }

    @Test("Until today, or tomorrow once the time has passed")
    func endTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = Date(timeIntervalSince1970: 1_795_156_200)            // 12:00 IST
        #expect(FocusCommand.until(hour: 12, minute: 30).until(from: now, calendar: cal) == now.addingTimeInterval(1800))
        #expect(FocusCommand.until(hour: 11, minute: 0).until(from: now, calendar: cal) == now.addingTimeInterval(23 * 3600))
        #expect(FocusCommand.minutes(50).until(from: now) == now.addingTimeInterval(3000))
        #expect(FocusCommand.minutes(120).label == "Focus 2 h")
    }
}
