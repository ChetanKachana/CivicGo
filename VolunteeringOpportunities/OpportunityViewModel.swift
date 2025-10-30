import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth
import ActivityKit

struct UserInfo: Identifiable, Hashable {
    let id: String
    let username: String
   
}

struct ManagerInfo: Identifiable, Hashable {
    let id: String
    let username: String
    let logoImageURL: String?
}

// MARK: - Opportunity View Model (Callbacks for CUD)
@MainActor
class OpportunityViewModel: ObservableObject {

    // MARK: - Published Properties (State exposed to SwiftUI Views)

    @Published var opportunities = [Opportunity]()
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isCurrentUserAManager: Bool = false

    @Published var managers = [ManagerInfo]()
    @Published var isLoadingManagers: Bool = false

    @Published var favoriteOpportunityIds = Set<String>()
    @Published var rsvpedOpportunityIds = Set<String>()

    @Published var isTogglingRsvp: Bool = false
    @Published var rsvpErrorMessage: String?
    @Published var isUpdatingAttendance: Bool = false
    @Published var attendanceErrorMessage: String?
    @Published var isRemovingAttendee: Bool = false
    @Published var removeAttendeeErrorMessage: String?

    @Published var allUserInfos: [String: UserInfo] = [:]
    @Published var isLoadingAllUsers: Bool = false


    private var activeLiveActivities: [String: Activity<EventLiveActivityAttributes>] = [:]
    private var activityUpdateTask: Task<Void, Never>?


    // MARK: - Private Properties
    private lazy var db = Firestore.firestore()
    private var opportunitiesListener: ListenerRegistration?
    private var userDataListener: ListenerRegistration?
    private var managersListener: ListenerRegistration?
    private var authCancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init() {
        print("OpportunityViewModel initialized.")
        Task { @MainActor in
            for activity in Activity<EventLiveActivityAttributes>.activities {
                self.activeLiveActivities[activity.attributes.opportunityId] = activity
                print("Reconnected to existing Live Activity for \(activity.attributes.eventName) (ID: \(activity.id))")
            }
        }
       
    }

    // MARK: - Setup & Teardown

    func setupAuthObservations(authViewModel: AuthenticationViewModel) {
        print("Setting up auth observations (user session & manager status) in OpportunityViewModel")
        authCancellables.forEach { $0.cancel() }; authCancellables.removeAll()

        authViewModel.$userSession
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                guard let self = self else { return }
                print("Auth Session change received in OppVM. User: \(user?.uid ?? "nil")")

                Task {
                    if let currentUser = user {
                        await self.fetchOpportunities()
                        await self.fetchManagers()
                        if !currentUser.isAnonymous {
                            self.fetchUserData(userId: currentUser.uid)
                        } else {
                             await self.clearUserData()
                        }
                    } else {
                        await self.clearAllDataAndListeners()
                        self.endAllLiveActivities()
                    }
                }
            }
            .store(in: &authCancellables)

        authViewModel.$isManager
            .receive(on: RunLoop.main)
            .sink { [weak self] isMgr in
                 if self?.isCurrentUserAManager != isMgr {
                     self?.isCurrentUserAManager = isMgr
                     print("Manager status updated: \(isMgr)")
                 }
            }
            .store(in: &authCancellables)
    }

    deinit {
        print("OpportunityViewModel deinited.")
        opportunitiesListener?.remove()
        userDataListener?.remove()
        managersListener?.remove()
        authCancellables.forEach { $0.cancel() }
        
        Task { @MainActor in
            self.endAllLiveActivities() 
        }
        print("OpportunityViewModel cleanup complete.")
    }

    // MARK: - Helper Methods (Internal Access)

    @MainActor
    func clearUserData() {
        print("Clearing user data listener and local state (Favorites, RSVPs).")
        userDataListener?.remove(); userDataListener = nil
        if !favoriteOpportunityIds.isEmpty { favoriteOpportunityIds = [] }
        if !rsvpedOpportunityIds.isEmpty { rsvpedOpportunityIds = [] }
    }

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
        // Clear allUserInfos as well
        if !allUserInfos.isEmpty { allUserInfos = [:] }
        errorMessage = nil; rsvpErrorMessage = nil; attendanceErrorMessage = nil; removeAttendeeErrorMessage = nil
        isLoading = false; isLoadingManagers = false; isLoadingAllUsers = false
        isTogglingRsvp = false; isUpdatingAttendance = false; isRemovingAttendee = false
        isCurrentUserAManager = false
    }

    enum ErrorType { case general, rsvp, attendance, removeAttendee }

    func clearErrorAfterDelay(_ errorType: ErrorType, duration: TimeInterval = 4.0) {
         DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
             guard let self = self else { return }
             Task { @MainActor in
                 switch errorType {
                 case .general:        if self.errorMessage != nil { self.errorMessage = nil }
                 case .rsvp:           if self.rsvpErrorMessage != nil { self.rsvpErrorMessage = nil }
                 case .attendance:     if self.attendanceErrorMessage != nil { self.attendanceErrorMessage = nil }
                 case .removeAttendee: if self.removeAttendeeErrorMessage != nil { self.removeAttendeeErrorMessage = nil }
                 }
             }
         }
     }

    func combine(date: Date, time: Date) -> Date? {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year; combinedComponents.month = dateComponents.month; combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour; combinedComponents.minute = timeComponents.minute; combinedComponents.second = timeComponents.second
        combinedComponents.timeZone = calendar.timeZone
        return calendar.date(from: combinedComponents)
    }

    @MainActor
    func fetchUserDetails(for userIds: Set<String>) async {
        guard !userIds.isEmpty else { return }

        let newUsersToFetch = userIds.filter { allUserInfos[$0] == nil }
        guard !newUsersToFetch.isEmpty else { return }

        print("Fetching details for \(newUsersToFetch.count) new users...")
        isLoadingAllUsers = true
        errorMessage = nil

        let userIdsArray = Array(newUsersToFetch)
        let chunkSize = 10
        var allFetchedUsers: [String: UserInfo] = [:]

        do {
            for i in stride(from: 0, to: userIdsArray.count, by: chunkSize) {
                let end = min(i + chunkSize, userIdsArray.count)
                let chunk = userIdsArray[i..<end]

                let querySnapshot = try await db.collection("users").whereField(FieldPath.documentID(), in: Array(chunk)).getDocuments()
                for document in querySnapshot.documents {
                    let data = document.data()
                    if let username = data["username"] as? String {
                        allFetchedUsers[document.documentID] = UserInfo(id: document.documentID, username: username)
                    }
                }
            }
            self.allUserInfos.merge(allFetchedUsers) { (current, new) in new } 
            print("Successfully fetched details for \(allFetchedUsers.count) users.")
        } catch {
            print("!!! Error fetching user details: \(error.localizedDescription)")
            self.errorMessage = "Failed to load some user details."
            self.clearErrorAfterDelay(.general)
        }
        isLoadingAllUsers = false
    }

    func username(for userId: String) -> String? {
        return allUserInfos[userId]?.username
    }


    // MARK: - Firestore Operations: Opportunities (Read, Create, Update, Delete)

    @MainActor
    func fetchOpportunities() {
        if opportunitiesListener != nil { print("Fetch Ops check: Listener already exists."); return }
        if !isLoading { isLoading = true }
        print("FETCHING Opportunities...")

        let collectionRef = db.collection("volunteeringOpportunities")
        opportunitiesListener = collectionRef
            .order(by: "eventTimestamp", descending: false)
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                 Task { @MainActor in
                     guard let self = self else { return }
                     self.isLoading = false

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
                     self.opportunities = newOpportunities
                     print(">>> ViewModel opportunities list updated with \(newOpportunities.count) items.")
                     if self.errorMessage != nil && self.errorMessage!.contains("Loading") {
                        self.errorMessage = nil
                     }

                   
                     let allAttendeeIds = Set(newOpportunities.flatMap { $0.attendeeIds })
                     if !allAttendeeIds.isEmpty {
                         await self.fetchUserDetails(for: allAttendeeIds)
                     }
                 }
            }
    }

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
                 Task { @MainActor in
                     guard let self = self else { return }
                     self.isLoadingManagers = false

                     if let error = error {
                         print("!!! Fetch Managers Error: \(error.localizedDescription)")
                         self.managers = []
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
                         self.allUserInfos[doc.documentID] = UserInfo(id: doc.documentID, username: username)
                         return ManagerInfo(id: doc.documentID, username: username, logoImageURL: data["logoImageURL"] as? String)
                     }
                     self.managers = newManagers.sorted { $0.username.lowercased() < $1.username.lowercased() }
                     print(">>> ViewModel managers list updated with \(self.managers.count) items.")
                 }
            }
    }


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

        self.isLoading = true
        self.errorMessage = nil

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

        let opportunityData: [String: Any] = [
            "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
            "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
            "creatorUserId": user.uid, "maxAttendees": maxAttendeesValue as Any, "attendeeIds": [],
            "attendanceRecords": [:]
        ]
        let collectionRef = db.collection("volunteeringOpportunities")
        print("Attempting Firestore addDocument by manager \(user.uid)...")

        collectionRef.addDocument(data: opportunityData) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { completion?(false); return }
                self.isLoading = false
                if let error = error {
                    let nsError = error as NSError; self.errorMessage = "Error Adding: \(error.localizedDescription)"
                    print("!!! Firestore Add Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
                    completion?(false)
                } else {
                    print(">>> Opportunity added successfully!"); self.errorMessage = nil
                    completion?(true)
                }
            }
        }
    }

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

         self.isLoading = true
         self.errorMessage = nil

         let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines); let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else { Task { @MainActor in self.errorMessage = "Name/location required."; self.isLoading = false }; completion?(false); return }
         guard let combinedEndDate = combine(date: eventDate, time: endTime) else { Task { @MainActor in self.errorMessage = "Error processing end time."; self.isLoading = false }; completion?(false); return }
         guard combinedEndDate > eventDate else { Task { @MainActor in self.errorMessage = "End time must be after start."; self.isLoading = false }; completion?(false); return }
         let maxAttendeesValue = (maxAttendeesInput ?? 0) > 0 ? maxAttendeesInput : nil
         let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description." : description

         let updatedData: [String: Any] = [
             "name": trimmedName, "location": trimmedLocation, "description": finalDescription,
             "eventTimestamp": Timestamp(date: eventDate), "endTimestamp": Timestamp(date: combinedEndDate),
             "maxAttendees": maxAttendeesValue as Any
         ]
         let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
         print("Attempting to update opportunity \(opportunityId) by manager \(user.uid)...")

         docRef.updateData(updatedData) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { completion?(false); return }
                self.isLoading = false
                 if let error = error {
                     let nsError = error as NSError; self.errorMessage = "Error Updating: \(error.localizedDescription)"
                     print("!!! Firestore Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
                     completion?(false)
                 } else {
                     print(">>> Opportunity \(opportunityId) updated successfully!"); self.errorMessage = nil
                     completion?(true)

                   
                     if let currentUser = Auth.auth().currentUser, !currentUser.isAnonymous {
                         if self.rsvpedOpportunityIds.contains(opportunityId) {
                             if let originalOpportunity = self.opportunities.first(where: { $0.id == opportunityId }) {

                                 let updatedOpportunity = Opportunity(
                                     id: originalOpportunity.id,
                                     name: trimmedName,
                                     location: trimmedLocation,
                                     description: finalDescription,
                                     eventTimestamp: Timestamp(date: eventDate),
                                     endTimestamp: Timestamp(date: combinedEndDate),
                                     creatorUserId: originalOpportunity.creatorUserId,
                                     organizerUsername: originalOpportunity.organizerUsername,
                                     maxAttendees: maxAttendeesValue,
                                     attendeeIds: originalOpportunity.attendeeIds,
                                     attendanceRecords: originalOpportunity.attendanceRecords
                                 )

                                 self.endLiveActivity(for: opportunityId)
                                 
                                 Task { @MainActor in
                                     self.startLiveActivity(for: updatedOpportunity)
                                 }
                             } else {
                                 print("Warning: Opportunity with ID \(opportunityId) not found in local cache after update. Cannot restart Live Activity with updated details.")
                             }
                         }
                     }
                 }
            }
         }
     }

    func deleteOpportunity(opportunityId: String) {
       guard isCurrentUserAManager else { Task { @MainActor in self.errorMessage = "Permission Denied." }; clearErrorAfterDelay(.general); return }
       guard let user = Auth.auth().currentUser, !user.isAnonymous else { Task { @MainActor in self.errorMessage = "Valid session required." }; return }

       Task { @MainActor in isLoading = true; errorMessage = nil }

       let docRef = db.collection("volunteeringOpportunities").document(opportunityId)
       print("Attempting to delete opportunity \(opportunityId) by manager \(user.uid)...")
       docRef.delete { [weak self] error in
           Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false
               if let error = error {
                    let nsError = error as NSError; self.errorMessage = "Error Deleting: \(error.localizedDescription)"
                    print("!!! Firestore Delete Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.general)
               } else {
                   print(">>> Opportunity \(opportunityId) deleted successfully."); self.errorMessage = nil
                   self.endLiveActivity(for: opportunityId)
               }
           }
       }
    }

    // MARK: - Live Activity Management
    func startLiveActivity(for opportunity: Opportunity) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled or authorized.")
            Task { @MainActor in self.rsvpErrorMessage = "Live Activities are disabled. Please enable them in Settings." }; clearErrorAfterDelay(.rsvp)
            return
        }

        if activeLiveActivities[opportunity.id] != nil {
            print("Live Activity for \(opportunity.name) is already active.")
            Task { await self.updateLiveActivity(for: opportunity) }
            return
        }

        guard opportunity.eventDate > Date() || opportunity.isCurrentlyOccurring else {
            print("Not starting Live Activity for past event: \(opportunity.name)")
            return
        }

        let initialContentState = EventLiveActivityAttributes.EventStatus(
            statusEmoji: "🗓️"
        )

        let attributes = EventLiveActivityAttributes(
            eventName: opportunity.name,
            eventLocation: opportunity.location,
            eventStartTime: opportunity.eventDate,
            eventEndTime: opportunity.endTime,
            opportunityId: opportunity.id
        )

        do {
            let activity = try Activity<EventLiveActivityAttributes>.request(
                attributes: attributes,
                contentState: initialContentState
            )
            activeLiveActivities[opportunity.id] = activity
            print("Started Live Activity for \(opportunity.name) (ID: \(activity.id))")

        } catch {
            print("Error starting Live Activity: \(error.localizedDescription)")
            Task { @MainActor in self.rsvpErrorMessage = "Failed to start Live Activity: \(error.localizedDescription)" }; clearErrorAfterDelay(.rsvp)
        }
    }

    func updateLiveActivity(for opportunity: Opportunity) async {
        guard let activity = activeLiveActivities[opportunity.id] else {
            print("No active Live Activity found for ID \(opportunity.id) to update.")
            return
        }

        let now = Date()
        let statusEmoji: String
        if opportunity.hasEnded {
            statusEmoji = "✅" // Event ended
        } else if opportunity.eventDate <= now {
            statusEmoji = "🔥" // Event started
        } else if opportunity.eventDate.timeIntervalSince(now) <= 30 * 60 {
            statusEmoji = "⏳" // Starting soon (within 30 min)
        } else {
            statusEmoji = "🗓️" // Upcoming
        }

        let updatedContentState = EventLiveActivityAttributes.EventStatus(
            statusEmoji: statusEmoji
        )

        print("Updating Live Activity for \(opportunity.name) (ID: \(activity.id)) with emoji: \(statusEmoji)")
        do {
            await activity.update(using: updatedContentState)
            print("Live Activity update successful.")
        } catch {
            print("Error updating Live Activity: \(error.localizedDescription)")
        }
    }

    func endLiveActivity(for opportunityId: String) {
        guard let activity = activeLiveActivities[opportunityId] else {
            print("No active Live Activity found for ID \(opportunityId) to end.")
            return
        }

        Task {
            print("Ending Live Activity for ID: \(opportunityId)")
         
            let dismissalDate = activity.attributes.eventStartTime.addingTimeInterval(30 * 60)
            await activity.end(using: activity.contentState, dismissalPolicy: .after(dismissalDate))
            activeLiveActivities.removeValue(forKey: opportunityId)
        }
    }

    func endAllLiveActivities() {
        print("Ending all active Live Activities.")
        for (_, activity) in activeLiveActivities {
            Task {
                await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
            }
        }
        activeLiveActivities.removeAll()
    }


    // MARK: - User Data Logic (Favorites & RSVPs)

    func fetchUserData(userId: String) {
        if userDataListener != nil { print("Fetch User Data check: Listener already exists."); return }
        print("Fetching user data (Favorites & RSVPs) for: \(userId)")
        userDataListener?.remove()

        let userDocRef = db.collection("users").document(userId)
        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] (documentSnapshot, error) in
            Task { @MainActor in
                guard let self = self else { return }
                var latestFavIds = Set<String>()
                var latestRsvpIds = Set<String>()

                if let error = error { print("!!! User Data Listener Error: \(error)"); return }
                guard let document = documentSnapshot else { print("User data documentSnapshot nil."); return }

                if document.exists, let data = document.data() {
                    latestFavIds = Set(data["favoriteOpportunityIds"] as? [String] ?? [])
                    latestRsvpIds = Set(data["rsvpedOpportunityIds"] as? [String] ?? [])
                    if let username = data["username"] as? String {
                        self.allUserInfos[userId] = UserInfo(id: userId, username: username)
                    }
                } else { print("User doc missing or nil for \(userId).") }

                if self.favoriteOpportunityIds != latestFavIds { self.favoriteOpportunityIds = latestFavIds }
                if self.rsvpedOpportunityIds != latestRsvpIds {
                    self.rsvpedOpportunityIds = latestRsvpIds
                     print("---> RSVPs Set Updated via Listener. New count: \(self.rsvpedOpportunityIds.count)")
                    self.syncLiveActivitiesWithRSVPs(latestRsvpIds: latestRsvpIds)
                }
            }
        }
    }

  
    private func syncLiveActivitiesWithRSVPs(latestRsvpIds: Set<String>) {
        for (oppId, activity) in activeLiveActivities where !latestRsvpIds.contains(oppId) {
            print("Sync: Ending Live Activity for \(oppId) (no longer RSVP'd).")
            self.endLiveActivity(for: oppId)
        }

        let currentActiveIds = Set(activeLiveActivities.keys)
        for opportunity in opportunities where latestRsvpIds.contains(opportunity.id) && !currentActiveIds.contains(opportunity.id) {
            if opportunity.eventDate > Date() || opportunity.isCurrentlyOccurring {
                print("Sync: Starting Live Activity for \(opportunity.id) (newly RSVP'd).")
                self.startLiveActivity(for: opportunity)
            }
        }
        
        for opportunity in opportunities where latestRsvpIds.contains(opportunity.id) && currentActiveIds.contains(opportunity.id) {
            Task { await self.updateLiveActivity(for: opportunity) }
        }
    }


    func isFavorite(opportunityId: String?) -> Bool {
         guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
         return favoriteOpportunityIds.contains(id)
     }

    func toggleFavorite(opportunity: Opportunity) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            Task { @MainActor in self.errorMessage = "Log in to save favorites." }; clearErrorAfterDelay(.general); return
        }
        let userId = user.uid; let opportunityId = opportunity.id; let isCurrentlyFavorite = self.favoriteOpportunityIds.contains(opportunityId)

        Task { @MainActor in
             var optimisticFavIds = self.favoriteOpportunityIds
             if isCurrentlyFavorite { optimisticFavIds.remove(opportunityId) } else { optimisticFavIds.insert(opportunityId) }
             self.favoriteOpportunityIds = optimisticFavIds
        }

        let userDocRef = db.collection("users").document(userId); let updateValue = isCurrentlyFavorite ? FieldValue.arrayRemove([opportunityId]) : FieldValue.arrayUnion([opportunityId])
        userDocRef.setData(["favoriteOpportunityIds": updateValue], merge: true) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    print("!!! Error updating favorites: \(error)"); self.errorMessage = "Failed to update favorite."
                    var revertedFavIds = self.favoriteOpportunityIds
                    if isCurrentlyFavorite { revertedFavIds.insert(opportunityId) } else { revertedFavIds.remove(opportunityId) }
                    self.favoriteOpportunityIds = revertedFavIds; self.clearErrorAfterDelay(.general)
                } else {
                    print("Favorites updated successfully."); self.errorMessage = nil
                }
            }
        }
    }

    func isRsvped(opportunityId: String?) -> Bool {
        guard let id = opportunityId, let user = Auth.auth().currentUser, !user.isAnonymous else { return false }
        return rsvpedOpportunityIds.contains(id)
    }

    func toggleRSVP(opportunity: Opportunity) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { Task { @MainActor in self.rsvpErrorMessage = "Log in to RSVP." }; clearErrorAfterDelay(.rsvp); return }
        guard !opportunity.isCurrentlyOccurring else { Task { @MainActor in self.rsvpErrorMessage = "Cannot change RSVP while event is ongoing." }; clearErrorAfterDelay(.rsvp); return }
        guard !opportunity.hasEnded else { Task { @MainActor in self.rsvpErrorMessage = "Event has ended." }; clearErrorAfterDelay(.rsvp); return }

        let userId = user.uid; let opportunityId = opportunity.id
        let isCurrentlyRsvped = self.rsvpedOpportunityIds.contains(opportunityId)
        if !isCurrentlyRsvped && opportunity.isFull { Task { @MainActor in self.rsvpErrorMessage = "Event is full." }; clearErrorAfterDelay(.rsvp); return }

        Task { @MainActor in
            var updatedSet = self.rsvpedOpportunityIds
            if isCurrentlyRsvped { updatedSet.remove(opportunityId); print("Optimistic UI: Removing RSVP ID \(opportunityId)") }
            else { updatedSet.insert(opportunityId); print("Optimistic UI: Inserting RSVP ID \(opportunityId)") }
            self.rsvpedOpportunityIds = updatedSet
            print("Optimistic update assigned. New local count: \(self.rsvpedOpportunityIds.count)")
            isTogglingRsvp = true; rsvpErrorMessage = nil
        }

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

        print("Committing RSVP batch write. UserID: \(userId), OpportunityID: \(opportunityId)")
        batch.commit { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }; self.isTogglingRsvp = false

                if let error = error {
                    let nsError = error as NSError
                    print("!!! BATCH COMMIT FAILED !!! Error: \(error.localizedDescription) Code: \(nsError.code)")
                    self.rsvpErrorMessage = "Failed to update RSVP."; self.clearErrorAfterDelay(.rsvp)
                    print("Reverting optimistic RSVP update due to Firestore error.")
                    var revertedSet = self.rsvpedOpportunityIds
                    if isCurrentlyRsvped { revertedSet.insert(opportunityId) } else { revertedSet.remove(opportunityId) }
                    self.rsvpedOpportunityIds = revertedSet
                    print("Reverted state. Final local count: \(self.rsvpedOpportunityIds.count)")

                    if !isCurrentlyRsvped {
                        self.endLiveActivity(for: opportunity.id)
                    }
                } else {
                    print(">>> BATCH COMMIT SUCCEEDED <<<"); self.rsvpErrorMessage = nil
                    if isCurrentlyRsvped {
                        self.endLiveActivity(for: opportunity.id)
                    } else {
                        await self.startLiveActivity(for: opportunity)
                    }
                }
            }
        }
    }


    // MARK: - Attendance Logic

    func recordAttendance(opportunityId: String, attendeeId: String, status: String?) {
        guard isCurrentUserAManager else { Task { @MainActor in self.attendanceErrorMessage = "Permission Denied." }; clearErrorAfterDelay(.attendance); return }
        guard Auth.auth().currentUser != nil else { Task { @MainActor in self.attendanceErrorMessage = "Valid session required." }; return }

        Task { @MainActor in isUpdatingAttendance = true; attendanceErrorMessage = nil }

        let oppDocRef = db.collection("volunteeringOpportunities").document(opportunityId)
        let fieldPath = "attendanceRecords.\(attendeeId)"
        let updatePayload: [String: Any] = [fieldPath: status != nil ? status! : FieldValue.delete()]

        print("Attempting attendance update: \(updatePayload)")
        oppDocRef.updateData(updatePayload) { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }; self.isUpdatingAttendance = false
                if let error = error {
                    let nsError = error as NSError; self.attendanceErrorMessage = "Error updating attendance."
                     print("!!! Attendance Update Error: \(error.localizedDescription) (Code: \(nsError.code))"); self.clearErrorAfterDelay(.attendance)
                } else { print(">>> Attendance recorded successfully."); self.attendanceErrorMessage = nil }
            }
        }
    }

    // MARK: - Manager Remove Attendee Logic

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
             Task { @MainActor in
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

}
