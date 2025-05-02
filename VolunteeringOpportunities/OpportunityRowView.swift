import SwiftUI

// MARK: - Opportunity Row View (Using .id() Modifier for RSVP Refresh - FINAL CORRECTED)
struct OpportunityRowView: View {
    // MARK: - Properties
    let opportunity: Opportunity // Data for this specific row
    // Removed let rsvpTriggerValue

    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access to favorites/RSVP state & actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access to user state/role

    // MARK: - Formatters (Static for efficiency)
    private static var timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter
    }()
    private static var durationFormatter: NumberFormatter = {
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter
     }()

    // MARK: - Computed Properties
    // Check if user is logged in and not anonymous
    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }
    // Check if the event was created by the current manager
    private var isCreatedByCurrentManager: Bool {
        guard authViewModel.isManager,
              let currentUserId = authViewModel.userSession?.uid,
              let creatorId = opportunity.creatorUserId
        else { return false }
        return currentUserId == creatorId
    }
    // Check if the current logged-in user has RSVP'd to this opportunity by reading ViewModel state
    private var isRsvpedByCurrentUser: Bool {
        viewModel.isRsvped(opportunityId: opportunity.id)
    }
    // Check if any tag should be displayed
    private var shouldShowTags: Bool {
        isCreatedByCurrentManager || isRsvpedByCurrentUser // isRsvped implies loggedInUser
    }
    // Check if the event has ended
    private var hasEventEnded: Bool {
        opportunity.hasEnded
    }

    // MARK: - Body
    var body: some View {
        // <<< CORRECTED: Read the trigger value into a local constant >>>
        let currentRsvpTriggerValue = viewModel.rsvpStateUpdateTrigger

        HStack(alignment: .top) { // Main horizontal layout for the row

            // --- Left Side: Event Details ---
            VStack(alignment: .leading, spacing: 5) { // Stack details vertically

                // --- Tags Area ---
                if shouldShowTags {
                    HStack(spacing: 5) { // Display tags side-by-side
                        if isCreatedByCurrentManager {
                            tagView(text: "Your Event", color: .green, label: "This is an event you created.")
                        }
                        if isRsvpedByCurrentUser { // <<< Uses computed property >>>
                            tagView(text: hasEventEnded ? "Attended" : "Attending",
                                    color: .orange,
                                    label: hasEventEnded ? "You attended this past event." : "You are RSVP'd.")
                        }
                    }
                    .padding(.bottom, 3) // Add padding below the HStack containing the tags
                } // End Tags Area

                // Event Name
                Text(opportunity.name).font(.headline).lineLimit(1)

                // Location Display
                if !opportunity.location.isEmpty {
                     HStack(spacing: 4) {
                         Image(systemName: "mappin.and.ellipse").font(.subheadline).foregroundColor(.secondary)
                         Text(opportunity.location).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                     }
                 }

                // Time Range and Duration Display
                HStack(spacing: 4) {
                     Image(systemName: "clock").foregroundColor(.blue).font(.caption)
                     Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) - \(opportunity.endDate, formatter: Self.timeOnlyFormatter)")
                         .font(.caption).foregroundColor(.secondary)
                     if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                         Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.caption2).foregroundColor(.gray)
                     }
                 }
                 .padding(.top, 2)

                // Attendee Count / Limit Display
                 HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.caption).foregroundColor(.secondary)
                    Text("Attendees: \(opportunity.attendeeCount)")
                    if let max = opportunity.maxAttendees, max > 0 { Text("/ \(max)"); if opportunity.isFull { Text("(Full)").foregroundColor(.orange).fontWeight(.medium) } }
                    else { Text("(Unlimited)") }
                 }
                 .font(.caption).foregroundColor(.secondary).padding(.top, 2)

                // Description Preview (Optional based on content)
                if !opportunity.description.isEmpty && opportunity.description != "No description provided." {
                     Text(opportunity.description).font(.footnote).foregroundColor(.secondary).lineLimit(2).padding(.top, 1)
                }

            } // End VStack (Details)

            Spacer() // Pushes favorite button to the right

            // --- Right Side: Conditional Favorite Button ---
            if isLoggedInUser && !hasEventEnded { // Show only if logged in and event hasn't ended
                Button { viewModel.toggleFavorite(opportunity: opportunity) } label: { // Action
                    Image(systemName: viewModel.isFavorite(opportunityId: opportunity.id) ? "heart.fill" : "heart")
                        .font(.title3).foregroundColor(viewModel.isFavorite(opportunityId: opportunity.id) ? .red : .gray) // Style
                        .frame(width: 44, height: 44, alignment: .center) // Tap Area
                }.buttonStyle(.plain) // Appearance
                 .transition(.opacity) // Animation
            }
            // --- End Conditional Favorite Button ---

        } // End HStack (Main Row Layout)
        .padding(.vertical, 8) // Vertical padding for spacing
        // Conditional Background Highlight for RSVP/Attended
        .listRowBackground(isLoggedInUser && isRsvpedByCurrentUser ? Color.green.opacity(0.15) : nil)
        // --- CORRECTED: Explicit ID Modifier Using LOCAL Trigger Constant ---
        .id("row_\(opportunity.id)_rsvpTrigger_\(currentRsvpTriggerValue)") // <<< Use local constant
        // --- End ID Modifier ---
        // Animate the background color change based on the computed property
        .animation(.easeInOut(duration: 0.3), value: isRsvpedByCurrentUser)

    } // End body

    // Helper function to build Tag View for cleaner code
    @ViewBuilder
    private func tagView(text: String, color: Color, label: String) -> some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2)).foregroundColor(color).clipShape(Capsule())
            .accessibilityLabel(label)
    }

} // End struct OpportunityRowView


