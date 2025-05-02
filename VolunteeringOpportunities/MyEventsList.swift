import SwiftUI

// MARK: - My Events List View (Grouped by Date with Past Events)
// Displays a list of opportunities created by the currently logged-in manager,
// grouped into Current/Future (by date) and Past sections. Includes an "Add" button.
struct MyEventsListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access all opportunities and actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access current user ID and manager status

    // MARK: - State
    // State variable to control the presentation of the create opportunity sheet
    @State private var showingCreateSheet = false

    // MARK: - Computed Properties for Filtering and Grouping "My" Events

    // Get current date/calendar for comparisons
    private var now: Date { Date() }
    private var calendar: Calendar { Calendar.current }

    // 1. Filter opportunities to show only those created by the current manager
    private var allMyOpportunities: [Opportunity] {
        // Ensure user is logged in and we have their ID before filtering
        guard let currentUserId = authViewModel.userSession?.uid, authViewModel.isManager else {
            return [] // Return empty if no valid manager session
        }
        // Filter the main list based on the creatorUserId matching the current user
        // Sort by start date descending initially to handle past events grouping easily
        return viewModel.opportunities
            .filter { $0.creatorUserId == currentUserId }
            .sorted { $0.eventDate > $1.eventDate } // Sort recent first overall
    }

    // 2. Filter into Upcoming/Occurring (non-expired) manager's events
    private var upcomingOrOccurringMyOpportunities: [Opportunity] {
        // Filter the manager's events where the end date is in the future
        // Then sort this subset ascending by start date for display order
        allMyOpportunities
            .filter { $0.endDate > now }
            .sorted { $0.eventDate < $1.eventDate }
    }
    // Sub-group Upcoming/Occurring into currently happening for its own section
    private var occurringMyOpportunities: [Opportunity] {
        upcomingOrOccurringMyOpportunities.filter { $0.eventDate <= now }
    }
    // Sub-group FUTURE manager's events by Date
    // Returns a dictionary where Key is the Start of the Day (Date) and Value is [Opportunity]
    private var futureMyOpportunitiesByDate: [Date: [Opportunity]] {
        let futureEvents = upcomingOrOccurringMyOpportunities.filter { $0.eventDate > now }
        // Group these future events by the calendar day they start on
        return Dictionary(grouping: futureEvents) { opportunity in
            calendar.startOfDay(for: opportunity.eventDate)
        }
    }
    // Get the sorted list of unique future dates for section creation
    private var sortedFutureMyEventDates: [Date] {
        futureMyOpportunitiesByDate.keys.sorted()
    }


    // 3. Filter into Past/Expired manager's events
    private var pastMyOpportunities: [Opportunity] {
        // Filter the manager's events where the end date is in the past or now
        // The initial descending sort of allMyOpportunities keeps these most-recent-past first
        allMyOpportunities.filter { $0.endDate <= now }
    }

    // Determine if there are *any* events created by the manager (past or present/future)
    private var hasAnyEvents: Bool {
        !allMyOpportunities.isEmpty
    }
    // Determine if there are any *upcoming* or *occurring* events created by the manager
     private var hasUpcomingOrOccurringEvents: Bool {
         !upcomingOrOccurringMyOpportunities.isEmpty
     }

    // MARK: - Formatter for Section Headers
    private static var sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 for seamless transition to the List edge
            // --- Conditional Content ---
            // Display Loading, Empty State, or the List with Sections
            if viewModel.isLoading && !hasAnyEvents { // Show loading only if truly nothing loaded yet
                 ProgressView("Loading Your Events...")
                     .padding(.top, 50)
                 Spacer() // Push loading indicator up
            } else if !viewModel.isLoading && !hasAnyEvents { // Check if absolutely no events exist after load
                 emptyStateView // Show appropriate empty state view
            } else {
                // Show the list view containing sections for current, future, and past events
                 actualListView
            }
        } // End VStack
        .navigationTitle("My Events") // Set the title for this specific tab
        .refreshable { // Allow pull-to-refresh
             print("Pull to refresh triggered on My Events list")
             await viewModel.fetchOpportunities() // Refresh the main list of opportunities
         }
        // --- Toolbar with Add Button ---
        // Appears because this whole view is only visible to managers
        .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 Button {
                     showingCreateSheet = true // Trigger the presentation of the create sheet
                 } label: {
                     Label("Add Opportunity", systemImage: "plus.circle.fill") // Standard Add icon
                 }
                 .accessibilityLabel("Add New Opportunity")
             }
         }
         // --- Sheet Modifier to Present Create View ---
         .sheet(isPresented: $showingCreateSheet) {
             // Present CreateOpportunityView configured for CREATING a new opportunity
             CreateOpportunityView(opportunityToEdit: nil) // Pass nil to indicate create mode
                 .environmentObject(viewModel) // Provide necessary ViewModels to the sheet
                 .environmentObject(authViewModel)
         }
    } // End body

    // MARK: - Extracted Subview Builders

    // --- View for Empty State ---
    // Shown when the manager has created no events at all.
    private var emptyStateView: some View {
        VStack(spacing: 15) {
             Spacer() // Push content to center vertically
             Image(systemName: "doc.text.magnifyingglass") // Icon suggesting creation/search
                 .font(.system(size: 60))
                 .foregroundColor(.secondary.opacity(0.7))
             Text("No Events Created Yet")
                 .font(.title2).fontWeight(.semibold)
             Text("Tap '+' in the top right to add your first event.") // Instruction
                 .font(.subheadline)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal, 40)
             Spacer()
             Spacer() // Add more space at bottom
         }
        .padding()
    }

    // --- The Actual List View Content with Sections for Current, Future (by Date), and Past ---
    private var actualListView: some View {
        List {
            // --- Section 1: Currently Occurring ---
            // Show this section only if there are events happening now created by the manager
            if !occurringMyOpportunities.isEmpty {
                Section("Currently Occurring") {
                    ForEach(occurringMyOpportunities) { opportunity in
                        listRowNavigationLink(for: opportunity) // Use helper
                    }
                }
            }

            // --- Sections 2+: FUTURE Events, Grouped by Date ---
            // Iterate over the unique future dates for manager's events
            ForEach(sortedFutureMyEventDates, id: \.self) { date in
                // Safely unwrap the array of opportunities for this specific date
                if let opportunitiesForDate = futureMyOpportunitiesByDate[date], !opportunitiesForDate.isEmpty {
                    // Create a Section for each unique future date
                    Section { // Section content
                        ForEach(opportunitiesForDate) { opportunity in
                            listRowNavigationLink(for: opportunity) // Use helper
                        }
                    } header: { // Section header
                        // Display the formatted date
                        Text(date, formatter: Self.sectionDateFormatter)
                    }
                }
            } // End ForEach over sorted future dates

            // --- Message if no upcoming/current events but past events exist ---
             if !hasUpcomingOrOccurringEvents && !pastMyOpportunities.isEmpty {
                 Section { // Use a section for consistent spacing and appearance
                     Text("No current or future events created by you.")
                         .foregroundColor(.secondary)
                         .font(.footnote)
                         .frame(maxWidth: .infinity, alignment: .center) // Center the text
                         .listRowBackground(Color(.systemGroupedBackground)) // Match background
                 }
             }

            // --- Final Section: Past Events ---
            // Show this section only if there are past events created by the manager
            if !pastMyOpportunities.isEmpty {
                Section("Past Events") {
                    // Iterate through past events (sorted most recent first)
                    ForEach(pastMyOpportunities) { opportunity in
                        listRowNavigationLink(for: opportunity)
                            .opacity(0.7) // Make past events slightly faded
                    }
                }
            }
        } // End List
        .listStyle(.insetGrouped) // Use insetGrouped style for section visuals
    } // End actualListView

    // --- Helper: Creates the NavigationLink row content ---
    // Reusable function to build the row structure with NavigationLink
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


} // End struct MyEventsListView


