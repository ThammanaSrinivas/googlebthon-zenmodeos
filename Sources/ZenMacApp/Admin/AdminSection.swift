import AppKit
import SwiftUI
import Albeit
import ZenAPI

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
        if case .idle = report { await loadReport(service, regenerate: false) }
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
    static let unpublished = "Team numbers appear at 5 people. Nobody's own numbers are ever shown."
    static let offline = "Can't reach the team numbers right now."
    static let failed = "The team numbers didn't load."
    static let retry = "Retry"
    static let gold = "Payout happens through HR; nothing moves in the app."
    static let reportTitle = "Monthly people report"
    static let fromNumbers = "Written from the numbers"
    static let regenerate = "Regenerate"
    static let regenerating = "Writing a new one… (up to 20 s)"
    static let webAdmin = "Open web admin"
    static let privacy = "Team averages for 5+ people only. Never a name next to a number."
    static let trend = "Focus hours per person, by week"
}

struct AdminSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let a = model.admin
        ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                header(a)
                switch a.load {
                case .idle, .loading:
                    HStack(spacing: ZenSpace.s2) {
                        ProgressView().controlSize(.small)
                        Text("Loading the team numbers…").zenType(.body).foregroundStyle(Color.zen.textBody)
                    }
                case .offline: retry(AdminCopy.offline)
                case .failed: retry(AdminCopy.failed)
                case .loaded(let d):
                    if d.published { numbers(d) } else { unpublished }
                    reportCard(a)
                }
                Text(AdminCopy.privacy).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    .padding(.top, ZenSpace.s2)
            }
            .padding(ZenSpace.s6)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task(id: a.team?.cohortId) { await a.refresh(model.services.admin) }
    }

    private func header(_ a: AdminModel) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Eyebrow(AdminCopy.eyebrow, color: Color.zen.textBrand)
                if a.dashboard?.includesDemo == true { DemoTag(AdminCopy.demo) }
                Spacer(minLength: 0)
                if let base = TeamWeb.base {
                    Button(AdminCopy.webAdmin) { NSWorkspace.shared.open(base.appending(path: "admin")) }
                        .buttonStyle(ZenSecondaryButtonStyle())
                }
            }
            Text(a.dashboard?.name ?? a.team?.name ?? "Your team").zenType(.display).foregroundStyle(Color.zen.textHeading)
                .accessibilityAddTraits(.isHeader)
            if let d = a.dashboard, d.published, let n = d.activeN {
                Text(AdminCopy.basedOn(n)).zenType(.body).foregroundStyle(Color.zen.textBody)
            }
        }
    }

    private func retry(_ text: String) -> some View {
        HStack(spacing: ZenSpace.s3) {
            Text(text).zenType(.body).foregroundStyle(Color.zen.textBody)
            Button(AdminCopy.retry) { Task { await model.admin.refresh(model.services.admin) } }
                .buttonStyle(ZenSecondaryButtonStyle())
        }
        .padding(ZenSpace.s5)
        .glassCard(radius: ZenRadius.lg)
    }

    private var unpublished: some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: "person.3").font(.system(size: 20)).foregroundStyle(Color.zen.textBrand)
            Text(AdminCopy.unpublished).zenType(.body).foregroundStyle(Color.zen.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
    }

    @ViewBuilder
    private func numbers(_ d: AdminDashboard) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: ZenSpace.s4, alignment: .top)], spacing: ZenSpace.s4) {
            ForEach(AdminCardKind.allCases, id: \.self) { kind in
                AdminCardView(kind: kind, card: kind.card(in: d.cards),
                              formula: kind == .rupeesPerMonth ? d.rupeeFormula : nil)
            }
        }
        HStack(alignment: .top, spacing: ZenSpace.s4) {
            trend(d.trend)
            if let claims = d.gold.claimsThisMonth, let inr = d.gold.sponsoredInr { gold(claims, inr) }
        }
    }

    private func trend(_ weeks: [AdminTrendWeek]) -> some View {
        let top = max(weeks.compactMap(\.focusH).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Text(AdminCopy.trend).font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            ForEach(weeks.prefix(4), id: \.week) { w in
                HStack(spacing: ZenSpace.s3) {
                    Text(w.week).font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption).frame(width: 74, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Color.zen.surfaceSunk.opacity(0.6))
                            .overlay(alignment: .leading) {
                                if let h = w.focusH, w.published {
                                    Capsule().fill(Color.zen.brandFill).frame(width: geo.size.width * h / top)
                                }
                            }
                    }
                    .frame(height: 8)
                    Text(w.published ? AdminFormat.value(w.focusH, of: .focusHours) : "–")
                        .font(ZenFont.number(12)).foregroundStyle(Color.zen.textHeading).frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(w.week): \(w.published ? AdminFormat.value(w.focusH, of: .focusHours) : "not enough people")")
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.lg)
    }

    private func gold(_ claims: Int, _ inr: Int) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Image(systemName: "sparkles").foregroundStyle(Color.zen.accentRewardText)
                Text("\(claims) Zen Gold weeks this month · \(AdminFormat.rupees(Double(inr))) sponsored")
                    .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
            }
            Text(AdminCopy.gold).zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.7)))
    }

    @ViewBuilder
    private func reportCard(_ a: AdminModel) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            HStack(spacing: ZenSpace.s2) {
                Text(AdminCopy.reportTitle).font(ZenFont.text(16, .semibold)).foregroundStyle(Color.zen.textHeading)
                if case .loaded(let r) = a.report {
                    Text(r.fallback ? AdminCopy.fromNumbers : "Gemini · \(r.month)").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                Spacer(minLength: 0)
                Button(AdminCopy.regenerate) { Task { await a.loadReport(model.services.admin, regenerate: true) } }
                    .buttonStyle(ZenLinkButtonStyle())
                    .disabled(isBusy(a.report))
            }
            switch a.report {
            case .idle, .loading:
                HStack(spacing: ZenSpace.s2) { ProgressView().controlSize(.small); Text("Loading the report…").zenType(.caption) }
            case .regenerating(let old):
                HStack(spacing: ZenSpace.s2) { ProgressView().controlSize(.small); Text(AdminCopy.regenerating).zenType(.caption) }
                if let old { reportBody(old).opacity(0.5) }
            case .failed:
                Text("The report didn't load.").zenType(.body).foregroundStyle(Color.zen.textBody)
            case .loaded(let r):
                reportBody(r)
            }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
    }

    private func isBusy(_ r: AdminModel.Report) -> Bool {
        switch r {
        case .loading, .regenerating: true
        default: false
        }
    }

    private func reportBody(_ r: PeopleReport) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s3) {
            Text(r.text).zenType(.body).foregroundStyle(Color.zen.textHeading).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(r.bullets.enumerated()), id: \.offset) { _, b in
                    HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                        Text("•").foregroundStyle(Color.zen.textBrand)
                        Text(b).zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !r.suggestions.isEmpty {
                Text("Try").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                ForEach(Array(r.suggestions.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                        Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Color.zen.textBrand)
                        Text(s).zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// One card: the title, this week, last week, the change (green good, ember not, grey neither).
struct AdminCardView: View {
    let kind: AdminCardKind
    let card: AdminCard
    let formula: String?

    var body: some View {
        let change = AdminFormat.change(card.change, of: kind)
        let good = AdminFormat.isImprovement(card.change, of: kind)
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Text(kind.title).font(ZenFont.text(13, .medium)).foregroundStyle(Color.zen.textBody)
            Text(AdminFormat.value(card.now, of: kind)).font(ZenFont.number(30)).foregroundStyle(Color.zen.textHeading)
                .minimumScaleFactor(0.6).lineLimit(1)
            HStack(spacing: ZenSpace.s2) {
                Text("last week \(AdminFormat.value(card.last, of: kind))").font(ZenFont.number(11)).foregroundStyle(Color.zen.textCaption)
                if let change {
                    Text(change).font(ZenFont.number(11.5))
                        .foregroundStyle(good == true ? Color.zen.scoreGain : good == false ? Color.zen.scoreDeduct : Color.zen.textCaption)
                }
            }
            if let formula {
                Text(formula).font(ZenFont.number(10)).foregroundStyle(Color.zen.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(ZenSpace.s5)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .glassCard(radius: ZenRadius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title): \(AdminFormat.value(card.now, of: kind)), last week \(AdminFormat.value(card.last, of: kind))"
                            + (change.map { ", \($0)" } ?? ""))
    }
}
