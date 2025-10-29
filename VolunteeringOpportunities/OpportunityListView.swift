import SwiftUI

// MARK: - Combined Search Result Enum (Defined at File Level with Manual Hashable)
enum SearchResult: Identifiable, Hashable { // Still declare conformance
    case opportunity(Opportunity)
    case manager(ManagerInfo)

    var id: String {
        switch self {
        case .opportunity(let opp): return "opp_\(opp.id)"
        case .manager(let mgr): return "mgr_\(mgr.id)"
        }
    }

    // --- Manually Implement Hashable ---
    func hash(into hasher: inout Hasher) {
        switch self {
        case .opportunity(let opp):
            hasher.combine(0) // Unique value for this case
            hasher.combine(opp) // Combine the associated value
        case .manager(let mgr):
            hasher.combine(1) // Different unique value for this case
            hasher.combine(mgr) // Combine the associated value
        }
    }

    // Manually Implement Equatable for clarity and robustness
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
         switch (lhs, rhs) {
         case (.opportunity(let lhsOpp), .opportunity(let rhsOpp)):
             return lhsOpp == rhsOpp // Relies on Opportunity's Equatable
         case (.manager(let lhsMgr), .manager(let rhsMgr)):
             return lhsMgr == rhsMgr // Relies on ManagerInfo's Equatable
         default:
             return false // Different enum cases are never equal
         }
     }
    // --- End Manual Implementation ---


    // Helper properties
    var opportunity: Opportunity? {
        guard case .opportunity(let opp) = self else { return nil }
        return opp
    }
    var manager: ManagerInfo? {
         guard case .manager(let mgr) = self else { return nil }
         return mgr
     }
}


// MARK: - Opportunity List View (Background Logic in List)
struct OpportunityListView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var showingCreateSheet = false
    @State private var showingLeaderboardSheet = false

    @State private var selectedFilter: EventFilter = .all
    @State private var searchText: String = ""
    // --- State for Custom Search ---
    @State private var isSearching: Bool = false // Track if search UI is active
    @FocusState private var searchTextFieldIsFocused: Bool // Focus for the custom TextField
    // --- End State ---

    @Namespace private var filterAnimation

    // Defines filters applied *only* when search is inactive
    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case available = "Available"
        case attending = "Attending"
        case favorites = "Favorites"
        var id: String { self.rawValue }
    }

    // MARK: - Computed Properties for Filtering, Searching, Grouping

    private var now: Date { Date() }
    private var calendar: Calendar { Calendar.current }

    // Check if the current user is logged in and not anonymous
    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    // --- Properties for NON-SEARCHING state ---

    // 1. Filter opportunities based on the selectedFilter state
    private var filteredOpportunities: [Opportunity] {
        let baseList = viewModel.opportunities
        // No need for isLoggedInUser check here, handled by filter cases

        switch selectedFilter {
        case .all:
            return baseList
        case .available:
            return baseList.filter { !$0.hasEnded && !$0.isFull }
        case .attending:
            guard isLoggedInUser, let uid = authViewModel.userSession?.uid else { return [] }
            return baseList.filter { viewModel.rsvpedOpportunityIds.contains($0.id) }
        case .favorites:
            guard isLoggedInUser, let uid = authViewModel.userSession?.uid else { return [] }
            return baseList.filter { viewModel.favoriteOpportunityIds.contains($0.id) }
        }
    }

    // 2. Group filtered opportunities for display when NOT searching
    private var nonExpiredFilteredOpportunities: [Opportunity] {
        filteredOpportunities.filter { $0.endDate > now }.sorted { $0.eventDate < $1.eventDate }
    }
    private var occurringFilteredOpportunities: [Opportunity] {
        nonExpiredFilteredOpportunities.filter { $0.eventDate <= now }
    }
    private var futureFilteredOpportunitiesByDate: [Date: [Opportunity]] {
        let futureEvents = nonExpiredFilteredOpportunities.filter { $0.eventDate > now }
        return Dictionary(grouping: futureEvents) { calendar.startOfDay(for: $0.eventDate) }
    }
    private var sortedFutureFilteredDates: [Date] {
        futureFilteredOpportunitiesByDate.keys.sorted()
    }

    // --- Properties for SEARCHING state ---

    // 3. Filter managers based on search text
    private var searchedManagers: [ManagerInfo] {
        guard !searchText.trimmed().isEmpty else { return [] }
        let lowercasedSearchText = searchText.trimmed().lowercased()
        return viewModel.managers.filter { mgr in
            mgr.username.lowercased().contains(lowercasedSearchText)
        }
    }

    // 4. Filter opportunities based on search text
    private var searchedOpportunities: [Opportunity] {
         guard !searchText.trimmed().isEmpty else { return [] }
         let lowercasedSearchText = searchText.trimmed().lowercased()
         return viewModel.opportunities.filter { opp in
             opp.name.lowercased().contains(lowercasedSearchText) ||
             opp.location.lowercased().contains(lowercasedSearchText) ||
             opp.description.lowercased().contains(lowercasedSearchText)
         }
         .sorted { $0.eventDate < $1.eventDate } // Sort search results chronologically
     }

    // --- General Computed Properties ---

    // Determine if the list should be considered empty based on search state
    private var isListEffectivelyEmpty: Bool {
        if isSearching {
            return searchedManagers.isEmpty && searchedOpportunities.isEmpty
        } else {
            return occurringFilteredOpportunities.isEmpty && sortedFutureFilteredDates.isEmpty
        }
    }

    // Should the Attending/Favorites filters be shown?
    private var showUserSpecificFilters: Bool {
        isLoggedInUser // Use the helper computed property
    }

    // MARK: - Formatter
    private static var sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) { // Main container

            // --- Conditional Top Bar: Filter/Search Button OR Search Field ---
            if isSearching {
                searchFieldBar // Show TextField and Cancel
                    .padding(.horizontal)
                    .padding(.vertical, 8) // Vertical padding for search bar area
                    .transition(.move(edge: .top).combined(with: .opacity)) // Animate appearance
            } else {
                filterBarAndSearchButton // Show Filter Pills and Search Icon
                    .padding(.horizontal)
                    .padding(.top, 8)      // Padding above filter bar when visible
                    .padding(.bottom, 10)   // Padding below filter bar when visible
                    .transition(.move(edge: .top).combined(with: .opacity)) // Animate appearance
            }
            // --- End Conditional Top Bar ---

            // Divider only shown when filter bar is visible
            Divider().opacity(isSearching ? 0 : 1)
                 .animation(.easeInOut(duration: 0.2), value: isSearching) // Animate divider fade

            // --- Conditional Content Area ---
            Group {
                // Show loading if either opportunities or managers are initially loading or actively loading
                if viewModel.isLoading || (viewModel.isLoadingManagers && viewModel.managers.isEmpty && viewModel.opportunities.isEmpty) {
                     loadingView
                 } else if let errorMessage = viewModel.errorMessage {
                     errorView(message: errorMessage) // Display errors
                 } else if isListEffectivelyEmpty {
                      // Show empty state based on search/filter context
                       emptyStateView(for: selectedFilter, isSearching: isSearching)
                 } else {
                     actualListView // Show the main list content
                 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow content to expand

        } // End main VStack
        .navigationTitle("Volunteering")
        .navigationBarTitleDisplayMode(.inline) // <--- ADD THIS LINE to make the title sticky
        
        .toolbar { // --- Toolbar ---
            ToolbarItem(placement: .navigationBarLeading) { leaderboardButton }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Loading indicator OR Manager Crown
                // Show loading indicator if either list is currently loading
                if viewModel.isLoading || viewModel.isLoadingManagers { ProgressView().tint(.primary) }
                else if authViewModel.isManager { Image(systemName: "crown.fill").foregroundColor(.indigo).accessibilityLabel("Manager Access") }

                if authViewModel.isManager { // Add Button
                    Button { showingCreateSheet = true } label: { Label("Add Opportunity", systemImage: "plus.circle.fill") }
                         .accessibilityLabel("Add New Opportunity")
                         //.font(.system(size:50))
                         
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
             CreateOpportunityView(opportunityToEdit: nil)
                 .environmentObject(viewModel).environmentObject(authViewModel)
         }
        .sheet(isPresented: $showingLeaderboardSheet) {
             LeaderboardView()
                 .environmentObject(authViewModel).environmentObject(viewModel)
         }
        .refreshable { // Keep Pull-to-refresh
             print("Pull to refresh triggered")
             await viewModel.fetchOpportunities()
             await viewModel.fetchManagers()
         }
         .task { // Keep initial fetch task
             // Data fetching is now primarily triggered by auth state changes in setupAuthObservations
             // This .task might be redundant if setupAuthObservations covers the initial load.
             // However, keeping it can act as a fallback if the view appears before auth state settles.
             print("OpportunityListView .task modifier.")
              // Consider adding checks to prevent redundant fetches if data already exists
              if viewModel.opportunities.isEmpty {
                  print("  -> Fetching initial opportunities.")
                  await viewModel.fetchOpportunities()
              }
              if viewModel.managers.isEmpty {
                   print("  -> Fetching initial managers.")
                   await viewModel.fetchManagers()
              }
         }
        // Animate changes based on the current display mode (searching or filtering)
        .animation(.default, value: isSearching)
        .animation(.default, value: selectedFilter)
        // Animate based on the data source driving the list
        .animation(.default, value: isSearching ? searchedOpportunities : filteredOpportunities)
        .animation(.default, value: isSearching ? searchedManagers : [])


    } // End body


    // MARK: - Helper Function for Row Background
    @ViewBuilder // Use ViewBuilder to allow returning different View types (Color or nil)
    private func backgroundForRow(for opportunity: Opportunity) -> some View {
        // Priority: Occurring > Attending > Favorited > Default
        // Access viewModel and authViewModel directly as they are EnvironmentObjects
        if opportunity.isCurrentlyOccurring {
            // Static Yellow - re-add pulsing animation logic here if desired
            AnimatedWaveBackgroundView(
                            startTime: opportunity.eventDate, // Pass start time
                            endTime: opportunity.endDate,      // Pass end time
                            baseColor: .mint// baseColor can be customized here if needed: baseColor: .orange
                        )
            
        } else if isLoggedInUser && viewModel.isRsvped(opportunityId: opportunity.id) {
            // Attending Background (Green)
            Color.green.opacity(0.15)
        } else if isLoggedInUser && viewModel.isFavorite(opportunityId: opportunity.id) {
            // Favorited Background (Red)
            AnimatedMeshBackgroundView(
                colors: [.red, .pink, .red.opacity(0.3)]
                        )
        } else {
            // Default Background (let the List decide)
            Color(UIColor.secondarySystemGroupedBackground)
        }
    }


    // MARK: - Extracted View Builders for UI Components

    /// Builds the bar showing filter pills and the search activation button.
    @ViewBuilder private var filterBarAndSearchButton: some View {
        HStack(spacing: 8) { // Add spacing between scroll view and button
            
                HStack(spacing: 0) { // Use 0 spacing inside, padding handles gaps
                    ForEach(EventFilter.allCases) { filter in
                        // Conditionally display user-specific filters
                        if filter == .all || filter == .available || showUserSpecificFilters {
                            filterButton(for: filter)
                                .padding(.horizontal, 2) // Spacing BETWEEN buttons
                        }
                    }
                }
                .padding(.horizontal, 4) // Padding inside scroll view edges
            // Constrain scroll view height
            Spacer()
            // Search Activation Button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = true // Activate search mode
                }
                // Delay focus slightly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    searchTextFieldIsFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(5) // Slightly larger tap area
            }
            .buttonStyle(.plain) // Remove default button chrome

        }
        // Optional background for the filter bar area
        // .padding(.vertical, 2)
        // .background( Capsule().fill(Color(.systemGray6)) )
         .onChange(of: authViewModel.userSession) { _, newUserSession in // Reset filter on logout/anon
               if (newUserSession == nil || newUserSession!.isAnonymous) && (selectedFilter == .favorites || selectedFilter == .attending) {
                   selectedFilter = .all
               }
          }
         .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3), value: selectedFilter) // Animate filter selection
    }

    /// Builds the search text field bar with a Cancel button.
    @ViewBuilder private var searchFieldBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary) // Search icon

            TextField("Search Events & Organizations...", text: $searchText)
                .focused($searchTextFieldIsFocused) // Bind focus state
                .textFieldStyle(.plain)
                .submitLabel(.search) // Keyboard return key type
                .onSubmit { // Action for return key
                    print("Search submitted: \(searchText)")
                    hideKeyboard()
                }

            // Clear button ('x') appears only when text field has content
            if !searchText.isEmpty {
                Button {
                    searchText = "" // Clear the text
                    searchTextFieldIsFocused = true // Keep focus
                } label: {
                    Image(systemName: "multiply.circle.fill")
                        .foregroundColor(.gray.opacity(0.6)) // Make it slightly subtle
                }
                .buttonStyle(.plain)
                .padding(.trailing, -2) // Adjust spacing if needed
            }

            // Cancel Button to exit search mode
            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false // Deactivate search mode
                    searchText = ""     // Clear text
                    hideKeyboard()
                }
            }
            .buttonStyle(.borderless) // Simple text appearance
            .foregroundColor(.accentColor)
        }
    }

    /// Builds a single filter button.
    private func filterButton(for filter: EventFilter) -> some View {
        Button {
            // Action: Update filter state, clear search, dismiss keyboard/focus
            selectedFilter = filter
            searchText = ""
            searchTextFieldIsFocused = false
            hideKeyboard()
            print("Filter selected: \(filter.rawValue)")
        } label: {
            if filter == .favorites {
                 Image(systemName: "heart.fill")
                     .foregroundColor(selectedFilter == filter ? .red : .gray)
                     .padding(.vertical, 6).padding(.horizontal, 14)
                     .background { // Animated highlight capsule
                         if selectedFilter == filter {
                             Capsule().fill(Color(.systemGray4)).matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                         } else {
                             Capsule().fill(Color(.systemGray6)) // Default background
                         }
                     }
                      .clipShape(Capsule()) // Ensure correct shape
            } else {
                 Text(filter.rawValue)
                     .font(.system(size: 14, weight: .medium))
                     .padding(.vertical, 6).padding(.horizontal, 14)
                     .background { // Animated highlight capsule
                         if selectedFilter == filter {
                             Capsule().fill(Color(.systemGray4)).matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                         } else {
                             Capsule().fill(Color(.systemGray6))
                         }
                     }
                      .clipShape(Capsule())
                     .foregroundColor(selectedFilter == filter ? Color(.label) : Color(.secondaryLabel)) // Adapt text color
            }
        }
        .buttonStyle(.plain) // Remove default button interaction visuals
    }

    /// Builds the Leaderboard button.
    private var leaderboardButton: some View {
         Button { showingLeaderboardSheet = true } label: { Label("Leaderboard", systemImage: "trophy.fill") }
         .accessibilityLabel("View Leaderboard")
     }

    /// Builds the view shown during initial loading.
    private var loadingView: some View {
        VStack { Spacer(); ProgressView("Loading...").padding(.bottom, 50); Spacer() }
    }

    /// Builds the view shown when a data fetching error occurs.
    private func errorView(message: String) -> some View {
        VStack(spacing: 15) {
             Spacer(); Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 50)).foregroundColor(.red)
             Text("Error Loading Data").font(.headline)
             Text(message).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button {
                 print("Retry Fetch tapped.")
                 Task {
                     await viewModel.fetchOpportunities()
                     await viewModel.fetchManagers()
                 }
             } label: { Label("Retry Fetch", systemImage: "arrow.clockwise") }
                 .buttonStyle(.borderedProminent).tint(.orange).padding(.top)
                 .disabled(viewModel.isLoading || viewModel.isLoadingManagers)
             Spacer()
         }.padding()
    }

    /// Builds the view shown when the list is empty (message varies).
    private func emptyStateView(for filter: EventFilter, isSearching: Bool) -> some View {
        VStack(spacing: 15) {
             Spacer()
             Image(systemName: isSearching ? "magnifyingglass" : emptyStateIcon(for: filter))
                 .font(.system(size: 60)).foregroundColor(.secondary.opacity(0.7))
             Text(isSearching ? "No Results Found" : emptyStateTitle(for: filter))
                 .font(.title2).fontWeight(.semibold).padding(.horizontal).multilineTextAlignment(.center)
             Text(isSearching ? "Try different search terms for events or organizations." : emptyStateSubtitle(for: filter))
                 .font(.subheadline).foregroundColor(.secondary)
                 .multilineTextAlignment(.center).padding(.horizontal, 40)
             // Only show Check Again if not searching
             if !isSearching {
                  Button { print("Check Again tapped."); Task { await viewModel.fetchOpportunities(); await viewModel.fetchManagers() } }
                  label: { Label("Check Again", systemImage: "arrow.clockwise") }
                  .buttonStyle(.bordered).padding(.top)
                  .disabled(viewModel.isLoading || viewModel.isLoadingManagers)
             }
            Spacer()
            Spacer() // Extra spacer for better vertical centering
         }.padding()
    }
    // Helpers for emptyStateView content
     private func emptyStateIcon(for filter: EventFilter) -> String {
         filter == .favorites ? "heart.slash.fill" : (filter == .attending ? "person.crop.circle.badge.checkmark" : "calendar.badge.exclamationmark")
     }
     private func emptyStateTitle(for filter: EventFilter) -> String {
         filter == .favorites ? "No Upcoming Favorites" : (filter == .attending ? "Not Attending Any Events" : (filter == .available ? "No Available Spots" : "No Upcoming Opportunities"))
     }
     private func emptyStateSubtitle(for filter: EventFilter) -> String {
         filter == .favorites ? "Favorite upcoming events to see them here." : (filter == .attending ? "RSVP to events to see them in this list." : (filter == .available ? "There are no upcoming events with available spots right now." : (authViewModel.isManager ? "Tap '+' to add an event!" : "Check back later or try a different filter.")))
     }


    /// Builds the main List view content, adapting to search state & APPLYING BACKGROUND
    private var actualListView: some View {
        List {
            // --- Conditional Sections based on Search State ---
            if isSearching { // <<-- Check isSearching state
                // --- SEARCHING STATE ---
                if !searchedManagers.isEmpty {
                    Section("Organizations / Managers") {
                        ForEach(searchedManagers) { manager in
                            managerRowLink(for: manager)
                                // Ensure manager rows have default background
                                .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                        }
                    }
                }

                if !searchedOpportunities.isEmpty {
                    Section(searchedManagers.isEmpty ? "Search Results" : "Matching Events") {
                         ForEach(searchedOpportunities) { opportunity in
                             listRowNavigationLink(for: opportunity)
                                 // Apply dynamic background to opportunity rows
                                 .listRowBackground(backgroundForRow(for: opportunity))
                         }
                    }
                }
                // If both are empty, the main emptyStateView will be shown

            } else {
                // --- NOT SEARCHING STATE (Filter Bar Active) ---
                if !occurringFilteredOpportunities.isEmpty {
                    Section("Currently Occurring") {
                        ForEach(occurringFilteredOpportunities) { opportunity in
                            listRowNavigationLink(for: opportunity)
                                .listRowBackground(backgroundForRow(for: opportunity))
                        }
                    }
                }

                ForEach(sortedFutureFilteredDates, id: \.self) { date in
                    if let opportunitiesForDate = futureFilteredOpportunitiesByDate[date], !opportunitiesForDate.isEmpty {
                        Section {
                            ForEach(opportunitiesForDate) { opportunity in
                                listRowNavigationLink(for: opportunity)
                                    .listRowBackground(backgroundForRow(for: opportunity))
                            }
                        } header: {
                            Text(date, formatter: Self.sectionDateFormatter)
                        }
                    }
                } // End ForEach over future dates
            } // End Conditional Sections
        } // End List
        .listStyle(.insetGrouped) // Use insetGrouped style for sections
        .scrollDismissesKeyboard(.interactively)
       
    } // End actualListView

    /// Helper: Creates NavigationLink for Opportunity rows.
    @ViewBuilder
    private func listRowNavigationLink(for opportunity: Opportunity) -> some View {
        ZStack(alignment: .leading) {
             NavigationLink {
                 OpportunityDetailView(opportunity: opportunity)
                     .environmentObject(viewModel).environmentObject(authViewModel)
             } label: { EmptyView() }.opacity(0) // Invisible navigation target
             // Visible row content
             OpportunityRowView(opportunity: opportunity)
                 .environmentObject(viewModel).environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)) // Consistent padding
    }

    /// Helper: Creates NavigationLink for Manager rows.
    @ViewBuilder
    private func managerRowLink(for manager: ManagerInfo) -> some View {
        ZStack(alignment: .leading) {
             NavigationLink {
                 ManagerProfileView(managerUserIdToView: manager.id) // Pass the specific ID to view
                     .environmentObject(authViewModel)
                     .environmentObject(viewModel) // Pass OpportunityViewModel
             } label: { EmptyView() }.opacity(0)
             // Visible row content
             ManagerRowView(managerInfo: manager)
                .environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)) // Consistent padding
    }

    // MARK: - Helper Functions
    /// Helper to dismiss the keyboard.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

} // End struct OpportunityListView


// MARK: - Manager Row View (for Search Results)
struct ManagerRowView: View {
    let managerInfo: ManagerInfo
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        HStack {
            // Manager Logo (Async)
            AsyncImage(url: URL(string: managerInfo.logoImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                         .frame(width: 40, height: 40).clipShape(Circle())
                default: // Empty or Failure state
                     Image(systemName: "person.crop.circle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40).foregroundColor(.secondary)
                }
            }

            // Manager Username
            Text(managerInfo.username).font(.headline)
            Spacer()
            // Indicate if this row points to the current logged-in user's own profile
            if managerInfo.id == authViewModel.userSession?.uid {
                  Image(systemName: "crown.fill").foregroundColor(.indigo)
                     .accessibilityLabel("Your Manager Profile")
            }
        }
        .padding(.vertical, 4) // Add slight vertical padding inside row
    }
}

// MARK: - String Extension (Ensure defined once in your project)
extension String {
    /// Returns a new string made by removing whitespace and newline characters
    /// from both ends of the receiver.
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}
 
#Preview {
          OpportunityListView()
       }
