import Foundation
import ActivityKit

struct EventActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var eventStartTime: Date // This one is dynamic for updates
        var statusMessage: String
    }

    // Static data
    var opportunityId: String
    var opportunityName: String
    var location: String
    var eventStartTime: Date // <<< ADD THIS if missing, or ensure it's here
    var eventEndTime: Date
}
