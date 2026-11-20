import SwiftUI
import Albeit
import ZenAPI

/// Today: one focal point (the score), the week, Zeno's last line, the cohort and Zen Gold.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .today

    enum Section: String, CaseIterable, Identifiable {
        case today = "Today", week = "Week", cohort = "Cohort", gold = "Zen Gold", settings = "Settings"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .week: "chart.bar"
            case .cohort: "person.3"
            case .gold: "sparkles"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        ZStack {
            ZenBackdrop(tone: .zen, glowAt: UnitPoint(x: 0.42, y: 0.3))
            HStack(spacing: ZenSpace.s4) {
                sidebar
                content
            }
            .padding(ZenSpace.s3)
            .padding(.top, 28)
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: ZenSpace.s1) {
            ZenLockup(size: 15).padding(.horizontal, ZenSpace.s3).padding(.bottom, ZenSpace.s5)
            ForEach(Section.allCases) { s in
                Button { section = s } label: {
                    Label(s.rawValue, systemImage: s.symbol)
                        .font(ZenFont.text(13.5, s == section ? .semibold : .medium))
                        .foregroundStyle(s == section ? Color.zen.textHeading : Color.zen.textBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ZenSpace.s3).frame(height: 34)
                        .background {
                            if s == section { RoundedRectangle(cornerRadius: ZenRadius.sm, style: .continuous).fill(Color.zen.surfaceCard.opacity(0.75)) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(s == section ? [.isSelected, .isButton] : .isButton)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text(model.user?.displayName ?? "Exploring").font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.textHeading)
                HStack(spacing: 6) {
                    Circle().fill(Color.zen.brandFill).frame(width: 7, height: 7)
                    Text(model.user == nil ? "This Mac only" : "2 of 2 devices · synced").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                }
                if model.isDemo { DemoTag().padding(.top, 4) }
            }
            .padding(ZenSpace.s3)
        }
        .padding(.vertical, ZenSpace.s5)
        .padding(.horizontal, ZenSpace.s2)
        .frame(width: 224)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: ZenRadius.xl))
    }

    private var content: some View {
        let snap = model.snapshot ?? FakeSnapshot.value
        return ScrollView {
            VStack(alignment: .leading, spacing: ZenSpace.s5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.Today.title).zenType(.headline).foregroundStyle(Color.zen.textHeading)
                        .accessibilityAddTraits(.isHeader)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .zenType(.body).foregroundStyle(Color.zen.textCaption)
                    Spacer()
                }
                Grid(horizontalSpacing: ZenSpace.s4, verticalSpacing: ZenSpace.s4) {
                    GridRow {
                        scoreTile(snap).gridCellColumns(2)
                        zenoTile
                    }
                    GridRow {
                        weekTile(snap).gridCellColumns(2)
                        goldTile(snap)
                    }
                    GridRow {
                        cohortTile.gridCellColumns(3)
                    }
                }
            }
            .padding(ZenSpace.s6)
        }
        .scrollIndicators(.hidden)
    }

    private func tile<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(ZenSpace.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard(radius: ZenRadius.widget)
    }

    private func scoreTile(_ snap: ScoreSnapshot) -> some View {
        tile {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Eyebrow("Zen Score · every screen")
                HStack(alignment: .firstTextBaseline, spacing: ZenSpace.s2) {
                    ScoreText(snap.score.text, size: 72)
                    Text("/10").font(ZenFont.number(16)).foregroundStyle(Color.zen.textCaption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zen Score \(snap.score.text) out of 10")
                Text(Copy.Today.goodDay).zenType(.caption).foregroundStyle(Color.zen.textCaption)
                VStack(spacing: ZenSpace.s2) {
                    ForEach(snap.devices) { d in
                        DeviceRow(symbol: d.kind == .iPhone ? "iphone" : "laptopcomputer", name: d.name, detail: d.detail)
                    }
                }
            }
        }
    }

    private var zenoTile: some View {
        tile {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Eyebrow(Copy.Today.zenoCard)
                if let (nudge, source) = model.lastNudge {
                    Text(nudge.line).font(ZenFont.text(17, .semibold)).foregroundStyle(Color.zen.textHeading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(source == .gemini ? Copy.Story.geminiCaption : "Zeno's fallback line · Gemini didn't answer in time")
                        .zenType(.caption).foregroundStyle(Color.zen.textCaption)
                } else {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Ask Zeno again") { Task { await model.refreshNudge(trigger: .checkIn) } }
                    .buttonStyle(ZenLinkButtonStyle())
                Text("Quiet: \(model.profile.quiet.summary)").zenType(.caption).foregroundStyle(Color.zen.textCaption)
            }
        }
    }

    private func weekTile(_ snap: ScoreSnapshot) -> some View {
        tile {
            VStack(alignment: .leading, spacing: ZenSpace.s4) {
                Eyebrow("This week · weekly streak \(snap.week.streakBefore)")
                WeekCells(week: snap.week)
            }
        }
    }

    private func goldTile(_ snap: ScoreSnapshot) -> some View {
        tile {
            VStack(alignment: .leading, spacing: ZenSpace.s3) {
                Eyebrow(Copy.Today.gold, color: Color.zen.accentRewardText)
                CellRow((0..<4).map { $0 < snap.week.goodDays ? .reward : .empty })
                Text(snap.week.isWon ? Copy.Today.goldOpen : Copy.Today.goldClosed)
                    .font(ZenFont.text(14, .semibold)).foregroundStyle(Color.zen.textHeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cohortTile: some View {
        tile {
            HStack(alignment: .center, spacing: ZenSpace.s6) {
                if let c = model.cohort {
                    VStack(alignment: .leading, spacing: ZenSpace.s2) {
                        Eyebrow("\(c.preview.organisation) · cohort", color: Color.zen.textBrand)
                        Text(c.preview.name).zenType(.title).foregroundStyle(Color.zen.textHeading)
                        Text("\(c.preview.memberCount) people · one group score, never a name").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                    Spacer()
                    if let score = c.score {
                        VStack(alignment: .trailing) {
                            Text(score.text).font(ZenFont.number(40)).foregroundStyle(Color.zen.textHeading)
                            Text("\(Int((c.goodDayRate ?? 0) * 100))% good days").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: ZenSpace.s2) {
                        Eyebrow("Cohort")
                        Text(Copy.Today.cohortJoin).zenType(.title).foregroundStyle(Color.zen.textHeading)
                        Text("Campuses and teams see one group score, for 5 or more. Never you.").zenType(.caption).foregroundStyle(Color.zen.textCaption)
                    }
                    Spacer()
                }
            }
        }
    }
}
