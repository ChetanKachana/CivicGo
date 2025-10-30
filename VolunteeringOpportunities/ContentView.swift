import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        Group {
            if authViewModel.userSession != nil {
                MainTabView()
                    
            } else {
                AuthenticationView()
            }
        }
    }
}
