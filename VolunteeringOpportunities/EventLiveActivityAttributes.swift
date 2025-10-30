import Foundation
import ActivityKit

struct EventLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = EventStatus

    let eventName: String
    let eventLocation: String
    let eventStartTime: Date
    let eventEndTime: Date
    let opportunityId: String

    public struct EventStatus: Codable, Hashable {
        var statusEmoji: String
    }
}
