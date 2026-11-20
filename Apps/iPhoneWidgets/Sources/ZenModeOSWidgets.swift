import SwiftUI
import WidgetKit

/// The iPhone's widget extension. Today it carries one thing: the Live Activity that follows the
/// Mac's focus on the Lock Screen and in the Dynamic Island.
@main
struct ZenModeOSWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}
