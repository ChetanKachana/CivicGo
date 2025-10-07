import Foundation
import FirebaseFirestore

// MARK: - Opportunity Model (Equatable & Hashable Conformance)
// Represents a volunteering opportunity with details, timing, RSVP, and attendance info.
struct Opportunity: Identifiable, Equatable, Hashable { // Conforms to Identifiable, Equatable, and Hashable

    // MARK: - Stored Properties
    let id: String                  // Unique Document ID from Firestore
    var name: String                // Name of the event
    var location: String            // Location description/address
    var description: String         // Detailed description of the event
    var eventTimestamp: Timestamp   // Start Date & Time (Firestore Timestamp)
    var endTimestamp: Timestamp     // End Date & Time (Firestore Timestamp)
    var creatorUserId: String?      // UID of the manager who created the event (Optional for older data)
    var organizerUsername: String?  // Organizer's username at time of creation (Optional)

    // RSVP Fields
    var maxAttendees: Int?          // Optional max attendees (nil or <= 0 means unlimited)
    var attendeeIds: [String]       // Array of UIDs for users who RSVP'd

    // Attendance Tracking
    var attendanceRecords: [String: String]? // Optional dictionary [AttendeeUID: "present"/"absent"]


    // MARK: - Computed Properties

    /// Returns the start timestamp as a Swift Date object.
    var eventDate: Date { eventTimestamp.dateValue() }
    /// Returns the end timestamp as a Swift Date object.
    var endDate: Date { endTimestamp.dateValue() }

    /// Returns the current number of attendees who have RSVP'd.
    var attendeeCount: Int { attendeeIds.count }

    /// Returns `true` if the event has reached its maximum attendee limit.
    var isFull: Bool {
        // If maxAttendees is not set (nil) or is zero/negative, it's unlimited.
        guard let max = maxAttendees, max > 0 else {
            return false // Not full if unlimited
        }
        // Otherwise, check if the current count meets or exceeds the maximum.
        return attendeeCount >= max
    }

    /// Returns `true` if the event's end time is in the past.
    var hasEnded: Bool {
        endDate < Date()
    }

    /// Returns `true` if the current time is between the event's start and end times.
    var isCurrentlyOccurring: Bool {
        let now = Date()
        return eventDate <= now && now < endDate // Start is inclusive, end is exclusive
    }

    /// Calculates the duration of the event in hours (Double).
    /// Returns nil if end date is somehow before start date (shouldn't happen with validation).
    var durationHours: Double? {
        let durationSeconds = endDate.timeIntervalSince(eventDate)
        guard durationSeconds >= 0 else { return nil } // Safety check
        return durationSeconds / 3600.0 // Convert seconds to hours
    }


    // MARK: - Initializer

    /// Failable Initializer to create an Opportunity from a Firestore DocumentSnapshot.
    init?(snapshot: DocumentSnapshot) {
        guard let data = snapshot.data() else {
            print("--- FAILED init: Snapshot data was nil for doc \(snapshot.documentID)")
            return nil
        }

        // --- Required field parsing ---
        guard let name = data["name"] as? String, !name.isEmpty,
              let location = data["location"] as? String, !location.isEmpty,
              let description = data["description"] as? String, // Description can be empty
              let eventTimestamp = data["eventTimestamp"] as? Timestamp,
              let endTimestamp = data["endTimestamp"] as? Timestamp
        else {
            print("--- FAILED init: Missing or invalid required field(s) for doc: \(snapshot.documentID)")
            return nil
        }
        // --- Additional Validation ---
        guard endTimestamp.dateValue() > eventTimestamp.dateValue() else {
             print("--- FAILED init: endTimestamp must be after eventTimestamp for doc: \(snapshot.documentID)")
             return nil
        }

        // --- Assign properties ---
        self.id = snapshot.documentID
        self.name = name
        self.location = location
        self.description = description
        self.eventTimestamp = eventTimestamp
        self.endTimestamp = endTimestamp

        // Optional/Defaulted fields
        self.creatorUserId = data["creatorUserId"] as? String
        self.organizerUsername = data["organizerUsername"] as? String
        self.maxAttendees = data["maxAttendees"] as? Int
        self.attendeeIds = data["attendeeIds"] as? [String] ?? [] // Default to empty array
        self.attendanceRecords = data["attendanceRecords"] as? [String: String] // Keep optional
    }

    // MARK: - Equatable Conformance (Compares content relevant to UI updates)
    static func == (lhs: Opportunity, rhs: Opportunity) -> Bool {
        // Check ID first for quick exit
        if lhs.id != rhs.id { return false }
        // Check fields critical for UI updates in lists/rows
        if lhs.attendeeIds != rhs.attendeeIds { return false } // Detects RSVP/attendee count changes
        if lhs.maxAttendees != rhs.maxAttendees { return false } // Detects capacity changes
        if lhs.name != rhs.name { return false } // If name is editable/displayed prominently
        if lhs.location != rhs.location { return false } // If location is displayed/editable
        if lhs.description != rhs.description { return false } // If description is displayed/editable
        if lhs.eventTimestamp != rhs.eventTimestamp { return false } // Detects time changes
        if lhs.endTimestamp != rhs.endTimestamp { return false } // Detects time changes
        // Check other fields like organizerUsername, creatorUserId if they affect display directly
        // if lhs.organizerUsername != rhs.organizerUsername { return false }
        // if lhs.attendanceRecords != rhs.attendanceRecords { return false } // Can be complex to compare dictionaries

        // If all relevant checks pass, they are considered equal for UI diffing.
        return true
    }

    // MARK: - Hashable Conformance (Based on unique ID)
    func hash(into hasher: inout Hasher) {
        // Hashing the unique identifier `id` is standard practice and sufficient
        // for Set storage and Dictionary keys when combined with the Equatable check.
        hasher.combine(id)
    }


    // MARK: - Debug/Preview Initializer & Data
    #if DEBUG
    /// Internal initializer used only for creating instances during testing or previews.
    internal init(id: String, name: String, location: String, description: String, eventTimestamp: Timestamp, endTimestamp: Timestamp, creatorUserId: String? = nil, organizerUsername: String? = nil, maxAttendees: Int? = nil, attendeeIds: [String] = [], attendanceRecords: [String: String]? = nil) {
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

    // Static preview instances using the internal initializer
    static var previewInstance: Opportunity {
         let start = Date().addingTimeInterval(3600 * 24) // Start tomorrow
         let end = start.addingTimeInterval(3600 * 2) // End 2 hours after start
         return Opportunity(id: "previewStatic", name: "Preview Event (Future)", location: "123 Preview Lane", description: "A description for the preview event.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 10, attendeeIds: ["user1", "user2"], attendanceRecords: ["user1": "present"])
    }
    static var previewInstanceFull: Opportunity { // Example for a full event
        let start = Date().addingTimeInterval(3600 * 48) // Start day after tomorrow
        let end = start.addingTimeInterval(3600 * 1) // 1 hour duration
         return Opportunity(id: "previewFull", name: "Park Cleanup (Full)", location: "Central Park", description: "Help us clean up the main park area. Gloves provided.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager2", organizerUsername: "Mgr Two", maxAttendees: 1, attendeeIds: ["user1"])
    }
     static var previewInstanceEnded: Opportunity { // Example for an ended event
         let start = Date().addingTimeInterval(-3600 * 26) // Started yesterday
         let end = start.addingTimeInterval(3600 * 2) // Ended yesterday
         return Opportunity(id: "previewEnded", name: "Soup Kitchen Service (Past)", location: "Downtown Shelter", description: "Served meals yesterday.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 10, attendeeIds: ["userA", "userB"], attendanceRecords: ["userA": "present", "userB": "absent"])
    }
     static var previewInstanceUnlimited: Opportunity { // Example for unlimited spots
          let start = Date().addingTimeInterval(3600 * 72) // Start in 3 days
          let end = start.addingTimeInterval(3600 * 4) // 4 hour duration
          return Opportunity(id: "previewUnlimited", name: "Community Garden Day", location: "Green Thumb Gardens", description: "Come help plant vegetables! All welcome.", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager3", organizerUsername: "Manager Three", maxAttendees: nil) // nil maxAttendees
     }
     static var previewInstanceOccurring: Opportunity { // Example for currently occurring event
          let start = Date().addingTimeInterval(-3600 * 1) // Started 1 hour ago
          let end = start.addingTimeInterval(3600 * 3) // Ends in 2 hours
          return Opportunity(id: "previewOccurring", name: "Library Book Sorting (Now!)", location: "Main Library - 2nd Floor", description: "Help sort donated books. Drop in anytime!", eventTimestamp: Timestamp(date: start), endTimestamp: Timestamp(date: end), creatorUserId: "manager1", organizerUsername: "Manager One", maxAttendees: 5, attendeeIds: ["userA", "userB", "userC"], attendanceRecords: ["userA": "present"])
     }
    #endif
} // End struct Opportunity
