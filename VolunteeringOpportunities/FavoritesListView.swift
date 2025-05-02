import SwiftUI

// MARK: - Favorites List View
// Displays favorited opportunities grouped into "Currently Occurring" and "Future" sections.
// Hides expired favorited events.
struct FavoritesListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access opportunities, favorites, and actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access auth state

    // MARK: - Computed Properties for Filtering and Grouping Favorites

    // Get current date for comparisons - recalculates when the view updates
    private var now: Date { Date() }

    // 1. Get only the opportunities marked as favorite
    private var allFavoriteOpportunities: [Opportunity] {
        viewModel.opportunities.filter { opp in
            viewModel.favoriteOpportunityIds.contains(opp.id)
        }
        // Opportunities are already sorted by eventDate (ascending) from the ViewModel fetch
    }

    // 2. Filter out expired favorites (end date is in the past)
    private var nonExpiredFavorites: [Opportunity] {
        allFavoriteOpportunities.filter { $0.endDate > now }
    }

    // 3. Group into Currently Occurring Favorites (started, but not yet ended)
    private var occurringFavorites: [Opportunity] {
        nonExpiredFavorites.filter { $0.eventDate <= now }
    }

    // 4. Group into Future Favorites (start date is in the future)
    private var futureFavorites: [Opportunity] {
        nonExpiredFavorites.filter { $0.eventDate > now }
    }

    // Determine if the favorites list should be considered empty from the user's perspective
    private var isListEffectivelyEmpty: Bool {
        // True if BOTH occurring and future favorite lists are empty after filtering
        occurringFavorites.isEmpty && futureFavorites.isEmpty
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 for seamless transition to list
            // --- Conditional Content ---
            // Show empty state if no relevant favorites exist
            if isListEffectivelyEmpty {
                 emptyStateView
            }
            // --- List of Favorites with Sections ---
            else {
                 actualListView // Show the list view directly
            }
        } // End main VStack
        .navigationTitle("Favorites")
        // Add refreshable if desired for favorites view too
         .refreshable {
             print("Pull to refresh triggered on Favorites list")
             // Fetching all opportunities usually updates favorites implicitly
             // if the user document listener is working correctly.
             viewModel.fetchOpportunities()
             // If you need to explicitly refresh just the user's favorites data:
             // if let userId = authViewModel.userSession?.uid, !authViewModel.userSession!.isAnonymous {
             //     viewModel.fetchUserFavorites(userId: userId)
             // }
         }
    } // End body

    // MARK: - Extracted Subviews / Helpers

    // --- View for Empty State ---
    private var emptyStateView: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "heart.text.square.fill") // Different icon
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.7))
            Text("No Upcoming Favorites") // Updated text
                .font(.title2).fontWeight(.semibold)
            Text("Favorite upcoming events from the main list by tapping the ♡ icon.") // More specific instruction
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Spacer()
            Spacer() // Add more space at bottom
        }
        .toolbar{
            ToolbarItem(placement: .navigationBarLeading) {
                 if viewModel.isLoading { ProgressView().tint(.primary) }
                 else if authViewModel.isManager { Image(systemName: "crown.fill").foregroundColor(.orange).accessibilityLabel("Manager Access") }
             }
        }
        .padding()
    }

    // --- The Actual List View Content with Sections ---
    private var actualListView: some View {
        List {
            // --- Currently Occurring Section ---
            if !occurringFavorites.isEmpty {
                Section("Currently Ongoing") {
                    ForEach(occurringFavorites) { opportunity in
                        listRowNavigationLink(for: opportunity) // Use helper
                    }
                }
            }

            // --- Future Section ---
            if !futureFavorites.isEmpty {
                Section("Future Events") {
                    ForEach(futureFavorites) { opportunity in
                        listRowNavigationLink(for: opportunity) // Use helper
                    }
                }
            }
        } // End List
        .listStyle(.insetGrouped) // Use insetGrouped style for consistency
    }

    // --- Helper: Creates the NavigationLink row content ---
    // (Identical helper function as in OpportunityListView)
    // Inside OpportunityListView.swift (and Favorites/MyEvents)

    @ViewBuilder
    private func listRowNavigationLink(for opportunity: Opportunity) -> some View {
        // Use ZStack for whole-row tappability
        ZStack(alignment: .leading) {
             // Invisible NavigationLink layer
             NavigationLink {
                 OpportunityDetailView(opportunity: opportunity).environmentObject(viewModel).environmentObject(authViewModel)
             } label: { EmptyView() }.opacity(0)
             // Visible Row Content (uses the OpportunityRowView which includes the .id modifier)
            OpportunityRowView(opportunity: opportunity).environmentObject(viewModel).environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)) // Consistent row padding
    }
} // End struct FavoritesListView
