import SwiftUI

// MARK: - Main Tab View (Favorites Tab Removed)

struct MainTabView: View {
    @EnvironmentObject var oppViewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        TabView {
            
            NavigationView {
                OpportunityListView()
            }
            .tabItem {
                Label("Opportunities", systemImage: "list.bullet.clipboard")
            }
            .tag(0)
            
            if authViewModel.isManager {
                NavigationView {
                    MyEventsListView()
                }
                .tabItem {
                    Label("My Events", systemImage: "person.badge.key.fill")
                }
                .tag(2)
            }
            
            
            NavigationView {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(3)
            
        }
        .environmentObject(oppViewModel)
        .environmentObject(authViewModel)
    }
    }

