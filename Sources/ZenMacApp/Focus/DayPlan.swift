import EventKit
import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// #4: "Plan my day" (today's calendar + the person's tasks › zenoPlanDay › top 3 and focus blocks,
/// booked into the calendar) and "Wrap up" (done and open › zenoWrapUp › a summary and what moves
/// to tomorrow). Tasks are typed once and kept on this Mac for the day.
@MainActor
@Observable
final class DayPlanModel {
    struct Task: Identifiable, Equatable, Codable {
        var id = UUID()
        var title: String
        var done = false
    }

    enum State: Equatable { case idle, planning, planned, wrapping, wrapped, failed(String) }

    static let tasksKey = "zen.plan.tasks"
    static let dayKey = "zen.plan.day"

    private let defaults: UserDefaults
    var tasks: [Task] = [] { didSet { save() } }
    private(set) var state: State = .idle
    private(set) var plan: PlanDayResult?
    private(set) var wrap: WrapUpResult?
    private(set) var booked = false
    private(set) var bookNote: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.string(forKey: Self.dayKey) == FocusDayKey.key(Date()),
           let data = defaults.data(forKey: Self.tasksKey), let saved = try? JSONDecoder().decode([Task].self, from: data) {
            tasks = saved
        }
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, tasks.count < 20 else { return }
        tasks.append(Task(title: String(t.prefix(100))))
    }

    func toggle(_ id: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].done.toggle() }
    }

    func remove(_ id: UUID) { tasks.removeAll { $0.id == id } }

    /// Today's busy events as HH:mm spans (from macOS Calendar, never sent anywhere else).
    static func busyToday(_ events: [CalendarLink.Event], now: Date = Date()) -> [DayBlock] {
        events.filter { $0.isBusy && !$0.isAllDay && Calendar.current.isDate($0.start, inSameDayAs: now) && $0.end > now }
            .prefix(20)
            .map { DayBlock(start: DayPlanner.text(max($0.start, Calendar.current.startOfDay(for: now))),
                            end: DayPlanner.text(min($0.end, Calendar.current.startOfDay(for: now).addingTimeInterval(86_340))),
                            title: String($0.title.prefix(100))) }
    }

    func planDay(work: any ZenoWorkService, events: [CalendarLink.Event], dayEnd: String, cohortId: String?, now: Date = Date()) async {
        state = .planning
        booked = false
        bookNote = nil
        let open = tasks.filter { !$0.done }.map(\.title)
        let request = PlanDayRequest(events: Self.busyToday(events, now: now), tasks: open, now: DayPlanner.text(now),
                                     dayEnd: dayEnd, cohortId: cohortId)
        do {
            plan = try await work.planDay(request)
        } catch {
            // The app's own plan: the first three tasks, free 50-minute gaps.
            plan = PlanDayResult(top3: Array(open.prefix(3)),
                                 blocks: DayPlanner.slots(now: request.now, dayEnd: dayEnd, busy: request.events, count: 3),
                                 line: "One thing at a time.", fallback: true)
        }
        state = .planned
    }

    /// Books the plan's blocks as busy "Focus" events (the Calendar hook's calendar).
    func book(calendarId: String?) {
        guard let plan else { return }
        let store = EKEventStore()
        guard [.fullAccess, .writeOnly].contains(EKEventStore.authorizationStatus(for: .event)) else {
            bookNote = "Connect your calendar to book these."
            return
        }
        let calendar = calendarId.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        var n = 0
        for b in plan.blocks {
            guard let start = DayPlanner.date(b.start, on: Date()), let end = DayPlanner.date(b.end, on: Date()), end > start else { continue }
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.title = "\(b.title) · ZenMode OS"
            e.startDate = start
            e.endDate = end
            e.availability = .busy
            if (try? store.save(e, span: .thisEvent, commit: false)) != nil { n += 1 }
        }
        try? store.commit()
        booked = n > 0
        bookNote = n == 0 ? "Calendar didn't take them." : (n == 1 ? "1 block booked." : "\(n) blocks booked.")
    }

    func wrapUp(work: any ZenoWorkService, today: DailyFocus) async {
        state = .wrapping
        let request = WrapUpRequest(done: tasks.filter(\.done).map(\.title), open: tasks.filter { !$0.done }.map(\.title),
                                    focusMin: today.focusMin, blocksKept: today.blocksKept)
        do {
            wrap = try await work.wrapUp(request)
        } catch {
            wrap = WrapUpResult(summary: "You finished \(request.done.count) and kept \(request.blocksKept) focus blocks today.",
                                moveToTomorrow: Array(request.open.prefix(3)), line: "Good work. Time to log off.", fallback: true)
        }
        state = .wrapped
    }

    private func save() {
        defaults.set(FocusDayKey.key(Date()), forKey: Self.dayKey)
        defaults.set(try? JSONEncoder().encode(tasks), forKey: Self.tasksKey)
    }
}

/// Today's "Zeno at work" card: the tasks, Plan my day, Wrap up.
struct DayPlanCard: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        let p = model.dayPlan
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s2) {
                Eyebrow(model.wrapUpOffered ? "Work's done" : "Plan my day", color: Color.zen.textBrand)
                Spacer(minLength: 0)
            }
            tasksList(p)
            HStack(spacing: ZenSpace.s2) {
                Button(p.state == .planning ? "Planning…" : "Plan my day") {
                    Task { await model.planMyDay() }
                }
                // Secondary: Focus is Today's one primary action.
                .buttonStyle(model.wrapUpOffered ? AnyButtonStyle(ZenLinkButtonStyle()) : AnyButtonStyle(ZenSecondaryButtonStyle()))
                .disabled(p.state == .planning)
                Button(p.state == .wrapping ? "Wrapping up…" : "Wrap up") {
                    Task { await model.wrapUpDay() }
                }
                .buttonStyle(model.wrapUpOffered ? AnyButtonStyle(ZenSecondaryButtonStyle()) : AnyButtonStyle(ZenLinkButtonStyle()))
                .disabled(p.state == .wrapping)
            }
            if p.state == .planned, let plan = p.plan { planView(plan, p) }
            if p.state == .wrapped, let wrap = p.wrap { wrapView(wrap) }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
    }

    private func tasksList(_ p: DayPlanModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(p.tasks) { t in
                HStack(spacing: ZenSpace.s2) {
                    Button { p.toggle(t.id) } label: {
                        Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(t.done ? Color.zen.textBrand : Color.zen.textCaption)
                    }
                    .buttonStyle(QuietIconButtonStyle())
                    .accessibilityLabel(t.done ? "Mark \(t.title) not done" : "Mark \(t.title) done")
                    Text(t.title).font(ZenFont.text(14)).foregroundStyle(t.done ? Color.zen.textCaption : Color.zen.textHeading)
                        .strikethrough(t.done)
                    Spacer(minLength: 0)
                    Button { p.remove(t.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(QuietIconButtonStyle()).foregroundStyle(Color.zen.textCaption)
                        .accessibilityLabel("Remove \(t.title)")
                }
            }
            if p.tasks.isEmpty && p.state == .idle {
                HStack(alignment: .top, spacing: ZenSpace.s3) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 15)).foregroundStyle(Color.zen.textBrand)
                    Text("Add what's on today. Zeno picks the three that matter and finds focus blocks between your meetings.")
                        .font(ZenFont.text(13)).foregroundStyle(Color.zen.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, ZenSpace.s1)
            }
            TextField("Add a task, then press Return", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { p.add(draft); draft = "" }
                .accessibilityLabel("Add a task")
        }
    }

    private func planView(_ plan: PlanDayResult, _ p: DayPlanModel) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                Text(plan.line).font(ZenFont.brand(22)).foregroundStyle(Color.zen.textHeading)
                Text(plan.fallback ? "Zeno" : "Zeno · Gemini").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            if !plan.top3.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.top3.enumerated()), id: \.offset) { i, t in
                        Text("\(i + 1). \(t)").font(ZenFont.text(14, .medium)).foregroundStyle(Color.zen.textHeading)
                    }
                }
            }
            ForEach(plan.blocks, id: \.self) { b in
                HStack(spacing: ZenSpace.s2) {
                    Text("\(b.start)–\(b.end)").font(ZenFont.number(12)).foregroundStyle(Color.zen.textBrand)
                    Text(b.title).font(ZenFont.text(13)).foregroundStyle(Color.zen.textBody)
                    Spacer(minLength: 0)
                    if let start = DayPlanner.date(b.start, on: Date()), let end = DayPlanner.date(b.end, on: Date()),
                       start <= Date().addingTimeInterval(10 * 60), end > Date().addingTimeInterval(120), !model.focus.isFocusing {
                        Button("Start") { model.startFocus(until: end, source: .plan) }.buttonStyle(ZenLinkButtonStyle())
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if plan.blocks.isEmpty { Text("No free gap long enough today.").zenType(.caption).foregroundStyle(Color.zen.textCaption) }
            HStack(spacing: ZenSpace.s2) {
                if !plan.blocks.isEmpty && !p.booked {
                    Button("Book these in my calendar") { p.book(calendarId: model.focus.settings.calendarId) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
                if let note = p.bookNote { Text(note).zenType(.caption).foregroundStyle(Color.zen.textCaption) }
            }
        }
    }

    private func wrapView(_ wrap: WrapUpResult) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Text(wrap.line).font(ZenFont.brand(22)).foregroundStyle(Color.zen.textHeading)
                Text(wrap.fallback ? "Zeno" : "Zeno · Gemini").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            Text(wrap.summary).zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
            if !wrap.moveToTomorrow.isEmpty {
                Text("Tomorrow: " + wrap.moveToTomorrow.joined(separator: " · ")).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
        }
    }
}
