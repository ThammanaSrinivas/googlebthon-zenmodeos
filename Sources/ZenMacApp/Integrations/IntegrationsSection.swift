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
}

/// Integrations: the person's workspace (if a company or campus gave them the seat), what it can
/// and can't see, its group challenge, and the tools ZenMode OS plugs into.
struct IntegrationsSection: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Integration.Kind? = nil

    private var workspace: Workspace? {
        switch model.profile.seat {
        case .team: .team
        case .campus: .campus
        case .personal: model.cohort != nil ? .campus : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                header
                if let workspace {
                    HStack(alignment: .top, spacing: ZenSpace.s4) {
                        WorkspaceCard(workspace: workspace)
                        ChallengeCard(workspace: workspace)
                            .frame(width: 340)
                    }
                } else {
                    SoloCard()
                }
                if let workspace, !workspace.isCampus {
                    HStack(alignment: .top, spacing: ZenSpace.s4) {
                        WorkReportCard()
                        TeamInsightsCard().frame(width: 340)
                    }
                }
                toolGrid
                adminNote
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.integrations.markCalendar(model.calendarLink.state == .connected) }
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

    private var toolGrid: some View {
        let tools = Integration.all.filter { i in
            if let filter { return i.kind == filter }
            // Campus tools show for campus seats; anyone can still find them under Campus.
            return workspace?.isCampus == true || i.kind != .campus
        }
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Text("Your tools").zenType(.title).foregroundStyle(Color.zen.textHeading)
                Spacer()
                FilterPill(selection: $filter)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: ZenSpace.s4), GridItem(.flexible(), spacing: ZenSpace.s4), GridItem(.flexible(), spacing: ZenSpace.s4)],
                      alignment: .leading, spacing: ZenSpace.s4) {
                ForEach(tools) { IntegrationCard(integration: $0, workspace: workspace) }
            }
        }
        .animation(ZenMotion.container, value: filter)
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

/// All · Work · Time · Campus.
private struct FilterPill: View {
    @Binding var selection: Integration.Kind?
    private let options: [(Integration.Kind?, String)] = [(nil, "All"), (.work, "Work"), (.time, "Time"), (.campus, "Campus")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { kind, label in
                let on = kind == selection
                Button { selection = kind } label: {
                    Text(label).font(ZenFont.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textBody)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 28)
                        .background { if on { Capsule().fill(Color.zen.surfaceRaised).shadow(color: .black.opacity(0.08), radius: 3, y: 1) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.zen.surfaceSunk))
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

/// One tool: what Zeno does with it, what it reads, and its switch.
private struct IntegrationCard: View {
    @Environment(AppModel.self) private var model
    let integration: Integration
    let workspace: Workspace?
    @State private var hovering = false

    var body: some View {
        let i = integration
        let on = model.integrations.isOn(i, workspace: workspace)
        let connecting = model.integrations.connecting.contains(i.id)
        let managed = i.managedByWorkspace && workspace != nil
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s3) {
                Image(systemName: i.symbol)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: i.hue)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.name).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Text(managed ? "Set by \(workspace!.name)" : (on ? IntegrationsCopy.connected : i.kind.rawValue.capitalized))
                        .font(ZenFont.number(10)).tracking(0.6)
                        .foregroundStyle(on ? Color.zen.textBrand : Color.zen.textCaption)
                }
                Spacer()
                control(on: on, connecting: connecting, managed: managed)
            }
            Text(i.does).font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textHeading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Reads: \(i.reads)").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                .fixedSize(horizontal: false, vertical: true)
            if on && i.id != "calendar" {
                DemoTag(IntegrationsCopy.demo)
            }
        }
        .padding(ZenSpace.s4)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
                .fill(on ? Color.zen.surfaceTint.opacity(0.85) : Color.zen.surfaceCard.opacity(hovering ? 0.85 : 0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous)
                .strokeBorder(on ? Color.zen.brandFill.opacity(0.35) : Color.zen.borderHairline, lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .animation(ZenMotion.calm(ZenMotion.t2), value: on)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(i.name), \(on ? "connected" : "not connected"). \(i.does)")
    }

    @ViewBuilder
    private func control(on: Bool, connecting: Bool, managed: Bool) -> some View {
        let i = integration
        if connecting {
            ProgressView().controlSize(.small).accessibilityLabel("Connecting \(i.name)")
        } else if managed {
            Toggle(i.name, isOn: Binding(get: { on }, set: { model.integrations.setManaged(i, on: $0) }))
                .labelsHidden().toggleStyle(.switch).tint(Color.zen.brandFill).controlSize(.small)
                .help(IntegrationsCopy.managedNote)
        } else if on {
            Toggle(i.name, isOn: Binding(get: { true }, set: { if !$0 { disconnect() } }))
                .labelsHidden().toggleStyle(.switch).tint(Color.zen.brandFill).controlSize(.small)
        } else {
            Button(IntegrationsCopy.connect) { connect() }
                .buttonStyle(ZenSecondaryButtonStyle())
                .controlSize(.small)
        }
    }

    private func connect() {
        if integration.id == "calendar" { model.connectCalendar() } else { model.integrations.connect(integration) }
    }

    private func disconnect() {
        if integration.id == "calendar" {
            // Access is the person's to take back in System Settings; this stops Zeno using it.
            model.preferences.values.quietInCalendarEvents = false
        }
        model.integrations.disconnect(integration)
    }
}
