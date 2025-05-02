import SwiftUI

// MARK: - Opportunity List View (Custom Filter Bar & Search & Attending Filter)
// Displays opportunities grouped by time/date. Includes a custom capsule-style
// filter bar, search functionality, and a button to present the Leaderboard.
// Uses .id() modifier on rows to ensure RSVP status updates immediately.
struct OpportunityListView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access opportunity data, state, and actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access auth state and manager role
    @State private var showingCreateSheet = false                  // Controls presentation of the create sheet
    @State private var showingLeaderboardSheet = false             // Controls presentation of the leaderboard sheet

    // State for the selected filter option
    @State private var selectedFilter: EventFilter = .all
    // State for the search text entered by the user
    @State private var searchText: String = ""
    // Focus state to manage the search text field focus and trigger UI changes
    @FocusState private var searchFieldIsFocused: Bool

    // Animation namespace for the filter highlight capsule
    @Namespace private var filterAnimation

    // Enum defining the available filter options - includes Attending
    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case available = "Available" // Not full & not ended
        case attending = "Attending" // RSVP'd events
        case favorites = "Favorites"
        var id: String { self.rawValue } // Conformance to Identifiable using rawValue
    }

    // MARK: - Computed Properties for Filtering, Searching, and Grouping

    // Get current date/calendar for time comparisons
    private var now: Date { Date() }
    private var calendar: Calendar { Calendar.current }

    // 1. Filter opportunities based on the selectedFilter state
    private var filterResults: [Opportunity] {
        let baseList = viewModel.opportunities // Start with all loaded opportunities
        let userId = authViewModel.userSession?.uid // Needed for favorites/attending check

        // Ensure user is logged in for filters that require it
        let isLoggedIn = userId != nil && authViewModel.userSession?.isAnonymous == false

        switch selectedFilter {
        case .all:
            return baseList // No additional filtering needed for 'All'
        case .available:
            // Filter for events that haven't ended AND are not full
            return baseList.filter { !$0.hasEnded && !$0.isFull }
        case .attending:
            guard isLoggedIn, let uid = userId else { return [] } // Must be logged in
            // Filter based on the opportunity ID being present in the ViewModel's RSVP'd set
            return baseList.filter { viewModel.rsvpedOpportunityIds.contains($0.id) }
        case .favorites:
            guard isLoggedIn, let uid = userId else { return [] } // Must be logged in
            // Filter based on the opportunity ID being present in the ViewModel's favorite set
            return baseList.filter { viewModel.favoriteOpportunityIds.contains($0.id) }
        }
    }

    // 2. Filter AGAIN based on search text (if any) applied to the already filtered list
    private var searchAndFilterResults: [Opportunity] {
        if searchText.isEmpty {
            return filterResults // If no search text, return the results from the selected filter
        } else {
            // If search text exists, filter the *already filtered* list
            let lowercasedSearchText = searchText.lowercased()
            return filterResults.filter { opportunity in
                // Check multiple fields for a match (case-insensitive)
                opportunity.name.lowercased().contains(lowercasedSearchText) ||
                opportunity.location.lowercased().contains(lowercasedSearchText) ||
                opportunity.description.lowercased().contains(lowercasedSearchText)
                // NOTE: Add organizer name search here if implemented
                // || (viewModel.cachedOrganizerName(for: opportunity.creatorUserId) ?? "").lowercased().contains(lowercasedSearchText)
            }
        }
    }

    // 3. Filter out expired opportunities FROM THE searchAndFilterResults
    private var nonExpiredFilteredOpportunities: [Opportunity] {
        searchAndFilterResults // Use the combined filter+search results
            .filter { $0.endDate > now } // Keep only events ending in the future
            .sorted { $0.eventDate < $1.eventDate } // Sort ascending by start date/time
    }

    // 4. Group into Currently Occurring FROM nonExpiredFilteredOpportunities
    private var occurringOpportunities: [Opportunity] {
        nonExpiredFilteredOpportunities.filter { $0.eventDate <= now } // Started but not ended
    }

    // 5. Group FUTURE opportunities by Date FROM nonExpiredFilteredOpportunities
    private var futureOpportunitiesByDate: [Date: [Opportunity]] {
        let futureEvents = nonExpiredFilteredOpportunities.filter { $0.eventDate > now } // Events starting after now
        // Group by the start of the calendar day
        return Dictionary(grouping: futureEvents) { opportunity in
            calendar.startOfDay(for: opportunity.eventDate)
        }
    }

    // 6. Get the sorted list of unique future dates (keys from the dictionary)
    private var sortedFutureDates: [Date] {
        futureOpportunitiesByDate.keys.sorted() // Sort dates chronologically
    }

    // Determine if the list (after filtering AND searching) is empty
    private var isListEffectivelyEmpty: Bool {
        // Check if both the occurring list and the future dates list are empty
        occurringOpportunities.isEmpty && sortedFutureDates.isEmpty
    }

    // Determine if the user-specific filters (Attending, Favorites) should be shown
    private var showUserSpecificFilters: Bool {
        // Only show if user is logged in and not anonymous
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }


    // MARK: - Formatter for Section Headers
    private static var sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) { // Main container, no spacing for seamless components

            // --- Custom Filter/Toolbar ---
            // Show filter bar only if search field is NOT focused AND not initially loading
            if !searchFieldIsFocused && !(viewModel.isLoading && viewModel.opportunities.isEmpty) {
                 filterBar // Use extracted computed property for the filter bar
                     .padding(.horizontal) // Add padding around the entire bar
                     .padding(.top, 8)      // Space above bar
                     .padding(.bottom, 10)   // Space below bar
                     .transition(.move(edge: .top).combined(with: .opacity)) // Animate appearance/disappearance
            }
            // --- End Custom Filter/Toolbar ---


            // --- Conditional Content Area ---
            // Decide which main view content to show based on state
            Group { // Use Group for conditional switching
                if viewModel.isLoading && viewModel.opportunities.isEmpty {
                    loadingView // Initial loading indicator
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage) // Error display
                } else if !viewModel.isLoading && isListEffectivelyEmpty {
                     // Empty state (message depends on filter and search status)
                     emptyStateView(for: selectedFilter, isSearching: !searchText.isEmpty) // Pass search status
                } else {
                    actualListView // The main list, filtered and sectioned
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow content to expand
            // --- End Conditional Content ---

        } // End main VStack
        .navigationTitle("Volunteering")
        // --- Searchable Modifier ---
         .searchable(text: $searchText,
                     placement: .navigationBarDrawer(displayMode: .automatic), // Use system default placement
                     prompt: "Search Name, Location, Desc...") // Placeholder text
         .focused($searchFieldIsFocused) // Bind focus state to the searchable field
         // --- End Searchable ---
         .onChange(of: searchFieldIsFocused) { _, isNowFocused in // Sync concept of searching if needed
             if !isNowFocused { hideKeyboard() } // Dismiss keyboard when focus lost
             print("Search focus changed: \(isNowFocused)")
         }
        .toolbar { // --- MODIFIED TOOLBAR ---
            // Leading Item: Leaderboard Button
            ToolbarItem(placement: .navigationBarLeading) {
                 leaderboardButton // Use extracted button
            }
            // Trailing Items: Loading/Crown and Add Button
            ToolbarItemGroup(placement: .navigationBarTrailing) { // Group trailing items
                // Loading indicator OR Manager Crown
                if viewModel.isLoading { ProgressView().tint(.primary) }
                else if authViewModel.isManager { Image(systemName: "crown.fill").foregroundColor(.orange).accessibilityLabel("Manager Access") }

                // Add Button (Managers Only)
                if authViewModel.isManager {
                    Button { showingCreateSheet = true } label: { Label("Add Opportunity", systemImage: "plus.circle.fill") }
                    .accessibilityLabel("Add New Opportunity")
                }
            }
        } // --- End Modified Toolbar ---
        .sheet(isPresented: $showingCreateSheet) { // Create Event Sheet
            CreateOpportunityView(opportunityToEdit: nil)
                .environmentObject(viewModel).environmentObject(authViewModel)
        }
        // --- Sheet for Leaderboard ---
        .sheet(isPresented: $showingLeaderboardSheet) {
             LeaderboardView() // Present the Leaderboard View
                 .environmentObject(authViewModel) // Pass necessary VMs
                 .environmentObject(viewModel)
         }
        .refreshable { // Pull-to-refresh
            print("Pull to refresh triggered on Opportunities list")
            await viewModel.fetchOpportunities() // Refresh data
        }
        // Animate changes based on filter selection and search results
        .animation(.default, value: selectedFilter)
        .animation(.default, value: searchAndFilterResults)

    } // End body


    // MARK: - Extracted View Builders

    /// Builds the custom, scrollable filter bar with search activation button.
    private var filterBar: some View {
        HStack(spacing: 0) { // Use 0 spacing; padding controls gap
            // Scrollable container for filter buttons
            
                HStack(spacing: 0) { // Inner HStack for buttons
                    ForEach(EventFilter.allCases) { filter in
                        // Conditionally display user-specific filters (Attending, Favorites)
                        if filter == .all || filter == .available || showUserSpecificFilters {
                            filterButton(for: filter) // Use helper to build each button
                                .padding(.horizontal, 2) // Spacing between buttons
                        }
                    }
                }
                .padding(.horizontal, 4) // Padding inside scroll view edges
            // Allow ScrollView to take available space

           
        } // End HStack
        .frame(height: 36) // Constrain the height of the filter bar
        .padding(.vertical, 2) // Add vertical padding to the bar itself
        // Background capsule for the entire bar, hidden when searching
        .background( Capsule().fill(Color(.systemGray6)).opacity(searchFieldIsFocused ? 0 : 1) )
        .animation(.easeInOut(duration: 0.25), value: searchFieldIsFocused) // Animate search transition
        // Reset filter logic if user logs out/becomes anonymous while on Favorites/Attending
        .onChange(of: authViewModel.userSession) { _, newUserSession in
             if (newUserSession == nil || newUserSession!.isAnonymous) && (selectedFilter == .favorites || selectedFilter == .attending) {
                 selectedFilter = .all
             }
        }
    }

    /// Builds a single filter button with text and animated background capsule.
    private func filterButton(for filter: EventFilter) -> some View {
        Button {
            // Action: Update the selected filter state with animation
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3)) {
                selectedFilter = filter
            }
            hideKeyboard() // Dismiss keyboard if active
            searchFieldIsFocused = false // Dismiss focus explicitly
            searchText = ""    // Clear search text when filter tapped
            print("Filter selected: \(filter.rawValue)")
        } label: {
            if filter == .favorites {
                Image(systemName: "heart.fill")
                    .foregroundColor(selectedFilter == filter ? .red : .gray)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background {
                        if selectedFilter == filter {
                            Capsule()
                                .fill(Color(.systemGray3))
                                .matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                        }
                    }
            } else {
                Text(filter.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background {
                        if selectedFilter == filter {
                            Capsule()
                                .fill(Color(.systemGray3))
                                .matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                        }
                    }
                    .foregroundColor(selectedFilter == filter ? Color(.label) : Color(.secondaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    /// Builds the search icon button that activates the search bar focus.
    private var searchIconButton: some View {
        Button {
            withAnimation {
                searchFieldIsFocused = true // Programmatically focus the .searchable TextField
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3) // Icon size
                .foregroundColor(.accentColor) // Use accent color
                .padding(5) // Increase tap area slightly
        }
        .buttonStyle(.plain) // Remove default button styling
    }

    /// Builds the Leaderboard button for the toolbar.
    private var leaderboardButton: some View {
         Button {
             showingLeaderboardSheet = true // Trigger the leaderboard sheet
         } label: {
             Label("Leaderboard", systemImage: "trophy.fill") // Trophy icon
         }
         .accessibilityLabel("View Leaderboard")
     }


    /// Builds the view shown during initial loading.
    private var loadingView: some View {
        VStack { Spacer(); ProgressView("Loading Opportunities...").padding(.bottom, 50); Spacer() }
    }

    /// Builds the view shown when a data fetching error occurs.
    private func errorView(message: String) -> some View {
        VStack(spacing: 15) {
             Spacer(); Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 50)).foregroundColor(.red)
             Text("Error Loading Data").font(.headline)
             Text(message).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
             Button { print("Retry Fetch tapped."); viewModel.fetchOpportunities() } label: { Label("Retry Fetch", systemImage: "arrow.clockwise") }
                 .buttonStyle(.borderedProminent).tint(.orange).padding(.top).disabled(viewModel.isLoading)
             Spacer()
         }.padding()
    }

    /// Builds the view shown when the filtered/searched list is empty. Message varies.
    private func emptyStateView(for filter: EventFilter, isSearching: Bool) -> some View {
        VStack(spacing: 15) {
             Spacer()
             Image(systemName: emptyStateIcon(for: filter, isSearching: isSearching)) // Dynamic icon
                 .font(.system(size: 60)).foregroundColor(.secondary.opacity(0.7))
             Text(emptyStateTitle(for: filter, isSearching: isSearching)) // Dynamic title
                 .font(.title2).fontWeight(.semibold).padding(.horizontal)
             Text(emptyStateSubtitle(for: filter, isSearching: isSearching)) // Dynamic subtitle
                 .font(.subheadline).foregroundColor(.secondary)
                 .multilineTextAlignment(.center).padding(.horizontal, 40)
             // Only show "Check Again" if not empty due to active search filtering results
             if !isSearching {
                 Button { print("Check Again tapped."); viewModel.fetchOpportunities() } label: { Label("Check Again", systemImage: "arrow.clockwise") }
                 .buttonStyle(.bordered).padding(.top).disabled(viewModel.isLoading)
             }
            Spacer()
         }.padding()
    }
    // Helper functions providing dynamic content for the empty state view
    private func emptyStateIcon(for filter: EventFilter, isSearching: Bool) -> String {
        isSearching ? "magnifyingglass" : (filter == .favorites ? "heart.slash.fill" : (filter == .attending ? "person.crop.circle.badge.checkmark" : "calendar.badge.exclamationmark"))
    }
     private func emptyStateTitle(for filter: EventFilter, isSearching: Bool) -> String {
        isSearching ? "No Matching Events" : (filter == .favorites ? "No Upcoming Favorites" : (filter == .attending ? "Not Attending Any Events" : (filter == .available ? "No Available Spots" : "No Upcoming Opportunities")))
    }
    private func emptyStateSubtitle(for filter: EventFilter, isSearching: Bool) -> String {
        isSearching ? "Clear the search text or try different keywords." : (filter == .favorites ? "Favorite upcoming events to see them here." : (filter == .attending ? "RSVP to events to see them in this list." : (filter == .available ? "There are no upcoming events with available spots right now." : (authViewModel.isManager ? "Tap '+' to add an event!" : "Check back later or try a different filter."))))
    }


    /// Builds the main List view containing sections based on filtered/searched data.
    private var actualListView: some View {
        List {
            // --- Section 1: Currently Occurring ---
            if !occurringOpportunities.isEmpty { // Use filtered & searched data
                Section("Currently Occurring") {
                    ForEach(occurringOpportunities) { opportunity in listRowNavigationLink(for: opportunity) } // Use helper
                }
            }

            // --- Sections for FUTURE Events, Grouped by Date ---
            ForEach(sortedFutureDates, id: \.self) { date in // Use filtered & searched data
                // Safely unwrap the opportunities for this specific date from the filtered dictionary
                if let opportunitiesForDate = futureOpportunitiesByDate[date], !opportunitiesForDate.isEmpty {
                    Section { // Section content
                        ForEach(opportunitiesForDate) { opportunity in listRowNavigationLink(for: opportunity) } // Use helper
                    } header: { // Section header
                        Text(date, formatter: Self.sectionDateFormatter) // Display formatted date
                    }
                }
            } // End ForEach over sorted future dates

        } // End List
        .listStyle(.insetGrouped) // Use insetGrouped style for section visuals
    } // End actualListView

    /// Helper function: Creates the NavigationLink wrapping the OpportunityRowView for list rows.
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

    // MARK: - Helper Functions
    /// Helper to dismiss the keyboard.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

} // End struct OpportunityListView


