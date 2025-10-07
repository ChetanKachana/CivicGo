import SwiftUI

// MARK: - Opportunity Row View (with Status Highlighting and Debugging Logs)
struct OpportunityRowView: View {
    // MARK: - Properties
    let opportunity: Opportunity // Data for this specific row

    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access to favorites/RSVP state & actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access to user state/role

    // MARK: - State for Animation (Kept for potential re-introduction later)
    @State private var isPulsing: Bool = false

    // MARK: - Formatters (Static for efficiency)
    private static var timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter
    }()
    private static var durationFormatter: NumberFormatter = {
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter
     }()

    // MARK: - Computed Properties with Logging
    private var isLoggedInUser: Bool {
        let value = authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
        // print("[\(opportunity.name.prefix(8))] isLoggedInUser: \(value)") // Optional detailed log
        return value
    }
    private var isCreatedByCurrentManager: Bool {
        guard authViewModel.isManager, let currentUserId = authViewModel.userSession?.uid, let creatorId = opportunity.creatorUserId else { return false }
        let value = currentUserId == creatorId
        // print("[\(opportunity.name.prefix(8))] isCreatedByCurrentManager: \(value)") // Optional detailed log
        return value
    }
    private var isRsvpedByCurrentUser: Bool {
        let value = viewModel.isRsvped(opportunityId: opportunity.id)
        // --- Add Log ---
        print("[\(opportunity.name.prefix(15))] isRsvpedByCurrentUser CHECK: \(value) (ViewModel contains: \(viewModel.rsvpedOpportunityIds.contains(opportunity.id)))")
        // --- End Log ---
        return value
    }
    private var isFavoritedByCurrentUser: Bool {
         let value = viewModel.isFavorite(opportunityId: opportunity.id)
        // --- Add Log ---
        print("[\(opportunity.name.prefix(15))] isFavoritedByCurrentUser CHECK: \(value) (ViewModel contains: \(viewModel.favoriteOpportunityIds.contains(opportunity.id)))")
        // --- End Log ---
         return value
     }
    private var shouldShowTags: Bool {
        isCreatedByCurrentManager || isRsvpedByCurrentUser || isCurrentlyOccurring
    }
    private var hasEventEnded: Bool {
        opportunity.hasEnded
    }
    private var isCurrentlyOccurring: Bool {
        let value = opportunity.isCurrentlyOccurring
        // --- Add Log ---
        print("[\(opportunity.name.prefix(15))] isCurrentlyOccurring CHECK: \(value)")
        // --- End Log ---
        return value
    }

    // MARK: - Dynamic Row Background View (Simplified for Debugging)
    
        private var rowBackground: some View {
            let bgColor: Color // No longer optional

            if isCurrentlyOccurring {
                 // Pulsing logic can be re-added here if desired once basic color works
                 bgColor = Color.yellow.opacity(0.20) // Static Yellow for debug
            } else if isLoggedInUser && isRsvpedByCurrentUser {
                bgColor = Color.green.opacity(0.15)
            } else if isLoggedInUser && isFavoritedByCurrentUser {
                bgColor = Color.red.opacity(0.15)
            } else {
                // --- Use Color.clear for the default ---
                bgColor = Color(UIColor.secondarySystemGroupedBackground) // Represents the default/transparent background
            }
            // Log the determined background type for debugging (keep this)
            print("[\(opportunity.name.prefix(15))] rowBackground SELECTED: \(bgColor == .clear ? "Default (Clear)" : bgColor.description)")
            return bgColor // Return the decided color
        }


    // MARK: - Body
    var body: some View {
         // --- Add Log to see when body is evaluated ---
        let _ = print("[\(opportunity.name.prefix(15))] BODY evaluated.")
        // --- End Log ---

        HStack(alignment: .top) { // Main horizontal layout

            // --- Left Side: Event Details ---
            VStack(alignment: .leading, spacing: 5) {

                // --- Tags Area ---
                if shouldShowTags {
                    HStack(spacing: 5) {
                        // Tag for manager's own event
                        if isCreatedByCurrentManager {
                            tagView(text: "Your Event", color: .indigo, label: "This is an event you created.")
                        }
                        // Tag for RSVP status (only if not currently happening)
                        if isRsvpedByCurrentUser && !isCurrentlyOccurring {
                            tagView(text: hasEventEnded ? "Attended" : "Attending",
                                    color: .green,
                                    label: hasEventEnded ? "You attended this past event." : "You are RSVP'd.")
                        }
                        // Tag for currently occurring event
                        
                    }
                    .padding(.bottom, 3)
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
                     Image(systemName: "clock").foregroundColor(.secondary).font(.caption)
                     Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) - \(opportunity.endDate, formatter: Self.timeOnlyFormatter)")
                         .font(.caption).foregroundColor(.secondary)
                     if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                         Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.caption2).foregroundColor(.gray)
                     }
                 }
                 .padding(.top, 2)

                // Available Spots Display
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.checkmark.fill")
                        .font(.caption)
                        .foregroundColor(availabilityColor()) // Dynamic color
                    Text(availabilityText())
                        .font(.caption)
                        .foregroundColor(availabilityColor()) // Dynamic color
                        .fontWeight(opportunity.isFull ? .medium : .regular) // Emphasize if full
                }
                .padding(.top, 2)

                // Description Preview (Optional based on content)
              //  let desc = opportunity.description.trimmed()
              //  if !desc.isEmpty && desc != "No description." && desc != "No description provided." {
              //       Text(desc).font(.footnote).foregroundColor(.secondary).lineLimit(2).padding(.top, 1)
              //  }

            } // End VStack (Details)

            Spacer() // Pushes favorite button to the right

            // --- Right Side: Conditional Favorite Button ---
            // Show only if logged in, event hasn't ended, and NOT currently occurring or RSVP'd
            if isLoggedInUser && !hasEventEnded && !isCurrentlyOccurring && !isRsvpedByCurrentUser {
                Button { viewModel.toggleFavorite(opportunity: opportunity) } label: {
                    Image(systemName: isFavoritedByCurrentUser ? "heart.fill" : "heart")
                        .font(.title3).foregroundColor(isFavoritedByCurrentUser ? .red : .gray)
                        .frame(width: 44, height: 44, alignment: .center) // Decent tap target size
                }.buttonStyle(.plain) // Remove default button chrome
                 .transition(.opacity) // Animate favorite changes
                 .animation(.default, value: isFavoritedByCurrentUser) // Animate the heart fill change
            }
            // --- End Conditional Favorite Button ---

        } // End HStack (Main Row Layout)
        .padding(.vertical, 8) // Vertical padding for spacing between rows
        // --- Use the computed property for the background ---
        .listRowBackground(
            // Pass the computed background color/view
            rowBackground
        )
        .id("row_\(opportunity.id)_rsvp_\(isRsvpedByCurrentUser)_fav_\(isFavoritedByCurrentUser)_current_\(isCurrentlyOccurring)")
        // Remove explicit animation on background for now during debugging
        // .animation(.easeInOut(duration: 0.3), value: isRsvpedByCurrentUser)

    } // End body

    // Helper function to build Tag View for cleaner code
    @ViewBuilder
    private func tagView(text: String, color: Color, label: String) -> some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2)).foregroundColor(color).clipShape(Capsule())
            .accessibilityLabel(label)
    }

    // MARK: - Availability Helpers

    /// Determines the text to display based on spot availability.
    private func availabilityText() -> String {
        guard let max = opportunity.maxAttendees, max > 0 else {
            return "Unlimited spots" // Handle nil or 0 max attendees
        }

        let remaining = max - opportunity.attendeeCount
        if remaining > 0 {
            return "\(remaining) spot\(remaining == 1 ? "" : "s") available"
        } else {
            return "Event Full"
        }
    }

    /// Determines the color for the availability text and icon.
    private func availabilityColor() -> Color {
        guard let max = opportunity.maxAttendees, max > 0 else {
            return .secondary // Gray for unlimited
        }

        let remaining = max - opportunity.attendeeCount
        if remaining > 0 {
            return .secondary // Gray if spots are still available
        } else {
            return .orange // Orange/Warning color if full
        }
    }

} // End struct OpportunityRowView

// Make sure String extension for trimmed() exists somewhere accessible
