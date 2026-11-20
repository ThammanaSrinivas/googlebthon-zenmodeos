import ZenAPI

/// Every sentence a person reads, named once. Voice (Albeit §38): say the kind thing, plainly;
/// say what people get, never what the system needs. Our name is always "ZenMode OS".
enum Copy {
    static let product = "ZenMode OS"

    enum Hello {
        static let kicker = "ZenMode OS · hello"
        static let line = "Hi, I'm Zeno. I live up here."
    }

    enum Story {
        struct Card {
            let eyebrow: String, title: String, body: String
        }

        static let cards = [
            Card(eyebrow: "1 of 3 · Zeno",
                 title: "Zeno lives in your notch.",
                 body: "One calm line, right where you already look: the notch on this Mac and the Dynamic Island on your iPhone. Never a countdown. Never a nag."),
            Card(eyebrow: "2 of 3 · One score",
                 title: "One score, every screen.",
                 body: "Your iPhone and this Mac count as one day. Only your Zen Score leaves the iPhone, never apps or minutes. Campuses and teams see a group score, and only for 5 or more."),
            Card(eyebrow: "3 of 3 · Zen Gold, with Gemini",
                 title: "Good weeks turn to gold.",
                 body: "Four good days win the week, and Zen Gold opens. Zeno's words are written by Gemini, from your score alone."),
        ]
        static let start = "Get started"
        static let haveCode = "I have a join code"
        static let feelingsHint = "Tap a feeling to see Zeno in the notch."
        static let sameOnIsland = "The same Zeno, on your iPhone's Dynamic Island."
        static let geminiLine = "Four good days. That's the week. Gold's open."
        static let geminiCaption = "Written by Gemini from your score alone"
        static let privacy = "Only the Zen Score leaves your iPhone."
    }

    /// One example line per feeling, as Zeno says them in the notch.
    static let feelingLines: [(kicker: String, line: String)] = [
        ("ZenMode · +5", "Good day locked in. Nice."),
        ("ZenMode · 10:09", "Stretch? You've been at it a while."),
        ("ZenMode · pickup 12", "Back again. Something on purpose?"),
        ("ZenMode · week 46", "Week won. That's ten in a row."),
        ("ZenMode · 22:40", "Bedtime soon. Last scroll?"),
    ]

    enum Seat {
        static let eyebrow = "Make it yours · 1 of 3"
        static let title = "Who's this Mac with?"
        static func option(_ s: Profile.Seat) -> (title: String, caption: String) {
            switch s {
            case .personal: ("Just me", "Your day, your score. Free, forever.")
            case .campus: ("My campus", "Join your class or hostel with a code.")
            case .team: ("My team", "Join your company's wellbeing program.")
            }
        }
        static let codeLabel = "Join code"
        static let codePrompt = "Six letters and numbers, from your campus or team."
        static let check = "Check code"
        static let notFound = "That code didn't match a group. Check it with whoever shared it."
        static let offline = "Can't reach ZenMode OS right now. Try again in a moment."
        static func privacy(_ kind: CohortPreview.Kind) -> String {
            "Your \(kind == .campus ? "campus" : "team") sees one group score, only for groups of 5 or more. Never your name, apps or minutes."
        }
        static let demoCode = "Demo code: ZEN4HS"
        static let skipCode = "Add a code later"
    }

    enum Uses {
        static let eyebrow = "Make it yours · 2 of 3"
        static let title = "What's this Mac for?"
        static let body = "Time on these never counts against you. On a computer, only distracting minutes do."
        static func label(_ u: Profile.Use) -> String {
            switch u {
            case .study: "Study"
            case .work: "Work"
            case .build: "Building things"
            case .create: "Creating"
            case .everything: "A bit of everything"
            }
        }
    }

    enum Quiet {
        static let eyebrow = "Make it yours · 3 of 3"
        static let title = "When should Zeno stay quiet?"
        static let body = "Zeno never speaks between 10:30 pm and 7 am. Pick the hours you'd like on top."
        static let presets: [(QuietHours, String, String)] = [
            (.classHours, "Class hours", "Weekdays, 9 am to 4 pm"),
            (.workHours, "Work hours", "Weekdays, 10 am to 6 pm"),
            (.none, "Only at night", "Zeno can speak in the day"),
        ]
        static let stripCaption = "A weekday, hour by hour"
    }

    enum Count {
        static let eyebrow = "Let it count"
        static let title = "Your day counts itself."
        static let body = "ZenMode OS notices which app is in front, so YouTube and Docs count differently. Window titles are read, never stored. Nothing to log, ever."
        static let allow = "Allow in System Settings"
        static let on = "Allowed"
        static let later = "Skip for now"
        static let nowInFront = "In front right now"
        static let titleNote = "Title read, never stored"
    }

    enum Bring {
        static let eyebrow = "Bring your day"
        static let title = "Bring your day here."
        static let body = "Scan this with your iPhone to bring your day along. Your Zen Score shows the same on both."
        static let google = "Continue with Google"
        static let explore = "Explore first"
        static let simulate = "Simulate the iPhone's approval"
        static let rotates = "This code changes every 5 minutes and works once."
        static let expired = "That code just changed."
    }

    enum Handoff {
        static let kicker = "Paired · iPhone + Mac"
        static func line(_ name: String) -> String { "Hi, \(name). Your day is here." }
        static let title = "Same score. Two screens."
        static let open = "Open Today"
    }

    enum Today {
        static let title = "Today"
        static let goodDay = "A good day is above 6.0"
        static let zenoCard = "Zeno's last line"
        static let quietNow = "Quiet hours: Zeno's resting"
        static let cohortJoin = "Join your campus or team"
        static let gold = "Zen Gold"
        static let goldClosed = "Gold opens when the week is won."
        static let goldOpen = "Week won. Gold is open till Sunday."
    }
}
