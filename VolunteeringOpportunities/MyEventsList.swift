import SwiftUI

// MARK: - My Events List View (with Dynamic Row Backgrounds)
// Displays a list of opportunities created by the currently logged-in manager,
// grouped into Current/Future and Past sections, with dynamic row backgrounds.
struct MyEventsListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access all opportunities and actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access current user ID and manager status

    // MARK: - State
    // Controls presentation of the create opportunity sheet
    @State private var showingCreateSheet = false

    // MARK: - Computed Properties for Filtering and Grouping "My" Events

    // Get current date/calendar for comparisons
    private var now: Date { Date() }
    private var calendar: Calendar { Calendar.current }

    // Helper to check login status (though should always be true if this view is shown)
    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    // 1. Filter opportunities to show only those created by the current manager
    private var allMyOpportunities: [Opportunity] {
        guard let currentUserId = authViewModel.userSession?.uid, authViewModel.isManager else { return [] }
        return viewModel.opportunities
            .filter { $0.creatorUserId == currentUserId }
            .sorted { $0.eventDate > $1.eventDate } // Sort recent first overall initially
    }

    // 2. Filter into Upcoming/Occurring (non-expired) manager's events
    // Sorted ascending for display order
    private var upcomingOrOccurringMyOpportunities: [Opportunity] {
        allMyOpportunities
            .filter { $0.endDate > now }
            .sorted { $0.eventDate < $1.eventDate }
    }
    // Sub-group: Currently happening manager events
    private var occurringMyOpportunities: [Opportunity] {
        upcomingOrOccurringMyOpportunities.filter { $0.eventDate <= now }
    }
    // Sub-group: Future manager events, grouped by the start of their day
    private var futureMyOpportunitiesByDate: [Date: [Opportunity]] {
        let futureEvents = upcomingOrOccurringMyOpportunities.filter { $0.eventDate > now }
        return Dictionary(grouping: futureEvents) { opportunity in
            calendar.startOfDay(for: opportunity.eventDate)
        }
    }
    // Get the sorted list of unique future dates for section creation
    private var sortedFutureMyEventDates: [Date] {
        futureMyOpportunitiesByDate.keys.sorted()
    }


    // 3. Filter into Past/Expired manager's events
    // Already sorted most-recent-past first due to initial allMyOpportunities sort
    private var pastMyOpportunities: [Opportunity] {
        allMyOpportunities.filter { $0.endDate <= now }
    }

    // Determine if there are *any* events created by the manager
    private var hasAnyEvents: Bool {
        !allMyOpportunities.isEmpty
    }
    // Determine if there are any *upcoming* or *occurring* events
     private var hasUpcomingOrOccurringEvents: Bool {
         !upcomingOrOccurringMyOpportunities.isEmpty
     }
     // Determine if the list should show the "No current or future..." message
     private var showNoUpcomingMessage: Bool {
         !hasUpcomingOrOccurringEvents && !pastMyOpportunities.isEmpty
     }


    // MARK: - Formatter for Section Headers
    private static var sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()

    // MARK: - Helper Function for Row Background (Matches OpportunityListView)
    @ViewBuilder
    private func backgroundForRow(for opportunity: Opportunity) -> some View {
        // Determine background view based on priority
        if opportunity.isCurrentlyOccurring {
            // Occurring: Animated Wave Background
            AnimatedWaveBackgroundView(
                startTime: opportunity.eventDate,
                endTime: opportunity.endDate,
                baseColor: .mint // Using yellow for consistency
            )
        } else if isLoggedInUser && viewModel.isRsvped(opportunityId: opportunity.id) {
            // Attending Background (Green) - Manager RSVP'd to own event
            Color.green.opacity(0.15)
        } else if isLoggedInUser && viewModel.isFavorite(opportunityId: opportunity.id) {
             // Favorited Background (Red) - Manager favorited own event
            AnimatedMeshBackgroundView(
                colors: [.red, .pink, .red.opacity(0.3)]
                        )
        } else {
            // Default Background
            Color(UIColor.secondarySystemGroupedBackground)// Use clear for ViewBuilder conformance
        }
    }


    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 for seamless transition to List
            // --- Conditional Content ---
            // Display Loading, Empty State, or the List with Sections
            if viewModel.isLoading && !hasAnyEvents { // Show loading only if truly nothing loaded yet
                 ProgressView("Loading Your Events...")
                     .padding(.top, 50)
                 Spacer() // Push loading indicator up
            } else if !viewModel.isLoading && !hasAnyEvents { // Check if absolutely no events exist after load
                 emptyStateView // Show appropriate empty state view
            } else {
                // Show the list view, passing filtered data
                 actualListView(
                     occurring: occurringMyOpportunities,
                     futureGrouped: futureMyOpportunitiesByDate,
                     sortedFutureDates: sortedFutureMyEventDates,
                     past: pastMyOpportunities,
                     showNoUpcomingMessage: showNoUpcomingMessage // Pass calculated bool
                 )
            }
        } // End VStack
        .navigationTitle("My Events")
        // Set the title for this specific tab
        .refreshable { // Allow pull-to-refresh
             print("Pull to refresh triggered on My Events list")
             await viewModel.fetchOpportunities() // Refresh the main list
         }
        // --- Toolbar with Add Button ---
        .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 Button {
                     showingCreateSheet = true // Trigger the presentation of the create sheet
                 } label: {
                     Label("Add Opportunity", systemImage: "plus.circle.fill")
                 }
                 .accessibilityLabel("Add New Opportunity")
             }
         }
         // --- Sheet Modifier to Present Create View ---
         .sheet(isPresented: $showingCreateSheet) {
             // Present CreateOpportunityView configured for CREATING
             CreateOpportunityView(opportunityToEdit: nil)
                 .environmentObject(viewModel) // Pass necessary ViewModels
                 .environmentObject(authViewModel)
         }
         // Animate background changes based on relevant ViewModel states
        .animation(.default, value: viewModel.opportunities)
        .animation(.default, value: viewModel.rsvpedOpportunityIds)
        .animation(.default, value: viewModel.favoriteOpportunityIds)

    } // End body

    // MARK: - Extracted Subview Builders

    /// Builds the view shown when the manager has created no events.
    private var emptyStateView: some View {
        VStack(spacing: 15) {
             Spacer()
             Image(systemName: "doc.text.magnifyingglass") // Icon suggesting creation/search
                 .font(.system(size: 60))
                 .foregroundColor(.secondary.opacity(0.7))
             Text("No Events Created Yet")
                 .font(.title2).fontWeight(.semibold)
             Text("Tap '+' in the top right to add your first event.")
                 .font(.subheadline)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal, 40)
             Spacer()
             Spacer()
         }
        .padding()
    }

    /// Builds the main List view content with sections for Current, Future (by Date), and Past.
    /// Accepts data as parameters to avoid redundant calculations.
    @ViewBuilder
    private func actualListView(
        occurring: [Opportunity],
        futureGrouped: [Date: [Opportunity]],
        sortedFutureDates: [Date],
        past: [Opportunity],
        showNoUpcomingMessage: Bool
    ) -> some View {
        List {
            // Section 1: Currently Occurring
            if !occurring.isEmpty {
                Section("Currently Occurring") {
                    ForEach(occurring) { opportunity in
                        listRowNavigationLink(for: opportunity)
                            // Apply dynamic background
                            .listRowBackground(backgroundForRow(for: opportunity))
                    }
                }
            }

            // Sections 2+: FUTURE Events, Grouped by Date
            ForEach(sortedFutureDates, id: \.self) { date in
                // Safely unwrap opportunities for the specific date
                if let opportunitiesForDate = futureGrouped[date], !opportunitiesForDate.isEmpty {
                    Section { // Section content
                        ForEach(opportunitiesForDate) { opportunity in
                            listRowNavigationLink(for: opportunity)
                                // Apply dynamic background
                                .listRowBackground(backgroundForRow(for: opportunity))
                        }
                    } header: { // Section header
                        Text(date, formatter: Self.sectionDateFormatter)
                    }
                }
            } // End ForEach over sorted future dates

            // Message if no upcoming/current events but past events exist
             if showNoUpcomingMessage {
                 Section {
                     Text("No current or future events created by you.")
                         .foregroundColor(.secondary).font(.footnote)
                         .frame(maxWidth: .infinity, alignment: .center)
                         .listRowBackground(Color(.systemGroupedBackground)) // Match system bg
                 }
             }

            // Final Section: Past Events
            if !past.isEmpty {
                Section("Past Events") {
                    ForEach(past) { opportunity in
                        listRowNavigationLink(for: opportunity)
                            .opacity(0.7) // Keep past events slightly faded
                            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground)) // Use default/clear background
                    }
                }
            }
        } // End List
        .listStyle(.insetGrouped)
        
    } // End actualListView

    /// Helper: Creates the NavigationLink row content. Background is applied by the caller (actualListView).
    @ViewBuilder
    private func listRowNavigationLink(for opportunity: Opportunity) -> some View {
        ZStack(alignment: .leading) {
             // Invisible NavigationLink layer for whole-row tap
             NavigationLink {
                 OpportunityDetailView(opportunity: opportunity)
                     .environmentObject(viewModel).environmentObject(authViewModel)
             } label: { EmptyView() }.opacity(0)
             // Visible Row Content (OpportunityRowView is now simple)
            OpportunityRowView(opportunity: opportunity)
                .environmentObject(viewModel).environmentObject(authViewModel)
         }
         // Consistent padding applied to the content within the ZStack
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
    }

} // End struct MyEventsListView

// --- Ensure dependent views/structs like AnimatedWaveBackgroundView, WaveShape, OpportunityRowView are accessible ---
