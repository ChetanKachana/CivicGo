import SwiftUI

// MARK: - Combined Search Result Enum (Defined at File Level with Manual Hashable)
enum SearchResult: Identifiable, Hashable {
    case opportunity(Opportunity)
    case manager(ManagerInfo)

    var id: String {
        switch self {
        case .opportunity(let opp): return "opp_\(opp.id)"
        case .manager(let mgr): return "mgr_\(mgr.id)"
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .opportunity(let opp):
            hasher.combine(0)
            hasher.combine(opp)
        case .manager(let mgr):
            hasher.combine(1)
            hasher.combine(mgr)
        }
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
         switch (lhs, rhs) {
         case (.opportunity(let lhsOpp), .opportunity(let rhsOpp)):
             return lhsOpp == rhsOpp
         case (.manager(let lhsMgr), .manager(let rhsMgr)):
             return lhsMgr == rhsMgr
         default:
             return false
         }
     }

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
    @State private var isSearching: Bool = false
    @FocusState private var searchTextFieldIsFocused: Bool

    @Namespace private var filterAnimation

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

    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    private var filteredOpportunities: [Opportunity] {
        let baseList = viewModel.opportunities

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

    private var searchedManagers: [ManagerInfo] {
        guard !searchText.trimmed().isEmpty else { return [] }
        let lowercasedSearchText = searchText.trimmed().lowercased()
        return viewModel.managers.filter { mgr in
            mgr.username.lowercased().contains(lowercasedSearchText)
        }
    }

    private var searchedOpportunities: [Opportunity] {
         guard !searchText.trimmed().isEmpty else { return [] }
         let lowercasedSearchText = searchText.trimmed().lowercased()
         return viewModel.opportunities.filter { opp in
             opp.name.lowercased().contains(lowercasedSearchText) ||
             opp.location.lowercased().contains(lowercasedSearchText) ||
             opp.description.lowercased().contains(lowercasedSearchText)
         }
         .sorted { $0.eventDate < $1.eventDate }
     }

    private var isListEffectivelyEmpty: Bool {
        if isSearching {
            return searchedManagers.isEmpty && searchedOpportunities.isEmpty
        } else {
            return occurringFilteredOpportunities.isEmpty && sortedFutureFilteredDates.isEmpty
        }
    }

    private var showUserSpecificFilters: Bool {
        isLoggedInUser
    }

    // MARK: - Formatter
    private static var sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {

            if isSearching {
                searchFieldBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                filterBarAndSearchButton
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Divider().opacity(isSearching ? 0 : 1)
                 .animation(.easeInOut(duration: 0.2), value: isSearching)

            Group {
                if viewModel.isLoading || (viewModel.isLoadingManagers && viewModel.managers.isEmpty && viewModel.opportunities.isEmpty) {
                     loadingView
                 } else if let errorMessage = viewModel.errorMessage {
                     errorView(message: errorMessage)
                 } else if isListEffectivelyEmpty {
                       emptyStateView(for: selectedFilter, isSearching: isSearching)
                 } else {
                     actualListView
                 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .navigationTitle("Volunteering")
        .navigationBarTitleDisplayMode(.inline)
        
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leaderboardButton }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.isLoading || viewModel.isLoadingManagers { ProgressView().tint(.primary) }
                else if authViewModel.isManager { Image(systemName: "crown.fill").foregroundColor(.indigo).accessibilityLabel("Manager Access") }

                if authViewModel.isManager {
                    Button { showingCreateSheet = true } label: { Label("Add Opportunity", systemImage: "plus.circle.fill") }
                         .accessibilityLabel("Add New Opportunity")
                         
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
        .refreshable {
             print("Pull to refresh triggered")
             await viewModel.fetchOpportunities()
             await viewModel.fetchManagers()
         }
         .task {
             print("OpportunityListView .task modifier.")
              if viewModel.opportunities.isEmpty {
                  print("  -> Fetching initial opportunities.")
                  await viewModel.fetchOpportunities()
              }
              if viewModel.managers.isEmpty {
                   print("  -> Fetching initial managers.")
                   await viewModel.fetchManagers()
              }
         }
        .animation(.default, value: isSearching)
        .animation(.default, value: selectedFilter)
        .animation(.default, value: isSearching ? searchedOpportunities : filteredOpportunities)
        .animation(.default, value: isSearching ? searchedManagers : [])


    }


    // MARK: - Helper Function for Row Background
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


    // MARK: - Extracted View Builders for UI Components

    @ViewBuilder private var filterBarAndSearchButton: some View {
        HStack(spacing: 8) {
            
                HStack(spacing: 0) {
                    ForEach(EventFilter.allCases) { filter in
                        if filter == .all || filter == .available || showUserSpecificFilters {
                            filterButton(for: filter)
                                .padding(.horizontal, 2)
                        }
                    }
                }
                .padding(.horizontal, 4)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    searchTextFieldIsFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(5)
            }
            .buttonStyle(.plain)

        }
         .onChange(of: authViewModel.userSession) { _, newUserSession in
               if (newUserSession == nil || newUserSession!.isAnonymous) && (selectedFilter == .favorites || selectedFilter == .attending) {
                   selectedFilter = .all
               }
          }
         .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3), value: selectedFilter)
    }

    @ViewBuilder private var searchFieldBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)

            TextField("Search Events & Organizations...", text: $searchText)
                .focused($searchTextFieldIsFocused)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    print("Search submitted: \(searchText)")
                    hideKeyboard()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchTextFieldIsFocused = true
                } label: {
                    Image(systemName: "multiply.circle.fill")
                        .foregroundColor(.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.trailing, -2)
            }

            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearching = false
                    searchText = ""
                    hideKeyboard()
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
        }
    }

    private func filterButton(for filter: EventFilter) -> some View {
        Button {
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
                     .background {
                         if selectedFilter == filter {
                             Capsule().fill(Color(.systemGray4)).matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                         } else {
                             Capsule().fill(Color(.systemGray6))
                         }
                     }
                      .clipShape(Capsule())
            } else {
                 Text(filter.rawValue)
                     .font(.system(size: 14, weight: .medium))
                     .padding(.vertical, 6).padding(.horizontal, 14)
                     .background {
                         if selectedFilter == filter {
                             Capsule().fill(Color(.systemGray4)).matchedGeometryEffect(id: "filterHighlight", in: filterAnimation)
                         } else {
                             Capsule().fill(Color(.systemGray6))
                         }
                     }
                      .clipShape(Capsule())
                     .foregroundColor(selectedFilter == filter ? Color(.label) : Color(.secondaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    private var leaderboardButton: some View {
         Button { showingLeaderboardSheet = true } label: { Label("Leaderboard", systemImage: "trophy.fill") }
         .accessibilityLabel("View Leaderboard")
     }

    private var loadingView: some View {
        VStack { Spacer(); ProgressView("Loading...").padding(.bottom, 50); Spacer() }
    }

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
             if !isSearching {
                  Button { print("Check Again tapped."); Task { await viewModel.fetchOpportunities(); await viewModel.fetchManagers() } }
                  label: { Label("Check Again", systemImage: "arrow.clockwise") }
                  .buttonStyle(.bordered).padding(.top)
                  .disabled(viewModel.isLoading || viewModel.isLoadingManagers)
             }
            Spacer()
            Spacer()
         }.padding()
    }
     private func emptyStateIcon(for filter: EventFilter) -> String {
         filter == .favorites ? "heart.slash.fill" : (filter == .attending ? "person.crop.circle.badge.checkmark" : "calendar.badge.exclamationmark")
     }
     private func emptyStateTitle(for filter: EventFilter) -> String {
         filter == .favorites ? "No Upcoming Favorites" : (filter == .attending ? "Not Attending Any Events" : (filter == .available ? "No Available Spots" : "No Upcoming Opportunities"))
     }
     private func emptyStateSubtitle(for filter: EventFilter) -> String {
         filter == .favorites ? "Favorite upcoming events to see them here." : (filter == .attending ? "RSVP to events to see them in this list." : (filter == .available ? "There are no upcoming events with available spots right now." : (authViewModel.isManager ? "Tap '+' to add an event!" : "Check back later or try a different filter.")))
     }


    private var actualListView: some View {
        List {
            if isSearching {
                if !searchedManagers.isEmpty {
                    Section("Organizations / Managers") {
                        ForEach(searchedManagers) { manager in
                            managerRowLink(for: manager)
                                .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
                        }
                    }
                }

                if !searchedOpportunities.isEmpty {
                    Section(searchedManagers.isEmpty ? "Search Results" : "Matching Events") {
                         ForEach(searchedOpportunities) { opportunity in
                             listRowNavigationLink(for: opportunity)
                                 .listRowBackground(backgroundForRow(for: opportunity))
                         }
                    }
                }

            } else {
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
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
       
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

    @ViewBuilder
    private func managerRowLink(for manager: ManagerInfo) -> some View {
        ZStack(alignment: .leading) {
             NavigationLink {
                 ManagerProfileView(managerUserIdToView: manager.id)
                     .environmentObject(authViewModel)
                     .environmentObject(viewModel)
             } label: { EmptyView() }.opacity(0)
             ManagerRowView(managerInfo: manager)
                .environmentObject(authViewModel)
         }
         .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
    }

    // MARK: - Helper Functions
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

}


// MARK: - Manager Row View (for Search Results)
struct ManagerRowView: View {
    let managerInfo: ManagerInfo
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        HStack {
            AsyncImage(url: URL(string: managerInfo.logoImageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                         .frame(width: 40, height: 40).clipShape(Circle())
                default:
                     Image(systemName: "person.crop.circle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40).foregroundColor(.secondary)
                }
            }

            Text(managerInfo.username).font(.headline)
            Spacer()
            if managerInfo.id == authViewModel.userSession?.uid {
                  Image(systemName: "crown.fill").foregroundColor(.indigo)
                     .accessibilityLabel("Your Manager Profile")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - String Extension (Ensure defined once in your project)
extension String {
    func trimmed() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}
 
#Preview {
          OpportunityListView()
       }

