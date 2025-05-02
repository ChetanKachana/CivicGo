import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth

// MARK: - Opportunity View Model (Using Counter for RSVP Refresh)
// Manages fetching, CUD, favoriting, RSVPing, attendance tracking, and manager removal of attendees
// for volunteering opportunities. Reacts to authentication state changes. Includes optimistic UI for RSVP
// and uses a counter to help trigger view updates for RSVP state changes.
class OpportunityViewModel: ObservableObject {

    // MARK: - Published Properties (State exposed to SwiftUI Views)

    // Core Data & State
    @Published var opportunities = [Opportunity]() { // Holds ALL fetched opportunities
         didSet { // Increment trigger whenever the main list updates from Firestore
             if oldValue != opportunities { // Basic check to avoid incrementing if identical array assigned
                 opportunityListUpdateTrigger += 1
                 print("Opportunities array updated (didSet), list trigger now \(opportunityListUpdateTrigger)")
             }
         }
    }
    @Published var errorMessage: String?                // General error messages (CUD, Fetch)
    @Published var isLoading: Bool = false                 // General loading state (fetch, CUD)
    @Published var isCurrentUserAManager: Bool = false     // Tracks if the current user has manager role

    // User-Specific Data
    @Published var favoriteOpportunityIds = Set<String>() // IDs of favorited opportunities
    @Published var rsvpedOpportunityIds = Set<String>() { // IDs of opportunities user RSVP'd to
         didSet { // Increment trigger whenever the set changes programmatically
             if oldValue != rsvpedOpportunityIds { // Only increment if value actually changed
                 rsvpStateUpdateTrigger += 1
                 print("rsvpedOpportunityIds changed (didSet), trigger now \(rsvpStateUpdateTrigger)")
             }
         }
    }

    // Action-Specific State
    @Published var isTogglingRsvp: Bool = false            // RSVP loading
    @Published var rsvpErrorMessage: String?              // RSVP errors
    @Published var isUpdatingAttendance: Bool = false      // Attendance update loading
    @Published var attendanceErrorMessage: String?        // Attendance update errors
    @Published var isRemovingAttendee: Bool = false        // Loading state for manager removing attendee
    @Published var removeAttendeeErrorMessage: String?    // Error for manager removing attendee

    // Counter to help force UI updates when RSVP or List state changes
    @Published var rsvpStateUpdateTrigger: Int = 0         // Trigger for RSVP status changes
    @Published var opportunityListUpdateTrigger: Int = 0   // Trigger for main list data changes

    // MARK: - Private Properties
    private var db = Firestore.firestore()                  // Firestore database reference
    private var opportunitiesListener: ListenerRegistration? // Listener for the opportunities collection
    private var userDataListener: ListenerRegistration?      // Combined listener for user's doc (favorites & RSVPs)
    private var authCancellables = Set<AnyCancellable>()    // Stores subscriptions to AuthenticationViewModel

    // MARK: - Initialization
    init() {
        print("OpportunityViewModel initialized.")
    }

    // MARK: - Setup & Teardown

    /// Connects this ViewModel to the AuthenticationViewModel to observe changes.
    func setupAuthObservations(authViewModel: AuthenticationViewModel) {
        print("Setting up auth observations (user session & manager status) in OpportunityViewModel")
        authCancellables.forEach { $0.cancel() }; authCancellables.removeAll() // Clear previous subs

        // Observe User Session
        authViewModel.$userSession
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                guard let self = self else { return }
                print("Auth Session change received in OppVM. User: \(user?.uid ?? "nil")")
                if user != nil { self.fetchOpportunities() } // Fetch opportunities if any user exists
                else { self.clearAllDataAndListeners() } // Clear everything on logout
                if let currentUser = user, !currentUser.isAnonymous { self.fetchUserData(userId: currentUser.uid) } // Fetch user data if logged in
                else { self.clearUserData() } // Clear user data if logged out or anonymous
            }
            .store(in: &authCancellables)

        // Observe Manager Status
        authViewModel.$isManager
            .receive(on: RunLoop.main)
            .sink { [weak self] isMgr in
                 if self?.isCurrentUserAManager != isMgr { self?.isCurrentUserAManager = isMgr; print("Manager status updated: \(isMgr)") }
            }
            .store(in: &authCancellables)
    }

    /// Cleans up Firestore listeners and Combine subscriptions.
    deinit {
        print("OpportunityViewModel deinited.")
        opportunitiesListener?.remove()
        userDataListener?.remove()
        authCancellables.forEach { $0.cancel() }
        print("OpportunityViewModel cleanup complete.")
    }

    // MARK: - Helper Methods (Internal Access)

    /// Clears local user-specific state (favorites, RSVPs) and stops the listener.
    func clearUserData() { // Default internal access
        print("Clearing user data listener and local state (Favorites, RSVPs).")
        userDataListener?.remove(); userDataListener = nil
        // Reset published sets only if they contain data to avoid redundant UI updates
        if !favoriteOpportunityIds.isEmpty { favoriteOpportunityIds = [] }
        if !rsvpedOpportunityIds.isEmpty { rsvpedOpportunityIds = [] }
        // No need to change trigger here, full clear handles it
    }

    /// Clears all data and listeners. Called on complete logout. Includes counter reset.
    func clearAllDataAndListeners() { // Default internal access
        print("Clearing all data, listeners, and resetting state in OppVM.")
        opportunitiesListener?.remove(); opportunitiesListener = nil
        userDataListener?.remove(); userDataListener = nil
        // Reset published arrays/sets
        if !opportunities.isEmpty { opportunities = [] }
        if !favoriteOpportunityIds.isEmpty { favoriteOpportunityIds = [] }
        if !rsvpedOpportunityIds.isEmpty { rsvpedOpportunityIds = [] }
        // Reset state variables
        errorMessage = nil; rsvpErrorMessage = nil; attendanceErrorMessage = nil; removeAttendeeErrorMessage = nil
        isLoading = false; isTogglingRsvp = false; isUpdatingAttendance = false; isRemovingAttendee = false
        isCurrentUserAManager = false
        rsvpStateUpdateTrigger = 0 // Reset RSVP trigger
        opportunityListUpdateTrigger = 0 // Reset List trigger
    }

    /// Enum to differentiate error types for auto-clearing. Accessible within the module.
    enum ErrorType { case general, rsvp, attendance, removeAttendee } // Default internal access

    /// Helper to auto-clear error messages after a delay. Accessible within the module.
    func clearErrorAfterDelay(_ errorType: ErrorType, duration: TimeInterval = 4.0) { // Default internal access
         DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
             guard let self = self else { return }
             switch errorType {
             case .general:        if self.errorMessage != nil { self.errorMessage = nil }
             case .rsvp:           if self.rsvpErrorMessage != nil { self.rsvpErrorMessage = nil }
             case .attendance:     if self.attendanceErrorMessage != nil { self.attendanceErrorMessage = nil }
             case .removeAttendee: if self.removeAttendeeErrorMessage != nil { self.removeAttendeeErrorMessage = nil }
             }
         }
     }

    /// Combines a Date (for day/month/year) with another Date (for time). Internal access.
    func combine(date: Date, time: Date) -> Date? { // Default internal access
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year; combinedComponents.month = dateComponents.month; combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour; combinedComponents.minute = timeComponents.minute; combinedComponents.second = timeComponents.second
        combinedComponents.timeZone = calendar.timeZone
        return calendar.date(from: combinedComponents)
    }


    // MARK: - Firestore Operations: Opportunities (Read, Create, Update, Delete)

    /// Fetches the main list of volunteering opportunities from Firestore.
    func fetchOpportunities() {
        guard Auth.auth().currentUser != nil else { print("Fetch Ops skipped."); clearAllDataAndListeners(); return }
        if opportunitiesListener == nil { isLoading = true } // Show loading only on initial fetch
        print("FETCHING Opportunities...")
        opportunitiesListener?.remove() // Ensure no duplicate listener

        let collectionRef = db.collection("volunteeringOpportunities")
        opportunitiesListener = collectionRef
            .order(by: "eventTimestamp", descending: false) // Sort by start time
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                 guard let self = self else { return }; self.isLoading = false // Stop loading indicator

                 if let error = error {
                     let nsError = error as NSError; let message = "Error Loading: \(error.localizedDescription)"
                     self.errorMessage = message; self.opportunities = [] // Clear data on error
                     if nsError.code == FirestoreErrorCode.permissionDenied.rawValue { self.errorMessage = "Permission Denied." }
                     print("!!! Firestore Read Error (\(nsError.code)): \(error.localizedDescription)"); return
                 }
                 guard let documents = querySnapshot?.documents else {
                     self.errorMessage = "Could not retrieve documents."; self.opportunities = []; print("!!! No documents found"); return
                 }

                 print(">>> Opportunity snapshot received with \(documents.count) documents.")
                 let newOpportunities = documents.compactMap { Opportunity(snapshot: $0) } // Map to local struct
                 // Check if the data actually changed before assigning to trigger didSet
                 if self.opportunities != newOpportunities {
                      self.opportunities = newOpportunities
                 } else {
                      // If data is the same, maybe just stop loading indicator without triggering didSet
                      print(">>> Opportunity snapshot data unchanged.")
                 }
                 if self.errorMessage != nil { self.errorMessage = nil } // Clear previous error on success
                 print(">>> ViewModel opportunities list updated check complete. Count: \(self.opportunities.count)")
            }
    }

    /// Adds a new opportunity to Firestore. Requires manager role. Includes attendee limit. Initializes attendanceRecords.
    func addOpportunity(name: String, location: String, description: String, eventDate: Date, endTime: Date, maxAttendeesInput: Int?) {
        guard isCurrentUserAManager else { self.errorMessage = "Permission Denied."; clearErrorAfterDelay(.general); return }
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { self.errorMessage = "Valid session required."; isLoading = false; return }
        isLoading = true; errorMessage = nil // Start loading

        // Input Validation
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else { self.errorMessage = "Name/location required."; isLoading = false; return }
        guard let combinedEndDate = combine(date: eventDate, time: endTime) else { self.errorMessage = "Error processing end time."; isLoading = false; return }
        guard combinedEndDate > eventDate else { self.errorMessage = "End time must be after start."; isLoading = false; return }

        let maxAttendeesValue = (maxAttendeesInput ?? 0) > 0 ? maxAttendeesInput : nil
        let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description." : description

        // Prepare data for Firestore
        let opportunityData: [String: Any] = [
            "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
            "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
            "creatorUserId": user.uid, "maxAttendees": maxAttendeesValue as Any, "attendeeIds": [],
            "attendanceRecords": [:] // Initialize empty attendance map
        ]
        let collectionRef = db.collection("volunteeringOpportunities")
        print("Attempting Firestore addDocument by manager \(user.uid)...")
        collectionRef.addDocument(data: opportunityData) { [weak self] error in
            print("--- addDocument Completion Handler Entered ---")
            guard let self = self else { return }; self.isLoading = false // Stop loading indicator
            if let error = error {
                let nsError = error as NSError; self.errorMessage = "Error Adding: \(error.localizedDescription)"
                print("!!! Firestore Add Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
            } else { print(">>> Opportunity added successfully!"); self.errorMessage = nil }
        }
    }

    /// Updates an existing opportunity in Firestore. Requires manager role. Includes attendee limit. Excludes attendance/attendee IDs.
    func updateOpportunity(opportunityId: String, name: String, location: String, description: String, eventDate: Date, endTime: Date, maxAttendeesInput: Int?) {
         guard isCurrentUserAManager else { self.errorMessage = "Permission Denied."; clearErrorAfterDelay(.general); return }
         guard let user = Auth.auth().currentUser, !user.isAnonymous else { self.errorMessage = "Valid session required."; isLoading = false; return }
         isLoading = true; errorMessage = nil // Start loading

         // Input Validation
         let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else { self.errorMessage = "Name/location required."; isLoading = false; return }
         guard let combinedEndDate = combine(date: eventDate, time: endTime) else { self.errorMessage = "Error processing end time."; isLoading = false; return }
         guard combinedEndDate > eventDate else { self.errorMessage = "End time must be after start."; isLoading = false; return }

         let maxAttendeesValue = (maxAttendeesInput ?? 0) > 0 ? maxAttendeesInput : nil
         let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description." : description

         // Prepare update data (excluding attendeeIds and attendanceRecords)
         let updatedData: [String: Any] = [
             "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
             "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
             "maxAttendees": maxAttendeesValue as Any
         ]
         let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
         print("Attempting to update opportunity \(opportunityId) by manager \(user.uid)...")
         docRef.updateData(updatedData) { [weak self] error in
             print("--- updateData Completion Handler Entered ---")
             guard let self = self else { return }; self.isLoading = false // Stop loading indicator
             if let error = error {
                 let nsError = error as NSError; self.errorMessage = "Error Updating: \(error.localizedDescription)"
                 print("!!! Firestore Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
             } else { print(">>> Opportunity \(opportunityId) updated successfully!"); self.errorMessage = nil }
         }
     }

    /// Deletes an opportunity from Firestore. Requires manager role.
    func deleteOpportunity(opportunityId: String) {
       guard isCurrentUserAManager else { self.errorMessage = "Permission Denied."; clearErrorAfterDelay(.general); return }
       guard let user = Auth.auth().currentUser, !user.isAnonymous else { self.errorMessage = "Valid session required."; isLoading = false; return }
       isLoading = true; errorMessage = nil // Start loading

       let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
       print("Attempting to delete opportunity \(opportunityId) by manager \(user.uid)...")
       docRef.delete { [weak self] error in
           print("--- delete Completion Handler Entered ---")
           guard let self = self else { return }; self.isLoading = false // Stop loading indicator
           if let error = error {
                let nsError = error as NSError; self.errorMessage = "Error Deleting: \(error.localizedDescription)"
                print("!!! Firestore Delete Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
           } else { print(">>> Opportunity \(opportunityId) deleted successfully."); self.errorMessage = nil }
       }
    }

    // MARK: - User Data Logic (Favorites & RSVPs)

    /// Fetches user-specific data (Favorites and RSVPs) and sets up ONE listener. Increments trigger on RSVP change.
    func fetchUserData(userId: String) {
        print("Fetching user data (Favorites & RSVPs) for: \(userId)")
        userDataListener?.remove() // Remove previous listener

        let userDocRef = db.collection("users").document(userId)
        // Use includeMetadataChanges: false to potentially reduce extra triggers
        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] (documentSnapshot, error) in
            guard let self = self else { return }

            let logTimestamp = Date().timeIntervalSince1970; print("[\(logTimestamp)] USER DATA LISTENER TRIGGERED for \(userId)")
            var latestFavIds = Set<String>()
            var latestRsvpIds = Set<String>()

            if let error = error { print("[\(logTimestamp)] !!! Listener Error: \(error)"); return }
            guard let document = documentSnapshot else { print("[\(logTimestamp)] documentSnapshot nil."); return }
            // let source = document.metadata.hasPendingWrites ? "Local" : "Server"; print("[\(logTimestamp)] Snap Meta: Src=\(source), Pending=\(document.metadata.hasPendingWrites), Exists=\(document.exists)")

            if document.exists, let data = document.data() {
                latestFavIds = Set(data["favoriteOpportunityIds"] as? [String] ?? [])
                latestRsvpIds = Set(data["rsvpedOpportunityIds"] as? [String] ?? [])
                // print("[\(logTimestamp)] Parsed Favs(\(latestFavIds.count)) | Parsed RSVPs(\(latestRsvpIds.count))")
            } else { print("[\(logTimestamp)] Doc missing/nil.") }

            let favsChanged = self.favoriteOpportunityIds != latestFavIds
            let rsvpsChanged = self.rsvpedOpportunityIds != latestRsvpIds // Compare BEFORE assigning
            // print("[\(logTimestamp)] Comparison: Favs Changed=\(favsChanged), RSVPs Changed=\(rsvpsChanged)")

            if favsChanged { self.favoriteOpportunityIds = latestFavIds; /* print("[\(logTimestamp)] ---> Favs Updated.") */ }
            if rsvpsChanged {
                self.rsvpedOpportunityIds = latestRsvpIds // Update the published set (triggers didSet)
                // Note: didSet on rsvpedOpportunityIds now handles incrementing rsvpStateUpdateTrigger
                print("[\(logTimestamp)] ---> RSVPs Set Updated via Listener.")
            }
            // print("[\(logTimestamp)] Listener Processed. Final VM RSVPs count: \(self.rsvpedOpportunityIds.count)")
            // print("[\(logTimestamp)] ==============================================")
        }
    }


    /// Checks if the current user has favorited a specific opportunity.
    func isFavorite(opportunityId: String?) -> Bool {
         guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
         return favoriteOpportunityIds.contains(id)
     }

    /// Toggles the favorite status of an opportunity for the current user.
    func toggleFavorite(opportunity: Opportunity) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { self.errorMessage = "Log in to save favorites."; clearErrorAfterDelay(.general); return }
        let userId = user.uid; let opportunityId = opportunity.id; let isCurrentlyFavorite = self.favoriteOpportunityIds.contains(opportunityId)
        // Optimistic UI Update
        var optimisticFavIds = self.favoriteOpportunityIds
        if isCurrentlyFavorite { optimisticFavIds.remove(opportunityId) } else { optimisticFavIds.insert(opportunityId) }
        self.favoriteOpportunityIds = optimisticFavIds
        // Firestore Update
        let userDocRef = db.collection("users").document(userId); let updateValue = isCurrentlyFavorite ? FieldValue.arrayRemove([opportunityId]) : FieldValue.arrayUnion([opportunityId])
        userDocRef.setData(["favoriteOpportunityIds": updateValue], merge: true) { [weak self] error in
            guard let self = self else { return }
            if let error = error { // Failure
                print("!!! Error updating favorites: \(error)"); self.errorMessage = "Failed to update favorite."
                var revertedFavIds = self.favoriteOpportunityIds // Revert UI
                if isCurrentlyFavorite { revertedFavIds.insert(opportunityId) } else { revertedFavIds.remove(opportunityId) }
                self.favoriteOpportunityIds = revertedFavIds; self.clearErrorAfterDelay(.general)
            } else { print("Favorites updated successfully."); self.errorMessage = nil } // Success
        }
    }

    /// Checks if the current user has RSVP'd to a specific opportunity.
    func isRsvped(opportunityId: String?) -> Bool {
        guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
        return rsvpedOpportunityIds.contains(id)
    }

    /// Toggles the RSVP status for the current user. Includes Optimistic UI and Revert on Failure.
    /// Uses counter trigger via didSet on rsvpedOpportunityIds.
    func toggleRSVP(opportunity: Opportunity) {
        // 1. Checks
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { self.rsvpErrorMessage = "Log in to RSVP."; clearErrorAfterDelay(.rsvp); return }
        guard !opportunity.hasEnded else { self.rsvpErrorMessage = "Event ended."; clearErrorAfterDelay(.rsvp); return }
        let userId = user.uid; let opportunityId = opportunity.id
        let isCurrentlyRsvped = self.rsvpedOpportunityIds.contains(opportunityId) // Check state BEFORE optimistic update
        if !isCurrentlyRsvped && opportunity.isFull { self.rsvpErrorMessage = "Event is full."; clearErrorAfterDelay(.rsvp); return }

        // 2. OPTIMISTIC UI UPDATE (Assigning New Set)
        // objectWillChange.send() // Not needed if using didSet on @Published var
        var updatedSet = self.rsvpedOpportunityIds // Create mutable copy
        if isCurrentlyRsvped { updatedSet.remove(opportunityId); print("Optimistic UI: Removing RSVP ID \(opportunityId)") }
        else { updatedSet.insert(opportunityId); print("Optimistic UI: Inserting RSVP ID \(opportunityId)") }
        self.rsvpedOpportunityIds = updatedSet // Assign new set back - triggers didSet which increments counter

        // 3. Start UI Loading State
        isTogglingRsvp = true; rsvpErrorMessage = nil

        // 4. Prepare Batch Write (Based on state BEFORE optimistic update)
        let batch = db.batch()
        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let userDocRef = db.collection("users").document(userId)
        if isCurrentlyRsvped { // Prepare REMOVE batch
            print("Preparing REMOVE RSVP (Batch)...")
            batch.updateData(["attendeeIds": FieldValue.arrayRemove([userId])], forDocument: oppDocRef)
            batch.setData(["rsvpedOpportunityIds": FieldValue.arrayRemove([opportunityId])], forDocument: userDocRef, merge: true)
        } else { // Prepare ADD batch
             print("Preparing ADD RSVP (Batch)...")
            batch.updateData(["attendeeIds": FieldValue.arrayUnion([userId])], forDocument: oppDocRef)
            batch.setData(["rsvpedOpportunityIds": FieldValue.arrayUnion([opportunityId])], forDocument: userDocRef, merge: true)
        }

        // 5. Commit the Batch
        print("Committing RSVP batch write. UserID: \(userId), OpportunityID: \(opportunityId)")
        batch.commit { [weak self] error in
            guard let self = self else { return }; self.isTogglingRsvp = false // Stop loading

            if let error = error { // --- FAILURE ---
                let nsError = error as NSError
                print("!!! BATCH COMMIT FAILED !!! Error: \(error.localizedDescription) Code: \(nsError.code)")
                self.rsvpErrorMessage = "Failed to update RSVP status."; self.clearErrorAfterDelay(.rsvp)

                // --- REVERT OPTIMISTIC UPDATE ON FAILURE ---
                print("Reverting optimistic RSVP update due to Firestore error.")
                // objectWillChange.send() // Notify before reverting - handled by didSet
                var revertedSet = self.rsvpedOpportunityIds // Get current (wrong) state
                if isCurrentlyRsvped { // If remove failed, add ID back locally
                    print("Revert: Inserting RSVP ID \(opportunityId) back")
                    revertedSet.insert(opportunityId)
                } else { // If add failed, remove ID locally
                    print("Revert: Removing RSVP ID \(opportunityId) back")
                    revertedSet.remove(opportunityId)
                }
                self.rsvpedOpportunityIds = revertedSet // Assign reverted set (triggers didSet again)
                print("Reverted state. Final local count: \(self.rsvpedOpportunityIds.count)")
                // --- End Revert ---

            } else { // --- SUCCESS ---
                print(">>> BATCH COMMIT SUCCEEDED <<<"); self.rsvpErrorMessage = nil
                // Optimistic update matches server. Listener confirmation might follow.
                // Counter already incremented by optimistic update.
            }
            // Removed Force Refresh
        } // End Commit Completion Handler
    } // End toggleRSVP


    // MARK: - Attendance Logic

    /// Records attendance for a specific attendee. Requires manager role.
    func recordAttendance(opportunityId: String, attendeeId: String, status: String?) {
        print("--- recordAttendance called - Opp: \(opportunityId), Att: \(attendeeId), Status: \(status ?? "nil")")
        guard isCurrentUserAManager else { self.attendanceErrorMessage = "Permission Denied."; clearErrorAfterDelay(.attendance); return }
        guard Auth.auth().currentUser != nil else { self.attendanceErrorMessage = "Valid session required."; return }
        isUpdatingAttendance = true; attendanceErrorMessage = nil // Start loading

        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let fieldPath = "attendanceRecords.\(attendeeId)" // Dot notation path
        let updatePayload: [String: Any] = [fieldPath: status != nil ? status! : FieldValue.delete()] // Use status or delete()

        print("Attempting attendance update: \(updatePayload)")
        oppDocRef.updateData(updatePayload) { [weak self] error in // Perform update
            guard let self = self else { return }; self.isUpdatingAttendance = false // Stop loading
            if let error = error {
                let nsError = error as NSError; self.attendanceErrorMessage = "Error updating attendance."
                 print("!!! Attendance Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.attendance)
            } else { print(">>> Attendance recorded successfully."); self.attendanceErrorMessage = nil }
        }
    }

    // MARK: - Manager Remove Attendee Logic

    /// Allows a manager to remove a specific attendee from an event via Batch Write.
    func managerRemoveAttendee(opportunityId: String, attendeeIdToRemove: String) {
        print("--- managerRemoveAttendee called - Opp: \(opportunityId), Attendee: \(attendeeIdToRemove)")
        guard isCurrentUserAManager else { self.removeAttendeeErrorMessage = "Permission Denied."; clearErrorAfterDelay(.removeAttendee); return }
        guard Auth.auth().currentUser != nil else { self.removeAttendeeErrorMessage = "Valid session required."; return }
        isRemovingAttendee = true; removeAttendeeErrorMessage = nil // Start loading

        let batch = db.batch()
        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let userDocRef = db.collection("users").document(attendeeIdToRemove)
        let attendanceFieldPath = "attendanceRecords.\(attendeeIdToRemove)"

        print("Preparing batch to remove attendee \(attendeeIdToRemove)...")
        batch.updateData(["attendeeIds": FieldValue.arrayRemove([attendeeIdToRemove])], forDocument: oppDocRef) // Action 1
        batch.setData(["rsvpedOpportunityIds": FieldValue.arrayRemove([opportunityId])], forDocument: userDocRef, merge: true) // Action 2
        batch.updateData([attendanceFieldPath: FieldValue.delete()], forDocument: oppDocRef) // Action 3

        // Commit Batch
        batch.commit { [weak self] error in
             guard let self = self else { return }; self.isRemovingAttendee = false // Stop loading indicator
             if let error = error {
                 let nsError = error as NSError; print("!!! MANAGER REMOVE ATTENDEE BATCH FAILED !!! Error: \(error) Code: \(nsError.code)")
                 self.removeAttendeeErrorMessage = "Failed to remove attendee."; self.clearErrorAfterDelay(.removeAttendee)
             } else { print(">>> MANAGER REMOVE ATTENDEE BATCH SUCCEEDED <<<"); self.removeAttendeeErrorMessage = nil } // Clear error on success
             // Listener updates should handle UI refresh.
         }
    }

} // End Class OpportunityViewModel


// MARK: - Helper Extensions
