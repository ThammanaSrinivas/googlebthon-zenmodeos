import ActivityKit
import Foundation

/// The Mac's focus block, as the iPhone's Live Activity holds it. This one file is compiled into
/// both the iPhone app (which starts, updates and ends the activity) and the widget extension
/// (which draws it): ActivityKit pairs the two by this type's name, so rename it in both or neither.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// When the Mac's focus ends. Shown as a clock time ("until 12:00"), never a countdown.
        var until: Date
    }
}
