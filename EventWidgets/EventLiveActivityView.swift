import SwiftUI
import WidgetKit
import ActivityKit

// --- Main UI View for Lock Screen & Expanded Dynamic Island ---
struct EventLiveActivityView: View {
    let context: ActivityViewContext<EventActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top Row: Icon, Name, Status
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .imageScale(.medium)
                    .foregroundColor(.accentColor) // Use app's accent color
                Text(context.attributes.opportunityName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(context.state.statusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            // Bottom Row: Location
            HStack {
                 Image(systemName: "location.fill")
                     .imageScale(.small)
                     .foregroundColor(.gray)
                 Text(context.attributes.location)
                     .font(.subheadline)
                     .foregroundColor(.gray)
                     .lineLimit(1)
            }
        }
        .padding(12) // Consistent padding
    }
}
