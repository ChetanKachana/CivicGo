import SwiftUI

// MARK: - Main Tab View (Favorites Tab Removed)
// The root TabView container shown after a user is authenticated.
// Favorites are now handled via filtering in OpportunityListView.
struct MainTabView: View {
    // EnvironmentObjects provided by the parent (YourAppNameApp)
    @EnvironmentObject var oppViewModel: OpportunityViewModel   // Access opportunity data
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access authentication state and role

    var body: some View {
        // TabView controlling the main sections of the app
        TabView {
            // Tab 1: Opportunities (Visible to ALL authenticated users)
            // This view will now contain the filtering logic
            NavigationView {
                OpportunityListView()
            }
            .tabItem {
                // Keep standard list icon, or use heart if preferred now? Let's keep list for now.
                Label("Opportunities", systemImage: "list.bullet.clipboard")
            }
            .tag(0) // Assign a tag for potential programmatic selection

            if authViewModel.isManager { // Only show if user is a manager
                 NavigationView {
                     MyEventsListView() // The view showing events created by the manager
                 }
                 .tabItem {
                     Label("My Events", systemImage: "person.badge.key.fill") // Icon indicating manager/created events
                 }
                 .tag(2) // Adjust tag if needed
            }


            // Tab 3 (Effectively): Profile (Visible to ALL authenticated users)
            NavigationView {
                ProfileView() // Displays user info, attendance, sign out, etc.
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(3) // Adjust tag if needed

        } // End TabView
        // Ensure ViewModels are explicitly available if direct children need them,
        // but usually environment handles it for NavigationView content.
        .environmentObject(oppViewModel)
        .environmentObject(authViewModel)
        // Optional: Animate the appearance/disappearance of My Events tab
        // .animation(.default, value: authViewModel.isManager)
    }
}

