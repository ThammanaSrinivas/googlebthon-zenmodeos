import SwiftUI
import Albeit
import ZenAPI

/// The Tools tab: what's on, what suits this seat, everything else by category with search, and a
/// way to ask for what's missing. Nothing here is a primary action: connecting is always secondary.
struct ToolsTab: View {
    @Environment(AppModel.self) private var model
    let workspace: Workspace?
    @State private var category: Integration.Category?
    @State private var query = ""

    var body: some View {
        let on = { (i: Integration) in model.integrations.isOn(i, workspace: workspace) }
        let connected = Integration.all.filter(on)
        let suggested = Integration.suggested(for: model.profile.seat, excluding: on)
        VStack(alignment: .leading, spacing: ZenSpace.s6) {
            ConnectedStrip(tools: connected, workspace: workspace)
            if !suggested.isEmpty {
                VStack(alignment: .leading, spacing: ZenSpace.s3) {
                    sectionTitle(IntegrationsCopy.suggested, caption: IntegrationsCopy.suggestedWhy(model.profile.seat, workspace))
                    // One row when it fits, two by two when the window narrows; never squeezed.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: ZenSpace.s4) {
                            ForEach(suggested) {
                                IntegrationCard(integration: $0, workspace: workspace, prominent: true)
                                    .frame(minWidth: 220, idealWidth: 240, maxWidth: .infinity)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZenSpace.s4, alignment: .top), count: 2),
                                  alignment: .leading, spacing: ZenSpace.s4) {
                            ForEach(suggested) { IntegrationCard(integration: $0, workspace: workspace, prominent: true) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack(alignment: .center, spacing: ZenSpace.s4) {
                    sectionTitle(IntegrationsCopy.all, caption: nil)
                    Spacer()
                    SearchField(text: $query)
                }
                CategoryPills(selection: $category)
                let tools = Integration.all.filter { i in
                    (category == nil || i.category == category)
                        && (query.isEmpty || "\(i.name) \(i.does) \(i.category.label)".localizedCaseInsensitiveContains(query))
                }
                if tools.isEmpty {
                    Text(IntegrationsCopy.noMatch(query)).zenType(.body).foregroundStyle(Color.zen.textCaption)
                        .padding(.vertical, ZenSpace.s4)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: ZenSpace.s3, alignment: .top)],
                              alignment: .leading, spacing: ZenSpace.s3) {
                        ForEach(tools) { IntegrationCard(integration: $0, workspace: workspace, prominent: false) }
                    }
                }
            }
            .animation(ZenMotion.container, value: category)
            .animation(ZenMotion.container, value: query)
            RequestCard()
        }
    }

    private func sectionTitle(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).zenType(.title).foregroundStyle(Color.zen.textHeading)
            if let caption { Text(caption).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
        }
    }
}

/// What's on, at a glance: one row of small chips.
private struct ConnectedStrip: View {
    let tools: [Integration]
    let workspace: Workspace?

    var body: some View {
        HStack(alignment: .center, spacing: ZenSpace.s3) {
            Eyebrow(IntegrationsCopy.connectedEyebrow(tools.count))
            if tools.isEmpty {
                Text(IntegrationsCopy.noneYet).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            } else {
                FlowLayout(spacing: ZenSpace.s2, lineSpacing: ZenSpace.s2) {
                    ForEach(tools) { t in
                        HStack(spacing: 6) {
                            ToolIcon(integration: t, size: 20)
                            Text(t.name).font(ZenFont.text(12.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                            if t.managedByWorkspace && workspace != nil {
                                Image(systemName: "building.2").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.zen.textCaption)
                            }
                        }
                        .padding(.leading, 4).padding(.trailing, 10).frame(height: 28)
                        .background(Capsule().fill(Color.zen.surfaceTint.opacity(0.9)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.55)))
    }
}

/// All · and the five categories.
private struct CategoryPills: View {
    @Binding var selection: Integration.Category?

    var body: some View {
        HStack(spacing: 2) {
            pill(nil, "All")
            ForEach(Integration.Category.allCases) { pill($0, $0.label) }
        }
        .padding(3)
        .background(Capsule().fill(Color.zen.surfaceSunk))
        .fixedSize()
    }

    private func pill(_ c: Integration.Category?, _ label: String) -> some View {
        let on = c == selection
        return Button { selection = c } label: {
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

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.zen.textCaption)
            TextField(IntegrationsCopy.search, text: $text).textFieldStyle(.plain).font(ZenFont.text(13))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.zen.textCaption) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, ZenSpace.s3).frame(width: 240, height: 32)
        .background(Capsule().fill(Color.zen.surfaceCard.opacity(0.8)))
        .overlay(Capsule().strokeBorder(Color.zen.borderHairline, lineWidth: 1))
    }
}

/// The tool's glyph on its hue.
struct ToolIcon: View {
    let integration: Integration
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: integration.symbol)
            .font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Color(hex: integration.hue)))
            .accessibilityHidden(true)
    }
}

/// One tool: what Zeno does with it, what it reads, and its switch. Prominent cards (Suggested)
/// are taller and say why they're suggested; grid cards are compact.
struct IntegrationCard: View {
    @Environment(AppModel.self) private var model
    let integration: Integration
    let workspace: Workspace?
    let prominent: Bool
    @State private var hovering = false

    var body: some View {
        let i = integration
        let on = model.integrations.isOn(i, workspace: workspace)
        let managed = i.managedByWorkspace && workspace != nil
        VStack(alignment: .leading, spacing: prominent ? ZenSpace.s3 : ZenSpace.s2) {
            HStack(alignment: .center, spacing: ZenSpace.s3) {
                ToolIcon(integration: i, size: prominent ? 38 : 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.name).font(ZenFont.text(prominent ? 15 : 14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .lineLimit(2)
                    Text(status(on: on, managed: managed)).font(ZenFont.number(9.5)).tracking(0.6).lineLimit(1)
                        .foregroundStyle(on ? Color.zen.textBrand : Color.zen.textCaption)
                }
                Spacer(minLength: 0)
                if !prominent { control(on: on, managed: managed) }
            }
            Text(i.does).font(ZenFont.text(prominent ? 13.5 : 12.5)).foregroundStyle(Color.zen.textHeading)
                .lineLimit(prominent ? 3 : 2).fixedSize(horizontal: false, vertical: true)
            Text("\(IntegrationsCopy.readsPrefix) \(i.reads)").font(ZenFont.text(11.5)).foregroundStyle(Color.zen.textCaption)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if on && !i.isLive && !managed { DemoTag(IntegrationsCopy.demo) }
            // Suggested cards keep the name whole and put the action at the foot.
            if prominent {
                Spacer(minLength: 0)
                control(on: on, managed: managed)
            }
        }
        .padding(prominent ? ZenSpace.s4 : ZenSpace.s3 + 2)
        .frame(maxWidth: .infinity, minHeight: prominent ? 176 : 156, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .fill(on ? Color.zen.surfaceTint.opacity(0.8) : Color.zen.surfaceCard.opacity(hovering ? 0.85 : 0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous)
                .strokeBorder(on ? Color.zen.brandFill.opacity(0.35) : Color.zen.borderHairline, lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .animation(ZenMotion.calm(ZenMotion.t2), value: on)
        .animation(ZenMotion.calm(ZenMotion.t1), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(i.name), \(on ? "connected" : "not connected"). \(i.does) Reads: \(i.reads)")
    }

    private func status(on: Bool, managed: Bool) -> String {
        if managed, let workspace { return "Set by \(workspace.name)".uppercased() }
        if on { return IntegrationsCopy.connected.uppercased() }
        return integration.category.label.uppercased()
    }

    @ViewBuilder
    private func control(on: Bool, managed: Bool) -> some View {
        let i = integration
        if model.integrations.connecting.contains(i.id) {
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
                .fixedSize()
                .accessibilityLabel("Connect \(i.name)")
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

/// "Request an integration": a name, sent, and the list of what's been asked for.
private struct RequestCard: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var thanked = false

    var body: some View {
        HStack(alignment: .center, spacing: ZenSpace.s5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(IntegrationsCopy.requestTitle).font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(thanked ? IntegrationsCopy.requestThanks : IntegrationsCopy.requestBody).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                if !model.integrations.requested.isEmpty {
                    Text("\(IntegrationsCopy.requestedPrefix) \(model.integrations.requested.prefix(4).joined(separator: ", "))")
                        .font(ZenFont.text(12)).foregroundStyle(Color.zen.textBody)
                }
            }
            Spacer(minLength: 0)
            TextField(IntegrationsCopy.requestPrompt, text: $name)
                .textFieldStyle(.plain).font(ZenFont.text(13.5))
                .padding(.horizontal, ZenSpace.s3).frame(width: 220, height: 34)
                .background(RoundedRectangle(cornerRadius: ZenRadius.md).fill(Color.zen.surfaceRaised))
                .onSubmit(send)
                .accessibilityLabel(IntegrationsCopy.requestPrompt)
            Button(IntegrationsCopy.request, action: send)
                .buttonStyle(ZenSecondaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderOutline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func send() {
        if model.integrations.request(name) {
            name = ""
            withAnimation(ZenMotion.container) { thanked = true }
        }
    }
}
