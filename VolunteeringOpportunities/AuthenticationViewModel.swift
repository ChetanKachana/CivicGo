import Foundation
import Combine
import FirebaseAuth

class AuthenticationViewModel: ObservableObject {
    @Published var userSession: User? // Holds the logged-in Firebase User object (can be anonymous)
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var authStateHandler: AuthStateDidChangeListenerHandle?

    init() {
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
            print("Auth state listener removed.")
        }
    }

    func listenToAuthState() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            self.userSession = user
            if let user = user {
                print("Auth State Changed. User: \(user.uid), Anonymous: \(user.isAnonymous), Email: \(user.email ?? "N/A")")
            } else {
                print("Auth State Changed. No User.")
                // If user becomes nil (e.g., after deleting anonymous user?),
                // attempt to sign in anonymously again to maintain session continuity for browsing.
                // Be careful not to create an infinite loop if sign-in repeatedly fails.
                // self.signInAnonymouslyIfNeeded() // Consider adding this carefully
            }
        }
    }

    // --- ADDED: Sign In Anonymously ---
    func signInAnonymously() {
        // Only sign in anonymously if there's truly NO user session
        guard Auth.auth().currentUser == nil else {
            print("Skipping anonymous sign-in: User session already exists.")
            // Ensure the listener has updated the @Published var
            self.userSession = Auth.auth().currentUser
            return
        }

        isLoading = true
        errorMessage = nil
        print("Attempting anonymous sign-in...")
        Auth.auth().signInAnonymously { [weak self] (authResult, error) in
            guard let self = self else { return }
            self.isLoading = false
            if let error = error {
                self.errorMessage = "Anonymous Sign In Failed: \(error.localizedDescription)"
                print("!!! Anonymous Sign In Error: \(error)")
                // Handle this failure - app might not work correctly without a session
            } else {
                self.errorMessage = nil
                print("Anonymous Sign In Successful. UID: \(authResult?.user.uid ?? "N/A")")
                // Listener will update userSession
            }
        }
    }
    // --- End Added ---


    // --- Sign In (Email/Password) ---
    func signIn(email: String, password: String) {
        // If user is currently anonymous, signing in with email/password
        // might automatically link accounts (Firebase handles this).
        isLoading = true
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] (result, error) in
            // ... (existing sign in logic) ...
             guard let self = self else { return }
             self.isLoading = false
             if let error = error {
                 self.errorMessage = "Sign In Failed: \(error.localizedDescription)"
                 print("!!! Sign In Error: \(error)")
             } else {
                 self.errorMessage = nil
                 print("Sign In Successful: \(result?.user.email ?? "No email")")
             }
        }
    }

    // --- Sign Up (Email/Password) ---
    func signUp(email: String, password: String) {
        // Signing up when anonymous *might* require explicit linking later,
        // or Firebase might handle it. Check Firebase docs for current behavior.
        isLoading = true
        errorMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] (result, error) in
           // ... (existing sign up logic) ...
             guard let self = self else { return }
             self.isLoading = false
             if let error = error {
                 self.errorMessage = "Sign Up Failed: \(error.localizedDescription)"
                 print("!!! Sign Up Error: \(error)")
             } else {
                 self.errorMessage = nil
                 print("Sign Up Successful: \(result?.user.email ?? "No email")")
                 // If needed, explicitly link anonymous account or create user doc here
             }
        }
    }

    // --- Sign Out ---
    func signOut() {
        // Signing out a non-anonymous user returns them to the "logged out" state.
        // We might want to immediately sign them back in anonymously.
        _ = Auth.auth().currentUser?.isAnonymous ?? false

        isLoading = true
        errorMessage = nil
        do {
            try Auth.auth().signOut()
            print("Sign Out Successful")
            // Now that user is nil, sign in anonymously again if they weren't already anonymous
            // This ensures they can continue browsing.
            // The listener handles the userSession update.
            // We don't need to call signInAnonymously explicitly here if the listener handles nil user state.

        } catch let signOutError as NSError {
            self.errorMessage = "Sign Out Failed: \(signOutError.localizedDescription)"
            print("!!! Sign Out Error: \(signOutError)")
        }
        isLoading = false
    }
}
