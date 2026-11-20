import Foundation

/// Waits (up to `timeout`) for `condition` to hold, checking every millisecond: the app's models do
/// their work in tasks they start themselves, and the fakes they talk to answer after short pauses.
@MainActor
func eventually(_ timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

/// A gregorian calendar in India, so dates in tests never depend on the machine running them.
let india: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()

/// A moment in November 2026, in India.
func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    india.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
