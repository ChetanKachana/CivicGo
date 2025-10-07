import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth

struct ManagerInfo: Identifiable, Hashable { // Ensure it conforms to required protocols
    let id: String // User ID
    let username: String
    let logoImageURL: String? // Optional logo for display in row
}
// MARK: - Opportunity View Model (Callbacks for CUD)
// Manages fetching, CUD, favoriting, RSVPing, attendance tracking, and manager removal of attendees
// for volunteering opportunities. Reacts to authentication state changes. Includes optimistic UI for RSVP.
// Uses completion handlers for add/update operations to signal success/failure to the view.
@MainActor // Ensures UI updates published by this VM happen on the main thread
class OpportunityViewModel: ObservableObject {

    // MARK: - Published Properties (State exposed to SwiftUI Views)

    // Core Data & State
    @Published var opportunities = [Opportunity]()         // Holds ALL fetched opportunities
    @Published var errorMessage: String?                // General error messages (CUD, Fetch)
    @Published var isLoading: Bool = false                 // General loading state (fetch, CUD)
    @Published var isCurrentUserAManager: Bool = false     // Tracks if the current user has manager role

    // Manager Data (Added for search)
    @Published var managers = [ManagerInfo]() // Holds fetched manager profiles
    @Published var isLoadingManagers: Bool = false // Specific loading for managers

    // User-Specific Data
    @Published var favoriteOpportunityIds = Set<String>() // IDs of favorited opportunities
    @Published var rsvpedOpportunityIds = Set<String>()   // IDs of opportunities user RSVP'd to (Updated optimistically)

    // Action-Specific State
    @Published var isTogglingRsvp: Bool = false            // RSVP loading
    @Published var rsvpErrorMessage: String?              // RSVP errors
    @Published var isUpdatingAttendance: Bool = false      // Attendance update loading
    @Published var attendanceErrorMessage: String?        // Attendance update errors
    @Published var isRemovingAttendee: Bool = false        // Loading state for manager removing attendee
    @Published var removeAttendeeErrorMessage: String?    // Error for manager removing attendee

    // --- Trigger Removed ---

    // MARK: - Private Properties
    private lazy var db = Firestore.firestore()             // Lazy initialization
    private var opportunitiesListener: ListenerRegistration? // Listener for the opportunities collection
    private var userDataListener: ListenerRegistration?      // Combined listener for user's doc (favorites & RSVPs)
    private var managersListener: ListenerRegistration?      // Listener for managers
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
            .receive(on: RunLoop.main) // Ensures sink block runs on main thread queue
            .sink { [weak self] user in // Keep weak self
                guard let self = self else { return } // Check for self
                print("Auth Session change received in OppVM. User: \(user?.uid ?? "nil")")

                // Use Task to safely call potentially MainActor-isolated methods
                Task {
                    if let currentUser = user {
                        // User logged in (or changed) - Fetch/Refetch data
                        await self.fetchOpportunities() // Fetch general opportunities
                        await self.fetchManagers()     // Fetch managers
                        if !currentUser.isAnonymous {
                            // Fetch user-specific data if not anonymous
                            self.fetchUserData(userId: currentUser.uid) // fetchUserData is not async, call directly
                        } else {
                             // Clear specific user data if user is anonymous
                             await self.clearUserData() // Ensure clearUserData is MainActor safe
                        }
                    } else {
                        // User logged out - Clear everything
                        await self.clearAllDataAndListeners() // Ensure clearAll is MainActor safe
                    }
                }
            }
            .store(in: &authCancellables)

        // Observe Manager Status
        authViewModel.$isManager
            .receive(on: RunLoop.main)
            .sink { [weak self] isMgr in
                 // Avoid redundant state updates if value hasn't changed
                 if self?.isCurrentUserAManager != isMgr {
                     self?.isCurrentUserAManager = isMgr
                     print("Manager status updated: \(isMgr)")
                 }
            }
            .store(in: &authCancellables)
    }

    /// Cleans up Firestore listeners and Combine subscriptions.
    deinit {
        print("OpportunityViewModel deinited.")
        opportunitiesListener?.remove()
        userDataListener?.remove()
        managersListener?.remove() // Remove managers listener
        authCancellables.forEach { $0.cancel() }
        print("OpportunityViewModel cleanup complete.")
    }

    // MARK: - Helper Methods (Internal Access)

    /// Clears local user-specific state (favorites, RSVPs) and stops the listener.
    @MainActor
    func clearUserData() {
        print("Clearing user data listener and local state (Favorites, RSVPs).")
        userDataListener?.remove(); userDataListener = nil
        if !favoriteOpportunityIds.isEmpty { favoriteOpportunityIds = [] }
        if !rsvpedOpportunityIds.isEmpty { rsvpedOpportunityIds = [] }
    }

    /// Clears all data and listeners. Called on complete logout.
    @MainActor
    func clearAllDataAndListeners() {
        print("Clearing all data, listeners, and resetting state in OppVM.")
        opportunitiesListener?.remove(); opportunitiesListener = nil
        userDataListener?.remove(); userDataListener = nil
        managersListener?.remove(); managersListener = nil
        if !opportunities.isEmpty { opportunities = [] }
        if !managers.isEmpty { managers = [] }
        if !favoriteOpportunityIds.isEmpty { favoriteOpportunityIds = [] }
        if !rsvpedOpportunityIds.isEmpty { rsvpedOpportunityIds = [] }
        errorMessage = nil; rsvpErrorMessage = nil; attendanceErrorMessage = nil; removeAttendeeErrorMessage = nil
        isLoading = false; isLoadingManagers = false;
        isTogglingRsvp = false; isUpdatingAttendance = false; isRemovingAttendee = false
        isCurrentUserAManager = false
        // Trigger Removed
    }

    /// Enum to differentiate error types for auto-clearing.
    enum ErrorType { case general, rsvp, attendance, removeAttendee }

    /// Helper to auto-clear error messages after a delay.
    func clearErrorAfterDelay(_ errorType: ErrorType, duration: TimeInterval = 4.0) {
         // Ensure this runs on the main thread as it modifies @Published vars
         DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
             guard let self = self else { return }
             Task { @MainActor in // Explicitly ensure modification on main actor
                 switch errorType {
                 case .general:        if self.errorMessage != nil { self.errorMessage = nil }
                 case .rsvp:           if self.rsvpErrorMessage != nil { self.rsvpErrorMessage = nil }
                 case .attendance:     if self.attendanceErrorMessage != nil { self.attendanceErrorMessage = nil }
                 case .removeAttendee: if self.removeAttendeeErrorMessage != nil { self.removeAttendeeErrorMessage = nil }
                 }
             }
         }
     }

    /// Combines a Date (for day/month/year) with another Date (for time).
    func combine(date: Date, time: Date) -> Date? {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year; combinedComponents.month = dateComponents.month; combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour; combinedComponents.minute = timeComponents.minute; combinedComponents.second = timeComponents.second
        combinedComponents.timeZone = calendar.timeZone // Use the system's current time zone
        return calendar.date(from: combinedComponents)
    }

    // --- Force Reload Function Removed (Relying on listeners/Equatable) ---


    // MARK: - Firestore Operations: Opportunities (Read, Create, Update, Delete)

    /// Fetches the main list of volunteering opportunities from Firestore.
    @MainActor
    func fetchOpportunities() {
        if opportunitiesListener != nil { print("Fetch Ops check: Listener already exists."); return }
        if !isLoading { isLoading = true }
        print("FETCHING Opportunities...")

        let collectionRef = db.collection("volunteeringOpportunities")
        opportunitiesListener = collectionRef
            .order(by: "eventTimestamp", descending: false)
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                 Task { @MainActor in // Ensure listener closure runs on MainActor
                     guard let self = self else { return }
                     self.isLoading = false // Stop opportunity loading

                     if let error = error {
                         let nsError = error as NSError; let message = "Error Loading Opportunities: \(error.localizedDescription)"
                         if self.errorMessage == nil { self.errorMessage = message }
                         self.opportunities = []
                         if nsError.code == FirestoreErrorCode.permissionDenied.rawValue { self.errorMessage = "Permission Denied loading opportunities." }
                         print("!!! Firestore Read Error (Opportunities) (\(nsError.code)): \(error.localizedDescription)"); return
                     }
                     guard let documents = querySnapshot?.documents else {
                         if self.errorMessage == nil { self.errorMessage = "Could not retrieve opportunity documents." }
                         self.opportunities = []; print("!!! No opportunity documents found"); return
                     }

                     print(">>> Opportunity snapshot received with \(documents.count) documents.")
                     let newOpportunities = documents.compactMap { Opportunity(snapshot: $0) }
                     // Assign directly. Rely on Equatable conformance for diffing.
                     self.opportunities = newOpportunities
                     print(">>> ViewModel opportunities list updated with \(newOpportunities.count) items.")
                     // Clear only general loading errors
                     if self.errorMessage != nil && self.errorMessage!.contains("Loading") {
                        self.errorMessage = nil
                     }
                 }
            }
    }

    /// Fetches users with the 'manager' role.
    @MainActor
    func fetchManagers() async {
        if managersListener != nil { print("Fetch Managers check: Listener already exists."); return }
        guard !isLoadingManagers else { print("Fetch Managers skipped: Already loading."); return }
        print("FETCHING Managers...")
        isLoadingManagers = true

        let collectionRef = db.collection("users")
        managersListener = collectionRef
            .whereField("role", isEqualTo: "manager")
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                 Task { @MainActor in // Ensure listener closure runs on MainActor
                     guard let self = self else { return }
                     self.isLoadingManagers = false // Stop manager loading

                     if let error = error {
                         print("!!! Fetch Managers Error: \(error.localizedDescription)")
                         self.managers = [] // Clear managers on error
                         return
                     }
                     guard let documents = querySnapshot?.documents else {
                         print("!!! No manager documents found.")
                         self.managers = []
                         return
                     }

                     print(">>> Manager snapshot received with \(documents.count) documents.")
                     let newManagers = documents.compactMap { doc -> ManagerInfo? in
                         let data = doc.data()
                         guard let username = data["username"] as? String else { return nil }
                         return ManagerInfo(id: doc.documentID, username: username, logoImageURL: data["logoImageURL"] as? String)
                     }
                     self.managers = newManagers.sorted { $0.username.lowercased() < $1.username.lowercased() }
                     print(">>> ViewModel managers list updated with \(self.managers.count) items.")
                 }
            }
    }


    /// Adds a new opportunity to Firestore. Calls completion handler on success/failure.
    func addOpportunity(name: String,
                        location: String,
                        description: String,
                        eventDate: Date,
                        endTime: Date,
                        maxAttendeesInput: Int?,
                        completion: ((_ success: Bool) -> Void)? = nil) {

        guard isCurrentUserAManager else {
            Task { @MainActor in self.errorMessage = "Permission Denied." }; clearErrorAfterDelay(.general)
            completion?(false); return
        }
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            Task { @MainActor in self.errorMessage = "Valid session required." }
            completion?(false); return
        }

        // Set loading state immediately on the main thread
        self.isLoading = true
        self.errorMessage = nil

        // Input Validation (Perform before Firestore call)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else {
            Task { @MainActor in self.errorMessage = "Name/location required."; self.isLoading = false }
            completion?(false); return
        }
        guard let combinedEndDate = combine(date: eventDate, time: endTime) else {
            Task { @MainActor in self.errorMessage = "Error processing end time."; self.isLoading = false }
            completion?(false); return
        }
        guard combinedEndDate > eventDate else {
            Task { @MainActor in self.errorMessage = "End time must be after start."; self.isLoading = false }
            completion?(false); return
        }
        let maxAttendeesValue = (maxAttendeesInput ?? 0) > 0 ? maxAttendeesInput : nil
        let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description." : description

        // Prepare data
        let opportunityData: [String: Any] = [
            "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
            "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
            "creatorUserId": user.uid, "maxAttendees": maxAttendeesValue as Any, "attendeeIds": [],
            "attendanceRecords": [:]
        ]
        let collectionRef = db.collection("volunteeringOpportunities")
        print("Attempting Firestore addDocument by manager \(user.uid)...")

        // Perform Firestore operation
        collectionRef.addDocument(data: opportunityData) { [weak self] error in
            // Process result on MainActor
            Task { @MainActor in
                guard let self = self else { completion?(false); return }
                self.isLoading = false // Stop loading regardless of outcome
                if let error = error {
                    let nsError = error as NSError; self.errorMessage = "Error Adding: \(error.localizedDescription)"
                    print("!!! Firestore Add Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
                    completion?(false) // Call completion with failure
                } else {
                    print(">>> Opportunity added successfully!"); self.errorMessage = nil
                    completion?(true) // Call completion with success
                }
            }
        }
    }

    /// Updates an existing opportunity in Firestore. Calls completion handler on success/failure.
    func updateOpportunity(opportunityId: String,
                           name: String,
                           location: String,
                           description: String,
                           eventDate: Date,
                           endTime: Date,
                           maxAttendeesInput: Int?,
                           completion: ((_ success: Bool) -> Void)? = nil) {

         guard isCurrentUserAManager else {
             Task { @MainActor in self.errorMessage = "Permission Denied." }; clearErrorAfterDelay(.general)
             completion?(false); return
         }
         guard let user = Auth.auth().currentUser, !user.isAnonymous else {
             Task { @MainActor in self.errorMessage = "Valid session required." }
             completion?(false); return
         }

         // Set loading state immediately on the main thread
         self.isLoading = true
         self.errorMessage = nil

         // Input Validation (Perform before Firestore call)
         let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else { Task { @MainActor in self.errorMessage = "Name/location required."; self.isLoading = false }; completion?(false); return }
         guard let combinedEndDate = combine(date: eventDate, time: endTime) else { Task { @MainActor in self.errorMessage = "Error processing end time."; self.isLoading = false }; completion?(false); return }
         guard combinedEndDate > eventDate else { Task { @MainActor in self.errorMessage = "End time must be after start."; self.isLoading = false }; completion?(false); return }
         let maxAttendeesValue = (maxAttendeesInput ?? 0) > 0 ? maxAttendeesInput : nil
         let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description." : description

         // Prepare update data
         let updatedData: [String: Any] = [
             "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
             "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
             "maxAttendees": maxAttendeesValue as Any
         ]
         let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
         print("Attempting to update opportunity \(opportunityId) by manager \(user.uid)...")

         // Perform Firestore operation
         docRef.updateData(updatedData) { [weak self] error in
            // Process result on MainActor
            Task { @MainActor in
                guard let self = self else { completion?(false); return }
                self.isLoading = false // Stop loading regardless of outcome
                 if let error = error {
                     let nsError = error as NSError; self.errorMessage = "Error Updating: \(error.localizedDescription)"
                     print("!!! Firestore Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
                     completion?(false) // Call completion with failure
                 } else {
                     print(">>> Opportunity \(opportunityId) updated successfully!"); self.errorMessage = nil
                     completion?(true) // Call completion with success
                 }
            }
         }
     }

    /// Deletes an opportunity from Firestore. Requires manager role.
    func deleteOpportunity(opportunityId: String) {
       guard isCurrentUserAManager else { Task { @MainActor in self.errorMessage = "Permission Denied." }; clearErrorAfterDelay(.general); return }
       guard let user = Auth.auth().currentUser, !user.isAnonymous else { Task { @MainActor in self.errorMessage = "Valid session required." }; return }

       // Decision to allow delete based on date happens in the View
       Task { @MainActor in isLoading = true; errorMessage = nil }

       let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
       print("Attempting to delete opportunity \(opportunityId) by manager \(user.uid)...")
       docRef.delete { [weak self] error in
           Task { @MainActor in // Ensure completion runs on MainActor
                guard let self = self else { return }
                self.isLoading = false
               if let error = error {
                    let nsError = error as NSError; self.errorMessage = "Error Deleting: \(error.localizedDescription)"
                    print("!!! Firestore Delete Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
               } else { print(">>> Opportunity \(opportunityId) deleted successfully."); self.errorMessage = nil }
           }
       }
    }

    // MARK: - User Data Logic (Favorites & RSVPs)

    /// Fetches user-specific data (Favorites and RSVPs) and sets up ONE listener.
    func fetchUserData(userId: String) {
        if userDataListener != nil { print("Fetch User Data check: Listener already exists."); return }
        print("Fetching user data (Favorites & RSVPs) for: \(userId)")
        userDataListener?.remove()

        let userDocRef = db.collection("users").document(userId)
        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] (documentSnapshot, error) in
            Task { @MainActor in // Ensure UI updates are on main actor
                guard let self = self else { return }
                var latestFavIds = Set<String>()
                var latestRsvpIds = Set<String>()

                if let error = error { print("!!! User Data Listener Error: \(error)"); return }
                guard let document = documentSnapshot else { print("User data documentSnapshot nil."); return }

                if document.exists, let data = document.data() {
                    latestFavIds = Set(data["favoriteOpportunityIds"] as? [String] ?? [])
                    latestRsvpIds = Set(data["rsvpedOpportunityIds"] as? [String] ?? [])
                } else { print("User doc missing or nil for \(userId).") }

                if self.favoriteOpportunityIds != latestFavIds { self.favoriteOpportunityIds = latestFavIds }
                if self.rsvpedOpportunityIds != latestRsvpIds {
                    self.rsvpedOpportunityIds = latestRsvpIds
                     print("---> RSVPs Set Updated via Listener. New count: \(self.rsvpedOpportunityIds.count)")
                }
            }
        }
    }

    /// Checks if the current user has favorited a specific opportunity.
    func isFavorite(opportunityId: String?) -> Bool {
         guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
         return favoriteOpportunityIds.contains(id)
     }

    /// Toggles the favorite status of an opportunity for the current user.
    func toggleFavorite(opportunity: Opportunity) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            Task { @MainActor in self.errorMessage = "Log in to save favorites." }; clearErrorAfterDelay(.general); return
        }
        let userId = user.uid; let opportunityId = opportunity.id; let isCurrentlyFavorite = self.favoriteOpportunityIds.contains(opportunityId)

        Task { @MainActor in // Optimistic UI Update
             var optimisticFavIds = self.favoriteOpportunityIds
             if isCurrentlyFavorite { optimisticFavIds.remove(opportunityId) } else { optimisticFavIds.insert(opportunityId) }
             self.favoriteOpportunityIds = optimisticFavIds
        }

        let userDocRef = db.collection("users").document(userId); let updateValue = isCurrentlyFavorite ? FieldValue.arrayRemove([opportunityId]) : FieldValue.arrayUnion([opportunityId])
        userDocRef.setData(["favoriteOpportunityIds": updateValue], merge: true) { [weak self] error in
            Task { @MainActor in // Ensure completion runs on MainActor
                guard let self = self else { return }
                if let error = error {
                    print("!!! Error updating favorites: \(error)"); self.errorMessage = "Failed to update favorite."
                    var revertedFavIds = self.favoriteOpportunityIds // Revert UI
                    if isCurrentlyFavorite { revertedFavIds.insert(opportunityId) } else { revertedFavIds.remove(opportunityId) }
                    self.favoriteOpportunityIds = revertedFavIds; self.clearErrorAfterDelay(.general)
                } else {
                    print("Favorites updated successfully."); self.errorMessage = nil
                }
            }
        }
    }

    /// Checks if the current user has RSVP'd to a specific opportunity.
    func isRsvped(opportunityId: String?) -> Bool {
        guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
        return rsvpedOpportunityIds.contains(id)
    }

    /// Toggles the RSVP status for the current user. (Removed completion handler)
    func toggleRSVP(opportunity: Opportunity) {
        // 1. Checks
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { Task { @MainActor in self.rsvpErrorMessage = "Log in to RSVP." }; clearErrorAfterDelay(.rsvp); return }
        guard !opportunity.isCurrentlyOccurring else { Task { @MainActor in self.rsvpErrorMessage = "Cannot change RSVP while event is ongoing." }; clearErrorAfterDelay(.rsvp); return }
        guard !opportunity.hasEnded else { Task { @MainActor in self.rsvpErrorMessage = "Event has ended." }; clearErrorAfterDelay(.rsvp); return }

        let userId = user.uid; let opportunityId = opportunity.id
        let isCurrentlyRsvped = self.rsvpedOpportunityIds.contains(opportunityId)
        if !isCurrentlyRsvped && opportunity.isFull { Task { @MainActor in self.rsvpErrorMessage = "Event is full." }; clearErrorAfterDelay(.rsvp); return }

        // 2. Optimistic UI Update & Start Loading (@MainActor)
        Task { @MainActor in
            var updatedSet = self.rsvpedOpportunityIds
            if isCurrentlyRsvped { updatedSet.remove(opportunityId); print("Optimistic UI: Removing RSVP ID \(opportunityId)") }
            else { updatedSet.insert(opportunityId); print("Optimistic UI: Inserting RSVP ID \(opportunityId)") }
            self.rsvpedOpportunityIds = updatedSet
            print("Optimistic update assigned. New local count: \(self.rsvpedOpportunityIds.count)")
            isTogglingRsvp = true; rsvpErrorMessage = nil // Start loading
        }

        // 4. Prepare Batch Write
        let batch = db.batch()
        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let userDocRef = db.collection("users").document(userId)
        if isCurrentlyRsvped {
            print("Preparing REMOVE RSVP (Batch)...")
            batch.updateData(["attendeeIds": FieldValue.arrayRemove([userId])], forDocument: oppDocRef)
            batch.setData(["rsvpedOpportunityIds": FieldValue.arrayRemove([opportunityId])], forDocument: userDocRef, merge: true)
        } else {
             print("Preparing ADD RSVP (Batch)...")
            batch.updateData(["attendeeIds": FieldValue.arrayUnion([userId])], forDocument: oppDocRef)
            batch.setData(["rsvpedOpportunityIds": FieldValue.arrayUnion([opportunityId])], forDocument: userDocRef, merge: true)
        }

        // 5. Commit the Batch
        print("Committing RSVP batch write. UserID: \(userId), OpportunityID: \(opportunityId)")
        batch.commit { [weak self] error in
            Task { @MainActor in // Ensure completion runs on MainActor
                guard let self = self else { return }; self.isTogglingRsvp = false

                if let error = error {
                    let nsError = error as NSError
                    print("!!! BATCH COMMIT FAILED !!! Error: \(error.localizedDescription) Code: \(nsError.code)")
                    self.rsvpErrorMessage = "Failed to update RSVP."; self.clearErrorAfterDelay(.rsvp)
                    // Revert Optimistic UI
                    print("Reverting optimistic RSVP update due to Firestore error.")
                    var revertedSet = self.rsvpedOpportunityIds
                    if isCurrentlyRsvped { revertedSet.insert(opportunityId) } else { revertedSet.remove(opportunityId) }
                    self.rsvpedOpportunityIds = revertedSet
                    print("Reverted state. Final local count: \(self.rsvpedOpportunityIds.count)")
                } else {
                    print(">>> BATCH COMMIT SUCCEEDED <<<"); self.rsvpErrorMessage = nil
                }
            }
        }
    }


    // MARK: - Attendance Logic

    /// Records attendance for a specific attendee. Requires manager role.
    func recordAttendance(opportunityId: String, attendeeId: String, status: String?) {
        guard isCurrentUserAManager else { Task { @MainActor in self.attendanceErrorMessage = "Permission Denied." }; clearErrorAfterDelay(.attendance); return }
        guard Auth.auth().currentUser != nil else { Task { @MainActor in self.attendanceErrorMessage = "Valid session required." }; return }

        Task { @MainActor in isUpdatingAttendance = true; attendanceErrorMessage = nil }

        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let fieldPath = "attendanceRecords.\(attendeeId)"
        let updatePayload: [String: Any] = [fieldPath: status != nil ? status! : FieldValue.delete()]

        print("Attempting attendance update: \(updatePayload)")
        oppDocRef.updateData(updatePayload) { [weak self] error in
            Task { @MainActor in // Ensure completion runs on MainActor
                guard let self = self else { return }; self.isUpdatingAttendance = false
                if let error = error {
                    let nsError = error as NSError; self.attendanceErrorMessage = "Error updating attendance."
                     print("!!! Attendance Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.attendance)
                } else { print(">>> Attendance recorded successfully."); self.attendanceErrorMessage = nil }
            }
        }
    }

    // MARK: - Manager Remove Attendee Logic

    /// Allows a manager to remove a specific attendee from an event via Batch Write.
    func managerRemoveAttendee(opportunityId: String, attendeeIdToRemove: String) {
        guard isCurrentUserAManager else { Task { @MainActor in self.removeAttendeeErrorMessage = "Permission Denied." }; clearErrorAfterDelay(.removeAttendee); return }
        guard Auth.auth().currentUser != nil else { Task { @MainActor in self.removeAttendeeErrorMessage = "Valid session required." }; return }

        Task { @MainActor in isRemovingAttendee = true; removeAttendeeErrorMessage = nil }

        let batch = db.batch()
        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let userDocRef = db.collection("users").document(attendeeIdToRemove)
        let attendanceFieldPath = "attendanceRecords.\(attendeeIdToRemove)"

        print("Preparing batch to remove attendee \(attendeeIdToRemove)...")
        batch.updateData(["attendeeIds": FieldValue.arrayRemove([attendeeIdToRemove])], forDocument: oppDocRef)
        batch.setData(["rsvpedOpportunityIds": FieldValue.arrayRemove([opportunityId])], forDocument: userDocRef, merge: true)
        batch.updateData([attendanceFieldPath: FieldValue.delete()], forDocument: oppDocRef)

        batch.commit { [weak self] error in
             Task { @MainActor in // Ensure completion runs on MainActor
                 guard let self = self else { return }; self.isRemovingAttendee = false
                 if let error = error {
                     let nsError = error as NSError; print("!!! MANAGER REMOVE ATTENDEE BATCH FAILED !!! Error: \(error) Code: \(nsError.code)")
                     self.removeAttendeeErrorMessage = "Failed to remove attendee."; self.clearErrorAfterDelay(.removeAttendee)
                 } else {
                     print(">>> MANAGER REMOVE ATTENDEE BATCH SUCCEEDED <<<"); self.removeAttendeeErrorMessage = nil
                }
             }
         }
    }

} // End Class OpportunityViewModel

// Helper struct for Manager Search Results (ensure defined once or moved)
// struct ManagerInfo: Identifiable, Hashable { ... }

// Helper String extension (ensure defined once)
// extension String { ... }
