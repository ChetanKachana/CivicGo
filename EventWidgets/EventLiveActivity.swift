import SwiftUI
import WidgetKit
import ActivityKit

// --- Main UI View for Lock Screen & Expanded Dynamic Island ---

// --- Widget Configuration for Live Activity ---
struct EventLiveActivity: Widget {
    let kind: String = "EventLiveActivity" // Unique identifier

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EventActivityAttributes.self) { context in
            // --- Lock Screen / Banner UI ---
            EventLiveActivityView(context: context)
            // Optional: Customize the appearance on the Lock Screen
            // .activityBackgroundTint(Color.black.opacity(0.2))
            // .activitySystemActionForegroundColor(Color.white)
            // .widgetURL(URL(string: "yourappscheme://opportunity/\(context.attributes.opportunityId)"))

        } dynamicIsland: { context in
            // --- Dynamic Island UI ---
            DynamicIsland {
                // --- Expanded Region (when user long-presses) ---
                 DynamicIslandExpandedRegion(.leading) {
                     Label { Text(context.attributes.opportunityName).font(.caption) }
                           icon: { Image(systemName: "calendar").foregroundColor(.accentColor) }
                 }
                 DynamicIslandExpandedRegion(.trailing) {
                     Text(context.state.statusMessage)
                        .font(.caption).bold()
                 }
                 DynamicIslandExpandedRegion(.bottom) {
                     HStack {
                        Image(systemName: "location.circle.fill").foregroundColor(.secondary)
                        Text(context.attributes.location).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                     }
                     // Optional: Text("Deep link here").font(.caption2)
                 }
                 // DynamicIslandExpandedRegion(.center) { Text("Center") } // If needed

            } compactLeading: {
                // --- Compact Leading (left side of notch) ---
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.accentColor)
                    .padding(.leading, 2)

            } compactTrailing: {
                 // --- Compact Trailing (right side of notch) ---
                 Text(context.state.statusMessage.prefix(10)) // Show a snippet
                     .font(.caption2)
                     .padding(.trailing, 2)

            } minimal: {
                 // --- Minimal (when multiple activities are active) ---
                 Image(systemName: "calendar")
                    .foregroundColor(.accentColor)
            }
            // Optional common configurations for Dynamic Island
            // .widgetURL(URL(string: "yourappscheme://opportunity/\(context.attributes.opportunityId)"))
            // .keylineTint(Color.accentColor)
        }
    }
}


// --- Preview Provider ---
