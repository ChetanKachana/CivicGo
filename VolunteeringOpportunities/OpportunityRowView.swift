import SwiftUI
import FirebaseFirestore // Needed only for Preview mock data below

// MARK: - Opportunity Row View
// Displays a summary of a single volunteering opportunity in a list.
// Includes a tappable link for the location and a conditional favorite button.
struct OpportunityRowView: View {
    // MARK: - Properties
    let opportunity: Opportunity          // The specific opportunity data for this row
    @EnvironmentObject var viewModel: OpportunityViewModel // Access favorite status and toggle action
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access user authentication state

    // MARK: - Formatters (Static for efficiency)
    private static var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a" // Example: "9:30 AM" / "1:00 PM"
        return formatter
    }()
    private static var dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // Example: "Oct 29"
        return formatter
    }()

    // MARK: - Body
    var body: some View {
        // Use an HStack for the main layout: Details on left, Button potentially on right.
        HStack(alignment: .top) { // Align content to the top vertically
            // Left side: Details about the opportunity
            VStack(alignment: .leading, spacing: 5) { // Stack details vertically
                // Opportunity Name
                Text(opportunity.name)
                    .font(.headline)
                    .lineLimit(1) // Prevent name from taking too many lines

                // Location Link (Uses helper subview for cleaner code)
                LocationLinkView(location: opportunity.location)

                // Date and Time info
                HStack(spacing: 4) { // Display date/time horizontally
                    Image(systemName: "calendar")
                        .foregroundColor(.red) // Keep icon for visual cue
                        .font(.caption)
                    Text("\(opportunity.eventDate, formatter: Self.dayMonthFormatter), \(opportunity.eventDate, formatter: Self.timeFormatter) - \(opportunity.endDate, formatter: Self.timeFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary) // Less emphasis on time
                }

                // Trimmed Description (Show only if provided and not default text)
                if !opportunity.description.isEmpty && opportunity.description != "No description provided." {
                     Text(opportunity.description)
                         .font(.footnote) // Smaller font for description preview
                         .foregroundColor(.secondary)
                         .lineLimit(2) // Limit description preview to 2 lines
                         .padding(.top, 1) // Small space above description
                }
            } // End VStack (Details)

            Spacer() // Pushes the favorite button (if shown) to the trailing edge

            // --- Conditional Favorite Button ---
            // Show button ONLY if user is logged in AND NOT anonymous
            if let user = authViewModel.userSession, !user.isAnonymous {
                Button {
                    // Action: Call the toggleFavorite method on the ViewModel instance
                    viewModel.toggleFavorite(opportunity: opportunity)
                } label: {
                    // Appearance: Dynamically choose heart icon based on favorite status
                    Image(systemName: viewModel.isFavorite(opportunityId: opportunity.id) ? "heart.fill" : "heart")
                        .font(.title3) // Slightly larger icon for easier tapping
                        .foregroundColor(viewModel.isFavorite(opportunityId: opportunity.id) ? .red : .gray) // Red when favorited
                        // Define a frame to ensure consistent size and tap area
                        .frame(width: 44, height: 44, alignment: .center) // Centered alignment within frame
                }
                .buttonStyle(.plain) // Use plain style to show only the icon without button chrome
            }
            // --- End Conditional Favorite Button ---

        } // End HStack (Main Row Layout)
        .padding(.vertical, 8) // Vertical padding for spacing between rows in a List
    } // End body
} // End struct OpportunityRowView


