import SwiftUI
import FirebaseCore 


class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    print("Firebase Configured via AppDelegate!")
    return true
  }
}

@main
struct VolunteeringOpportunitiesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var authViewModel = AuthenticationViewModel()
    @StateObject var opportunityViewModel = OpportunityViewModel()
 

    @Environment(\.scenePhase) var scenePhase

    init() {
        let oppVM = OpportunityViewModel()
        _opportunityViewModel = StateObject(wrappedValue: oppVM)
        _authViewModel = StateObject(wrappedValue: AuthenticationViewModel())
        
    }

    var body: some Scene {
        WindowGroup {
           ContentView()
             .environmentObject(authViewModel)
             .environmentObject(opportunityViewModel)
             .onAppear {
                  opportunityViewModel.setupAuthObservations(authViewModel: authViewModel)
                  print("App ContentView appeared, OpportunityViewModel auth observations set up.")
             }
            
        }
    }
}
