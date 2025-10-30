import Foundation
import FirebaseFirestore

struct Opportunity: Identifiable, Equatable, Hashable {

    let id: String
    var name: String
    var location: String
    var description: String
    var eventTimestamp: Timestamp
    var endTimestamp: Timestamp
    var creatorUserId: String?
    var organizerUsername: String?

    var maxAttendees: Int?
    var attendeeIds: [String]

    var attendanceRecords: [String: String]?


    var eventDate: Date { eventTimestamp.dateValue() }
    var endDate: Date { endTimestamp.dateValue() }
    var endTime: Date {
        endTimestamp.dateValue()
    }

    var attendeeCount: Int { attendeeIds.count }

    var isFull: Bool {
        guard let max = maxAttendees, max > 0 else {
            return false
        }
        return attendeeCount >= max
    }

    var hasEnded: Bool {
        endDate < Date()
    }

    var isCurrentlyOccurring: Bool {
        let now = Date()
        return eventDate <= now && now < endDate
    }

    var durationHours: Double? {
        let durationSeconds = endDate.timeIntervalSince(eventDate)
        guard durationSeconds >= 0 else { return nil }
        return durationSeconds / 3600.0
    }

    public init(id: String, name: String, location: String, description: String, eventTimestamp: Timestamp, endTimestamp: Timestamp, creatorUserId: String? = nil, organizerUsername: String? = nil, maxAttendees: Int? = nil, attendeeIds: [String] = [], attendanceRecords: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.location = location
        self.description = description
        self.eventTimestamp = eventTimestamp
        self.endTimestamp = endTimestamp
        self.creatorUserId = creatorUserId
        self.organizerUsername = organizerUsername
        self.maxAttendees = maxAttendees
        self.attendeeIds = attendeeIds
        self.attendanceRecords = attendanceRecords
    }

    init?(snapshot: DocumentSnapshot) {
        guard let data = snapshot.data() else {
            print("--- FAILED init: Snapshot data was nil for doc \(snapshot.documentID)")
            return nil
        }

        guard let name = data["name"] as? String, !name.isEmpty,
              let location = data["location"] as? String, !location.isEmpty,
              let description = data["description"] as? String,
              let eventTimestamp = data["eventTimestamp"] as? Timestamp,
              let endTimestamp = data["endTimestamp"] as? Timestamp
        else {
            print("--- FAILED init: Missing or invalid required field(s) for doc: \(snapshot.documentID)")
            return nil
        }
        guard endTimestamp.dateValue() > eventTimestamp.dateValue() else {
             print("--- FAILED init: endTimestamp must be after eventTimestamp for doc: \(snapshot.documentID)")
             return nil
        }

        self.id = snapshot.documentID
        self.name = name
        self.location = location
        self.description = description
        self.eventTimestamp = eventTimestamp
        self.endTimestamp = endTimestamp

        self.creatorUserId = data["creatorUserId"] as? String
        self.organizerUsername = data["organizerUsername"] as? String
        self.maxAttendees = data["maxAttendees"] as? Int
        self.attendeeIds = data["attendeeIds"] as? [String] ?? []
        self.attendanceRecords = data["attendanceRecords"] as? [String: String]
    }

    static func == (lhs: Opportunity, rhs: Opportunity) -> Bool {
        if lhs.id != rhs.id { return false }
        if lhs.attendeeIds != rhs.attendeeIds { return false }
        if lhs.maxAttendees != rhs.maxAttendees { return false }
        if lhs.name != rhs.name { return false }
        if lhs.location != rhs.location { return false }
        if lhs.description != rhs.description { return false }
        if lhs.eventTimestamp != rhs.eventTimestamp { return false }
        if lhs.endTimestamp != rhs.endTimestamp { return false }

        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }


    #if DEBUG
   
    static var previewInstance: Opportunity {
         let start = Date().addingTimeInterval(3600 * 24)
         let end = start.addingTimeInterval(3600 * 2)
         return Opportunity(id: "previewStatic", name: "Preview Event (Future)", location: "123 Preview Lane", description: "A description for the preview event.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 10, attendeeIds: ["user1", "user2"], attendanceRecords: ["user1": "present"])
    }
    static var previewInstanceFull: Opportunity {
        let start = Date().addingTimeInterval(3600 * 48)
        let end = start.addingTimeInterval(3600 * 1)
         return Opportunity(id: "previewFull", name: "Park Cleanup (Full)", location: "Central Park", description: "Help us clean up the main park area. Gloves provided.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager2", organizerUsername: "Mgr Two", maxAttendees: 1, attendeeIds: ["user1"])
    }
     static var previewInstanceEnded: Opportunity {
         let start = Date().addingTimeInterval(-3600 * 26)
         let end = start.addingTimeInterval(3600 * 2)
         return Opportunity(id: "previewEnded", name: "Soup Kitchen Service (Past)", location: "Downtown Shelter", description: "Served meals yesterday.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 10, attendeeIds: ["userA", "userB"], attendanceRecords: ["userA": "present", "userB": "absent"])
    }
     static var previewInstanceUnlimited: Opportunity {
          let start = Date().addingTimeInterval(3600 * 72)
          let end = start.addingTimeInterval(3600 * 4)
          return Opportunity(id: "previewUnlimited", name: "Community Garden Day", location: "Green Thumb Gardens", description: "Come help plant vegetables! All welcome.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager3", organizerUsername: "Manager Three", maxAttendees: nil)
     }
     static var previewInstanceOccurring: Opportunity {
          let start = Date().addingTimeInterval(-3600 * 1)
          let end = start.addingTimeInterval(3600 * 3)
          return Opportunity(id: "previewOccurring", name: "Library Book Sorting (Now!)", location: "Main Library - 2nd Floor", description: "Help sort donated books. Drop in anytime!", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 5, attendeeIds: ["userA", "userB", "userC"], attendanceRecords: ["userA": "present"])
     }
    #endif
}
