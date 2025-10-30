import SwiftUI

// MARK: - Favorites List View
struct FavoritesListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // MARK: - Computed Properties for Filtering and Grouping Favorites

    private var now: Date { Date() }

    private var allFavoriteOpportunities: [Opportunity] {
        viewModel.opportunities.filter { opp in
            viewModel.favoriteOpportunityIds.contains(opp.id)
        }
    }

    private var nonExpiredFavorites: [Opportunity] {
        allFavoriteOpportunities.filter { $0.endDate > now }
    }

    private var occurringFavorites: [Opportunity] {
        nonExpiredFavorites.filter { $0.eventDate <= now }
    }

    private var futureFavorites: [Opportunity] {
        nonExpiredFavorites.filter { $0.eventDate > now }
    }

    private var isListEffectivelyEmpty: Bool {
        occurringFavorites.isEmpty && futureFavorites.isEmpty
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if isListEffectivelyEmpty {
                 emptyStateView
            }
            else {
                 actualListView
            }
        }
        .navigationTitle("Favorites")
        
         .refreshable {
             print("Pull to refresh triggered on Favorites list")
             viewModel.fetchOpportunities()
         }
    }

    // MARK: - Extracted Subviews / Helpers

    private var emptyStateView: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.7))
            Text("No Upcoming Favorites")
                .font(.title2).fontWeight(.semibold)
            Text("Favorite upcoming events from the main list by tapping the ♡ icon.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .toolbar{
            ToolbarItem(placement: .navigationBarLeading) {
                 if viewModel.isLoading { ProgressView().tint(.primary) }
                 else if authViewModel.isManager { Image(systemName: "crown.fill").foregroundColor(.indigo).accessibilityLabel("Manager Access") }
             }
        }
        .padding()
    }

    private var actualListView: some View {
        List {
            if !occurringFavorites.isEmpty {
                Section("Currently Ongoing") {
                    ForEach(occurringFavorites) { opportunity in
                        listRowNavigationLink(for: opportunity)
                    }
                }
            }

            if !futureFavorites.isEmpty {
                Section("Future Events") {
                    ForEach(futureFavorites) { opportunity in
                        listRowNavigationLink(for: opportunity)
                    }
                }
            }
        }
        
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func listRowNavigationLink(for opportunity: Opportunity) -> some View {
        ZStack(alignment: .leading) {
             NavigationLink {
                 OpportunityDetailView(opportunity: opportunity).environmentObject(viewModel).environmentObject(authViewModel)
             } label: { EmptyView() }.opacity(0)
            OpportunityRowView(opportunity: opportunity).environmentObject(viewModel).environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
    }
}
