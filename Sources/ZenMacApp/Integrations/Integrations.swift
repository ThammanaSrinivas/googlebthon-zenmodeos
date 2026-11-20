import Foundation
import Observation
import ZenAPI

/// The tools ZenMode OS can plug into. Each reads the least it can: a status, a time, never content.
struct Integration: Identifiable, Equatable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case time, work, chat, focus, campus

        var id: String { rawValue }

        var label: String {
            switch self {
            case .time: "Calendar & calls"
            case .work: "Projects & code"
            case .chat: "Chat"
            case .focus: "Focus & automation"
            case .campus: "Campus"
            }
        }
    }

    let id: String
    let name: String
    let symbol: String
    /// The tile's hue, so the grid reads at a glance. Not the tool's brand colour.
    let hue: UInt32
    let category: Category
    /// What Zeno does with it, in one sentence.
    let does: String
    /// What it reads, and what it never reads.
    let reads: String
    /// Connected by the workspace admin for everyone; each person can still switch it off.
    let managedByWorkspace: Bool
    /// The seats this tool is suggested for.
    let suggestedFor: Set<Profile.Seat>
    /// Connects for real today (the Mac's calendar); the rest are demo connections for now.
    var isLive = false

    static let all: [Integration] = [
        // Calendar & calls
        Integration(id: "calendar", name: "Calendar", symbol: "calendar", hue: 0x2AA136, category: .time,
                    does: "Zeno goes quiet in meetings and classes, with a heads-up first.",
                    reads: "Busy times on this Mac. Never who's invited or what's said.",
                    managedByWorkspace: false, suggestedFor: [.personal, .campus], isLive: true),
        Integration(id: "google", name: "Google Workspace", symbol: "envelope.badge", hue: 0x2F6FDB, category: .time,
                    does: "Calendar blocks become quiet hours, and Gmail holds the non-urgent mail during focus.",
                    reads: "Busy times and how many mails wait. Never a single mail.",
                    managedByWorkspace: false, suggestedFor: [.team]),
        Integration(id: "outlook", name: "Microsoft 365", symbol: "tray.full", hue: 0x1E6BC2, category: .time,
                    does: "Outlook's focus time and meetings set when Zeno speaks.",
                    reads: "Busy times. Never mail or invites.",
                    managedByWorkspace: false, suggestedFor: []),
        Integration(id: "zoom", name: "Zoom", symbol: "video.bubble", hue: 0x2D8CFF, category: .time,
                    does: "Zeno stays quiet on calls.",
                    reads: "When a call starts and ends.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "teams", name: "Microsoft Teams", symbol: "video", hue: 0x4F5BD5, category: .time,
                    does: "Zeno stays quiet on calls, and your status says Focusing in a session.",
                    reads: "When a call starts and ends.", managedByWorkspace: false, suggestedFor: []),
        // Projects & code
        Integration(id: "jira", name: "Jira", symbol: "ticket", hue: 0x2F6FDB, category: .work,
                    does: "A ticket in progress counts as focus, so deep work never costs the score.",
                    reads: "Ticket status and key. Never the ticket itself.",
                    managedByWorkspace: true, suggestedFor: [.team]),
        Integration(id: "linear", name: "Linear", symbol: "checklist", hue: 0x5E5FD6, category: .work,
                    does: "An issue in progress counts as focus.",
                    reads: "Issue status. Never the issue itself.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "asana", name: "Asana", symbol: "circle.grid.2x1", hue: 0xD9541E, category: .work,
                    does: "Time on your tasks for the day counts as focus, by project.",
                    reads: "Task status and project. Never the task text.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "clickup", name: "ClickUp", symbol: "checkmark.square", hue: 0x7A4BC2, category: .work,
                    does: "Tasks in progress count as focus, and your timesheet fills itself.",
                    reads: "Task status. Never the task text.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", hue: 0x3B3F46, category: .work,
                    does: "Coding and reviews count as focus time.",
                    reads: "That you pushed or reviewed. Never the code.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "notion", name: "Notion", symbol: "doc.text", hue: 0x4A4F46, category: .work,
                    does: "Writing and planning count as focus time.",
                    reads: "Which workspace is open. Never the page.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "figma", name: "Figma", symbol: "pencil.and.outline", hue: 0xC2410C, category: .work,
                    does: "Design time counts as focus, file by file in your timesheet.",
                    reads: "That a file is open. Never the design.", managedByWorkspace: false, suggestedFor: []),
        // Chat
        Integration(id: "slack", name: "Slack", symbol: "number", hue: 0x7A4BC2, category: .chat,
                    does: "Your status says Focusing during quiet hours and focus sessions.",
                    reads: "Nothing. It only sets your status.", managedByWorkspace: true, suggestedFor: [.team]),
        Integration(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right", hue: 0x5865F2, category: .chat,
                    does: "Server pings wait during focus, and your status says Focusing.",
                    reads: "Nothing. It only sets your status.", managedByWorkspace: false, suggestedFor: [.campus]),
        // Focus & automation
        Integration(id: "focus", name: "Shortcuts & Focus", symbol: "moon.circle", hue: 0x6B5BD2, category: .focus,
                    does: "Zeno turns on your Mac's Focus for a session, and a Focus you set tells Zeno to stay quiet.",
                    reads: "Which Focus is on.", managedByWorkspace: false, suggestedFor: [.personal]),
        Integration(id: "browser", name: "Browser extension", symbol: "safari", hue: 0x0F7A18, category: .focus,
                    does: "Tells YouTube from Docs in Chrome, Arc and Safari, without Accessibility.",
                    reads: "The site's domain. Never the page or your history.",
                    managedByWorkspace: false, suggestedFor: [.personal, .team, .campus]),
        Integration(id: "raycast", name: "Raycast", symbol: "command", hue: 0xFF6363, category: .focus,
                    does: "Start a focus session, ask Zeno or check your score without leaving Raycast.",
                    reads: "Nothing. It only sends commands.", managedByWorkspace: false, suggestedFor: []),
        Integration(id: "spotify", name: "Spotify", symbol: "music.note", hue: 0x1DB954, category: .focus,
                    does: "Focus playlists count as on purpose, so music while you work never costs the score.",
                    reads: "That focus music is playing. Never what.", managedByWorkspace: false, suggestedFor: [.personal]),
        // Campus
        Integration(id: "classroom", name: "Google Classroom", symbol: "graduationcap", hue: 0x1E8E3E, category: .campus,
                    does: "Class times become quiet hours, and due dates get one calm heads-up.",
                    reads: "Class times and due dates. Never your work.", managedByWorkspace: false, suggestedFor: [.campus]),
        Integration(id: "moodle", name: "Moodle", symbol: "books.vertical", hue: 0xE07B00, category: .campus,
                    does: "Lecture times become quiet hours; deadlines get one heads-up.",
                    reads: "Course times and due dates. Never submissions.", managedByWorkspace: false, suggestedFor: [.campus]),
        Integration(id: "canvas", name: "Canvas LMS", symbol: "square.stack.3d.up", hue: 0xB4232A, category: .campus,
                    does: "Lecture times become quiet hours; deadlines get one heads-up.",
                    reads: "Course times and due dates. Never submissions.", managedByWorkspace: false, suggestedFor: []),
    ]

    /// Up to four tools that fit this seat, the ones already on left out.
    static func suggested(for seat: Profile.Seat, excluding on: (Integration) -> Bool) -> [Integration] {
        Array(all.filter { $0.suggestedFor.contains(seat) && !on($0) }.prefix(4))
    }
}

/// The person's workspace, as a seat sees it.
struct Workspace: Equatable, Sendable {
    let name: String
    let monogram: String
    let program: String
    let plan: String
    let seats: Int
    let managedBy: String
    let challenge: String
    let challengeDetail: String
    let isCampus: Bool

    static let team = Workspace(name: "Acme Labs", monogram: "AL", program: "Wellbeing program", plan: "Teams plan",
                                seats: 120, managedBy: "the People team", challenge: "Calm Thursdays",
                                challengeDetail: "As a team: four good days this week, Thursday included.", isCampus: false)
    static let campus = Workspace(name: "IIT Madras", monogram: "IIT", program: "Student wellbeing", plan: "Campus plan",
                                  seats: 860, managedBy: "the Wellness Centre", challenge: "Exam-week evenings",
                                  challengeDetail: "As a hostel: phones down after 10 pm, four nights this week.", isCampus: true)
}

/// Which tools are connected. The calendar is real (EventKit); the rest are demo connections
/// until the backend can hold their tokens.
@MainActor
@Observable
final class IntegrationsModel {
    private(set) var connected: Set<String>
    private(set) var connecting: Set<String> = []
    /// Workspace-managed tools this person switched off for themselves.
    private(set) var optedOut: Set<String>
    /// Tools people asked for, newest first.
    private(set) var requested: [String]

    private static let key = "zen.integrations.v1"
    private static let optOutKey = "zen.integrations.optout.v1"
    private static let requestKey = "zen.integrations.requests.v1"

    init() {
        connected = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
        optedOut = Set(UserDefaults.standard.stringArray(forKey: Self.optOutKey) ?? [])
        requested = UserDefaults.standard.stringArray(forKey: Self.requestKey) ?? []
    }

    func isOn(_ i: Integration, workspace: Workspace?) -> Bool {
        if i.managedByWorkspace && workspace != nil { return !optedOut.contains(i.id) }
        return connected.contains(i.id)
    }

    func connect(_ i: Integration) {
        guard !connecting.contains(i.id) else { return }
        connecting.insert(i.id)
        Task {
            // TODO(buildathon): OAuth through ZenCorePrivate; the token lives on the server, never here.
            try? await Task.sleep(for: .milliseconds(900))
            connecting.remove(i.id)
            connected.insert(i.id)
            save()
        }
    }

    func disconnect(_ i: Integration) {
        connected.remove(i.id)
        save()
    }

    func setManaged(_ i: Integration, on: Bool) {
        if on { optedOut.remove(i.id) } else { optedOut.insert(i.id) }
        save()
    }

    /// The calendar's state comes from the real link.
    func markCalendar(_ on: Bool) {
        if on { connected.insert("calendar") } else { connected.remove("calendar") }
    }

    /// Records a request (trimmed, no repeats). Returns false for an empty one.
    @discardableResult
    func request(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        requested.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        requested.insert(clean, at: 0)
        UserDefaults.standard.set(requested, forKey: Self.requestKey)
        return true
    }

    private func save() {
        UserDefaults.standard.set(Array(connected), forKey: Self.key)
        UserDefaults.standard.set(Array(optedOut), forKey: Self.optOutKey)
    }
}
