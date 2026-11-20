import SwiftUI
import Albeit
import ZenAPI

/// Calendar: the month (or week) as Notion Calendar lays it out, with each day's Zen Score as a dot
/// at the top-left of its cell and the person's plans inside it. Hover a day for its detail; click
/// to pin it in the panel on the right.
struct CalendarSection: View {
    enum Mode: String, CaseIterable { case month, week }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor = Date()
    @State private var mode: Mode = .month
    @State private var selected: Date?
    @State private var hovered: Date?
    @State private var pointer: Date?
    @FocusState private var focused: Bool

    var body: some View {
        let link = model.calendarLink
        let source = CalendarDays(model: model, now: Date())
        let shown = mode == .month ? source.monthGrid(anchor) : source.week(anchor)
        let days = shown.days
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            header
            if link.state != .connected { banner(link.state) }
            HStack(alignment: .top, spacing: ZenSpace.s4) {
                grid(days)
                if let date = selected, let day = days.first(where: { $0.date == date }) {
                    DayDetailCard(day: day, weekLine: source.weekLine(for: date), quietLine: quietLine,
                                  connected: link.state == .connected, onClose: { pin(nil) })
                        .frame(width: 300)
                        .glassCard(radius: ZenRadius.xl)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            .overlayPreferenceValue(DayAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let date = hovered, date != selected, let anchor = anchors[date], let day = days.first(where: { $0.date == date }) {
                        preview(day, weekLine: source.weekLine(for: date), cell: proxy[anchor], in: proxy.size)
                    }
                }
            }
            HStack {
                ScoreLegend()
                Spacer()
                Text(CalendarCopy.keys).font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
            }
        }
        .padding(ZenSpace.s6)
        .animation(reduceMotion ? nil : ZenMotion.container, value: selected)
        .animation(reduceMotion ? nil : ZenMotion.calm(ZenMotion.t1), value: hovered)
        .task(id: "\(shown.range.start.timeIntervalSince1970)-\(link.state == .connected)-\(link.revision)") {
            link.load(shown.range)
        }
        .onAppear {
            focused = true
            #if DEBUG
            // Debug renders: ZEN_CAL_PIN=today pins today, ZEN_CAL_HOVER=yyyy-MM-dd shows that day's preview.
            let env = ProcessInfo.processInfo.environment
            if env["ZEN_CAL_PIN"] == "today" { selected = CalendarDays.calendar.startOfDay(for: Date()) }
            if env["ZEN_CAL_MODE"] == "week" { mode = .week }
            if env["ZEN_CAL_SAMPLE"] != nil { link.debugSamples(around: Date()) }
            if let raw = env["ZEN_CAL_HOVER"] {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                hovered = f.date(from: raw).map { CalendarDays.calendar.startOfDay(for: $0) }
            }
            #endif
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: ZenSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                Text(title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).zenType(.body).foregroundStyle(Color.zen.textCaption)
            }
            DemoTag(CalendarCopy.demoHistory)
            Spacer()
            HStack(spacing: 4) {
                stepButton("chevron.left", label: CalendarCopy.previous) { step(-1) }
                stepButton("chevron.right", label: CalendarCopy.following) { step(1) }
            }
            Button(CalendarCopy.today) { goToday() }
                .buttonStyle(ZenSecondaryButtonStyle())
            ModePicker(selection: $mode)
        }
    }

    private var title: String {
        if mode == .month { return anchor.formatted(.dateTime.month(.wide)) }
        let week = CalendarDays.calendar.dateInterval(of: .weekOfYear, for: anchor)!
        let last = week.end.addingTimeInterval(-1)
        return "\(week.start.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// The year for a month; the week's streak line for a week.
    private var subtitle: String {
        mode == .month ? anchor.formatted(.dateTime.year()) : CalendarDays(model: model, now: Date()).weekLine(for: anchor)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.zen.textHeading)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.zen.textHeading.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Connect

    @ViewBuilder
    private func banner(_ state: CalendarLink.State) -> some View {
        HStack(alignment: .center, spacing: ZenSpace.s3) {
            Image(systemName: state == .denied ? "calendar.badge.exclamationmark" : "calendar.badge.plus")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state == .denied ? CalendarCopy.deniedTitle : CalendarCopy.connectTitle)
                    .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(state == .denied ? CalendarCopy.deniedBody : CalendarCopy.bannerBody)
                    .zenType(.caption).foregroundStyle(Color.zen.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ZenSpace.s4)
            if state == .denied {
                Button(CalendarCopy.openSettings) { Task { await model.calendarLink.connect() } }
                    .buttonStyle(ZenSecondaryButtonStyle())
            } else {
                Button(CalendarCopy.connect) { model.connectCalendar() }
                    .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, ZenSpace.s4).padding(.vertical, ZenSpace.s3)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceTint.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
    }

    // MARK: Grid

    private func grid(_ days: [CalendarDay]) -> some View {
        Group {
            if mode == .month {
                MonthGrid(days: days, selected: selected, hovered: hovered, onHover: hover, onSelect: { pin($0) })
            } else {
                WeekBoard(days: days, selected: selected, hovered: hovered, onHover: hover, onSelect: { pin($0) })
            }
        }
        .background(Color.zen.surfaceCard.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: ZenRadius.xl, style: .continuous))
        .glassCard(radius: ZenRadius.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -7) }
        .onKeyPress(.downArrow) { move(by: 7) }
        .onKeyPress(.escape) { pin(nil); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "tT")) { _ in goToday(); return .handled }
    }

    /// The hover preview: beside the day, on whichever side has room.
    private func preview(_ day: CalendarDay, weekLine: String, cell: CGRect, in size: CGSize) -> some View {
        let width: CGFloat = 280, estimatedHeight: CGFloat = 330
        let x = cell.maxX + 10 + width <= size.width ? cell.maxX + 10 : max(0, cell.minX - 10 - width)
        let y = min(max(0, cell.minY - 6), max(0, size.height - estimatedHeight))
        return DayDetailCard(day: day, weekLine: weekLine, quietLine: quietLine, connected: model.calendarLink.state == .connected)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).strokeBorder(Color.zen.borderHairline, lineWidth: 1))
            .modifier(ZenLift())
            .offset(x: x, y: y)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private var quietLine: String { CalendarCopy.quiet(model.profile.quiet.summary) }

    // MARK: Moving around

    /// Shows a day's preview after a short pause; once one is showing, moving to the next day
    /// switches at once, and leaving the grid lets it go.
    private func hover(_ date: Date, _ inside: Bool) {
        if inside {
            pointer = date
            if hovered != nil { hovered = date; return }
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                if pointer == date { hovered = date }
            }
        } else if pointer == date {
            pointer = nil
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                if pointer == nil { hovered = nil }
            }
        }
    }

    private func pin(_ date: Date?) {
        selected = date
        if let date { hovered = nil; keepVisible(date) }
    }

    private func move(by days: Int) -> KeyPress.Result {
        let cal = CalendarDays.calendar
        let from = selected ?? cal.startOfDay(for: Date())
        guard let next = cal.date(byAdding: .day, value: days, to: from) else { return .ignored }
        pin(next)
        return .handled
    }

    private func step(_ direction: Int) {
        let cal = CalendarDays.calendar
        anchor = cal.date(byAdding: mode == .month ? .month : .weekOfYear, value: direction, to: anchor) ?? anchor
        hovered = nil
    }

    private func goToday() {
        let today = CalendarDays.calendar.startOfDay(for: Date())
        anchor = today
        pin(today)
    }

    /// Moving the selection past the edge turns the page.
    private func keepVisible(_ date: Date) {
        let cal = CalendarDays.calendar
        let same = mode == .month ? cal.isDate(date, equalTo: anchor, toGranularity: .month)
                                  : cal.isDate(date, equalTo: anchor, toGranularity: .weekOfYear)
        if !same { anchor = date }
    }
}

/// Month · Week, as a quiet segmented pill.
private struct ModePicker: View {
    @Binding var selection: CalendarSection.Mode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CalendarSection.Mode.allCases, id: \.self) { m in
                let on = m == selection
                Button { selection = m } label: {
                    Text(m == .month ? CalendarCopy.month : CalendarCopy.week)
                        .font(ZenFont.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.zen.textHeading : Color.zen.textBody)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 28)
                        .background { if on { Capsule().fill(Color.zen.surfaceRaised).shadow(color: .black.opacity(0.06), radius: 2, y: 1) } }
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
