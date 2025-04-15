import SwiftUI

// MARK: - Opportunity List View
// Displays the main list of available volunteering opportunities.
// Includes loading, error, empty states, pull-to-refresh, manual refresh,
// and a conditional "Add" button for logged-in, non-anonymous users.
struct OpportunityListView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access opportunity data
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access auth state for conditional UI
    @State private var showingCreateSheet = false                  // Controls presentation of the create sheet

    // MARK: - Body
    var body: some View {
        VStack { // Main container for the entire view content
            // --- Conditional Content using Extracted Views ---
            // Decide which view to show based on the ViewModel's state
            if viewModel.isLoading && viewModel.opportunities.isEmpty {
                loadingView // Show loading indicator when initially loading
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage) // Show error message view
            } else if viewModel.opportunities.isEmpty {
                emptyStateView // Show message indicating no opportunities
            } else {
                listDisplayView // Show the main list content (List + Button)
            }
            // --- End Conditional Content ---

            Spacer() // Pushes content towards the top

        } // End main VStack
        .navigationTitle("Volunteering") // Set the title for the Navigation Bar
        .toolbar { // Define items for the Navigation Bar
            // Loading Indicator (appears on the left when isLoading is true)
            ToolbarItem(placement: .navigationBarLeading) {
                 if viewModel.isLoading { ProgressView() }
             }
            // Add ("+") Button (appears on the right for non-anonymous users)
            ToolbarItem(placement: .navigationBarTrailing) {
                if let user = authViewModel.userSession, !user.isAnonymous {
                    Button { showingCreateSheet = true } label: { Label("Add Opportunity", systemImage: "plus.circle.fill") }
                }
             }
        } // End .toolbar
        .sheet(isPresented: $showingCreateSheet) { // Define the modal sheet for creating opportunities
            // Present CreateOpportunityView, passing necessary ViewModels
            CreateOpportunityView()
                .environmentObject(viewModel)
                .environmentObject(authViewModel)
        }
        // Initial data fetch is handled by OpportunityViewModel's setupUserObservations
    } // End body


    // MARK: - Extracted Subview Builders (Helper Computed Properties)

    // --- View for Loading State ---
    private var loadingView: some View {
        ProgressView("Loading Opportunities...")
           .padding(.top, 50) // Add padding for better vertical positioning
    }

    // --- View Function for Error State ---
    // Takes the specific error message as input
    private func errorView(message: String) -> some View {
        VStack(spacing: 15) {
             Image(systemName: "exclamationmark.triangle.fill")
                 .font(.largeTitle)
                 .foregroundColor(.red)
             Text("Error Loading Data")
                .font(.headline)
             Text(message) // Display the actual error message
                 .font(.caption)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal)
             Button("Retry Fetch") { // Allow user to retry
                 viewModel.fetchOpportunities()
             }
                 .buttonStyle(.borderedProminent)
                 .tint(.orange)
         }
         .padding(.top, 50)
    }

    // --- View for Empty State ---
    // Displayed when no opportunities are available
    private var emptyStateView: some View {
        VStack(spacing: 15) {
             Image(systemName: "list.bullet.clipboard")
                 .font(.largeTitle)
                 .foregroundColor(.secondary)
             Text("No Opportunities Found")
                 .font(.headline)
             Text("Check back later or tap '+' to add a new volunteering opportunity.")
                 .font(.caption)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal)
             Button { // Allow user to manually check again
                 viewModel.fetchOpportunities()
             } label: {
                 Label("Check Again", systemImage: "arrow.clockwise")
             }
                 .buttonStyle(.bordered)
                 .padding(.top)
                 .disabled(viewModel.isLoading) // Disable if already loading
         }
        .padding(.top, 50)
    }

    // --- Composite View for List Display ---
    // This combines the actual List and the Refresh Button below it
    private var listDisplayView: some View {
        VStack { // Use VStack to arrange List and Button vertically
            actualListView // Embed the extracted List view
            refreshButton  // Embed the extracted Button view
        }
    }

    // --- Extracted: The Actual List View Content ---
    // Contains the List and ForEach logic
    private var actualListView: some View {
        List {
            // Iterate over opportunities using the view model's data
            // Use .id for ForEach as 'viewModel.opportunities' is not a Binding here
            ForEach(viewModel.opportunities, id: \.id) { opportunity in

                // NavigationLink to the detail screen for each opportunity
                NavigationLink {
                    // Destination View: Pass the specific opportunity
                    OpportunityDetailView(opportunity: opportunity)
                    // No need to pass environment objects if DetailView doesn't require them
                    // .environmentObject(viewModel) // Removed if not needed
                    // .environmentObject(authViewModel) // Removed if not needed
                } label: {
                    // Row Content View: Create OpportunityRowView
                    // No longer needs viewModel passed explicitly
                    OpportunityRowView(opportunity: opportunity)
                    // OpportunityRowView also doesn't need authViewModel via environment now
                }
                .buttonStyle(PlainButtonStyle()) // Ensure the whole row is tappable
                // --- .listRowBackground for coloring REMOVED ---

            } // End ForEach
        } // End List
        .listStyle(PlainListStyle()) // Use plain style for edge-to-edge list
        .refreshable { // Enable pull-to-refresh
            print("Pull to refresh triggered")
            viewModel.fetchOpportunities()
        }
    } // End actualListView computed property

    // --- Extracted: Refresh Button View ---
    // The manual refresh button displayed below the list
    private var refreshButton: some View {
        Button {
            print("Manual refresh button tapped")
            viewModel.fetchOpportunities()
        } label: {
            Label("Refresh List", systemImage: "arrow.clockwise")
        }
         // Standard bordered style
        .padding(.vertical)     // Add vertical spacing
        .disabled(viewModel.isLoading) // Disable while loading
    } // End refreshButton computed property

} // End struct OpportunityListView


