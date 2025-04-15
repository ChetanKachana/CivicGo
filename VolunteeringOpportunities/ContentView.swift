import SwiftUI

struct ContentView: View {
    // Get AuthViewModel from environment to check login state
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    // OppViewModel is also in environment, available to children

    var body: some View {
        Group { // Group allows conditional view switching
            if authViewModel.userSession != nil {
                // User is LOGGED IN - Show the main app TabView
                MainTabView()
            } else {
                // User is LOGGED OUT - Show the Authentication screen
                AuthenticationView()
            }
        }
        // ViewModels are already injected by the App struct
    }
}
