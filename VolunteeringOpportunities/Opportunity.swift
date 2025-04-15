import Foundation
import FirebaseFirestore

struct Opportunity: Identifiable {
    let id: String
    var name: String
    var location: String
    var description: String
    var eventTimestamp: Timestamp // Start Time
    var endTimestamp: Timestamp   // End Time <-- ADDED

    // Computed properties for Date access
    var eventDate: Date {
        eventTimestamp.dateValue()
    }
    var endDate: Date { // <-- ADDED
        endTimestamp.dateValue()
    }

    // --- Manual Mapping ---

    init?(snapshot: DocumentSnapshot) {
        print("--- Attempting to init Opportunity for doc: \(snapshot.documentID)")
        guard let data = snapshot.data() else {
            print("--- FAILED init: Snapshot data was nil for doc \(snapshot.documentID)")
            return nil
        }
        print("--- Data for \(snapshot.documentID): \(data)")
        print("--- Checking 'name' type: \(type(of: data["name"]))")
        print("--- Checking 'location' type: \(type(of: data["location"]))")
        print("--- Checking 'description' type: \(type(of: data["description"]))")
        print("--- Checking 'eventTimestamp' type: \(type(of: data["eventTimestamp"]))")
        print("--- Checking 'endTimestamp' type: \(type(of: data["endTimestamp"]))") // <-- ADDED Check

        guard let name = data["name"] as? String else {
            print("--- FAILED init: Could not parse 'name'. Value: \(String(describing: data["name"])). Is it missing or not a String?")
            return nil
        }
        guard let location = data["location"] as? String else {
            print("--- FAILED init: Could not parse 'location'. Value: \(String(describing: data["location"])). Is it missing or not a String?")
            return nil
        }
        guard let description = data["description"] as? String else {
            print("--- FAILED init: Could not parse 'description'. Value: \(String(describing: data["description"])). Is it missing or not a String?")
            return nil
        }
        guard let eventTimestamp = data["eventTimestamp"] as? Timestamp else {
            print("--- FAILED init: Could not parse 'eventTimestamp'. Value: \(String(describing: data["eventTimestamp"])). Is it missing or not a Firestore Timestamp?")
            return nil
        }
        // --- ADDED Parsing for endTimestamp ---
        guard let endTimestamp = data["endTimestamp"] as? Timestamp else {
             print("--- FAILED init: Could not parse 'endTimestamp'. Value: \(String(describing: data["endTimestamp"])). Is it missing or not a Firestore Timestamp?")
             return nil
        }
        // --- End Added Parsing ---

        print("--- SUCCESS init: Parsed all fields for doc: \(snapshot.documentID)")
        self.id = snapshot.documentID
        self.name = name
        self.location = location
        self.description = description
        self.eventTimestamp = eventTimestamp
        self.endTimestamp = endTimestamp // <-- ASSIGN
    }

    // --- Method to convert back to dictionary ---
    func toDictionary() -> [String: Any] {
        return [
            "name": name,
            "location": location,
            "description": description,
            "eventTimestamp": eventTimestamp,
            "endTimestamp": endTimestamp // <-- ADDED Field
        ]
    }
}
