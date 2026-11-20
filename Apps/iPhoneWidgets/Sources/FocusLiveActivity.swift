import ActivityKit
import Albeit
import SwiftUI
import WidgetKit
import ZenAPI

/// "Focusing until 12:00" while the Mac focuses: a calm Zeno and the end time, never a countdown.
/// Past the end time (the activity's stale date) it reads "Focus done" until the app ends it.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLockScreen(until: context.state.until, done: context.isStale)
                .activityBackgroundTint(Color.zen.island.opacity(0.86))
                .activitySystemActionForegroundColor(Color.zen.islandText)
        } dynamicIsland: { context in
            let until = context.state.until, done = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ZenMark().fill(Color.zen.islandDetail, style: FillStyle(eoFill: true))
                            .frame(width: 13, height: 13)
                        Text(FocusIslandCopy.name).font(ZenFont.text(13, .semibold)).foregroundStyle(Color.zen.islandDetail)
                    }
                    .padding(.leading, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FocusIslandCopy.name)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: ZenSpace.s3) {
                        ZenoStill(done ? .pleasant : .calm).frame(width: 58)
                        FocusLines(until: until, done: done, size: 19)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                ZenoStill(done ? .pleasant : .calm).frame(width: 26)
            } compactTrailing: {
                Text(done ? FocusIslandCopy.doneShort : FocusIslandCopy.untilShort(until))
                    .font(ZenFont.text(14, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.zen.islandText)
                    .accessibilityLabel(done ? FocusIslandCopy.done : FocusIslandCopy.focusing(until))
            } minimal: {
                ZenMark().fill(Color.zen.brandSoft, style: FillStyle(eoFill: true))
                    .frame(width: 15, height: 15)
                    .accessibilityLabel(done ? FocusIslandCopy.done : FocusIslandCopy.focusing(until))
            }
            .keylineTint(Color.zen.brandSoft)
        }
    }
}

/// The Lock Screen banner: Zeno, the name, the end time, where it comes from.
private struct FocusLockScreen: View {
    let until: Date
    let done: Bool

    var body: some View {
        HStack(spacing: ZenSpace.s4) {
            ZenoStill(done ? .pleasant : .calm)
                .frame(width: 66)
                .background(
                    RadialGradient(colors: [Color.zen.brandFill.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 52)
                        .frame(width: 120, height: 120)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(FocusIslandCopy.eyebrow)
                    .font(ZenFont.number(10.5)).tracking(1.05)
                    .foregroundStyle(Color.zen.islandDetail)
                FocusLines(until: until, done: done, size: 21)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ZenSpace.s5)
        .padding(.vertical, ZenSpace.s4)
    }
}

/// "Focusing until 12:00" over "on your Mac", read by VoiceOver as one line.
private struct FocusLines: View {
    let until: Date
    let done: Bool
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(done ? FocusIslandCopy.done : FocusIslandCopy.focusing(until))
                .font(ZenFont.text(size, .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.zen.islandText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(FocusIslandCopy.onYourMac)
                .font(ZenFont.text(size * 0.7))
                .foregroundStyle(Color.zen.islandDetail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FocusIslandCopy.name). \(done ? FocusIslandCopy.done : FocusIslandCopy.focusing(until)) \(FocusIslandCopy.onYourMac).")
    }
}

/// The words. The end time is the Mac's 24-hour "HH:mm", in this phone's time zone.
enum FocusIslandCopy {
    static let name = "ZenMode OS"
    static let eyebrow = "ZenMode OS · Focus".uppercased()
    static let onYourMac = "on your Mac"
    static let done = "Focus done"
    static let doneShort = "done"
    static func focusing(_ until: Date) -> String { "Focusing until \(DayPlanner.text(until))" }
    static func untilShort(_ until: Date) -> String { "until \(DayPlanner.text(until))" }
}
