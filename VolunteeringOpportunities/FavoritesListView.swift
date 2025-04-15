import SwiftUI

// MARK: - Favorites List View (Reintroduced)
// Displays opportunities that the logged-in user has marked as favorite.
struct FavoritesListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access opportunities and favorite IDs
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Needed by OpportunityRowView

    // MARK: - Computed Properties
    // Filter the main opportunities list based on the favoriteOpportunityIds set
    private var favoriteOpportunities: [Opportunity] {
        viewModel.opportunities.filter { opp in
            // Check if the opportunity's ID exists in the favorites set
            viewModel.isFavorite(opportunityId: opp.id)
        }
        // Sort the resulting favorites list by event date
         .sorted { $0.eventDate < $1.eventDate }
    }

    // MARK: - Body
    var body: some View {
        VStack {
            // --- Empty State ---
            if favoriteOpportunities.isEmpty {
                 VStack(spacing: 15) {
                     Image(systemName: "heart.slash.fill") // Icon for empty favorites
                         .font(.system(size: 60))
                         .foregroundColor(.secondary.opacity(0.7))
                     Text("No Favorites Yet")
                         .font(.title2).fontWeight(.semibold)
                     Text("Tap the ♡ icon on an opportunity in the main list to save it here.") // Updated text
                         .font(.subheadline)
                         .multilineTextAlignment(.center)
                         .foregroundColor(.secondary)
                         .padding(.horizontal, 40)
                     Spacer()
                 }
                 .padding(.top, 80)
            }
            // --- List of Favorites ---
            else {
                 List {
                     ForEach(favoriteOpportunities) { opportunity in
                         NavigationLink {
                             // Destination View
                             OpportunityDetailView(opportunity: opportunity)
                                 // Pass EnvironmentObjects if DetailView needs them
                                 // .environmentObject(viewModel)
                                 // .environmentObject(authViewModel)
                         } label: {
                             // Row Content View
                             OpportunityRowView(opportunity: opportunity)
                             // Provide VMs needed by OpportunityRowView via environment
                             .environmentObject(viewModel)
                             .environmentObject(authViewModel)
                         }
                         .buttonStyle(PlainButtonStyle())
                         // --- Removed listRowBackground for RSVP coloring ---
                     } // End ForEach
                 } // End List
                 .listStyle(PlainListStyle())
            } // End else (List Display)
        } // End main VStack
        .navigationTitle("Favorites") // Set the title for the navigation bar
    } // End body
} // End struct FavoritesListView


