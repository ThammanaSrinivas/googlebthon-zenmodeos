import Foundation
import Observation
import ZenAPI

/// The tools ZenMode OS can plug into. Each reads the least it can: a status, a time, never content.
struct Integration: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case work, campus, time }

    let id: String
    let name: String
    let symbol: String
    /// The tile's hue, so the grid reads at a glance. Not the tool's brand colour.
    let hue: UInt32
    let kind: Kind
    /// What Zeno does with it, in one sentence.
    let does: String
    /// What it reads, and what it never reads.
    let reads: String
    /// Connected by the workspace admin for everyone; each person can still switch it off.
    let managedByWorkspace: Bool

    static let all: [Integration] = [
        Integration(id: "calendar", name: "Calendar", symbol: "calendar", hue: 0x2AA136, kind: .time,
                    does: "Zeno goes quiet in meetings and classes, with a heads-up first.",
                    reads: "Busy times on this Mac. Never who's invited or what's said.", managedByWorkspace: false),
        Integration(id: "slack", name: "Slack", symbol: "number", hue: 0x7A4BC2, kind: .work,
                    does: "Your status says Focusing during quiet hours and focus sessions.",
                    reads: "Nothing. It only sets your status.", managedByWorkspace: true),
        Integration(id: "jira", name: "Jira", symbol: "ticket", hue: 0x2F6FDB, kind: .work,
                    does: "A ticket in progress counts as focus, so deep work never costs the score.",
                    reads: "Ticket status and key. Never the ticket itself.", managedByWorkspace: true),
        Integration(id: "linear", name: "Linear", symbol: "checklist", hue: 0x5E5FD6, kind: .work,
                    does: "An issue in progress counts as focus.",
                    reads: "Issue status. Never the issue itself.", managedByWorkspace: false),
        Integration(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", hue: 0x3B3F46, kind: .work,
                    does: "Coding and reviews count as focus time.",
                    reads: "That you pushed or reviewed. Never the code.", managedByWorkspace: false),
        Integration(id: "notion", name: "Notion", symbol: "doc.text", hue: 0x4A4F46, kind: .work,
                    does: "Writing and planning count as focus time.",
                    reads: "Which workspace is open. Never the page.", managedByWorkspace: false),
        Integration(id: "teams", name: "Microsoft Teams", symbol: "video", hue: 0x4F5BD5, kind: .work,
                    does: "Zeno stays quiet on calls, and your status says Focusing in a session.",
                    reads: "When a call starts and ends.", managedByWorkspace: false),
        Integration(id: "zoom", name: "Zoom", symbol: "video.bubble", hue: 0x2D8CFF, kind: .time,
                    does: "Zeno stays quiet on calls.",
                    reads: "When a call starts and ends.", managedByWorkspace: false),
        Integration(id: "classroom", name: "Google Classroom", symbol: "graduationcap", hue: 0x1E8E3E, kind: .campus,
                    does: "Class times become quiet hours, and due dates get one calm heads-up.",
                    reads: "Class times and due dates. Never your work.", managedByWorkspace: false),
    ]
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

    private static let key = "zen.integrations.v1"
    private static let optOutKey = "zen.integrations.optout.v1"

    init() {
        connected = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
        optedOut = Set(UserDefaults.standard.stringArray(forKey: Self.optOutKey) ?? [])
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

    private func save() {
        UserDefaults.standard.set(Array(connected), forKey: Self.key)
        UserDefaults.standard.set(Array(optedOut), forKey: Self.optOutKey)
    }
}
