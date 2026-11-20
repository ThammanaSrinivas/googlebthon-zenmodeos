import SwiftUI
import Albeit
import ZenAPI
import MacUsage

enum SettingsCopy {
    static let title = "Settings"
    static let appearanceTitle = "Appearance"
    static let appearanceCaption = "Paper by day, ink by night, or follow the Mac."
    static let notchTitle = "Zeno in the notch"
    static let notchToggle = "Zeno speaks in the notch"
    static let notchCaption = "One calm line when it matters. Never a countdown, never a nag."
    static let howOften = "How often"
    static let moments = "Speak up for"
    static let quietTitle = "Quiet hours"
    static let quietNight = "Every night, 10:30 pm to 7 am, Zeno stays quiet. Add your own hours on top."
    static let custom = "Custom"
    static let quietInEvents = "Quiet during busy calendar events"
    static let connectFirst = "Connect your calendar in Calendar first."
    static let islandTitle = "Dynamic Island on your iPhone"
    static let islandCaption = "Saved with your account. Your iPhone picks these up when it syncs."
    static let islandScore = "Show the Zen Score in the compact Island"
    static let islandGoodDay = "Good day moment"
    static let islandFocus = "Focus sessions, counting up"
    static let islandReactions = "Circle reactions"
    static let privacyTitle = "What leaves this Mac"
    static let leaves = "Your Zen Score, distracting minutes and pull-backs, for your own screens and your circle's group score."
    static let stays = "App names, window titles, calendar events and anything you type stay on this Mac."
    static let preview = "Preview"
    static let test = "Test Zeno in the notch"
    static let replay = "Replay onboarding"
    static let signOut = "Sign out"
}

/// Settings: Zeno in the notch, quiet hours, the iPhone's Island, and what leaves this Mac.
/// Everything saves as you change it and applies at once.
struct SettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                Text(SettingsCopy.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    VStack(spacing: ZenSpace.s4) {
                        AppearanceSettings()
                        NotchSettings()
                        QuietSettings()
                        IslandSettings()
                        PrivacySettings()
                    }
                    .frame(maxWidth: .infinity)
                    NotchPreviewCard()
                        .frame(width: 380)
                }
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }
}

/// A settings group: a Clash title over glass.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).zenType(.title).foregroundStyle(Color.zen.textHeading)
                if let caption { Text(caption).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
            }
            content
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.widget)
    }
}

/// A switch row: label left, the system switch right, tinted green.
private struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                if let detail { Text(detail).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.zen.brandFill)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Paper, ink, or whatever the Mac is set to: three swatches, the chosen one ringed.
private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.preferences
        SettingsGroup(title: SettingsCopy.appearanceTitle, caption: SettingsCopy.appearanceCaption) {
            HStack(spacing: ZenSpace.s3) {
                ForEach(PreferenceValues.Appearance.allCases, id: \.self) { a in
                    let on = prefs.values.appearance == a
                    Button { withAnimation(ZenMotion.calm(ZenMotion.t3)) { prefs.values.appearance = a } } label: {
                        VStack(spacing: ZenSpace.s2) {
                            swatch(a)
                                .frame(width: 112, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                                    .strokeBorder(on ? Color.zen.textBrand : Color.zen.borderHairline, lineWidth: on ? 2 : 1))
                            Text(a.label).font(ZenFont.text(12.5, on ? .semibold : .regular)).foregroundStyle(Color.zen.textHeading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.label)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    @ViewBuilder
    private func swatch(_ a: PreferenceValues.Appearance) -> some View {
        switch a {
        case .light: mini(ground: Color(hex: 0xF2F1EC), card: Color(hex: 0xFAF9F5), ink: Color(hex: 0x12160F))
        case .dark: mini(ground: Color(hex: 0x0E110E), card: Color(hex: 0x161A16), ink: Color(hex: 0xF2F3EE))
        case .system:
            HStack(spacing: 0) {
                mini(ground: Color(hex: 0xF2F1EC), card: Color(hex: 0xFAF9F5), ink: Color(hex: 0x12160F))
                mini(ground: Color(hex: 0x0E110E), card: Color(hex: 0x161A16), ink: Color(hex: 0xF2F3EE))
            }
        }
    }

    private func mini(ground: Color, card: Color, ink: Color) -> some View {
        ZStack(alignment: .topLeading) {
            ground
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.85)).frame(width: 26, height: 5)
                RoundedRectangle(cornerRadius: 5).fill(card).frame(height: 26)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2AA136)).frame(width: 18, height: 6).padding(.leading, 6) }
            }
            .padding(8)
        }
    }
}

private struct NotchSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.preferences
        SettingsGroup(title: SettingsCopy.notchTitle, caption: SettingsCopy.notchCaption) {
            SwitchRow(title: SettingsCopy.notchToggle, isOn: $prefs.values.zenoInNotch)
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                HStack {
                    Text(SettingsCopy.howOften).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    Spacer()
                    Text("\(model.preferences.spentToday) of \(prefs.values.frequency.perDay) today")
                        .font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                }
                Picker(SettingsCopy.howOften, selection: $prefs.values.frequency) {
                    ForEach(PreferenceValues.Frequency.allCases, id: \.self) { f in
                        Text("\(f.label) · \(f.perDay) a day").tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(SettingsCopy.moments).font(ZenFont.text(13.5, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .padding(.top, ZenSpace.s2)
                ForEach(PreferenceValues.Moment.allCases, id: \.self) { m in
                    SwitchRow(title: m.title, detail: m.example, isOn: Binding(
                        get: { prefs.values.moments.contains(m) },
                        set: { on in if on { prefs.values.moments.insert(m) } else { prefs.values.moments.remove(m) } }))
                }
            }
            .disabled(!prefs.values.zenoInNotch)
            .opacity(prefs.values.zenoInNotch ? 1 : 0.45)
        }
        .animation(ZenMotion.container, value: prefs.values.zenoInNotch)
    }
}

private struct QuietSettings: View {
    @Environment(AppModel.self) private var model
    private let dayNames = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        @Bindable var prefs = model.preferences
        let quiet = prefs.values.quiet
        let presets: [(QuietHours, String)] = [(.classHours, "Class hours"), (.workHours, "Work hours"), (.none, "Only at night")]
        let isCustom = !presets.contains { $0.0 == quiet }
        SettingsGroup(title: SettingsCopy.quietTitle, caption: SettingsCopy.quietNight) {
            HStack(spacing: ZenSpace.s2) {
                ForEach(presets, id: \.1) { preset in
                    chip(preset.1, on: quiet == preset.0) { model.setQuiet(preset.0) }
                }
                chip(SettingsCopy.custom, on: isCustom) {
                    if !isCustom { model.setQuiet(QuietHours(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)) }
                }
            }
            if isCustom {
                HStack(spacing: ZenSpace.s5) {
                    Stepper(value: Binding(get: { quiet.start }, set: { v in model.setQuiet(QuietHours(weekdays: quiet.weekdays, start: v, end: max(v + 30, quiet.end))) }),
                            in: 7 * 60...21 * 60, step: 30) {
                        Text("From \(Self.clock(quiet.start))").font(ZenFont.number(13)).foregroundStyle(Color.zen.textHeading)
                    }
                    Stepper(value: Binding(get: { quiet.end }, set: { v in model.setQuiet(QuietHours(weekdays: quiet.weekdays, start: min(quiet.start, v - 30), end: v)) }),
                            in: 7 * 60 + 30...22 * 60 + 30, step: 30) {
                        Text("to \(Self.clock(quiet.end))").font(ZenFont.number(13)).foregroundStyle(Color.zen.textHeading)
                    }
                }
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                        let on = quiet.weekdays.contains(wd)
                        Button {
                            var days = quiet.weekdays
                            if on { days.remove(wd) } else { days.insert(wd) }
                            model.setQuiet(QuietHours(weekdays: days, start: quiet.start, end: quiet.end))
                        } label: {
                            Text(dayNames[wd - 1]).font(ZenFont.number(12))
                                .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textHeading)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.zen.actionPrimary : Color.zen.surfaceSunk))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[wd - 1])
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .transition(.opacity)
            }
            QuietStrip(quiet: quiet)
            SwitchRow(title: SettingsCopy.quietInEvents,
                      detail: model.calendarLink.state == .connected ? nil : SettingsCopy.connectFirst,
                      isOn: $prefs.values.quietInCalendarEvents)
        }
        .animation(ZenMotion.container, value: quiet)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(ZenFont.text(13, .semibold))
                .foregroundStyle(on ? Color.zen.onActionPrimary : Color.zen.textHeading)
                .padding(.horizontal, ZenSpace.s3 + 2).frame(height: 32)
                .background(Capsule().fill(on ? Color.zen.actionPrimary : Color.zen.surfaceSunk))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    static func clock(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "am" : "pm")
    }
}

private struct IslandSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.preferences
        SettingsGroup(title: SettingsCopy.islandTitle, caption: SettingsCopy.islandCaption) {
            HStack(spacing: ZenSpace.s3) {
                IslandPill(feeling: .calm, score: prefs.values.islandScore ? (model.snapshot?.score.text ?? "8.1") : "")
                DemoTag("Saved on this Mac")
            }
            SwitchRow(title: SettingsCopy.islandScore, isOn: $prefs.values.islandScore)
            SwitchRow(title: SettingsCopy.islandGoodDay, detail: "\"Good day · 8.1 · 3 of 4 good days\"", isOn: $prefs.values.islandGoodDay)
            SwitchRow(title: SettingsCopy.islandFocus, detail: "Never a countdown", isOn: $prefs.values.islandFocus)
            SwitchRow(title: SettingsCopy.islandReactions, detail: "Who reacted, and react back", isOn: $prefs.values.islandReactions)
        }
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model

    /// This Mac's day, as the sync last left it.
    static func syncLine(_ status: MacDaySync.Status?) -> String {
        switch status {
        case .upToDate(let at)?: "This Mac's day sent \(at.formatted(date: .omitted, time: .shortened))"
        case .publishing?: "Sending this Mac's day…"
        case .waiting?: "This Mac's day goes out shortly"
        case .offline?: "Offline: this Mac's day waits and goes when you're back"
        case .signedOut?: "Signed out: nothing leaves this Mac"
        case .rejected?: "The server didn't take this Mac's day"
        case .idle?, nil: "Measuring this Mac"
        }
    }

    var body: some View {
        SettingsGroup(title: SettingsCopy.privacyTitle) {
            Label(SettingsCopy.leaves, systemImage: "arrow.up.circle").font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
            Label(SettingsCopy.stays, systemImage: "lock").font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
            if let user = model.user {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                        Text(Self.syncLine(model.daySyncStatus)).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                    Spacer()
                    Button(SettingsCopy.signOut) { model.signOut() }.buttonStyle(ZenSecondaryButtonStyle())
                }
            }
            Button(SettingsCopy.replay) { model.replayOnboarding() }.buttonStyle(ZenLinkButtonStyle())
        }
    }
}

/// The notch as it will look, with a button that makes the real one speak.
private struct NotchPreviewCard: View {
    @Environment(AppModel.self) private var model
    @State private var feeling: ZenoFeeling = .happy

    var body: some View {
        let enabled = model.preferences.values.zenoInNotch
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            Eyebrow(SettingsCopy.preview)
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
                    .fill(Color.zen.island)
                RadialGradient(colors: [feeling.skin.glow.opacity(0.3), .clear], center: UnitPoint(x: 0.2, y: 1), startRadius: 0, endRadius: 180)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
                HStack(spacing: ZenSpace.s3) {
                    ZenoView(feeling).frame(width: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ZENMODE · PREVIEW").font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(feeling.skin.glow)
                        Text(enabled ? "Good day locked in. Nice." : "Zeno's off. Nothing here.")
                            .font(ZenFont.text(14.5, .semibold)).foregroundStyle(Color.zen.islandText)
                    }
                }
                .padding(.horizontal, ZenSpace.s4).padding(.top, 22)
            }
            .frame(height: 124)
            .opacity(enabled ? 1 : 0.5)
            Picker("Feeling", selection: $feeling) {
                ForEach([ZenoFeeling.happy, .pleasant, .curious, .proud, .sleepy], id: \.self) { f in
                    Text(f.rawValue.capitalized).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button(SettingsCopy.test) { model.testZeno(feeling) }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(!enabled)
            Text("Quiet: \(model.preferences.values.quiet.summary). Test ignores quiet hours.")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.widget)
    }
}
