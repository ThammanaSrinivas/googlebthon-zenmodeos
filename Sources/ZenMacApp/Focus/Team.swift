import AppKit
import SwiftUI
import Albeit
import ZenAPI
import ZenFocus

/// The person's team on the Mac: Ask Zeno (#12, grounded only in the team's notes), the Focus
/// Report link, "What my admin sees", the join link, and the Zen Gold claim when the week is a Zen
/// Gold week and the team has a sponsor (#15 glue). Every number the admin sees is the server's.
@MainActor
@Observable
final class TeamModel {
    enum Load: Equatable { case idle, loading, none, ready(TeamInfo), signedOut, failed(String) }
    enum Ask: Equatable { case idle, asking, answered(AskResult), failed(String) }
    enum Claim: Equatable { case idle, claiming, claimed(Int), notYet(String) }

    private(set) var load: Load = .idle
    private(set) var ask: Ask = .idle
    private(set) var claim: Claim = .idle
    private(set) var reportLink: FocusReportLink?
    private(set) var reportNote: String?

    var team: TeamInfo? { if case .ready(let t) = load { t } else { nil } }

    func refresh(_ service: any TeamService) async {
        load = .loading
        do {
            load = try await service.myTeam().map(Load.ready) ?? .none
        } catch {
            load = error == .signedOut ? .signedOut : .failed(error == .offline ? "You're offline." : "Couldn't load your team.")
        }
    }

    func ask(_ question: String, work: any ZenoWorkService) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let team, !q.isEmpty else { return }
        ask = .asking
        do {
            ask = .answered(try await work.ask(cohortId: team.cohortId, question: String(q.prefix(300))))
        } catch {
            ask = .failed(error == .notAMember ? "You're not on this team any more." : "Zeno couldn't answer just now.")
        }
    }

    func makeReportLink(_ service: any TeamService, showName: Bool) async {
        reportNote = nil
        do {
            let link = try await service.focusReportLink(isoWeek: ISOWeek.key(Date()), showName: showName)
            reportLink = link
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            reportNote = "Link copied. It stops working in 30 days."
        } catch {
            reportNote = error == .offline ? "You're offline." : "Couldn't make the link."
        }
    }

    func claimGold(_ service: any TeamService) async {
        guard let team else { return }
        claim = .claiming
        do {
            claim = .claimed(try await service.claimGold(cohortId: team.cohortId, isoWeek: ISOWeek.key(Date())))
        } catch {
            claim = .notYet(error == .notAGoldWeek ? "Not a Zen Gold week yet: 5 days with a kept block." : "Couldn't claim just now.")
        }
    }
}

/// ISO week keys, "2026-W47" (Monday first, the cohort's weeks).
enum ISOWeek {
    static func key(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// The Mondays-to-today day keys of `date`'s week.
    static func daysSoFar(_ date: Date, timeZone: TimeZone = .current) -> [String] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        guard let monday = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        var out: [String] = []
        var d = monday
        while d <= date {
            out.append(FocusDayKey.key(d, timeZone: timeZone))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

/// "Your team" on Today: Ask Zeno, the Focus Report, what the admin sees, Zen Gold.
struct TeamCard: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var showName = false
    @State private var keptDays = 0
    @State private var joinText = ""

    var body: some View {
        let t = model.team
        VStack(alignment: .leading, spacing: ZenSpace.s4) {
            HStack(spacing: ZenSpace.s2) {
                Eyebrow(t.team.map { "Your team · \($0.name)" } ?? "Your team", color: Color.zen.textBrand)
                if model.isDemo { DemoTag() }
                Spacer(minLength: 0)
                if let privacy = TeamWeb.privacy {
                    Button("What my admin sees") { NSWorkspace.shared.open(privacy) }.buttonStyle(ZenLinkButtonStyle())
                }
            }
            switch t.load {
            case .idle, .loading:
                HStack(spacing: ZenSpace.s2) { ProgressView().controlSize(.small); Text("Loading your team…").zenType(.caption) }
            case .signedOut:
                Text("Sign in to see your team.").zenType(.body).foregroundStyle(Color.zen.textBody)
            case .none:
                Text("You're not on a team yet. Your admin's join link adds you; the admin only ever sees team numbers for 5 or more people.")
                    .zenType(.body).foregroundStyle(Color.zen.textBody).fixedSize(horizontal: false, vertical: true)
                joinField
            case .failed(let why):
                HStack {
                    Text(why).zenType(.body).foregroundStyle(Color.zen.scoreDeduct)
                    Button("Try again") { Task { await t.refresh(model.services.team) } }.buttonStyle(ZenLinkButtonStyle())
                }
            case .ready(let team):
                askZeno(team)
                Divider().opacity(0.4)
                report
                if team.goldSponsorInr > 0 { gold(team) }
            }
        }
        .padding(ZenSpace.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: ZenRadius.xl)
        .task {
            if t.load == .idle { await t.refresh(model.services.team) }
            keptDays = await model.focus.keptDaysThisWeek()
        }
    }

    /// A join link opens the team's join page; a 6-letter code joins here.
    private var joinField: some View {
        HStack(spacing: ZenSpace.s2) {
            TextField("Paste your team's join link or code", text: $joinText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(join)
                .accessibilityLabel("Team join link or code")
            Button("Join", action: join).buttonStyle(ZenPrimaryButtonStyle())
                .disabled(joinText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func join() {
        let text = joinText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme == "https", url.path.hasPrefix("/join/") {
            NSWorkspace.shared.open(url)
        } else if JoinCode(text) != nil {
            model.codeText = text
            model.joinCohort()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await model.team.refresh(model.services.team)
            }
        }
        joinText = ""
    }

    private func askZeno(_ team: TeamInfo) -> some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            Text("Ask Zeno about the team").font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
            HStack(spacing: ZenSpace.s2) {
                TextField(team.hasNotes ? "What are this quarter's goals?" : "Your admin hasn't added notes yet", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.team.ask(question, work: model.services.work) } }
                    .accessibilityLabel("Question for Zeno about the team's notes")
                Button(model.team.ask == .asking ? "Asking…" : "Ask") { Task { await model.team.ask(question, work: model.services.work) } }
                    .buttonStyle(ZenPrimaryButtonStyle())
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || model.team.ask == .asking)
            }
            switch model.team.ask {
            case .answered(let a):
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.answer).zenType(.body).foregroundStyle(Color.zen.textHeading).fixedSize(horizontal: false, vertical: true)
                    Label(a.grounded ? "From your team's notes" : "Not in your team's notes",
                          systemImage: a.grounded ? "checkmark.seal.fill" : "questionmark.circle")
                        .zenType(.caption).foregroundStyle(a.grounded ? Color.zen.textBrand : Color.zen.textCaption)
                    if a.grounded, let quote = a.quote, !quote.isEmpty {
                        Text("“\(quote)”").font(ZenFont.text(12).italic()).foregroundStyle(Color.zen.textCaption)
                    }
                }
                .accessibilityElement(children: .combine)
            case .failed(let why):
                Text(why).zenType(.caption).foregroundStyle(Color.zen.scoreDeduct)
            default: EmptyView()
            }
        }
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s2) {
            HStack(spacing: ZenSpace.s2) {
                Text("My Focus Report").font(ZenFont.text(15, .semibold)).foregroundStyle(Color.zen.textHeading)
                Spacer(minLength: 0)
                Toggle("Show my name", isOn: $showName).toggleStyle(.checkbox).font(ZenFont.text(12))
                Button("Copy a link") { Task { await model.team.makeReportLink(model.services.team, showName: showName) } }
                    .buttonStyle(ZenSecondaryButtonStyle())
                if let link = model.team.reportLink {
                    Button("Open") { NSWorkspace.shared.open(link.url) }.buttonStyle(ZenLinkButtonStyle())
                }
            }
            Text(model.team.reportNote ?? "This week's focus hours, kept blocks and Zen Score, for anyone with the link. No apps, no minutes.")
                .zenType(.caption).foregroundStyle(Color.zen.textCaption)
        }
    }

    private func gold(_ team: TeamInfo) -> some View {
        HStack(spacing: ZenSpace.s3) {
            Image(systemName: "sparkles").foregroundStyle(Color.zen.accentRewardText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zen Gold for teams · ₹\(team.goldSponsorInr) a gold week").font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                Text(goldLine).zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
            Spacer(minLength: 0)
            if case .claimed = model.team.claim {} else if keptDays >= 5 {
                Button(model.team.claim == .claiming ? "Claiming…" : "Claim") { Task { await model.team.claimGold(model.services.team) } }
                    .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
        .padding(ZenSpace.s3)
        .background(RoundedRectangle(cornerRadius: ZenRadius.lg, style: .continuous).fill(Color.zen.accentRewardTint.opacity(0.7)))
    }

    private var goldLine: String {
        switch model.team.claim {
        case .claimed(let inr): "Claimed: ₹\(inr) of gold, paid through HR."
        case .notYet(let why): why
        default: keptDays >= 5 ? "This is a Zen Gold week. Claim it." : "\(keptDays) of 5 days with a kept block this week."
        }
    }
}
