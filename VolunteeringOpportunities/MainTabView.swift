import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var oppViewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        TabView {
            // Opportunities Tab
            NavigationView { OpportunityListView() }
                .tabItem { Label("Opportunities", systemImage: "list.bullet.clipboard") }

            // --- ADDED BACK: Conditional Favorites Tab ---
            if let user = authViewModel.userSession, !user.isAnonymous {
                NavigationView { FavoritesListView() } // Use the re-created view
                    .tabItem { Label("Favorites", systemImage: "heart.fill") }
            }
            // --- End ADDED BACK ---

            // Profile Tab
            NavigationView { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
         // Inject models for all tabs and their children
         .environmentObject(oppViewModel)
         .environmentObject(authViewModel)
    }
}

// MARK: - Profile View (Simple Example)
struct ProfileView: View {
     @EnvironmentObject var authViewModel: AuthenticationViewModel
     // State to control presentation of the Authentication sheet
     @State private var showAuthSheet = false

     var body: some View {
         VStack(spacing: 30) { // Increased spacing

             if let user = authViewModel.userSession {
                 // --- Content based on User Type ---
                 if user.isAnonymous {
                     // --- Anonymous User View ---
                     Image(systemName: "person.crop.circle.badge.questionmark")
                         .font(.system(size: 80))
                         .foregroundColor(.orange)
                     Text("Browsing Anonymously")
                         .font(.title2)
                     Text("Log in or sign up to save favorites and create opportunities.")
                         .font(.subheadline)
                         .foregroundColor(.secondary)
                         .multilineTextAlignment(.center)
                         .padding(.horizontal)

                     Button {
                         showAuthSheet = true // Show the login/signup sheet
                     } label: {
                         Text("Log In / Sign Up")
                             .padding(.horizontal, 30) // Make button wider
                     }
                     .buttonStyle(.borderedProminent)
                     .tint(.blue) // Use a standard tint

                 } else {
                     // --- Logged-in User View ---
                     Image(systemName: "person.crop.circle.fill")
                         .font(.system(size: 80))
                         .foregroundColor(.green) // Indicate logged-in status
                     Text(user.email ?? "Email not available") // Show email
                         .font(.title2)

                     // Loading / Sign Out Button
                     if authViewModel.isLoading && authViewModel.userSession != nil { // Show Progress only if related to sign out
                         ProgressView("Signing Out...")
                     } else {
                         Button("Sign Out", role: .destructive) {
                             authViewModel.signOut()
                         }
                         .buttonStyle(.borderedProminent)
                     }
                 }
             } else {
                 // --- Should ideally not happen with anonymous sign-in ---
                 // Shows if initial anonymous sign-in failed
                 Image(systemName: "exclamationmark.triangle")
                     .font(.system(size: 80))
                     .foregroundColor(.red)
                 Text("Not Connected")
                     .font(.title2)
                 Text("Could not establish a session. Please check your connection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                 Button("Retry Connection") {
                     authViewModel.signInAnonymously() // Try anonymous again
                 }
                 .buttonStyle(.bordered)
             }

             Spacer() // Push content up

             // Display general errors (like sign out failure)
             if let errorMessage = authViewModel.errorMessage {
                 Text(errorMessage)
                     .foregroundColor(.red)
                     .font(.caption)
                     .multilineTextAlignment(.center)
                     .padding(.top)
             }
         }
         .padding()
         .navigationTitle("Profile")
         // --- Sheet for Authentication ---
         .sheet(isPresented: $showAuthSheet) {
             // Present the existing AuthenticationView modally
             AuthenticationView()
                 .environmentObject(authViewModel) // Pass the VM
                 // Optional: Add presentation detents for partial sheet
                 // .presentationDetents([.medium, .large])
                 .presentationDetents([.large, .fraction(0.999)])
         }
     }
}
