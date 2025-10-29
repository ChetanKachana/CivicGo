import Foundation
import ActivityKit

// Must be available to both main app target and widget extension target
struct EventLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = EventStatus // Alias for clarity

    // Static data (doesn't change during the activity's lifetime)
    let eventName: String
    let eventLocation: String
    let eventStartTime: Date
    let eventEndTime: Date // NEW: Added eventEndTime
    let opportunityId: String // Unique ID to manage activity lifecycle

    // Dynamic data (can be updated during the activity, e.g., countdown emoji)
    // The widget will primarily use eventStartTime and Date() to determine the main message.
    public struct EventStatus: Codable, Hashable {
        var statusEmoji: String // Example: 🗓️, ⏳, 🔥, ✅
    }
}

