import Testing
@testable import ZenLogic

struct NamePolicyTests {
    @Test func everyListedWordAndStemIsRefusedOnItsOwn() {
        for w in NamePolicy.words.sorted() + NamePolicy.stems {
            #expect(NamePolicy.check(w) == .offensive, "\(w)")
        }
    }

    @Test func aWordRefusesOnlyAsAWholeWord() {
        #expect(NamePolicy.check("tit") == .offensive)
        #expect(NamePolicy.check("title") == .ok)
    }

    @Test func wordsFoldCaseAccentsAndLookalikes() {
        #expect(NamePolicy.nameWords("Bï7ch-Ç0de 2x") == ["bitch", "code", "x"])
    }

    @Test func contactsAreRefused() {
        #expect(NamePolicy.check("find me at t.me/someone") == .contact)
        #expect(NamePolicy.check("call 98765 43210") == .contact)
    }

    @Test func shownKeepsAShowableNameOnly() {
        #expect(NamePolicy.shown("Asha") == "Asha")
        #expect(NamePolicy.shown("sh1t") == nil)
        #expect(NamePolicy.shown("www.spam.example") == nil)
        #expect(NamePolicy.shown(nil) == nil)
    }
}

struct DisplayNameTests {
    @Test func tidyTrimsAndCollapsesWhitespace() {
        #expect(DisplayName.tidy("  Asha \n  K  ") == "Asha K")
        #expect(DisplayName.tidy("   ") == "")
    }

    @Test func validateSaysWhatIsWrong() {
        #expect(DisplayName.validate("  Asha ") == .success("Asha"))
        #expect(DisplayName.validate("   ") == .failure(.empty))
        #expect(DisplayName.validate(String(repeating: "a", count: 41)) == .failure(.tooLong(max: 40)))
        #expect(DisplayName.validate(String(repeating: "a", count: 31), maxLength: DisplayName.maxCohortNameLength) == .failure(.tooLong(max: 30)))
        #expect(DisplayName.validate("Hostel 4 🌿", maxLength: 30) == .success("Hostel 4 🌿"))
        #expect(DisplayName.validate("sh1t happens") == .failure(.notAllowed(.offensive)))
        #expect(DisplayName.validate("www.spam.example") == .failure(.notAllowed(.contact)))
    }

    @Test func lengthCountsWhatPeopleSee() {
        // 40 flags are 80 scalars but 40 characters.
        #expect(DisplayName.validate(String(repeating: "🇮🇳", count: 40)) == .success(String(repeating: "🇮🇳", count: 40)))
    }

    @Test func shownFallsBackKindly() {
        #expect(DisplayName.shown("Kamal") == "Kamal")
        #expect(DisplayName.shown(nil) == DisplayName.fallback)
        #expect(DisplayName.shown("  ") == DisplayName.fallback)
        #expect(DisplayName.shown("sh1t") == DisplayName.fallback)
    }

    @Test func everyProblemHasAMessage() {
        let problems: [DisplayName.Problem] = [.empty, .tooLong(max: 30), .notAllowed(.contact), .notAllowed(.offensive)]
        #expect(Set(problems.map(DisplayName.message(for:))).count == problems.count)
    }
}
