import Foundation
import FirebaseCore
import Combine
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

// MARK: - Authentication View Model (Anonymous & Google Sign-In)
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var userSession: User?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var userRole: String?
    @Published var username: String?
    @Published var isManager: Bool = false

    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private var userDataListener: ListenerRegistration?
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()

    private var usernameCache: [String: String] = [:]

    // MARK: - Initialization & Deinitialization
    init() {
        print("AuthenticationViewModel initialized.")
        setupBindings()
        listenToAuthState()
    }

    deinit {
        print("AuthenticationViewModel deinited.")
        if let handle = authStateHandler { Auth.auth().removeStateDidChangeListener(handle); print("Auth state listener removed.") }
        userDataListener?.remove(); print("User data listener removed.")
        cancellables.forEach { $0.cancel() }
    }

    // MARK: - Setup Methods

    private func setupBindings() {
        $userRole
            .map { role -> Bool in
                let managerStatus = role == "manager"
                return managerStatus
            }
            .receive(on: RunLoop.main)
            .assign(to: \.isManager, on: self)
            .store(in: &cancellables)
    }

    func listenToAuthState() {
        if let handle = authStateHandler { Auth.auth().removeStateDidChangeListener(handle) }

        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            let previousUID = self.userSession?.uid
            print("Auth State Changed Listener Fired. New User UID: \(user?.uid ?? "nil")")

            if previousUID != user?.uid {
                 self.userSession = user
                 print("Updated userSession property.")
            }

            self.userDataListener?.remove(); self.userDataListener = nil
            if self.userRole != nil || self.username != nil {
                 Task { @MainActor in
                     self.userRole = nil
                     self.username = nil
                     print("Cleared previous user data listener and state (role, username).")
                 }
            }

            if let currentUser = user {
                if !currentUser.isAnonymous {
                    print("Non-anonymous user \(currentUser.uid) detected. Starting user data listener...")
                    self.listenForUserData(userId: currentUser.uid)
                } else {
                    print("Anonymous user \(currentUser.uid) detected. Setting defaults.")
                     Task { @MainActor in
                         self.userRole = "anonymous"
                         self.username = "Guest"
                         self.isManager = false
                     }
                }
            } else {
                print("No user detected (logged out state). Role/Username remain nil.")
            }
        }
    }

    private func listenForUserData(userId: String) {
        let userDocRef = db.collection("users").document(userId)
        print("Attaching Firestore user data listener to path: \(userDocRef.path)")

        userDataListener = userDocRef.addSnapshotListener(includeMetadataChanges: false) { [weak self] documentSnapshot, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    print("!!! Listener Error: \(error.localizedDescription)")
                    if self.userRole != "user" { self.userRole = "user" }
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
                     if let nameToCache = fetchedUsername?.nilIfEmpty { self.usernameCache[userId] = nameToCache }
                } else {
                     print("User document \(userId) does not exist. Assuming 'user' role, nil username.")
                     role = "user"; fetchedUsername = nil
                }

                 if self.userRole != role { self.userRole = role }
                 if self.username != fetchedUsername { self.username = fetchedUsername }
            }
        }
    }

    // MARK: - User Document Handling (Enhanced Logging)

    private func createUserDocument(userId: String, email: String?, username: String? = nil, displayName: String? = nil) {
        let userDocRef = db.collection("users").document(userId)

        let derivedUsername = username?.nilIfEmpty ?? displayName?.nilIfEmpty ?? email?.components(separatedBy: "@").first?.nilIfEmpty ?? "User_\(userId.prefix(4))"
        let finalUsername = derivedUsername.count >= 3 ? derivedUsername : "User_\(userId.prefix(8))"

        let userData: [String: Any] = [
            "email": email?.nilIfEmpty as Any,
            "username": finalUsername,
            "role": "user",
            "createdAt": FieldValue.serverTimestamp(),
            "favoriteOpportunityIds": [],
            "rsvpedOpportunityIds": []
        ]

        print("--- [createUserDocument] Attempting for UID: \(userId)")
        print("--- [createUserDocument] Final Derived Username: '\(finalUsername)' (Length: \(finalUsername.count))")
        print("--- [createUserDocument] Provided Email: \(email ?? "nil")")
        print("--- [createUserDocument] Data to Send: \(userData)")

        userDocRef.setData(userData, merge: true) { error in
            if let err = error {
                let nsError = err as NSError
                print("!!! [createUserDocument] ERROR setting/merging user document for \(userId):")
                print("    Error Description: \(err.localizedDescription)")
                print("    Domain: \(nsError.domain), Code: \(nsError.code)")
                print("    UserInfo: \(nsError.userInfo)")
            } else {
                print(">>> [createUserDocument] User document data set/merged successfully for \(userId).")
                 Task { @MainActor [weak self] in
                     self?.usernameCache[userId] = finalUsername
                     print(">>> [createUserDocument] Updated username cache for \(userId).")
                 }
            }
        }
        print("--- [createUserDocument] setData call initiated for \(userId). Completion handler pending.")
    }


    // MARK: - Sign In Methods

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
                Task { @MainActor in
                    guard let self = self else { return }
                    print("[signInWithGoogle] Firebase signIn completion handler fired.")

                    self.isLoading = false

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
                    self.errorMessage = nil

                    print(">>> [signInWithGoogle] Preparing to call createUserDocument...")
                    self.createUserDocument(
                        userId: firebaseUser.uid,
                        email: firebaseUser.email,
                        displayName: firebaseUser.displayName
                    )
                    print("<<< [signInWithGoogle] Called createUserDocument.")
                }
            }
        }
    }

    // MARK: - Sign Out
    func signOut() {
        print("Attempting sign out for user: \(userSession?.uid ?? "N/A")...")
        Task { @MainActor in isLoading = true; errorMessage = nil }

        Task { @MainActor in
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

    @MainActor
    func updateUsername(newUsername: String) async {
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

        isLoading = true
        errorMessage = nil

        do {
            print("Checking username uniqueness for '\(trimmedUsername)'...")
            let querySnapshot = try await db.collection("users")
                                          .whereField("username", isEqualTo: trimmedUsername)
                                          .limit(to: 1)
                                          .getDocuments()

            if !querySnapshot.isEmpty && querySnapshot.documents[0].documentID != userId {
                 print("!!! Username '\(trimmedUsername)' is already taken by user \(querySnapshot.documents[0].documentID).")
                 self.errorMessage = "Username already taken. Please choose another."
                 isLoading = false
                 return
            } else {
                 print("Username '\(trimmedUsername)' is unique or belongs to current user.")
            }

            let userDocRef = db.collection("users").document(userId)
            let updateData: [String: Any] = ["username": trimmedUsername]
            print("Attempting to update username to '\(trimmedUsername)' for user \(userId)...")

            try await userDocRef.updateData(updateData)

            print(">>> Username updated successfully to '\(trimmedUsername)' in Firestore.")
            self.errorMessage = nil

        } catch {
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

        isLoading = false
    }


    // MARK: - Username Fetching (for specific IDs)

    func fetchUsername(for userId: String, completion: @escaping (String?) -> Void) {
        if let cachedName = usernameCache[userId] {
            DispatchQueue.main.async { completion(cachedName) }
            return
        }

        print("Username cache miss. Fetching username for specific User ID: \(userId)")
        let userDocRef = db.collection("users").document(userId)

        userDocRef.getDocument { [weak self] (documentSnapshot, error) in
            DispatchQueue.main.async {
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

}
