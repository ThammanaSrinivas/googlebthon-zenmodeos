import SwiftUI
import Albeit
import ZenAPI

// MARK: - The Recaps page

/// Every week on record, by month, as cards; at the foot, the streak so far. A card opens its week
/// over the page.
struct RecapsPage: View {
    enum Filter: String, CaseIterable { case all = "All", won = "Won", short = "Short" }

    let entries: [RecapEntry]
    let streak: StreakCalendar?
    let open: (RecapEntry) -> Void
    let back: () -> Void
    @State private var filter: Filter = .all

    var body: some View {
        let shown = entries.filter { filter == .all || (filter == .won) == $0.isWon }
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s8) {
                header
                everyWeek(shown)
                if let streak { StreakSoFar(streak: streak, entries: entries) }
            }
            .padding(ZenSpace.s6)
            .animation(ZenMotion.container, value: filter)
        }
        .scrollIndicators(.hidden)
        .onExitCommand(perform: back)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text(WeekCopy.backToWeek)
                    }
                }
                .buttonStyle(ZenSecondaryButtonStyle())
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel(WeekCopy.backHint)
                Spacer()
                DemoTag(WeekCopy.demoHistory)
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Text(WeekCopy.recapsPageTitle).zenType(.display).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text(WeekCopy.recapsPageLede).zenType(.body).foregroundStyle(Color.zen.textBody)
                }
                Spacer()
                SegmentPill(options: Filter.allCases.map(\.rawValue), selected: filter.rawValue) { filter = Filter(rawValue: $0) ?? .all }
            }
        }
    }

    private func everyWeek(_ shown: [RecapEntry]) -> some View {
        let months = Dictionary(grouping: shown) { Calendar.current.dateInterval(of: .month, for: $0.id)!.start }
        return VStack(alignment: .leading, spacing: ZenSpace.s8) {
            ForEach(months.keys.sorted(by: >), id: \.self) { month in
                VStack(alignment: .leading, spacing: ZenSpace.s4) {
                    Text(month.formatted(.dateTime.month(.wide).year())).zenType(.title).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: ZenSpace.s5)], alignment: .leading, spacing: ZenSpace.s5) {
                        ForEach(months[month] ?? []) { entry in
                            RecapCard(entry: entry) { open(entry) }
                        }
                    }
                }
            }
            if shown.isEmpty {
                Text(WeekCopy.noMatches).zenType(.body).foregroundStyle(Color.zen.textCaption)
            }
        }
    }
}

/// A quiet segmented pill: the picked option on raised paper.
struct SegmentPill: View {
    let options: [String]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = o == selected
                Button { pick(o) } label: {
                    Text(o).font(ZenFont.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textBody)
                        .padding(.horizontal, ZenSpace.s3 + 2).frame(height: 30)
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

// MARK: - One recap, over the page

/// A recap opened over the page: the page dims and blurs behind it, and the week sits on its own
/// sheet, its story on the left and its numbers on the right. Escape, the close button or a click
/// on the dim closes it; Tab stays inside until it does; ⌘← and ⌘→ step to the older or newer week.
struct RecapOverlay: View {
    enum Spot: Hashable { case close, older, newer, story, share }

    let entries: [RecapEntry]
    @Binding var openID: Date?
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Spot?

    var body: some View {
        let index = entries.firstIndex { $0.id == openID }
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.55 : 0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { openID = nil }
                .accessibilityHidden(true)
            if let index {
                sheet(entries[index], index: index)
                    .padding(ZenSpace.s8)
            }
        }
        .onExitCommand { openID = nil }
        .onKeyPress(.tab, phases: .down) { press in
            cycle(back: press.modifiers.contains(.shift), index: index)
            return .handled
        }
        .onAppear { focus = .close }
    }

    private func sheet(_ entry: RecapEntry, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        return ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s6) {
                header(entry, index: index)
                HStack(alignment: .top, spacing: ZenSpace.s8) {
                    RecapStory(entry: entry)
                        .frame(width: 300, height: 520)
                        .focused($focus, equals: .story)
                    RecapNumbers(entry: entry, focus: $focus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(ZenSpace.s8)
            .id(entry.id)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 1080)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            shape.fill(Color.zen.surfaceRaised)
                .overlay(alignment: .topLeading) {
                    // The sheet catches the week's light in its corner.
                    RadialGradient(colors: [Color(hex: entry.tone.glow, alpha: scheme == .dark ? 0.18 : 0.22), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 520)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.zen.borderHairline, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22), radius: 40, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recap, week \(entry.weekNumber)")
        .accessibilityAddTraits(.isModal)
    }

    private func header(_ entry: RecapEntry, index: Int) -> some View {
        HStack(alignment: .top, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                HStack(spacing: ZenSpace.s3) {
                    Eyebrow("Week \(entry.weekNumber) · \(entry.range)", color: Color.zen.textBrand)
                    RecapOutcomeBadge(entry: entry)
                }
                Text(entry.headline).font(ZenFont.brand(34)).tracking(-0.9).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text(entry.body).font(ZenFont.text(15)).lineSpacing(5).foregroundStyle(Color.zen.textBody)
                    .frame(maxWidth: 640, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ZenSpace.s4)
            HStack(spacing: ZenSpace.s2) {
                iconButton("chevron.left", WeekCopy.olderWeek, spot: .older, enabled: index + 1 < entries.count) {
                    openID = entries[index + 1].id
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                iconButton("chevron.right", WeekCopy.newerWeek, spot: .newer, enabled: index > 0) {
                    openID = entries[index - 1].id
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                iconButton("xmark", WeekCopy.closeRecap, spot: .close, enabled: true) { openID = nil }
                    .keyboardShortcut(.cancelAction)
                    .padding(.leading, ZenSpace.s2)
            }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, spot: Spot, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(RoundIconButtonStyle())
        .disabled(!enabled)
        .focused($focus, equals: spot)
        .accessibilityLabel(label)
        .help(label)
    }

    /// Tab and Shift-Tab go round the sheet's controls and never leave it.
    private func cycle(back: Bool, index: Int?) {
        guard let index else { return }
        var order: [Spot] = [.close]
        if index + 1 < entries.count { order.append(.older) }
        if index > 0 { order.append(.newer) }
        order += [.story, .share]
        let at = focus.flatMap(order.firstIndex(of:)) ?? -1
        let next = back ? (at <= 0 ? order.count - 1 : at - 1) : (at + 1) % order.count
        focus = order[next]
    }
}

/// A round icon control: raised paper, an outline that firms up on hover, a sink on press, a brand
/// ring on keyboard focus, faded when it can't be used.
struct RoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.zen.textHeading)
                .frame(width: 36, height: 36)
                .background(Circle().fill(hovering && isEnabled ? Color.zen.surfaceTint : Color.zen.surfaceCard))
                .overlay(Circle().strokeBorder(hovering && isEnabled ? Color.zen.textBrand.opacity(0.6) : Color.zen.borderOutline, lineWidth: 1))
                .overlay { if focused { Circle().strokeBorder(Color.zen.textBrand, lineWidth: 2.5).padding(-4) } }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(ZenMotion.calm(ZenMotion.t1), value: configuration.isPressed)
                .animation(ZenMotion.calm(ZenMotion.t2), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Circle())
        }
    }
}

/// The week in numbers: each screen's part, the week as cells, the month as a pattern, and the
/// sheet's one primary action, Share.
private struct RecapNumbers: View {
    @Environment(AppModel.self) private var model
    let entry: RecapEntry
    var focus: FocusState<RecapOverlay.Spot?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s5) {
            HStack(spacing: ZenSpace.s3) {
                stat(WeekCopy.statGood, "\(entry.goodDays)", "of 7")
                stat(WeekCopy.scoreLabel, entry.average?.text ?? "–", WeekCopy.scoreSublabel)
                stat(WeekCopy.statPullBacks, "\(entry.pullBacks)", "on this Mac")
                stat(WeekCopy.statMac, ClockMinutes.text(entry.macTotal), "distracting")
            }
            ScreensChart(entry: entry)
            HStack(alignment: .center, spacing: ZenSpace.s4) {
                PatternTile(month: Archetype.deepWorker.month(seed: UInt64(2026 + entry.index)), kind: model.preferences.values.pattern)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Your month around it · \(model.preferences.values.pattern.rawValue)")
                    Text(WeekCopy.patternLine).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ShareImageButton(fileName: "ZenMode OS week \(entry.weekNumber).png", make: { ImageExport.png(RecapShareImage(entry: entry)) }) {
                    Label(WeekCopy.shareWeek, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .focused(focus, equals: .share)
                .accessibilityHint(WeekCopy.shareHint)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(ZenFont.number(9)).tracking(0.8).foregroundStyle(Color.zen.textCaption)
            Text(value).font(ZenFont.number(22)).foregroundStyle(Color.zen.textHeading).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(ZenFont.text(11)).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.6)))
        .accessibilityElement(children: .combine)
    }
}

/// Each screen's part, day by day: this Mac's distracting minutes as bars (green on a good day),
/// the iPhone as score-only cells. Each day's score is the lower of the two.
private struct ScreensChart: View {
    let entry: RecapEntry

    var body: some View {
        let peak = max(entry.macMinutes.compactMap { $0 }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack {
                Eyebrow(WeekCopy.screens)
                Spacer()
                Text(WeekCopy.lowerOfTwo).font(ZenFont.text(11)).foregroundStyle(Color.zen.textCaption)
            }
            HStack(alignment: .bottom, spacing: ZenSpace.s2) {
                lane(symbol: "laptopcomputer", name: WeekCopy.mac)
                ForEach(0..<7, id: \.self) { i in
                    let m = entry.macMinutes[i]
                    let good = entry.days[i]?.isGoodDay == true
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        if let m {
                            Text(ClockMinutes.short(m)).font(ZenFont.number(8.5)).foregroundStyle(Color.zen.textCaption)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(good ? Color.zen.brandFill.opacity(0.85) : Color(hex: 0xD9541E).opacity(0.75))
                                .frame(height: max(4, 54 * CGFloat(m) / CGFloat(peak)))
                        } else {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.zen.borderOutline, lineWidth: 1).frame(height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 74)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This Mac: \(ClockMinutes.text(entry.macTotal)) distracting across the week")
            HStack(spacing: ZenSpace.s2) {
                lane(symbol: "iphone", name: WeekCopy.iPhone)
                ForEach(0..<7, id: \.self) { i in
                    let d = entry.days[i]
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(d == nil ? Color.clear : (d!.isGoodDay ? Color.zen.brandFill.opacity(0.85) : Color.zen.textHeading.opacity(0.14)))
                        .overlay { if d == nil { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.zen.borderOutline, lineWidth: 1) } }
                        .frame(maxWidth: .infinity).frame(height: 18)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("iPhone: score only, its minutes stay on the phone")
            HStack(spacing: ZenSpace.s2) {
                Text("").frame(width: 66)
                ForEach(RecapBook.shortNames, id: \.self) { d in
                    Text(String(d.prefix(1))).font(ZenFont.number(9)).foregroundStyle(Color.zen.textCaption).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Text(WeekCopy.iPhoneScoreOnly).font(ZenFont.text(11)).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s4)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.55)))
    }

    private func lane(symbol: String, name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
            Text(name).font(ZenFont.text(11.5, .semibold))
        }
        .foregroundStyle(Color.zen.textHeading)
        .frame(width: 66, alignment: .leading)
    }
}

/// Minutes the way every card writes them.
enum ClockMinutes {
    static func text(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m" }
    static func short(_ m: Int) -> String { m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m" }
}

// MARK: - The recap story

/// A recap as the phones tell it: five slides on ink, a step at a time. Click the left third to go
/// back, anywhere else to go on; ← → work too, and hovering pauses. It plays itself unless Reduce
/// Motion is on.
struct RecapStory: View {
    let entry: RecapEntry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var slide = 0
    @State private var startedAt = Date()
    @State private var hovering = false

    static let count = 5
    static let seconds = 6.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxl, style: .continuous)
        ZStack(alignment: .top) {
            InkTable()
            RadialGradient(colors: [Color(hex: entry.tone.glow, alpha: 0.28), .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 260)
            slideView
                .id(slide)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 14)), removal: .opacity))
                .padding(.horizontal, ZenSpace.s5)
                .padding(.top, ZenSpace.s8)
                .padding(.bottom, ZenSpace.s5)
            progress
                .padding(.horizontal, ZenSpace.s4).padding(.top, ZenSpace.s3)
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(-1) }
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(1) }
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(1) }
            }
            .accessibilityHidden(true)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
        .onHover { hovering = $0 }
        .focusable()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .animation(ZenMotion.container, value: slide)
        .onChange(of: entry.id) { _, _ in slide = 0; startedAt = Date() }
        .task(id: "\(entry.id.timeIntervalSince1970)-\(slide)-\(hovering)") {
            guard !reduceMotion, !hovering, slide < Self.count - 1 else { return }
            startedAt = Date()
            try? await Task.sleep(for: .seconds(Self.seconds))
            if !Task.isCancelled { step(1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recap story for week \(entry.weekNumber), slide \(slide + 1) of \(Self.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        #if DEBUG
        .onAppear {
            if let s = ProcessInfo.processInfo.environment["ZEN_WEEK_SLIDE"].flatMap(Int.init) { slide = min(max(s, 0), Self.count - 1) }
        }
        #endif
    }

    private func step(_ d: Int) {
        slide = min(max(slide + d, 0), Self.count - 1)
        startedAt = Date()
    }

    private var progress: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || hovering)) { tl in
            let elapsed = min(tl.date.timeIntervalSince(startedAt) / Self.seconds, 1)
            HStack(spacing: 4) {
                ForEach(0..<Self.count, id: \.self) { i in
                    GeometryReader { geo in
                        Capsule().fill(Color.white.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.9))
                                    .frame(width: geo.size.width * (i < slide ? 1 : (i == slide ? (reduceMotion ? 1 : elapsed) : 0)))
                            }
                    }
                    .frame(height: 3)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var slideView: some View {
        switch slide {
        case 0: opener
        case 1: screens
        case 2: goodDays
        case 3: turn
        default: nextWeek
        }
    }

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased()).font(ZenFont.number(10)).tracking(1).foregroundStyle(entry.isWon ? Ink.goldSoft : Ink.green)
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            kicker("Week \(entry.weekNumber) · \(entry.range)")
            Spacer(minLength: 0)
            ZenoView(entry.feeling).frame(width: 150).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(WeekCopy.coverTitle).font(ZenFont.brand(30)).tracking(-0.6).foregroundStyle(Ink.text)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(WeekCopy.scoreLabel) · \(WeekCopy.scoreSublabel)".uppercased()).font(ZenFont.number(10)).tracking(0.8).foregroundStyle(Ink.caption)
                Text(entry.average?.text ?? "–").font(ZenFont.number(56)).foregroundStyle(entry.isWon ? Ink.gold : Ink.text)
            }
            Text(entry.outcome).font(ZenFont.text(15, .semibold)).foregroundStyle(Ink.body)
        }
    }

    private var screens: some View {
        let peak = max(entry.macMinutes.compactMap { $0 }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: ZenSpace.s4) {
            kicker(WeekCopy.screens)
            Text(WeekCopy.twoScreens).font(ZenFont.brand(26)).tracking(-0.5).foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            Label(WeekCopy.thisMac, systemImage: "laptopcomputer").font(ZenFont.text(12, .semibold)).foregroundStyle(Ink.body)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let m = entry.macMinutes[i] ?? 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.days[i]?.isGoodDay == true ? Ink.fill : Color(hex: 0xD9541E).opacity(0.8))
                        .frame(height: max(4, 90 * CGFloat(m) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            Text("\(ClockMinutes.text(entry.macTotal)) distracting · \(entry.pullBacks) pull-backs").font(ZenFont.number(11)).foregroundStyle(Ink.caption)
            Label(WeekCopy.iPhone, systemImage: "iphone").font(ZenFont.text(12, .semibold)).foregroundStyle(Ink.body)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = entry.days[i]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(d == nil ? Color.clear : (d!.isGoodDay ? Ink.fill : Ink.well))
                        .overlay { if d == nil { RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.line, lineWidth: 1) } }
                        .frame(height: 16).frame(maxWidth: .infinity)
                }
            }
            Text(WeekCopy.iPhoneScoreOnly).font(ZenFont.text(11.5)).foregroundStyle(Ink.caption)
        }
    }

    private var goodDays: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            kicker(WeekCopy.statGood)
            Text("\(entry.goodDays) of 7 above 6.0").font(ZenFont.brand(26)).tracking(-0.5).foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = entry.days[i]
                    let good = d?.isGoodDay == true
                    let won = entry.wonOn == i
                    HStack {
                        Text(RecapBook.shortNames[i].uppercased()).font(ZenFont.number(10)).foregroundStyle(good ? Ink.onGreen.opacity(0.7) : Ink.mono)
                            .frame(width: 34, alignment: .leading)
                        Text(d?.text ?? "–").font(ZenFont.number(15)).foregroundStyle(good ? Ink.onGreen : Ink.body)
                        Spacer()
                        if won { Text(WeekCopy.wonIt).font(ZenFont.text(10.5, .semibold)).foregroundStyle(Ink.onGold) }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(won ? Ink.gold : (good ? Ink.fill : Ink.well)))
                }
            }
        }
    }

    private var turn: some View {
        let day = entry.isWon ? (entry.wonOn ?? entry.bestDay) : entry.hardDay
        let score = day.flatMap { entry.days[$0] }
        return VStack(alignment: .leading, spacing: ZenSpace.s3) {
            kicker(entry.isWon ? WeekCopy.highlight : WeekCopy.inTheWay)
            Spacer(minLength: 0)
            ZenoView(entry.isWon ? .happy : .pleasant).frame(width: 120).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(day.map { entry.isWon ? "\(RecapBook.dayNames[$0]) won it" : "\(RecapBook.dayNames[$0]) dipped" } ?? WeekCopy.noScores)
                .font(ZenFont.brand(28)).tracking(-0.6).foregroundStyle(Ink.text)
            Text(score?.text ?? "–").font(ZenFont.number(44)).foregroundStyle(entry.isWon ? Ink.gold : Color(hex: 0xFF8A3D))
            Text(entry.isWon ? WeekCopy.highlightLine : WeekCopy.inTheWayLine).font(ZenFont.text(13.5)).lineSpacing(4).foregroundStyle(Ink.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nextWeek: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            kicker(WeekCopy.nextWeekKicker)
            Text(entry.isWon ? WeekCopy.goldOpens : WeekCopy.winNext).font(ZenFont.brand(26)).tracking(-0.5).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Text(WeekCopy.tryNext.uppercased()).font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(Ink.green)
                Text(entry.experiment).font(ZenFont.text(15, .semibold)).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg).fill(Color.white.opacity(0.06)))
            Spacer(minLength: 0)
            HStack(spacing: ZenSpace.s2) {
                Text("\(entry.streakAfter)").font(ZenFont.number(28)).foregroundStyle(Ink.gold)
                Text(WeekCopy.weeksInARow).font(ZenFont.text(13, .semibold)).foregroundStyle(Ink.text)
            }
            MilestoneGarland(streak: entry.streakAfter, target: Milestone.next(after: entry.streakAfter) ?? entry.streakAfter, size: 11)
        }
    }
}

// MARK: - The streak so far

/// At the foot of Recaps: the milestones reached, three numbers, and the weeks as a calendar.
private struct StreakSoFar: View {
    let streak: StreakCalendar
    let entries: [RecapEntry]

    var body: some View {
        let won = entries.filter(\.isWon).count
        let days = entries.flatMap(\.days).compactMap { $0 }
        let rate = days.isEmpty ? 0 : days.filter(\.isGoodDay).count * 100 / days.count
        let shape = RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous)
        HStack(alignment: .top, spacing: ZenSpace.s10) {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                Text(WeekCopy.streakSoFar.uppercased()).font(ZenFont.number(10.5)).tracking(1).foregroundStyle(Ink.caption)
                HStack(spacing: ZenSpace.s6) {
                    number("\(won) of \(entries.count)", WeekCopy.weeksWon)
                    number("\(streak.bestStreak)", WeekCopy.bestStreak)
                    number("\(rate)%", WeekCopy.goodDayRate)
                }
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Text(WeekCopy.milestones.uppercased()).font(ZenFont.number(9.5)).tracking(0.9).foregroundStyle(Ink.mono)
                    HStack(spacing: ZenSpace.s3) {
                        ForEach(Milestone.all, id: \.self) { m in
                            let reached = streak.bestStreak >= m
                            VStack(spacing: 4) {
                                Text("\(m)").font(ZenFont.number(17)).foregroundStyle(reached ? Ink.onGold : Ink.mono)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(reached ? Ink.gold : Color.white.opacity(0.06)))
                                    .overlay(Circle().strokeBorder(reached ? .clear : Ink.line, lineWidth: 1))
                                Text(m == 1 ? "week" : "weeks").font(ZenFont.text(10)).foregroundStyle(Ink.mono)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(m) week milestone, \(reached ? "reached" : "not yet")")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StreakGrid(streak: streak, cell: 20, gap: 4)
                .fixedSize()
        }
        .padding(ZenSpace.s8)
        .background(InkTable())
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .modifier(ZenLift())
        .environment(\.colorScheme, .dark)
    }

    private func number(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(ZenFont.number(30)).foregroundStyle(Ink.text)
            Text(label).font(ZenFont.text(12)).foregroundStyle(Ink.caption)
        }
        .accessibilityElement(children: .combine)
    }
}
