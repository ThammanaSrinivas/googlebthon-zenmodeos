import Foundation
import Testing
@testable import ZenAPI

@Suite("The Zeno nudge: schema, guardrails, fallback")
struct ZenoNudgeTests {
    @Test("Decodes the server's JSON, including snake_case actions")
    func decodes() throws {
        let json = #"{"feeling":"curious","line":"Back again. On purpose?","action":"start_focus"}"#
        let nudge = try JSONDecoder().decode(ZenoNudge.self, from: Data(json.utf8))
        #expect(nudge == ZenoNudge(feeling: .curious, line: "Back again. On purpose?", action: .startFocus))
    }

    @Test("A feeling outside the schema fails to decode")
    func rejectsUnknownFeeling() {
        let json = #"{"feeling":"angry","line":"Hey.","action":"none"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ZenoNudge.self, from: Data(json.utf8)) }
    }

    @Test("Lines over 40 characters are rejected")
    func tooLong() {
        let line = String(repeating: "a", count: 41)
        #expect(throws: NudgeRejection.tooLong(41)) { try ZenoNudge(feeling: .happy, line: line).validated() }
        #expect(throws: Never.self) { try ZenoNudge(feeling: .happy, line: String(repeating: "a", count: 40)).validated() }
    }

    @Test("Empty and whitespace lines are rejected; good lines are trimmed")
    func emptyAndTrim() throws {
        #expect(throws: NudgeRejection.empty) { try ZenoNudge(feeling: .happy, line: "   ").validated() }
        #expect(try ZenoNudge(feeling: .happy, line: "  Nice.  ").validated().line == "Nice.")
    }

    @Test("Zeno never quotes time spent", arguments: ["41 minutes of reels.", "3 h today, easy.", "Over 2hrs. Hm.", "12 min in."])
    func noMinutes(line: String) {
        #expect(throws: NudgeRejection.mentionsMinutes) { try ZenoNudge(feeling: .curious, line: line).validated() }
    }

    @Test("Scores and counts are fine")
    func numbersThatAreFine() throws {
        _ = try ZenoNudge(feeling: .happy, line: "8.1 today. 3 of 4 good days.").validated()
    }

    @Test("In the notch, sad shows as pleasant")
    func neverSadInTheNotch() {
        #expect(ZenoNudge(feeling: .sad, line: "x").notchFeeling == .pleasant)
        #expect(ZenoNudge(feeling: .happy, line: "x").notchFeeling == .happy)
    }

    @Test("The fallback line itself passes the guardrails")
    func fallbackIsValid() throws {
        #expect(try ZenoNudge.fallback.validated() == ZenoNudge.fallback)
    }

    private struct Failing: ZenoNudgeService {
        func nudge(for context: NudgeContext) async throws -> ZenoNudge { throw URLError(.notConnectedToInternet) }
    }

    private struct Slow: ZenoNudgeService {
        func nudge(for context: NudgeContext) async throws -> ZenoNudge {
            try await Task.sleep(for: .seconds(5))
            return ZenoNudge(feeling: .happy, line: "Too late.")
        }
    }

    private struct BreaksRules: ZenoNudgeService {
        func nudge(for context: NudgeContext) async throws -> ZenoNudge { ZenoNudge(feeling: .happy, line: "45 minutes of YouTube, wow.") }
    }

    private struct Good: ZenoNudgeService {
        func nudge(for context: NudgeContext) async throws -> ZenoNudge { ZenoNudge(feeling: .happy, line: "Good day locked in.") }
    }

    private let context = NudgeContext(scoreTenths: 81, goodDaysThisWeek: 3, weeklyStreak: 9, hourOfDay: 11, trigger: .pickup)

    @Test("An error falls back to the fixed line")
    func errorFallsBack() async {
        let (nudge, source) = await ResilientNudges(Failing()).nudge(for: context)
        #expect(nudge == .fallback)
        #expect(source == .fallback)
    }

    @Test("A timeout falls back to the fixed line")
    func timeoutFallsBack() async {
        let (nudge, source) = await ResilientNudges(Slow(), timeout: .milliseconds(100)).nudge(for: context)
        #expect(nudge == .fallback)
        #expect(source == .fallback)
    }

    @Test("A line that breaks a guardrail falls back")
    func guardrailFallsBack() async {
        #expect(await ResilientNudges(BreaksRules()).nudge(for: context).1 == .fallback)
    }

    @Test("A good line comes through as Gemini's")
    func goodLine() async {
        let (nudge, source) = await ResilientNudges(Good()).nudge(for: context)
        #expect(nudge.line == "Good day locked in.")
        #expect(source == .gemini)
    }
}
