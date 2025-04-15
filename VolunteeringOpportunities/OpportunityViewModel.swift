import Foundation
import FirebaseFirestore
import Combine          // For reactive programming (e.g., @Published, AnyCancellable)
import FirebaseAuth       // For checking user authentication state

// MARK: - Opportunity View Model (with Favorites)
// Manages fetching, creating, and handling user favoriting of volunteering opportunities.
// Reacts to authentication state changes to fetch appropriate data.
class OpportunityViewModel: ObservableObject {

    // MARK: - Published Properties (State exposed to SwiftUI Views)
    // These properties will automatically trigger UI updates when their values change.

    @Published var opportunities = [Opportunity]()         // Holds ALL fetched opportunities
    @Published var errorMessage: String?                // Stores error messages for UI display
    @Published var isLoading: Bool = false                 // Indicates if data is being fetched/updated
    @Published var favoriteOpportunityIds = Set<String>() // Set of IDs of opportunities the user has favorited

    // MARK: - Private Properties
    private var db = Firestore.firestore()                  // Firestore database reference
    private var opportunitiesListener: ListenerRegistration? // Listener for the opportunities collection
    private var userFavoritesListener: ListenerRegistration? // Listener for the current user's favorites data
    private var authViewModelCancellable: AnyCancellable?    // Subscription to AuthenticationViewModel's user session changes

    // MARK: - Initialization
    init() {
        print("OpportunityViewModel initialized.")
        // No complex Combine pipelines needed for simple favorites array handling
    }

    // MARK: - Setup & Teardown

    // Connects this ViewModel to the AuthenticationViewModel.
    // This allows OpportunityViewModel to react when the user logs in, logs out,
    // or switches between anonymous/authenticated states.
    func setupUserObservations(authViewModel: AuthenticationViewModel) {
        print("Setting up user observations in OpportunityViewModel")
        authViewModelCancellable?.cancel() // Ensure no duplicate subscriptions

        // Subscribe to changes in the 'userSession' published property of AuthenticationViewModel.
        authViewModelCancellable = authViewModel.$userSession
            .receive(on: RunLoop.main) // Ensure UI-related updates happen on the main thread
            .sink { [weak self] user in // Use weak self to prevent retain cycles
                guard let self = self else { return }
                print("Auth state change received. User: \(user?.uid ?? "nil"), Anonymous: \(user?.isAnonymous ?? true)")

                // --- React to Authentication State Change ---

                // Fetch general opportunities list if *any* user session exists (including anonymous).
                // This depends on Firestore rules allowing reads for any authenticated user.
                if user != nil {
                    self.fetchOpportunities()
                } else {
                    // No user session exists (e.g., after explicit sign out and before anonymous sign-in).
                    self.opportunities = [] // Clear the main list
                    self.isLoading = false
                    self.errorMessage = nil
                    self.clearUserFavorites() // Clear any potentially lingering favorites data
                    print("No user session. Opportunities and user data cleared.")
                }

                // Fetch user-specific favorites data ONLY if the user is logged in AND NOT anonymous.
                if let currentUser = user, !currentUser.isAnonymous {
                    print("Non-anonymous user detected (\(currentUser.uid)). Fetching user favorites.")
                    self.fetchUserFavorites(userId: currentUser.uid) // Fetch favorites for this specific user
                } else {
                    // User is anonymous or nil - clear favorites data and stop listening.
                    print("User is anonymous or nil. Clearing user favorites data.")
                    self.clearUserFavorites()
                }
            }
    }

    // Cleans up Firestore listeners and Combine subscriptions when the ViewModel instance is deallocated.
    deinit {
        print("OpportunityViewModel deinited. Removing listeners...")
        opportunitiesListener?.remove()
        userFavoritesListener?.remove()
        authViewModelCancellable?.cancel()
        print("OpportunityViewModel listeners removed.")
    }

    // MARK: - Private Helper Methods

    // Clears local user-specific state (favorites) and stops the Firestore listener for user data.
    private func clearUserFavorites() {
        userFavoritesListener?.remove() // Stop listening to the previous user's document
        userFavoritesListener = nil
        favoriteOpportunityIds = [] // Clear the local set of favorite IDs
        print("User favorites data cleared.")
    }

    // MARK: - Firestore Operations

    // Fetches the main list of all volunteering opportunities from Firestore.
    // Requires an authenticated user session (anonymous OK, based on typical rules).
    func fetchOpportunities() {
        // Ensure a user session exists before attempting fetch.
        guard Auth.auth().currentUser != nil else {
            print("Fetch Opportunities skipped: No user session found unexpectedly.")
            self.opportunities = []; self.isLoading = false; self.errorMessage = nil; self.clearUserFavorites()
            return
        }

        isLoading = true
        errorMessage = nil
        print("Attempting to fetch opportunities...")
        opportunitiesListener?.remove() // Avoid attaching multiple listeners

        let collectionRef = db.collection("volunteeringOpportunities")
        opportunitiesListener = collectionRef
            .order(by: "eventTimestamp", descending: false) // Order chronologically
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                 guard let self = self else { return }
                 self.isLoading = false // Fetch attempt finished

                 // Handle potential errors during fetch
                 if let error = error {
                     let nsError = error as NSError
                     if nsError.domain == FirestoreErrorDomain && nsError.code == 7 { // Permission Denied
                          self.errorMessage = "Permission Denied: Cannot read opportunities. Check Firestore rules."
                          print("!!! Firestore Read Error (Permission Denied): \(error.localizedDescription)")
                     } else {
                          self.errorMessage = "Error Loading Opportunities: \(error.localizedDescription)"
                          print("!!! Firestore Read Error: \(error)")
                     }
                     self.opportunities = [] // Clear data on error
                     return // Stop processing
                 }

                 // Process the fetched documents
                 guard let documents = querySnapshot?.documents else {
                     self.errorMessage = "Could not retrieve opportunity documents."
                     print("!!! No documents reference found (querySnapshot?.documents was nil)")
                     self.opportunities = []
                     return
                 }

                 print(">>> Snapshot received with \(documents.count) documents.")
                 // Map Firestore documents to local Opportunity objects using the custom initializer
                 self.opportunities = documents.compactMap { Opportunity(snapshot: $0) }
                 self.errorMessage = nil // Clear any previous error on success
                 print(">>> ViewModel opportunities list updated. Count: \(self.opportunities.count)")
            }
    }

    // Adds a new opportunity to Firestore (requires a non-anonymous user).
    func addOpportunity(name: String, location: String, description: String, eventDate: Date, endDate: Date) {
        // Ensure the user is logged in and not anonymous before allowing creation.
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
             self.errorMessage = "Please log in or sign up to add an opportunity."
             print("Add opportunity failed: User is anonymous or not logged in.")
              DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.errorMessage = nil } // Auto-clear message
             return
         }
         let userId = user.uid // We have a valid, non-anonymous user ID

        isLoading = true
        errorMessage = nil

        // --- Input Validation ---
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.errorMessage = "Please fill in name and location."; self.isLoading = false; return
        }
        guard endDate > eventDate else {
            self.errorMessage = "End time must be after start time."; self.isLoading = false; return
        }
        // --- End Validation ---

        let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No description provided." : description

        // Prepare data dictionary for the new Firestore document.
        let opportunityData: [String: Any] = [
            "name": name,
            "location": location,
            "description": finalDescription,
            "eventTimestamp": Timestamp(date: eventDate), // Convert Date to Firestore Timestamp
            "endTimestamp": Timestamp(date: endDate),
            "creatorUserId": userId // Store the ID of the user who created the opportunity
        ]
        let collectionRef = db.collection("volunteeringOpportunities")

        // Add the document to Firestore.
        collectionRef.addDocument(data: opportunityData) { [weak self] error in
            guard let self = self else { return }
            self.isLoading = false // Operation finished

            if let error = error {
                // Handle Firestore write errors, checking specifically for permission issues.
                let nsError = error as NSError
                if nsError.domain == FirestoreErrorDomain && nsError.code == 7 { // Permission Denied (Code 7)
                    self.errorMessage = "Permission Denied: Cannot add opportunity. Check Firestore write rules."
                    print("!!! Firestore Write Error (Permission Denied): \(error.localizedDescription)")
                } else {
                    // Handle other potential errors (network, etc.)
                    self.errorMessage = "Error Adding Opportunity: \(error.localizedDescription)"
                    print("!!! Error adding document: \(error)")
                }
            } else {
                // Success!
                self.errorMessage = nil // Clear any previous errors.
                print("Opportunity added successfully by user \(userId)!")
                // The OpportunityListView's Firestore listener will automatically pick up the new document.
            }
        }
    }


    // MARK: - User Favorites Logic (for non-anonymous users)

    // Fetches the user's document to get the array of favorite opportunity IDs.
    // Sets up a listener for real-time updates to the favorites.
    func fetchUserFavorites(userId: String) {
        print("Fetching favorites for non-anonymous user: \(userId)")
        userFavoritesListener?.remove() // Ensure no duplicate listeners for user data

        let userDocRef = db.collection("users").document(userId) // Reference to the user's document

        // Attach a listener to the user's document
        userFavoritesListener = userDocRef.addSnapshotListener { [weak self] (documentSnapshot, error) in
            guard let self = self else { return }

            var fetchedFavIds = Set<String>() // Start with an empty set for this update

            // Handle errors fetching/listening to the document
            if let error = error {
                print("!!! Error listening to user favorites document for \(userId): \(error)")
                // Clear local state on persistent errors to avoid showing stale data
            }
            // Process the document snapshot if it exists
            else if let document = documentSnapshot, document.exists, let data = document.data() {
                // Try to parse the 'favoriteOpportunityIds' field as an array of Strings
                if let ids = data["favoriteOpportunityIds"] as? [String] {
                    fetchedFavIds = Set(ids) // Populate the set with fetched IDs
                    print("Fetched \(fetchedFavIds.count) favorite IDs for \(userId).")
                } else {
                    // Field might be missing or of the wrong type
                    print("User doc \(userId) missing/invalid 'favoriteOpportunityIds' field. Assuming no favorites.")
                }
            } else {
                 // Document doesn't exist or the snapshot was nil
                 print("User document missing or snapshot nil for \(userId). Assuming no favorites.")
            }

            // --- Update Published Property ---
            // Update the @Published set, which will trigger UI updates in observing views.
            self.favoriteOpportunityIds = fetchedFavIds
            print("Favorites set updated. Count: \(self.favoriteOpportunityIds.count)")
        }
    }

    // Checks if a specific opportunity ID is present in the current user's favorites set.
    // Returns false if the user is anonymous or the provided ID is nil.
    func isFavorite(opportunityId: String?) -> Bool {
         guard let id = opportunityId, Auth.auth().currentUser?.isAnonymous == false else {
             return false // Anonymous users cannot have favorites; nil ID cannot be checked.
         }
         // Check if the ID exists in the local set of favorite IDs.
         return favoriteOpportunityIds.contains(id)
     }

    // Adds or removes an opportunity ID from the user's 'favoriteOpportunityIds' array in Firestore.
    // Requires a non-anonymous user. Uses optimistic UI updates.
    func toggleFavorite(opportunity: Opportunity) {
        // Ensure user is logged in and not anonymous.
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            print("Cannot toggle favorite: User is anonymous or not logged in.")
            self.errorMessage = "Please log in or sign up to save favorites."
            // Clear the error message automatically after a few seconds.
             DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                 if self.errorMessage == "Please log in or sign up to save favorites." {
                    self.errorMessage = nil
                }
             }
            return
        }
        let userId = user.uid
        let opportunityId = opportunity.id // Get the non-optional ID from the struct.

        let userDocRef = db.collection("users").document(userId)
        // Check the *current local state* to determine the action (add or remove).
        let isCurrentlyFavorite = self.favoriteOpportunityIds.contains(opportunityId)

        // --- Optimistic UI Update ---
        // Modify the local @Published set *before* the Firestore call for immediate UI feedback.
        var optimisticFavIds = self.favoriteOpportunityIds // Create a mutable copy.
        if isCurrentlyFavorite {
            optimisticFavIds.remove(opportunityId) // Remove if it was favorited.
            print("Optimistic UI remove: \(opportunityId)")
        } else {
            optimisticFavIds.insert(opportunityId) // Add if it wasn't favorited.
            print("Optimistic UI insert: \(opportunityId)")
        }
        // Update the @Published property - this triggers UI refresh via Combine.
        self.favoriteOpportunityIds = optimisticFavIds
        // --- End Optimistic Update ---

        // --- Prepare Firestore Update ---
        // Use Firestore FieldValue arrayUnion/arrayRemove for atomic operations on the array.
        let updateValue = isCurrentlyFavorite ?
            FieldValue.arrayRemove([opportunityId]) : // Action to remove the ID from the array.
            FieldValue.arrayUnion([opportunityId])   // Action to add the ID (only if not already present).

        print("Updating Firestore favorites for Opp ID: \(opportunityId). Action: \(isCurrentlyFavorite ? "Remove" : "Add"). User: \(userId)")

        // Use setData with merge: true. This is crucial because:
        // 1. It creates the 'users' document if it doesn't exist.
        // 2. It creates the 'favoriteOpportunityIds' field if it doesn't exist.
        // 3. It correctly performs the arrayUnion/arrayRemove operation.
        userDocRef.setData(["favoriteOpportunityIds": updateValue], merge: true) { [weak self] error in
            guard let self = self else { return } // Safely unwrap self.

            // --- Handle Firestore Completion ---
            if let error = error {
                // If the Firestore update fails:
                print("!!! Error updating favorites array for \(userId): \(error)")
                self.errorMessage = "Failed to update favorites."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.errorMessage = nil } // Auto-clear error.

                // --- REVERT OPTIMISTIC UPDATE ON FAILURE ---
                // Restore the local state to what it was *before* the optimistic update attempt.
                print("Reverting optimistic favorite update due to Firestore error.")
                if isCurrentlyFavorite {
                    // Failed to remove, so add it back locally.
                    self.favoriteOpportunityIds.insert(opportunityId)
                } else {
                    // Failed to add, so remove it locally.
                    self.favoriteOpportunityIds.remove(opportunityId)
                }
                // --- End Revert ---

            } else {
                // Firestore update succeeded.
                print("Firestore favorites array updated successfully for \(userId).")
                // The optimistic UI update already reflected the change. The Firestore listener
                // will eventually receive this update too, confirming the state. No further local change needed here.
            }
        } // End setData callback
    } // End toggleFavorite

} // End Class OpportunityViewModel
