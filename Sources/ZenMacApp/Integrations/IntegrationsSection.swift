import SwiftUI
import Albeit
import ZenAPI

enum IntegrationsCopy {
    static let eyebrow = "Integrations"
    static let title = "Works where you work."
    static let lede = "ZenMode OS reads the least it can from each tool: a status, a time, never the content. Your workspace sets things up; what you connect stays yours."
    static let sees = "What %@ sees"
    static let seesYes = ["Your group's Zen Score, for groups of 5 or more", "How many seats are active this week", "How the group's challenge is going"]
    static let seesNo = ["Your name next to any number", "Apps, minutes or window titles", "Calendar events, tickets or messages"]
    static let managedNote = "Set up by your workspace. You can switch it off for yourself."
    static let connect = "Connect"
    static let connected = "Connected"
    static let demo = "Demo connection"
    static let soloTitle = "Bring ZenMode OS to your team"
    static let soloBody = "Teams and campuses get cohort circles, a weekly digest written by Gemini, and an admin view with group scores only. Priced per seat; every seat gets the full app."
    static let soloCode = "Have a join code?"
    static let adminTitle = "For admins"
    static let adminBody = "Group scores and trends for cohorts of 5 or more, and a weekly digest written by Gemini. Never a name, an app or a minute."
    static let tabTools = "Tools"
    static let tabWork = "Your work week"
    static let tabWorkspace = "Workspace"
    static let suggested = "Suggested for you"
    static let all = "All integrations"
    static let search = "Search tools"
    static let readsPrefix = "Reads:"
    static let noneYet = "Nothing connected yet. Start with a suggestion below."
    static let requestTitle = "Missing a tool?"
    static let requestBody = "Tell us what you'd like ZenMode OS to work with."
    static let requestThanks = "Thanks. We'll tell you when it lands."
    static let requestPrompt = "Tool name, e.g. Trello"
    static let request = "Request"
    static let requestedPrefix = "Asked for:"

    static func connectedEyebrow(_ n: Int) -> String { n == 0 ? "Connected" : "Connected · \(n)" }
    static func noMatch(_ q: String) -> String { "Nothing matches \"\(q)\". Ask for it below." }
    static func suggestedWhy(_ seat: Profile.Seat, _ w: Workspace?) -> String {
        switch seat {
        case .team: "What \(w?.name ?? "your team") uses, and what helps most at a desk."
        case .campus: "For classes, deadlines and evenings in the hostel."
        case .personal: "The few that help most when it's just you."
        }
    }
}

/// Integrations, in tabs so the page never sprawls: the tools first (what's on, what suits you,
/// everything else), then Focus Mode (the hooks and work hours), your work week (time tracked by
/// itself, for workspace seats), and the workspace (who gave the seat and what they can see).
struct IntegrationsSection: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .tools

    enum Tab: String, CaseIterable, Identifiable {
        case tools, focus, work, workspace
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .tools: "square.grid.2x2.fill"
            case .focus: "moon.fill"
            case .work: "clock.fill"
            case .workspace: "building.2.fill"
            }
        }
        var label: String {
            switch self {
            case .focus: "Focus Mode"
            case .tools: IntegrationsCopy.tabTools
            case .work: IntegrationsCopy.tabWork
            case .workspace: IntegrationsCopy.tabWorkspace
            }
        }
    }

    private var workspace: Workspace? {
        switch model.profile.seat {
        case .team: .team
        case .campus: .campus
        case .personal: model.cohort != nil ? .campus : nil
        }
    }

    /// The work week is for workspace seats that track work, not campus or personal ones.
    private var tabs: [Tab] { workspace.map { $0.isCampus ? [.tools, .focus, .workspace] : Tab.allCases } ?? [.tools, .focus, .workspace] }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                header
                TabPills(tabs: tabs, selection: $tab)
                Group {
                    switch tab {
                    case .focus: FocusHooksTab()
                    case .tools: ToolsTab(workspace: workspace)
                    case .work:
                        HStack(alignment: .top, spacing: ZenSpace.s4) {
                            WorkReportCard()
                            TeamInsightsCard().frame(width: 340)
                        }
                    case .workspace: workspaceTab
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .padding(ZenSpace.s6)
            .animation(ZenMotion.container, value: tab)
            Color.clear.frame(height: 1).id("end")
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // Debug renders: ZEN_INTEGRATIONS_SCROLL=end shows the foot of the tab.
        .task {
            if ProcessInfo.processInfo.environment["ZEN_INTEGRATIONS_SCROLL"] != nil {
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
        #endif
        }
        .onAppear {
            model.integrations.markCalendar(model.calendarLink.state == .connected)
            if let t = model.integrationsTab { tab = t; model.integrationsTab = nil }
            #if DEBUG
            // Debug renders: ZEN_INTEGRATIONS_TAB=tools|focus|work|workspace.
            if let raw = ProcessInfo.processInfo.environment["ZEN_INTEGRATIONS_TAB"], let t = Tab(rawValue: raw) { tab = t }
            #endif
        }
        .onChange(of: model.calendarLink.state) { _, s in model.integrations.markCalendar(s == .connected) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Eyebrow(IntegrationsCopy.eyebrow + (workspace.map { " · \($0.name)" } ?? ""), color: Color.zen.textBrand)
                // The workspace and its challenge are demo until the admin side exists.
                DemoTag()
            }
            Text(IntegrationsCopy.title).zenType(.display).foregroundStyle(Color.zen.textHeading)
                .accessibilityAddTraits(.isHeader)
            Text(IntegrationsCopy.lede).zenType(.body).foregroundStyle(Color.zen.textBody)
                .frame(maxWidth: 680, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var workspaceTab: some View {
        if let workspace {
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    WorkspaceCard(workspace: workspace)
                    ChallengeCard(workspace: workspace).frame(width: 340)
                }
                adminNote
            }
        } else {
            SoloCard()
        }
    }

    private var adminNote: some View {
        HStack(spacing: ZenSpace.s4) {
            Image(systemName: "person.2.badge.gearshape").font(.system(size: 20)).foregroundStyle(Color.zen.textBrand)
            VStack(alignment: .leading, spacing: 2) {
                Text(IntegrationsCopy.adminTitle).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(IntegrationsCopy.adminBody).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.6)))
    }
}

/// The section's tabs: a glyph and a name each, raised when open, a wash on hover, a ring for the
/// keyboard. ⌘1 ⌘2 … jump between them.
private struct TabPills: View {
    let tabs: [IntegrationsSection.Tab]
    @Binding var selection: IntegrationsSection.Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element) { i, t in
                let on = t == selection
                Button { selection = t } label: {
                    HStack(spacing: 7) {
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Color.zen.textBrand : Color.zen.textCaption)
                        Text(t.label)
                    }
                    .padding(.horizontal, ZenSpace.s4).frame(height: 36)
                }
                .buttonStyle(SegmentStyle(on: on, size: 13.5))
                .focusEffectDisabled()
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                .help("\(t.label) (⌘\(i + 1))")
                .accessibilityLabel(t.label)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.zen.surfaceSunk))
        .overlay(Capsule().strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .fixedSize()
    }
}

/// The seat: who gave it, the program, and in plain words what they can and can't see.
private struct WorkspaceCard: View {
    let workspace: Workspace

    var body: some View {
        HStack(alignment: .top, spacing: ZenSpace.s6) {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(spacing: ZenSpace.s3) {
                    Text(workspace.monogram)
                        .font(ZenFont.brand(workspace.monogram.count > 2 ? 15 : 18)).foregroundStyle(Color(hex: 0xF2FFF2))
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x2AA136), Color(hex: 0x0F5F1A)], startPoint: .top, endPoint: .bottom)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name).zenType(.title).foregroundStyle(Color.zen.textHeading)
                        Text("\(workspace.program) · \(workspace.plan)").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                }
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    fact("Your seat", "Pro, paid by \(workspace.name)")
                    fact("Seats", "\(workspace.seats) \(workspace.isCampus ? "students" : "people")")
                    fact("Managed by", workspace.managedBy.prefix(1).uppercased() + workspace.managedBy.dropFirst())
                }
            }
            .frame(maxWidth: 280, alignment: .leading)
            Divider().overlay(Color.zen.borderHairline)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(String(format: IntegrationsCopy.sees, workspace.name))
                ForEach(IntegrationsCopy.seesYes, id: \.self) { line in seeRow(line, yes: true) }
                ForEach(IntegrationsCopy.seesNo, id: \.self) { line in seeRow(line, yes: false) }
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            Spacer()
            Text(value).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
        }
    }

    private func seeRow(_ text: String, yes: Bool) -> some View {
        HStack(spacing: ZenSpace.s2) {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(yes ? Color.zen.textBrand : Color.zen.textCaption)
                .frame(width: 18, height: 18)
                .background(Circle().fill(yes ? Color.zen.surfaceTint : Color.zen.surfaceSunk))
            Text(text).font(ZenFont.text(13)).foregroundStyle(yes ? Color.zen.textHeading : Color.zen.textBody)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(yes ? "Can see" : "Never sees"): \(text)")
    }
}

/// The workspace's group challenge, progress shown for the group only.
private struct ChallengeCard: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow("Challenge · set by \(workspace.name)", color: Color.zen.accentRewardText)
            Text(workspace.challenge).zenType(.title).foregroundStyle(Color.zen.textHeading)
            Text(workspace.challengeDetail).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
            CellRow([.reward, .reward, .reward, .empty])
            HStack {
                Text("3 of 4 days, as a group").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                Spacer()
                Text("Ends Sunday").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
            }
            Text("Group progress only, for 5 or more.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.widget, style: .continuous).strokeBorder(Color.zen.accentReward.opacity(0.45), lineWidth: 1))
    }
}

/// No workspace yet: the B2B offer, and a way in with a code.
private struct SoloCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: ZenSpace.s6) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow("Teams & Campuses · per seat", color: Color.zen.textBrand)
                Text(IntegrationsCopy.soloTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
                Text(IntegrationsCopy.soloBody).zenType(.body).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(IntegrationsCopy.soloCode) { model.choose(seat: .team) }
                .buttonStyle(ZenPrimaryButtonStyle())
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
    }
}
