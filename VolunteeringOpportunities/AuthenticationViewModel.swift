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
// Includes enhanced logging for user document creation and async username update with uniqueness check.
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var userSession: User? // Holds the logged-in Firebase User object (anonymous or Google)
    @Published var isLoading: Bool = false // General loading state for sign-in/out/update actions
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
            .map { role -> Bool in
                let managerStatus = role == "manager"
                // Optional: Log only when role is actually set/changed for less verbosity
                // if role != nil { print("Derived isManager status: \(managerStatus) (from role: \(role ?? "nil"))") }
                return managerStatus
            }
            .receive(on: RunLoop.main)
            .assign(to: \.isManager, on: self)
            .store(in: &cancellables)
    }

    /// Establishes a listener for Firebase Authentication state changes.
    func listenToAuthState() {
        if let handle = authStateHandler { Auth.auth().removeStateDidChangeListener(handle) }

        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            let previousUID = self.userSession?.uid
            print("Auth State Changed Listener Fired. New User UID: \(user?.uid ?? "nil")")

            // Update userSession only if the user actually changed
            if previousUID != user?.uid {
                 self.userSession = user
                 print("Updated userSession property.")
            }

            // Clean up previous user's Firestore listener and reset role/username state
            self.userDataListener?.remove(); self.userDataListener = nil
            if self.userRole != nil || self.username != nil {
                 Task { @MainActor in // Ensure UI updates are on main thread
                     self.userRole = nil
                     self.username = nil
                     print("Cleared previous user data listener and state (role, username).")
                 }
            }

            // If a user is logged in, fetch their data
            if let currentUser = user {
                if !currentUser.isAnonymous { // Fetch data only for non-anonymous (Google) users
                    print("Non-anonymous user \(currentUser.uid) detected. Starting user data listener...")
                    self.listenForUserData(userId: currentUser.uid)
                } else { // Handle anonymous user state
                    print("Anonymous user \(currentUser.uid) detected. Setting defaults.")
                     Task { @MainActor in // Ensure UI updates are on main thread
                         self.userRole = "anonymous"
                         self.username = "Guest"
                         self.isManager = false
                     }
                }
            } else { // No user logged in (logged out state)
                print("No user detected (logged out state). Role/Username remain nil.")
            }
        }
    }

    /// Listens for real-time changes on the *current* user's document in Firestore to fetch role and username.
    private func listenForUserData(userId: String) {
        let userDocRef = db.collection("users").document(userId)
        print("Attaching Firestore user data listener to path: \(userDocRef.path)")

        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] documentSnapshot, error in
            // Ensure updates happen on the main actor context
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    print("!!! Listener Error: \(error.localizedDescription)")
                    if self.userRole != "user" { self.userRole = "user" } // Default role on error
                    if self.username != nil { self.username = nil }
                    return
                }

                guard let document = documentSnapshot else {
                     print("User data listener documentSnapshot was nil.")
                     if self.userRole != "user" { self.userRole = "user" }
                     if self.username != nil { self.username = nil }
                     return
                }

                var role: String? = nil
                var fetchedUsername: String? = nil

                if document.exists, let data = document.data() {
                     role = data["role"] as? String ?? "user"
                     fetchedUsername = data["username"] as? String
                     // print("User document exists. Parsed role: '\(role ?? "nil")', Parsed username: '\(fetchedUsername ?? "nil")'")
                     if let nameToCache = fetchedUsername?.nilIfEmpty { self.usernameCache[userId] = nameToCache }
                } else {
                     print("User document \(userId) does not exist. Assuming 'user' role, nil username.")
                     role = "user"; fetchedUsername = nil
                }

                 if self.userRole != role { self.userRole = role }
                 if self.username != fetchedUsername { self.username = fetchedUsername }
                 // print("User Data listener processed. Final Role: \(self.userRole ?? "nil"), Username: \(self.username ?? "nil")")
            } // End Task @MainActor
        }
    }

    // MARK: - User Document Handling (Enhanced Logging)

    /// Creates or merges user data in Firestore after signup or login.
    private func createUserDocument(userId: String, email: String?, username: String? = nil, displayName: String? = nil) {
        let userDocRef = db.collection("users").document(userId)

        let derivedUsername = username?.nilIfEmpty ?? displayName?.nilIfEmpty ?? email?.components(separatedBy: "@").first?.nilIfEmpty ?? "User_\(userId.prefix(4))"
        // Ensure minimum length for username based on rules
        let finalUsername = derivedUsername.count >= 3 ? derivedUsername : "User_\(userId.prefix(8))" // Ensure >= 3 chars

        // --- Prepare data for Firestore ---
        let userData: [String: Any] = [
            "email": email?.nilIfEmpty as Any, // Send null if email is nil or empty
            "username": finalUsername,       // Use final username
            "role": "user",
            "createdAt": FieldValue.serverTimestamp(),
            "favoriteOpportunityIds": [], // Send empty array
            "rsvpedOpportunityIds": []    // Send empty array
        ]

        // --- DETAILED LOGGING ---
        print("--- [createUserDocument] Attempting for UID: \(userId)")
        print("--- [createUserDocument] Final Derived Username: '\(finalUsername)' (Length: \(finalUsername.count))") // Log final username
        print("--- [createUserDocument] Provided Email: \(email ?? "nil")")
        print("--- [createUserDocument] Data to Send: \(userData)")
        // --- END LOGGING ---

        userDocRef.setData(userData, merge: true) { error in
            if let err = error {
                let nsError = err as NSError
                print("!!! [createUserDocument] ERROR setting/merging user document for \(userId):")
                print("    Error Description: \(err.localizedDescription)")
                print("    Domain: \(nsError.domain), Code: \(nsError.code)")
                print("    UserInfo: \(nsError.userInfo)")
                // Optionally update UI state on main actor
                // Task { @MainActor [weak self] in self?.errorMessage = "Profile setup failed..." }
            } else {
                print(">>> [createUserDocument] User document data set/merged successfully for \(userId).")
                 Task { @MainActor [weak self] in
                     self?.usernameCache[userId] = finalUsername // Cache the final username
                     print(">>> [createUserDocument] Updated username cache for \(userId).")
                 }
            }
        }
        print("--- [createUserDocument] setData call initiated for \(userId). Completion handler pending.")
    }


    // MARK: - Sign In Methods

    /// Signs the user in anonymously using Firebase Auth.
    func signInAnonymously() {
        guard Auth.auth().currentUser == nil else {
            print("Skipping anonymous sign-in: User session already exists (\(Auth.auth().currentUser?.uid ?? "N/A"))."); return
        }
        Task { @MainActor in isLoading = true; errorMessage = nil }
        print("Attempting anonymous sign-in...")
        Auth.auth().signInAnonymously { [weak self] (authResult, error) in
            Task { @MainActor in
                guard let self = self else { return }; self.isLoading = false
                if let error = error {
                    self.errorMessage = "Anonymous Sign In Failed: \(error.localizedDescription)"
                    print("!!! Anonymous Sign In Error: \(error)"); return
                }
                print("Anonymous Sign In Successful. UID: \(authResult?.user.uid ?? "N/A")")
            }
        }
    }

    /// Initiates the Google Sign-In flow and links it with Firebase Auth.
    func signInWithGoogle() {
        Task { @MainActor in isLoading = true; errorMessage = nil }
        print("[signInWithGoogle] Starting Google Sign In flow...")

        guard let clientID = FirebaseApp.app()?.options.clientID else {
             print("!!! Google Sign In Error: Firebase Client ID not found.")
             Task { @MainActor in errorMessage = "Google Sign-In configuration error."; isLoading = false }
             return
        }
        let config = GIDConfiguration(clientID: clientID); GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("!!! Google Sign In Error: Could not get root view controller.")
            Task { @MainActor in errorMessage = "Could not initiate Google Sign-In UI."; isLoading = false }
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            guard let self = self else { return }
            print("[signInWithGoogle] GIDSignIn completion handler fired.")

            if let error = error {
                 print("!!! [signInWithGoogle] Google Sign In SDK Error: \(error.localizedDescription) Code: \((error as NSError).code)")
                 if (error as NSError).code != GIDSignInError.canceled.rawValue {
                      Task { @MainActor in self.errorMessage = "Google Sign-In failed." }
                 }
                 Task { @MainActor in self.isLoading = false }; return
            }

            guard let user = result?.user, let idToken = user.idToken?.tokenString else {
                print("!!! [signInWithGoogle] Google Sign In Error: Missing user or ID token from Google result.")
                Task { @MainActor in self.errorMessage = "Google Sign-In data error."; self.isLoading = false }; return
            }
            print("[signInWithGoogle] Successfully obtained Google ID token.")

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)

            print("[signInWithGoogle] Attempting Firebase sign in with Google credential...")
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                Task { @MainActor in // Ensure Firebase completion is on MainActor
                    guard let self = self else { return }
                    print("[signInWithGoogle] Firebase signIn completion handler fired.")

                    self.isLoading = false // Stop loading AFTER Firebase attempt completes

                    if let error = error {
                        print("!!! [signInWithGoogle] Firebase Google Sign In Error: \(error.localizedDescription)")
                        self.errorMessage = "Failed to link Google account with Firebase."
                        return
                    }

                    guard let firebaseUser = authResult?.user else {
                         print("!!! [signInWithGoogle] Firebase Google Sign In Error: No user returned in authResult.")
                         self.errorMessage = "Firebase authentication failed."
                         return
                    }

                    print(">>> [signInWithGoogle] Firebase Google Sign In Successful: UID: \(firebaseUser.uid), Email: \(firebaseUser.email ?? "N/A"), DisplayName: \(firebaseUser.displayName ?? "N/A")")
                    self.errorMessage = nil // Clear any previous errors

                    print(">>> [signInWithGoogle] Preparing to call createUserDocument...")
                    self.createUserDocument( // Call non-async function from MainActor context
                        userId: firebaseUser.uid,
                        email: firebaseUser.email,
                        displayName: firebaseUser.displayName
                    )
                    print("<<< [signInWithGoogle] Called createUserDocument.")
                } // End Task @MainActor for Firebase completion
            } // End Firebase Auth completion
        } // End GIDSignIn completion
    }

    // MARK: - Sign Out
    /// Signs the user out from Firebase Auth and Google Sign In SDK.
    func signOut() {
        print("Attempting sign out for user: \(userSession?.uid ?? "N/A")...")
        Task { @MainActor in isLoading = true; errorMessage = nil }

        Task { @MainActor in // Ensure state clearing is on MainActor
             userDataListener?.remove(); userDataListener = nil
             if userRole != nil { userRole = nil }
             if username != nil { username = nil }
             print("User data listener removed and role/username state cleared.")
        }

        GIDSignIn.sharedInstance.signOut()
        print("Signed out from Google SDK.")

        do {
            try Auth.auth().signOut()
            print("Firebase Sign Out Successful")
        } catch let signOutError as NSError {
             print("!!! Firebase Sign Out Error: \(signOutError)")
             Task { @MainActor in self.errorMessage = "Sign Out Failed: \(signOutError.localizedDescription)" }
        }
        Task { @MainActor in self.isLoading = false }
    }

    // MARK: - Update Username (with Uniqueness Check)

    /// Updates the username for the currently logged-in user in Firestore, checking for uniqueness first.
    @MainActor // Ensures UI updates run on the main thread
    func updateUsername(newUsername: String) async {
        // 1. Basic Checks & Validation
        guard let user = userSession, !user.isAnonymous else {
            self.errorMessage = "You must be logged in to change your username."
            return
        }
        let userId = user.uid
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUsername.isEmpty else {
            self.errorMessage = "Username cannot be empty."
            return
        }
        guard trimmedUsername.count >= 3 && trimmedUsername.count <= 30 else {
             self.errorMessage = "Username must be between 3 and 30 characters."
             return
        }
        if trimmedUsername == self.username {
            print("Username hasn't changed.")
            return
        }

        // 2. Start Loading State
        isLoading = true
        errorMessage = nil

        // --- 3. Uniqueness Check ---
        do {
            print("Checking username uniqueness for '\(trimmedUsername)'...")
            let querySnapshot = try await db.collection("users")
                                          .whereField("username", isEqualTo: trimmedUsername)
                                          .limit(to: 1)
                                          .getDocuments()

            if !querySnapshot.isEmpty && querySnapshot.documents[0].documentID != userId {
                 // Username is taken by someone else
                 print("!!! Username '\(trimmedUsername)' is already taken by user \(querySnapshot.documents[0].documentID).")
                 self.errorMessage = "Username already taken. Please choose another."
                 isLoading = false // Stop loading
                 return // Exit before updating
            } else {
                 // Username is unique or belongs to the current user
                 print("Username '\(trimmedUsername)' is unique or belongs to current user.")
            }

            // --- 4. Perform Update (If uniqueness check passed) ---
            let userDocRef = db.collection("users").document(userId)
            let updateData: [String: Any] = ["username": trimmedUsername]
            print("Attempting to update username to '\(trimmedUsername)' for user \(userId)...")

            try await userDocRef.updateData(updateData)

            print(">>> Username updated successfully to '\(trimmedUsername)' in Firestore.")
            self.errorMessage = nil // Clear error on success
            // The listener should update the @Published var username

        } catch { // Catch errors from query OR update
            let nsError = error as NSError
            print("!!! Error during username update process: \(error.localizedDescription) (Code: \(nsError.code))")
             if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                  self.errorMessage = "Permission denied updating username."
             } else if nsError.code == FirestoreErrorCode.notFound.rawValue {
                  self.errorMessage = "User profile not found. Cannot update username."
             } else {
                  self.errorMessage = "Failed to update username: \(error.localizedDescription)"
             }
        }

        // 5. Stop Loading State (always happens after try/catch)
        isLoading = false
        // --- End Uniqueness Check & Update ---
    }


    // MARK: - Username Fetching (for specific IDs)

    /// Fetches the username for a given User ID from Firestore, using a cache first.
    func fetchUsername(for userId: String, completion: @escaping (String?) -> Void) {
        if let cachedName = usernameCache[userId] {
            DispatchQueue.main.async { completion(cachedName) }
            return
        }

        print("Username cache miss. Fetching username for specific User ID: \(userId)")
        let userDocRef = db.collection("users").document(userId)

        userDocRef.getDocument { [weak self] (documentSnapshot, error) in
            DispatchQueue.main.async { // Ensure completion on main thread
                guard let self = self else { completion(nil); return }
                var fetchedUsername: String? = nil
                if let error = error {
                    print("!!! Error fetching user document \(userId) for username: \(error.localizedDescription)")
                } else if let document = documentSnapshot, document.exists {
                    fetchedUsername = document.data()?["username"] as? String
                    if let nameToCache = fetchedUsername?.nilIfEmpty {
                         self.usernameCache[userId] = nameToCache
                    }
                } else {
                    print("User document \(userId) not found when fetching username.")
                }
                completion(fetchedUsername?.nilIfEmpty)
            }
        }
    }

} // End Class AuthenticationViewModel

