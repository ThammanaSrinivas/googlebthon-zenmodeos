import Foundation
import Testing
import ZenAPI
@testable import ZenMacApp

/// True when every "ZenMode" in `text` is the full name, "ZenMode OS".
func usesFullBrandName(_ text: String) -> Bool {
    var rest = Substring(text)
    while let r = rest.range(of: "ZenMode") {
        if !rest[r.upperBound...].hasPrefix(" OS") { return false }
        rest = rest[r.upperBound...]
    }
    return true
}

@Suite("Copy: every sentence a person reads")
struct CopyTests {
    @Test("The brand check itself")
    func brandCheck() {
        #expect(usesFullBrandName("ZenMode OS · hello"))
        #expect(usesFullBrandName("No brand here"))
        #expect(!usesFullBrandName("ZenMode · +5"))
        #expect(!usesFullBrandName("ZenMode OS and ZenMode"))
    }

    @Test("The product is always ZenMode OS, in full")
    func product() {
        #expect(Copy.product == "ZenMode OS")
        let lines = [Copy.Hello.kicker, Copy.Hello.line, Copy.Seat.offline, Copy.Count.body, Copy.Story.privacy]
            + Copy.Story.cards.flatMap { [$0.eyebrow, $0.title, $0.body] }
        for line in lines { #expect(usesFullBrandName(line), "\(line)") }
    }

    @Test("Zeno's example lines in the notch say ZenMode OS in full")
    func feelingKickers() {
        for (kicker, _) in Copy.feelingLines { #expect(usesFullBrandName(kicker), "\(kicker)") }
    }

    @Test("The story is three cards, numbered 1 to 3")
    func story() {
        #expect(Copy.Story.cards.count == 3)
        for (i, card) in Copy.Story.cards.enumerated() {
            #expect(card.eyebrow.hasPrefix("\(i + 1) of 3"))
            #expect(!card.title.isEmpty && !card.body.isEmpty)
        }
    }

    @Test("The iPhone sends its score only, and the story says so")
    func privacyPromise() {
        #expect(Copy.Story.cards[1].body.contains("never apps or minutes"))
        #expect(Copy.Story.privacy == "Only the Zen Score leaves your iPhone.")
    }

    @Test("One example line per feeling the story shows (five)")
    func feelingLines() {
        #expect(Copy.feelingLines.count == 5)
        for item in Copy.feelingLines { #expect(!item.kicker.isEmpty && !item.line.isEmpty) }
    }

    @Test("Every seat has its own title and caption")
    func seats() {
        let options = Profile.Seat.allCases.map(Copy.Seat.option)
        #expect(Set(options.map(\.title)).count == Profile.Seat.allCases.count)
        #expect(options.allSatisfy { !$0.caption.isEmpty })
        #expect(Copy.Seat.option(.personal).title == "Just me")
    }

    @Test("Group privacy names the kind of group and the minimum of 5")
    func groupPrivacy() {
        #expect(Copy.Seat.privacy(.campus).hasPrefix("Your campus sees"))
        #expect(Copy.Seat.privacy(.team).hasPrefix("Your team sees"))
        #expect(Copy.Seat.privacy(.team).contains("5 or more"))
        #expect(Copy.Seat.demoCode.hasSuffix("ZEN4HS"))
        #expect(JoinCode("ZEN4HS") != nil)
    }

    @Test("Every use has its own label")
    func uses() {
        #expect(Set(Profile.Use.allCases.map(Copy.Uses.label)).count == Profile.Use.allCases.count)
    }

    @Test("The quiet presets are class hours, work hours and nights only")
    func quietPresets() {
        let presets = Copy.Quiet.presets
        #expect(presets.map(\.0) == [.classHours, .workHours, .none])
        #expect(presets.map(\.1) == ["Class hours", "Work hours", "Only at night"])
    }

    @Test("The hand-off greets by name")
    func handoff() {
        #expect(Copy.Handoff.line("Kamal") == "Hi, Kamal. Your day is here.")
    }
}

@Suite("Copy: the two sign-in roles")
struct SignInRoleCopyTests {
    @Test("Employee and employer each have their own title, caption and symbol")
    func roles() {
        let member = Copy.Bring.role(.member), admin = Copy.Bring.role(.admin)
        #expect(member.title == "I'm joining my team")
        #expect(admin.title == "I run a team")
        #expect(member.title != admin.title && member.symbol != admin.symbol)
        #expect(admin.caption.contains("5 or more") && admin.caption.contains("never a name"))
    }

    @Test("The hand-off's admin lines name the team and keep the group promise")
    func handoffAdmin() {
        #expect(Copy.Handoff.adminReady("Payments").hasPrefix("You run Payments."))
        #expect(Copy.Handoff.adminReady("Payments").contains("5 or more"))
        #expect(Copy.Handoff.createTitle == "Create your team on the web")
    }

    @Test("A mic that didn't open says why: the setting when it's off, a retry otherwise")
    func micDidNotOpen() {
        let off = VoiceCopy.micDidNotOpen(.denied)
        #expect(off.contains("System Settings › Privacy & Security › Microphone") && usesFullBrandName(off))
        let other = VoiceCopy.micDidNotOpen(.granted)
        #expect(other.contains("try again") && !other.contains("System Settings"))
        #expect(VoiceCopy.micDidNotOpen(.undetermined) == other)
    }

    @Test("A chat counts as live from connecting until it ends, so Hey Zeno waits for it")
    func voiceIsLive() {
        #expect(AppModel.isLive(.connecting) && AppModel.isLive(.listening) && AppModel.isLive(.thinking) && AppModel.isLive(.speaking))
        #expect(!AppModel.isLive(.idle) && !AppModel.isLive(.ended) && !AppModel.isLive(.error))
    }
}
