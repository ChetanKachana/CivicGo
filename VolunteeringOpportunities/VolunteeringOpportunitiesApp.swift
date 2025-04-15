import SwiftUI
import FirebaseCore // Import Firebase Core

// --- AppDelegate for Firebase Initialization ---
// This class handles the setup of Firebase when the app launches.
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // Configure Firebase using the GoogleService-Info.plist file
    FirebaseApp.configure()
    print("Firebase Configured via AppDelegate!")
    return true
  }
}

// --- Main Application Struct ---
@main // Marks this as the entry point of the application
struct YourAppNameApp: App { // Replace YourAppNameApp with your actual app name

  // Register the AppDelegate class to ensure Firebase gets configured
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  // --- State Objects for ViewModels ---
  // Use @StateObject to create and manage the lifecycle of these ViewModels.
  // They will persist for the life of the app scene.

  // Manages user authentication state (login, signup, anonymous, session)
  @StateObject var authViewModel = AuthenticationViewModel()

  // Manages volunteering opportunity data (fetching, favorites based on auth state)
  @StateObject var opportunityViewModel = OpportunityViewModel()

  // MARK: - Body
  // Defines the app's scene structure
  var body: some Scene {
    WindowGroup {
       // The root view of the application
       ContentView()
         // Inject both ViewModels into the SwiftUI environment,
         // making them accessible to ContentView and its descendants.
         .environmentObject(authViewModel)
         .environmentObject(opportunityViewModel)
         // Perform setup actions when the ContentView first appears.
         .onAppear {
              // --- REMOVED AUTOMATIC ANONYMOUS SIGN-IN ---
              // We no longer automatically sign in the user anonymously on launch.
              // The user will be presented with AuthenticationView if no session exists.
              // authViewModel.signInAnonymously() // <-- This line was removed

              // --- Setup Link Between ViewModels ---
              // Tell the OpportunityViewModel to start observing changes
              // in the AuthenticationViewModel's user session. This triggers
              // appropriate data fetching (opportunities, favorites) based on auth state.
              opportunityViewModel.setupUserObservations(authViewModel: authViewModel)
              print("App appeared, OpportunityViewModel observations set up.")
         }
    }
  }
}
