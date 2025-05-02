import SwiftUI
import FirebaseFirestore // Only needed if fetching directly here, not needed if ViewModel handles all

// MARK: - Leaderboard View
// Displays ranked users based on attended volunteer hours with filtering options.
struct LeaderboardView: View {
    // MARK: - State and Environment
    // Use @StateObject because this View OWNS the LeaderboardViewModel instance
    @StateObject private var viewModel = LeaderboardViewModel()
    // Action to dismiss the sheet presentation
    @Environment(\.dismiss) var dismiss

    // Animation namespace for the sliding filter highlight
    @Namespace private var filterAnimation

    // MARK: - Body
    var body: some View {
        NavigationView { // Embed in NavigationView for Title and Dismiss button
            VStack(spacing: 0) { // Main container, no spacing for seamless components
                // --- Custom Filter Bar ---
                // Show filter bar unless the view is initially loading with no data yet
                if !(viewModel.isLoading && viewModel.rankedUsers.isEmpty) {
                    filterBar // Use extracted computed property for the filter UI
                        .padding(.horizontal) // Padding around the filter bar
                        .padding(.vertical, 10) // Vertical padding for the bar area
                         // Background for the bar area
                }

                Divider() // Separator between filter bar and list content

                // --- Main Content Area (List, Loading, Error, Empty) ---
                // Use a Group to switch content based on ViewModel state
                Group {
                    if viewModel.isLoading {
                        // Show loading indicator while fetching data
                        ProgressView("Loading Leaderboard...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity) // Center vertically & horizontally
                    } else if let error = viewModel.errorMessage {
                        // Display error message if fetching failed
                        ErrorStateView(message: error) // Use helper view
                            .frame(maxHeight: .infinity) // Center vertically
                    } else if viewModel.rankedUsers.isEmpty {
                        // Show message if no data found for the selected filter
                        EmptyStateView(message: "No attendance data found for '\(viewModel.selectedTimeFilter.rawValue)'.") // Use helper view
                            .frame(maxHeight: .infinity) // Center vertically
                    } else {
                        // Display the ranked list of users
                        leaderboardList // Use extracted computed property for the List
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow content to expand

            } // End VStack
            .navigationTitle("Leaderboard") // Set the title
            .navigationBarTitleDisplayMode(.inline) // Use inline style
            .toolbar { // Add dismiss ('X') button to the toolbar
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                         Image(systemName: "xmark.circle.fill")
                             .imageScale(.large) // Make icon slightly larger
                             .foregroundStyle(.gray) // Use gray for less emphasis
                    }
                }
            }
            // Use .task modifier for async operations tied to view lifecycle
            .task {
                // Fetch data only if list is currently empty when view appears
                if viewModel.rankedUsers.isEmpty {
                     await viewModel.fetchLeaderboardData()
                }
            }
            // Enable pull-to-refresh functionality
            .refreshable {
                 await viewModel.fetchLeaderboardData() // Call fetch action on refresh
            }
            // Display error messages (general fetch errors) in an overlay at the bottom
            .overlay(alignment: .bottom) {
                errorOverlay // Use extracted computed property for the error overlay
            }
            // Animate the appearance/disappearance of the error overlay
            .animation(.default, value: viewModel.errorMessage != nil)

        } // End NavigationView
        // Apply specific navigation style if needed for iPad presentation consistency
        // .navigationViewStyle(.stack)
    } // End body

    // MARK: - Extracted View Builders

    /// Builds the custom, scrollable filter bar using Buttons.
    private var filterBar: some View {
        HStack(spacing: 0) { // Use 0 spacing; padding controls gap
             // Iterate through all defined time filters
            ForEach(LeaderboardViewModel.TimeFilter.allCases) { filter in
                filterButton(for: filter) // Use helper to build each button
                    .padding(.horizontal, 8) // Spacing between buttons
            }
             // Push buttons left (optional)
        }
        .frame(height: 36) // Constrain the height of the filter bar
        .padding(.vertical, 4) // Add vertical padding to the bar itself
        // Background capsule for the entire bar
        .background( Capsule().fill(Color(.systemGray5)) ) // Slightly darker gray background
        // Animate filter selection changes implicitly via state change
        .animation(.default, value: viewModel.selectedTimeFilter)
    }

    /// Builds a single filter button with text and animated background capsule.
    private func filterButton(for filter: LeaderboardViewModel.TimeFilter) -> some View {
        Button {
            // Action: Update the selected filter state and trigger refetch
            // Use smooth spring animation for selection change
            withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.7, blendDuration: 0.1)) {
                viewModel.selectedTimeFilter = filter
            }
            // Tell ViewModel to refetch data based on the new filter
            viewModel.filterChanged()
            print("Leaderboard Filter selected: \(filter.rawValue)")
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 13, weight: .medium)) // Font styling for filter text
                .padding(.vertical, 6)   // Vertical padding inside button
                .padding(.horizontal, 14) // Horizontal padding inside button
                .background { // Use background modifier for conditional capsule highlight
                    // Animate the capsule background using matchedGeometryEffect
                    if viewModel.selectedTimeFilter == filter {
                        Capsule()
                            .fill(Color(.systemBackground)) // Use system background (adapts to light/dark)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1) // Subtle shadow
                            .matchedGeometryEffect(id: "leaderboardFilterHighlight", in: filterAnimation) // Animation ID
                    }
                }
                // Adjust text color based on selection for contrast
                .foregroundColor(viewModel.selectedTimeFilter == filter ? Color(.label) : Color(.secondaryLabel)) // Use adaptable label colors
        }
        .buttonStyle(.plain) // Remove default button visual chrome
    }

    /// Builds the List displaying the ranked users.
    private var leaderboardList: some View {
        List {
            // --- Header Row ---
            HStack {
                Text("#").font(.caption).fontWeight(.semibold).frame(width: 35, alignment: .leading) // Rank column header
                Text("User").font(.caption).fontWeight(.semibold) // Username column header
                Spacer() // Push hours header to the right
                Text("Hours").font(.caption).fontWeight(.semibold).frame(width: 60, alignment: .trailing) // Hours column header
            }
            .foregroundStyle(.secondary) // Use secondary color for header text
            .listRowSeparator(.hidden) // Hide separator for header row
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)) // Adjust header padding

            // --- Ranked User Rows ---
            // Iterate over the ranked users provided by the ViewModel
            ForEach(viewModel.rankedUsers) { user in
                HStack {
                    // Rank Column
                    Text("\(user.rank ?? 0)") // Show rank (default 0 if somehow nil)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(width: 35, alignment: .leading) // Fixed width for alignment

                    // Username Column
                    Text(user.username)
                        .font(.subheadline)
                        .lineLimit(1) // Prevent long names wrapping excessively

                    Spacer() // Push hours to the right

                    // Hours Column
                    Text(formatHours(user.totalHours)) // Format hours using helper
                        .font(.subheadline.monospacedDigit()) // Monospaced for number alignment
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .trailing) // Fixed width for alignment
                }
                // Apply background highlight based on rank (top 3)
                .listRowBackground(rankBackgroundColor(for: user.rank))
                .listRowSeparator(.hidden) // Hide separators between user rows
                .padding(.vertical, 6) // Add padding inside each row's background
            }
        } // End List
        .listStyle(.plain) // Use plain style for custom row backgrounds and spacing
        .contentMargins(.horizontal, 0, for: .scrollContent) // Reduce default horizontal inset if needed
    }

    /// Builds the error message overlay displayed at the bottom.
    @ViewBuilder
    private var errorOverlay: some View {
        // Show overlay only if there's a general error message from the LeaderboardViewModel
        if let error = viewModel.errorMessage {
             Text(error)
                 .font(.caption).foregroundColor(.white).padding(10) // Style error text
                 .background(Color.black.opacity(0.75), in: Capsule()) // Dark background
                 .padding(.bottom) // Padding from the bottom edge
                 .transition(.opacity.combined(with: .move(edge: .bottom))) // Animate appearance/disappearance
                 .id("ErrorOverlay_\(error)") // Use error as ID to help transition on change
                 // Removed the .onAppear call to clear error after delay
         }
     }


    // MARK: - Helper Functions

    /// Formats the hours for display (e.g., "10.5", "8").
    private func formatHours(_ hours: Double) -> String {
        // Use basic string formatting, removing trailing ".0" for whole numbers
        return String(format: "%.1f", hours).replacingOccurrences(of: ".0", with: "")
    }

    /// Determines the background color for a row based on rank.
    private func rankBackgroundColor(for rank: Int?) -> Color? {
        guard let rank = rank else { return nil } // No color if rank is nil
        switch rank {
        case 1: return Color.red.opacity(0.15)   // Light red for 1st
        case 2: return Color.orange.opacity(0.15) // Light orange for 2nd
        case 3: return Color.green.opacity(0.15)  // Light green for 3rd
        default: return nil                      // Default (clear) background for others
        }
    }

    // MARK: - Helper Empty/Error Views (Defined inline for completeness)
    /// Simple view to display when the list is empty.
    struct EmptyStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "chart.bar.xaxis").font(.system(size: 50)).foregroundColor(.secondary); Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding(); Spacer() }
        }
    }
    /// Simple view to display when an error occurs.
     struct ErrorStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.largeTitle); Text(message).foregroundColor(.red).multilineTextAlignment(.center).padding(.top, 4); Spacer() }.padding()
        }
    }

} // End struct LeaderboardView

