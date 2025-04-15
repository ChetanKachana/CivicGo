import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var showLogin = true // Start with Login view displayed

    var body: some View {
        VStack {
            // App Logo or Title
            Text("Volunteer App")
                .font(.system(size: 40, weight: .bold, design: .rounded)) // Example styling
                .padding(.vertical, 40)

            // Login/Signup Form Area
            if showLogin {
                LoginView(showLogin: $showLogin)
                    .environmentObject(authViewModel)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))) // Add transition
            } else {
                SignupView(showLogin: $showLogin)
                    .environmentObject(authViewModel)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) // Add transition
            }
              // Animate the switch

            Spacer() // Push buttons towards bottom

            // --- ADDED: Browse Anonymously Button ---
            VStack { // Group button and potential loading indicator
                if authViewModel.isLoading && authViewModel.userSession == nil {
                    // Show loading only if specifically triggered by anon sign-in
                    // This check prevents showing loading during email/pass attempts
                    ProgressView()
                } else {
                    Button {
                        authViewModel.signInAnonymously() // Call the anonymous sign-in function
                    } label: {
                        Text("Browse as Guest")
                    }
                    // Use a less prominent style
                    .buttonStyle(.bordered)
                    .tint(.secondary) // Gray tint
                }
            }
            .padding(.bottom, 30) // Add some bottom padding
            // --- End ADDED ---

        }
        .padding() // Padding for the outer VStack
        // Add background?
        // .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
