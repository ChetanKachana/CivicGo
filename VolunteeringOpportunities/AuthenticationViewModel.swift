import Foundation
import FirebaseCore
import Combine
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn // Still needed for Google Sign-In

// MARK: - Authentication View Model (Anonymous & Google Sign-In)
// Manages authentication state using Firebase for Anonymous and Google providers.
// Fetches associated user data (role, username) for the current user from Firestore.
// Provides a function to fetch usernames for arbitrary user IDs.
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var userSession: User? // Holds the logged-in Firebase User object (anonymous or Google)
    @Published var isLoading: Bool = false // General loading state for sign-in/out actions
    @Published var errorMessage: String?    // Displays errors to the user
    @Published var userRole: String?        // Stores the role string ("manager", "user", etc.) fetched from Firestore for current user
    @Published var username: String?        // Stores the current user's display name fetched/updated in Firestore
    @Published var isManager: Bool = false    // Convenience boolean derived from userRole for current user

    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle? // Firebase auth state listener handle
    private var userDataListener: ListenerRegistration? // Firestore listener for current user's document
    private let db = Firestore.firestore()          // Firestore database reference
    private var cancellables = Set<AnyCancellable>() // Stores Combine subscriptions

    // Cache for fetched usernames to reduce Firestore reads
    private var usernameCache: [String: String] = [:]

    // MARK: - Initialization & Deinitialization
    init() {
        print("AuthenticationViewModel initialized.")
        setupBindings()     // Setup reactive derivation of isManager
        listenToAuthState() // Start listening for Firebase Auth changes
    }

    deinit {
        print("AuthenticationViewModel deinited.")
        // Clean up listeners and subscriptions to prevent memory leaks
        if let handle = authStateHandler { Auth.auth().removeStateDidChangeListener(handle); print("Auth state listener removed.") }
        userDataListener?.remove(); print("User data listener removed.")
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Setup Methods

    /// Sets up a Combine pipeline to automatically update `isManager` whenever `userRole` changes.
    private func setupBindings() {
        $userRole
            .map { role -> Bool in // Determine manager status based on role string
                let managerStatus = role == "manager"
                if role != nil { // Log only when role is actually set/changed
                    print("Derived isManager status: \(managerStatus) (from role: \(role ?? "nil"))")
                }
                return managerStatus
            }
            .receive(on: RunLoop.main) // Ensure UI updates happen on the main thread
            .assign(to: \.isManager, on: self) // Assign the result to the isManager property
            .store(in: &cancellables) // Store the subscription reference
    }

    /// Establishes a listener for Firebase Authentication state changes.
    /// When the user logs in or out, this triggers updates to userSession and related user data fetching.
    func listenToAuthState() {
        // Remove existing listener first to prevent duplicates
        if let handle = authStateHandler { Auth.auth().removeStateDidChangeListener(handle) }

        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            let previousUID = self.userSession?.uid // Store previous UID for comparison
            print("Auth State Changed Listener Fired. New User UID: \(user?.uid ?? "nil")")

            // --- User Session Update ---
            // Update userSession only if the user actually changed
            if previousUID != user?.uid {
                 self.userSession = user
                 print("Updated userSession property.")
            }

            // --- User Data Fetching Logic (Role & Username) ---
            self.userDataListener?.remove(); self.userDataListener = nil // Stop listening for previous user's data
            // Reset local role and username state whenever auth changes
            if self.userRole != nil { self.userRole = nil }
            if self.username != nil { self.username = nil } // Reset username
            print("Cleared previous user data listener and state (role, username).")

            // If a user is logged in, fetch their data
            if let currentUser = user {
                if !currentUser.isAnonymous { // Fetch data only for non-anonymous (Google) users
                    print("Non-anonymous user \(currentUser.uid) detected. Starting user data listener...")
                    self.listenForUserData(userId: currentUser.uid)
                } else { // Handle anonymous user state
                    print("Anonymous user \(currentUser.uid) detected. Setting defaults.")
                    self.userRole = "anonymous" // Set role explicitly for anonymous state
                    self.username = "Guest"    // Set default guest username
                    self.isManager = false    // Anonymous users cannot be managers
                }
            } else { // No user logged in (logged out state)
                print("No user detected (logged out state). Role/Username remain nil.")
            }
            // --- End User Data Fetching Logic ---
        }
    }

    /// Listens for real-time changes on the *current* user's document in Firestore to fetch role and username.
    private func listenForUserData(userId: String) {
        let userDocRef = db.collection("users").document(userId)
        print("Attaching Firestore user data listener to path: \(userDocRef.path)")

        // Use includeMetadataChanges: false to potentially reduce extra triggers from cache/server sync differences
        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] documentSnapshot, error in
            guard let self = self else { return }
            let logTimestamp = Date().timeIntervalSince1970 // For detailed logging
            print("[\(logTimestamp)] AUTH VIEW MODEL - User Data Listener Triggered for \(userId)")

            if let error = error {
                print("[\(logTimestamp)] !!! Listener Error: \(error.localizedDescription)")
                if self.userRole != "user" { self.userRole = "user" } // Default role on error
                if self.username != nil { self.username = nil }
                print("[\(logTimestamp)] ==============================================")
                return
            }

            guard let document = documentSnapshot else {
                 print("[\(logTimestamp)] User data listener documentSnapshot was nil.")
                 if self.userRole != "user" { self.userRole = "user" } // Default role
                 if self.username != nil { self.username = nil }      // Clear username
                 print("[\(logTimestamp)] ==============================================")
                 return
            }

            // Log metadata for debugging listener triggers
            let hasPendingWrites = document.metadata.hasPendingWrites
            let source = hasPendingWrites ? "Local Cache" : "Server"
            print("[\(logTimestamp)] Snapshot Metadata: Source=\(source), hasPendingWrites=\(hasPendingWrites), Exists=\(document.exists)")

            var role: String? = nil
            var fetchedUsername: String? = nil

            if document.exists, let data = document.data() {
                 // Document exists, parse fields safely
                 role = data["role"] as? String ?? "user" // Default role to 'user' if missing/invalid
                 fetchedUsername = data["username"] as? String // Username is optional
                 print("[\(logTimestamp)] User document exists. Parsed role: '\(role ?? "nil")', Parsed username: '\(fetchedUsername ?? "nil")'")

                 // --- Update Cache for Current User ---
                 if let nameToCache = fetchedUsername?.nilIfEmpty {
                    self.usernameCache[userId] = nameToCache
                    print("[\(logTimestamp)] Updated username cache for current user.")
                 }
                 // --- End Update Cache ---

            } else {
                 // Document doesn't exist
                 print("[\(logTimestamp)] User document \(userId) does not exist. Assuming 'user' role, nil username.")
                 role = "user"; fetchedUsername = nil // Default if doc missing
            }

            // --- Compare and Update Published Properties ---
             // Update role only if it actually changed
             if self.userRole != role {
                  self.userRole = role
                  print("[\(logTimestamp)] ---> User role updated in ViewModel.")
             }
             // Update username only if it actually changed
             if self.username != fetchedUsername {
                  self.username = fetchedUsername
                  print("[\(logTimestamp)] ---> Username updated in ViewModel.")
             }

            print("[\(logTimestamp)] User Data listener processed. Final Role: \(self.userRole ?? "nil"), Username: \(self.username ?? "nil")")
            print("[\(logTimestamp)] ==============================================")
        }
    }

    // MARK: - User Document Handling

    /// Creates or merges user data in Firestore after signup or login.
    /// Ensures essential fields like role and username are present.
    private func createUserDocument(userId: String, email: String?, username: String? = nil, displayName: String? = nil) {
        let userDocRef = db.collection("users").document(userId)

        // Derive initial username logic: Use passed username > Google display name > email prefix > default "User_..."
        let derivedUsername = username?.nilIfEmpty ?? displayName?.nilIfEmpty ?? email?.components(separatedBy: "@").first?.nilIfEmpty ?? "User_\(userId.prefix(4))"

        // Prepare data, ensuring required fields for rules are included
        // Ensure keys match exactly what your Security Rules expect on create/update
        let userData: [String: Any] = [
            "email": email ?? "",            // Store email if available from provider
            "username": derivedUsername,     // Use derived username
            "role": "user",                  // Default role for new/merged users
            "createdAt": FieldValue.serverTimestamp(), // Use server timestamp for creation/update time
            "favoriteOpportunityIds": FieldValue.arrayUnion([]), // Ensure array exists using arrayUnion([])
            "rsvpedOpportunityIds": FieldValue.arrayUnion([])    // Ensure array exists using arrayUnion([])
        ]

        print("Creating/Merging Firestore user document for \(userId) with username: '\(derivedUsername)'...")
        // Use setData WITH MERGE to safely create the document OR update existing fields
        // without overwriting fields not included in userData (like role if already set to manager).
        // It also handles creating the array fields correctly if they don't exist.
        userDocRef.setData(userData, merge: true) { [weak self] error in // Capture self weakly
            if let error = error {
                print("!!! Error setting/merging user document data: \(error.localizedDescription)")
                 // Potentially set errorMessage here if this merge is critical
                 // DispatchQueue.main.async { self?.errorMessage = "Could not save profile data." }
            } else {
                print("User document data set/merged successfully for \(userId).")
                 // Update local cache after successful creation/merge
                 DispatchQueue.main.async { // Ensure cache update is on main thread
                     self?.usernameCache[userId] = derivedUsername
                 }
            }
        }
    }


    // MARK: - Sign In Methods

    /// Signs the user in anonymously using Firebase Auth.
    func signInAnonymously() {
        guard Auth.auth().currentUser == nil else {
            print("Skipping anonymous sign-in: User session already exists (\(Auth.auth().currentUser?.uid ?? "N/A"))."); return
        }
        isLoading = true; errorMessage = nil
        print("Attempting anonymous sign-in...")
        Auth.auth().signInAnonymously { [weak self] (authResult, error) in
            guard let self = self else { return }; self.isLoading = false // Stop loading
            if let error = error {
                self.errorMessage = "Anonymous Sign In Failed: \(error.localizedDescription)"
                print("!!! Anonymous Sign In Error: \(error)"); return
            }
            print("Anonymous Sign In Successful. UID: \(authResult?.user.uid ?? "N/A")")
            // Auth state listener handles session update and setting default role/username
        }
    }

    /// Initiates the Google Sign-In flow and links it with Firebase Auth.
    func signInWithGoogle() {
        isLoading = true; errorMessage = nil // Start loading
        print("Starting Google Sign In flow...")

        // 1. Get Client ID from Firebase config
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("!!! Google Sign In Error: Firebase Client ID not found.")
            errorMessage = "Google Sign-In configuration error."; isLoading = false; return
        }

        // 2. Configure Google Sign In SDK
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // 3. Get Root View Controller for presentation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("!!! Google Sign In Error: Could not get root view controller.")
            errorMessage = "Could not initiate Google Sign-In UI."; isLoading = false; return
        }

        // 4. Start Google Sign In flow presented from root view controller
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            guard let self = self else { return }

            // Handle Google SDK sign-in result
            if let error = error {
                // Don't show error message if user cancelled
                if (error as NSError).code != GIDSignInError.canceled.rawValue {
                     self.errorMessage = "Google Sign-In failed."
                }
                print("!!! Google Sign In SDK Error: \(error.localizedDescription)"); self.isLoading = false; return
            }

            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                print("!!! Google Sign In Error: Missing user or ID token from Google result.")
                self.errorMessage = "Google Sign-In data error."; self.isLoading = false; return
            }

            // 5. Create Firebase credential using Google ID token
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)

            // 6. Sign in to Firebase Authentication with the Google credential
            print("Attempting Firebase sign in with Google credential...")
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                guard let self = self else { return }; self.isLoading = false // Stop loading AFTER Firebase attempt

                if let error = error {
                    print("!!! Firebase Google Sign In Error: \(error.localizedDescription)")
                    self.errorMessage = "Failed to link Google account with Firebase." // More specific error?
                    return
                }

                // --- Firebase Sign In with Google SUCCESS ---
                print("Firebase Google Sign In Successful: \(authResult?.user.uid ?? "N/A")")
                self.errorMessage = nil // Clear any previous errors

                // Ensure Firestore user document exists/is updated (uses merge: true)
                // Pass Google's display name to potentially initialize username
                self.createUserDocument(
                    userId: authResult!.user.uid,
                    email: authResult?.user.email,
                    displayName: authResult?.user.displayName
                )
                // Auth state listener handles the main session update in the UI
            }
        }
    }

    // MARK: - Sign Out
    /// Signs the user out from Firebase Auth and Google Sign In SDK.
    func signOut() {
        print("Attempting sign out for user: \(userSession?.uid ?? "N/A")...")
        isLoading = true; errorMessage = nil

        // Clean up Firestore listener BEFORE signing out
        userDataListener?.remove(); userDataListener = nil
        if userRole != nil { userRole = nil } // Reset role state
        if username != nil { username = nil } // Reset username state
        print("User data listener removed and role/username state cleared.")

        // Sign out from Google SDK state if applicable
        GIDSignIn.sharedInstance.signOut()
        print("Signed out from Google SDK.")

        // Sign out from Firebase Auth
        do {
            try Auth.auth().signOut()
            print("Firebase Sign Out Successful")
            // The Auth state listener (`listenToAuthState`) will automatically handle
            // the userSession becoming nil and resetting state further if needed.
        } catch let signOutError as NSError {
            self.errorMessage = "Sign Out Failed: \(signOutError.localizedDescription)"
            print("!!! Firebase Sign Out Error: \(signOutError)")
        }
        // Stop loading indicator after all sign out attempts
        self.isLoading = false
    }

    // MARK: - Update Username
    /// Updates the username for the currently logged-in user in Firestore.
    func updateUsername(newUsername: String) {
        // 1. Check Authentication & Get User ID
        guard let user = userSession, !user.isAnonymous else {
            self.errorMessage = "You must be logged in to change your username."; return
        }
        let userId = user.uid
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Validate Input
        guard !trimmedUsername.isEmpty else {
            self.errorMessage = "Username cannot be empty."; return
        }
        guard trimmedUsername.count >= 3 && trimmedUsername.count <= 30 else {
             self.errorMessage = "Username must be between 3 and 30 characters."
             return
         }

        // 3. Start Loading State
        isLoading = true // Use general isLoading or create a specific one for username update
        errorMessage = nil

        // 4. Prepare Firestore Update
        let userDocRef = db.collection("users").document(userId)
        let updateData: [String: Any] = ["username": trimmedUsername]

        print("Attempting to update username to '\(trimmedUsername)' for user \(userId)...")

        // 5. Perform Update using updateData (document must exist)
        userDocRef.updateData(updateData) { [weak self] error in
            guard let self = self else { return }
            self.isLoading = false // Stop loading

            if let error = error {
                 let nsError = error as NSError
                 print("!!! Firestore Username Update Error: \(error.localizedDescription) (Code: \(nsError.code))")
                 if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                      self.errorMessage = "Permission denied updating username." // Should not happen with correct rules
                 } else if nsError.code == FirestoreErrorCode.notFound.rawValue {
                      self.errorMessage = "User profile not found. Cannot update username." // Should only happen if doc deleted externally
                 } else {
                      self.errorMessage = "Failed to update username: \(error.localizedDescription)"
                 }
                 // Consider not auto-clearing username update errors immediately
            } else {
                 print(">>> Username updated successfully to '\(trimmedUsername)'")
                 self.errorMessage = nil // Clear error on success
                 // The listener (`listenForUserData`) will automatically update the @Published var username
                 // It will also update the cache via the listener logic.
            }
        }
    }

    // MARK: - Username Fetching (for specific IDs - e.g., event creators, leaderboard)

    /// Fetches the username for a given User ID from Firestore, using a cache first.
    /// - Parameters:
    ///   - userId: The UID of the user whose username is needed.
    ///   - completion: A closure called on the main thread with the fetched username (String?) or nil.
    func fetchUsername(for userId: String, completion: @escaping (String?) -> Void) {
        // 1. Check cache first
        if let cachedName = usernameCache[userId] {
            // print("Username cache hit for \(userId): '\(cachedName)'") // Optional log
            DispatchQueue.main.async { completion(cachedName) }
            return
        }

        // 2. Not in cache, fetch from Firestore
        print("Username cache miss. Fetching username for specific User ID: \(userId)")
        let userDocRef = db.collection("users").document(userId)

        userDocRef.getDocument { [weak self] (documentSnapshot, error) in
            // Ensure completion handler is called on the main thread
            DispatchQueue.main.async {
                guard let self = self else { completion(nil); return } // Check if self still exists

                var fetchedUsername: String? = nil // Prepare result

                if let error = error {
                    print("!!! Error fetching user document \(userId) for username: \(error.localizedDescription)")
                    // Don't cache errors
                } else if let document = documentSnapshot, document.exists {
                    fetchedUsername = document.data()?["username"] as? String
                    print("Fetched username '\(fetchedUsername ?? "nil")' for user \(userId)")
                    // Update cache if username found and not empty
                    if let nameToCache = fetchedUsername?.nilIfEmpty {
                         self.usernameCache[userId] = nameToCache
                         print("Updated username cache for \(userId).")
                    }
                } else {
                    print("User document \(userId) not found when fetching username.")
                    // Optionally cache 'not found' state? For now, just return nil.
                }
                completion(fetchedUsername?.nilIfEmpty) // Return username or nil if empty/not found/error
            }
        }
    }


} // End Class AuthenticationViewModel

// MARK: - Helper Extensions

