import AppKit
import SwiftUI
import Albeit
import ZenAPI
import ZenMock

/// The team admin's view in the app: the same numbers as the web admin page. Every number is a
/// server-side average of 5 or more people with data; under that, no numbers at all. Never a name
/// next to a number (the roster is web-only).
@MainActor
@Observable
final class AdminModel {
    enum Load: Equatable { case idle, loading, loaded(AdminDashboard), offline, failed }
    enum Report: Equatable { case idle, loading, loaded(PeopleReport), regenerating(PeopleReport?), failed }

    /// The team this person administers; nil hides the section.
    private(set) var team: AdminTeam?
    private(set) var load: Load = .idle
    private(set) var report: Report = .idle

    var dashboard: AdminDashboard? { if case .loaded(let d) = load { d } else { nil } }

    /// Asks once at launch and after sign-in; a member, someone signed out or offline gets no section.
    func refreshTeam(_ service: any AdminService) async {
        do {
            team = try await service.adminTeam()
        } catch {
            team = nil
        }
        if team == nil { load = .idle; report = .idle }
    }

    func refresh(_ service: any AdminService) async {
        if team == nil { await refreshTeam(service) }
        guard let team else { return }
        if dashboard == nil { load = .loading }
        do {
            load = .loaded(try await service.dashboard(cohortId: team.cohortId))
        } catch {
            switch error {
            case .notAdmin, .signedOut:
                self.team = nil
                load = .idle
            case .offline: load = .offline
            case .invalid: load = .failed
            }
            return
        }
        // Under 5 people there's no report either: it's written from the numbers.
        if case .idle = report, dashboard?.published == true { await loadReport(service, regenerate: false) }
    }

    func loadReport(_ service: any AdminService, regenerate: Bool, now: Date = Date()) async {
        guard let team else { return }
        let current: PeopleReport? = if case .loaded(let r) = report { r } else { nil }
        report = regenerate ? .regenerating(current) : .loading
        do {
            report = .loaded(try await service.peopleReport(cohortId: team.cohortId, month: Self.month(now), regenerate: regenerate))
        } catch {
            report = current.map(Report.loaded) ?? .failed
        }
    }

    /// "2026-11" in India time (the team's month).
    static func month(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}


enum AdminCopy {
    static let eyebrow = "Team admin"
    static func basedOn(_ n: Int) -> String { n == 1 ? "Based on 1 person" : "Based on \(n) people" }
    static let demo = "includes demo data"
    static let unpublishedTitle = "Your team's numbers are on their way"
    static let unpublished = "Team numbers appear at 5 people. Nobody's own numbers are ever shown."
    static let unpublishedMore = "Once 5 people have a week of focus data, this page shows what the team's focus time is worth, week by week."
    static let unpublishedPreview = ["Rupees reclaimed a month", "Focus hours per person", "Evenings kept free", "The monthly people report"]
    static let unpublishedPreviewTitle = "What you'll see then"
    static let loading = "Loading the team numbers…"
    static let offline = "Can't reach the team numbers right now."
    static let failed = "The team numbers didn't load."
    static let retryHint = "Your numbers are safe; this only fetches them again."
    static let retry = "Retry"
    static let heroKicker = "Reclaimed for the team"
    static let aMonth = "a month"
    static let perPerson = "per person, a month"
    static let yearly = "a year at this pace"
    static let howWeCount = "How we count"
    static let trend = "Focus hours per person, by week"
    static let thisWeek = "This week"
    static let legendBaseline = "Baseline"
    static let legendReclaimed = "Reclaimed"
    static let supportingTitle = "What's behind it · changes vs last week"
    static let goldKicker = "Zen Gold · this month"
    static let goldWeek = "Zen Gold week won"
    static let goldWeeks = "Zen Gold weeks won"
    static let goldSponsored = "sponsored this month"
    static let gold = "Payout happens through HR; nothing moves in the app."
    static let reportTitle = "Monthly people report"
    static let reportLoading = "Loading the report…"
    static let reportFailed = "The report didn't load. Regenerate to try again."
    static let fromNumbers = "Written from the numbers"
    static let fromGemini = "Written by Gemini from team averages"
    static let regenerate = "Regenerate"
    static let regenerateHelp = "Write this month's report again from the latest team averages"
    static let regenerating = "Writing a new one… (up to 20 s)"
    static let tryThis = "Try this month"
    static let copied = "Copied"
    static let copyHelp = "Copy to paste into your team channel"
    static let patternTitle = "Good days"
    static let patternCaption = "Good-day rate, week by week"
    static let patternEmpty = "Fills in as the weeks are counted"
    static let share = "Share the report"
    static let shareSubject = "Team focus report"
    static let webAdmin = "Open web admin"
    static let privacy = "Team averages for 5+ people only. Never a name next to a number."
    static let trustTitle = "About these numbers"
    static let trustActive = " with data this week"
    static let trustGate = "Team averages for 5+ people only, worked out on the server"
    static let trustNames = "Never a name next to a number; the roster lives on the web"
    static let trustDemo = "Includes demo data"
}

struct AdminSection: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 1100

    var body: some View {
        let a = model.admin
        let wide = width >= 980
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s6) {
                header(a)
                switch a.load {
                case .idle, .loading:
                    loadingHero
                case .offline: retry(AdminCopy.offline, symbol: "wifi.slash")
                case .failed: retry(AdminCopy.failed, symbol: "exclamationmark.arrow.trianglehead.counterclockwise")
                case .loaded(let d):
                    if d.published { numbers(d, a, wide: wide) } else { unpublished }
                }
                if a.dashboard?.published != true {
                HStack(spacing: ZenSpace.s2) {
                    Image(systemName: "lock.shield").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.zen.textBrand)
                    Text(AdminCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, ZenSpace.s1)
                }
            }
            .padding(.horizontal, wide ? ZenSpace.s8 : ZenSpace.s6)
            .padding(.vertical, ZenSpace.s6)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        // Debug renders: ZEN_ADMIN_ANCHOR=metrics|report scrolls there.
        .task {
            if let raw = ProcessInfo.processInfo.environment["ZEN_ADMIN_ANCHOR"] {
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(raw, anchor: .top)
            }
        }
        #endif
        }
        .task(id: a.team?.cohortId) { await a.refresh(service) }
    }

    /// The admin service (debug renders can stand in another state with ZEN_ADMIN_STATE).
    private var service: any AdminService {
        #if DEBUG
        if let debug = AdminDebugService.fromEnvironment() { return debug }
        #endif
        return model.services.admin
    }

    // MARK: Header

    private func header(_ a: AdminModel) -> some View {
        let d = a.dashboard
        return HStack(alignment: .bottom, spacing: ZenSpace.s4) {
            VStack(alignment: .leading, spacing: ZenSpace.s2) {
                Eyebrow(AdminCopy.eyebrow, color: Color.zen.textBrand)
                Text(d?.name ?? a.team?.name ?? "Your team").zenType(.headline).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: ZenSpace.s2) {
                    if let d, d.published, let n = d.activeN {
                        Label(AdminCopy.basedOn(n), systemImage: "person.2.fill")
                            .font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                            .labelStyle(BasedOnLabelStyle())
                    }
                    if d?.includesDemo == true { DemoTag(AdminCopy.demo) }
                    if let d, d.published {
                        Text("Week \(AdminStory.shortWeek(d.week).dropFirst())").font(ZenFont.number(11.5))
                            .foregroundStyle(Color.zen.textCaption)
                    }
                }
            }
            Spacer(minLength: ZenSpace.s4)
            actions(a)
        }
    }

    /// One primary for the page (share the numbers with leadership), the web admin as secondary.
    @ViewBuilder
    private func actions(_ a: AdminModel) -> some View {
        let report: PeopleReport? = if case .loaded(let r) = a.report { r } else { nil }
        HStack(spacing: ZenSpace.s3) {
            if let base = TeamWeb.base {
                Button { NSWorkspace.shared.open(base.appending(path: "admin")) } label: {
                    Label(AdminCopy.webAdmin, systemImage: "safari")
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
            if let d = a.dashboard, let text = AdminStory.shareText(d, report: report) {
                ShareLink(item: text, subject: Text("\(d.name) · \(AdminCopy.shareSubject)"), message: nil) {
                    Label(AdminCopy.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .accessibilityHint("Shares the team averages, the formula and the report as text")
            }
        }
    }

    // MARK: States

    private var loadingHero: some View {
        HStack(spacing: ZenSpace.s3) {
            ProgressView().controlSize(.small)
            Text(AdminCopy.loading).font(ZenFont.text(15, .medium)).foregroundStyle(AdminInk.body)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(RoundedRectangle(cornerRadius: ZenRadius.xxxl, style: .continuous).fill(AdminInk.ground))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    /// Offline or failed: one calm card, Retry is the page's primary (nothing else to do).
    private func retry(_ text: String, symbol: String) -> some View {
        HStack(spacing: ZenSpace.s5) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(Color.zen.textBrand)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.zen.surfaceTint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(ZenFont.text(16, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(AdminCopy.retryHint).zenType(.body).foregroundStyle(Color.zen.textBody)
            }
            Spacer(minLength: ZenSpace.s4)
            Button { Task { await model.admin.refresh(service) } } label: {
                Label(AdminCopy.retry, systemImage: "arrow.clockwise")
            }
            .buttonStyle(ZenPrimaryButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxl)
    }

    /// Under 5 people: no number anywhere, an illustration and what's coming.
    private var unpublished: some View {
        HStack(alignment: .center, spacing: ZenSpace.s10) {
            SeatsIllustration().frame(width: 260, height: 200)
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                Text(AdminCopy.unpublishedTitle).zenType(.title).foregroundStyle(Color.zen.textHeading)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Text(AdminCopy.unpublished).zenType(.bodyStrong).foregroundStyle(Color.zen.textHeading)
                    Text(AdminCopy.unpublishedMore).zenType(.body).foregroundStyle(Color.zen.textBody)
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: ZenSpace.s2) {
                    Eyebrow(AdminCopy.unpublishedPreviewTitle)
                    ForEach(AdminCopy.unpublishedPreview, id: \.self) { item in
                        Label(item, systemImage: "circle.dashed").font(ZenFont.text(13.5)).foregroundStyle(Color.zen.textBody)
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(ZenSpace.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xxxl)
    }

    // MARK: Numbers

    @ViewBuilder
    private func numbers(_ d: AdminDashboard, _ a: AdminModel, wide: Bool) -> some View {
        AdminHero(dashboard: d, wide: width >= 820)
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Eyebrow(AdminCopy.supportingTitle)
            let columns = Array(repeating: GridItem(.flexible(), spacing: ZenSpace.s4, alignment: .top), count: width >= 1000 ? 4 : 2)
            LazyVGrid(columns: columns, alignment: .leading, spacing: ZenSpace.s4) {
                ForEach(AdminCardKind.metrics, id: \.self) { kind in
                    AdminMetricTile(kind: kind, card: kind.card(in: d.cards), series: AdminStory.series(d, kind))
                }
            }
        }
        .id("metrics")
        let gold: AdminGoldTile? = d.gold.claimsThisMonth.flatMap { c in d.gold.sponsoredInr.map { AdminGoldTile(claims: c, sponsoredInr: $0) } }
        let report = AdminReportCard(report: a.report, dashboard: d, wide: width >= 760) {
            Task { await a.loadReport(service, regenerate: true) }
        }
        let trust = AdminTrustTile(activeN: d.activeN, includesDemo: d.includesDemo)
        Group {
            if wide {
                HStack(alignment: .top, spacing: ZenSpace.s4) {
                    report
                    VStack(spacing: ZenSpace.s4) {
                        if let gold { gold }
                        trust
                    }
                    .frame(width: 300)
                }
            } else {
                VStack(alignment: .leading, spacing: ZenSpace.s4) {
                    if let gold { gold }
                    report
                    trust
                }
            }
        }
        .id("report")
    }
}

/// "Based on 12 people" with its icon, as a quiet pill.
private struct BasedOnLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11)).foregroundStyle(Color.zen.textBrand)
            configuration.title
        }
        .padding(.horizontal, ZenSpace.s3).padding(.vertical, 5)
        .background(Capsule().fill(Color.zen.surfaceTint))
        .overlay(Capsule().strokeBorder(Color.zen.brandFill.opacity(0.25), lineWidth: 1))
    }
}

/// Five seats around a soft light: the gate before team numbers appear. Decorative.
private struct SeatsIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.zen.brandSoft.opacity(0.45), Color.zen.brandSoft.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 120))
                .scaleEffect(breathe ? 1.06 : 0.94)
            ForEach(0..<5, id: \.self) { i in
                let angle = Angle.degrees(Double(i) * 72 - 90)
                RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                    .fill(Color.zen.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: ZenRadius.md, style: .continuous)
                        .strokeBorder(Color.zen.brandFill.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .overlay(Image(systemName: "person.fill").font(.system(size: 18)).foregroundStyle(Color.zen.textBrand.opacity(0.8)))
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                    .offset(x: cos(angle.radians) * 74, y: sin(angle.radians) * 74)
            }
            ZenMark().fill(Color.zen.textBrand, style: FillStyle(eoFill: true)).frame(width: 30, height: 30)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(ZenMotion.calm(ZenMotion.t5 * 2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

#if DEBUG
/// Debug renders only: ZEN_ADMIN_STATE=unpublished|offline|loading shows that state with the demo team.
struct AdminDebugService: AdminService {
    let state: String

    static func fromEnvironment() -> AdminDebugService? {
        ProcessInfo.processInfo.environment["ZEN_ADMIN_STATE"].map(AdminDebugService.init(state:))
    }

    func adminTeam() async throws(AdminError) -> AdminTeam? { AdminTeam(cohortId: FakeAdmin.cohortId, name: "Payments") }

    func dashboard(cohortId: String) async throws(AdminError) -> AdminDashboard {
        switch state {
        case "offline": throw .offline
        case "failed": throw .invalid
        case "loading":
            try? await Task.sleep(for: .seconds(60))
            throw .offline
        case "unpublished":
            return AdminDashboard(name: "Payments", week: "2026-W47", membersN: 4, activeN: nil, includesDemo: true, published: false,
                                  hourlyCostInr: 1200, goldSponsorInr: 0, orgBrainText: "",
                                  cards: AdminCards(focusHours: .empty, keptRate: .empty, afterHoursShare: .empty,
                                                    goodDayRate: .empty, rupeesPerMonth: .empty),
                                  trend: [], gold: AdminGold(claimsThisMonth: nil, sponsoredInr: nil), rupeeFormula: nil)
        default: return try await FakeAdmin().dashboard(cohortId: cohortId)
        }
    }

    func peopleReport(cohortId: String, month: String, regenerate: Bool) async throws(AdminError) -> PeopleReport {
        if state == "regenerating" && regenerate { try? await Task.sleep(for: .seconds(60)) }
        return try await FakeAdmin().peopleReport(cohortId: cohortId, month: month, regenerate: regenerate)
    }
}
#endif
