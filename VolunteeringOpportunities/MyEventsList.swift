import SwiftUI

// MARK: - My Events List View (with Dynamic Row Backgrounds)
struct MyEventsListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // MARK: - State
    @State private var showingCreateSheet = false

    // MARK: - Computed Properties for Filtering and Grouping "My" Events

    private var now: Date { Date() }
    private var calendar: Calendar { Calendar.current }

    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    private var allMyOpportunities: [Opportunity] {
        guard let currentUserId = authViewModel.userSession?.uid, authViewModel.isManager else { return [] }
        return viewModel.opportunities
            .filter { $0.creatorUserId == currentUserId }
            .sorted { $0.eventDate > $1.eventDate }
    }

    private var upcomingOrOccurringMyOpportunities: [Opportunity] {
        allMyOpportunities
            .filter { $0.endDate > now }
            .sorted { $0.eventDate < $1.eventDate }
    }
    private var occurringMyOpportunities: [Opportunity] {
        upcomingOrOccurringMyOpportunities.filter { $0.eventDate <= now }
    }
    private var futureMyOpportunitiesByDate: [Date: [Opportunity]] {
        let futureEvents = upcomingOrOccurringMyOpportunities.filter { $0.eventDate > now }
        return Dictionary(grouping: futureEvents) { opportunity in
            calendar.startOfDay(for: opportunity.eventDate)
        }
    }
    private var sortedFutureMyEventDates: [Date] {
        futureMyOpportunitiesByDate.keys.sorted()
    }


    private var pastMyOpportunities: [Opportunity] {
        allMyOpportunities.filter { $0.endDate <= now }
    }

    private var hasAnyEvents: Bool {
        !allMyOpportunities.isEmpty
    }
     private var hasUpcomingOrOccurringEvents: Bool {
         !upcomingOrOccurringMyOpportunities.isEmpty
     }
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
        if opportunity.isCurrentlyOccurring {
            AnimatedWaveBackgroundView(
                startTime: opportunity.eventDate,
                endTime: opportunity.endDate,
                baseColor: .mint
            )
        } else if isLoggedInUser && viewModel.isRsvped(opportunityId: opportunity.id) {
            Color.green.opacity(0.15)
        } else if isLoggedInUser && viewModel.isFavorite(opportunityId: opportunity.id) {
            AnimatedMeshBackgroundView(
                colors: [.red, .pink, .red.opacity(0.3)]
                        )
        } else {
            Color(UIColor.secondarySystemGroupedBackground)
        }
    }


    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && !hasAnyEvents {
                 ProgressView("Loading Your Events...")
                     .padding(.top, 50)
                 Spacer()
            } else if !viewModel.isLoading && !hasAnyEvents {
                 emptyStateView
            } else {
                 actualListView(
                     occurring: occurringMyOpportunities,
                     futureGrouped: futureMyOpportunitiesByDate,
                     sortedFutureDates: sortedFutureMyEventDates,
                     past: pastMyOpportunities,
                     showNoUpcomingMessage: showNoUpcomingMessage
                 )
            }
        }
        .navigationTitle("My Events")
        .refreshable {
             print("Pull to refresh triggered on My Events list")
             await viewModel.fetchOpportunities()
         }
        .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 Button {
                     showingCreateSheet = true
                 } label: {
                     Label("Add Opportunity", systemImage: "plus.circle.fill")
                 }
                 .accessibilityLabel("Add New Opportunity")
             }
         }
         .sheet(isPresented: $showingCreateSheet) {
             CreateOpportunityView(opportunityToEdit: nil)
                 .environmentObject(viewModel)
                 .environmentObject(authViewModel)
         }
        .animation(.default, value: viewModel.opportunities)
        .animation(.default, value: viewModel.rsvpedOpportunityIds)
        .animation(.default, value: viewModel.favoriteOpportunityIds)

    }

    // MARK: - Extracted Subview Builders

    private var emptyStateView: some View {
        VStack(spacing: 15) {
             Spacer()
             Image(systemName: "doc.text.magnifyingglass")
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

    @ViewBuilder
    private func actualListView(
        occurring: [Opportunity],
        futureGrouped: [Date: [Opportunity]],
        sortedFutureDates: [Date],
        past: [Opportunity],
        showNoUpcomingMessage: Bool
    ) -> some View {
        List {
            if !occurring.isEmpty {
                Section("Currently Occurring") {
                    ForEach(occurring) { opportunity in
                        listRowNavigationLink(for: opportunity)
                            .listRowBackground(backgroundForRow(for: opportunity))
                    }
                }
            }

            ForEach(sortedFutureDates, id: \.self) { date in
                if let opportunitiesForDate = futureGrouped[date], !opportunitiesForDate.isEmpty {
                    Section {
                        ForEach(opportunitiesForDate) { opportunity in
                            listRowNavigationLink(for: opportunity)
                                .listRowBackground(backgroundForRow(for: opportunity))
                        }
                    } header: {
                        Text(date, formatter: Self.sectionDateFormatter)
                    }
                }
            }

             if showNoUpcomingMessage {
                 Section {
                     Text("No current or future events created by you.")
                         .foregroundColor(.secondary).font(.footnote)
                         .frame(maxWidth: .infinity, alignment: .center)
                         .listRowBackground(Color(.systemGroupedBackground))
                 }
             }

            if !past.isEmpty {
                Section("Past Events") {
                    ForEach(past) { opportunity in
                        listRowNavigationLink(for: opportunity)
                            .opacity(0.7)
                            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
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
                 OpportunityDetailView(opportunity: opportunity)
                     .environmentObject(viewModel).environmentObject(authViewModel)
             } label: { EmptyView() }.opacity(0)
            OpportunityRowView(opportunity: opportunity)
                .environmentObject(viewModel).environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
    }

}
