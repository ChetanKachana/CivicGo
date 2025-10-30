import SwiftUI

// MARK: - Opportunity Row View
struct OpportunityRowView: View {
    // MARK: - Properties
    let opportunity: Opportunity

    // MARK: - Environment Objects
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // MARK: - State for Animation 
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
        return value
    }
    private var isCreatedByCurrentManager: Bool {
        guard authViewModel.isManager, let currentUserId = authViewModel.userSession?.uid, let creatorId = opportunity.creatorUserId else { return false }
        let value = currentUserId == creatorId
        return value
    }
    private var isRsvpedByCurrentUser: Bool {
        let value = viewModel.isRsvped(opportunityId: opportunity.id)
        print("[\(opportunity.name.prefix(15))] isRsvpedByCurrentUser CHECK: \(value) (ViewModel contains: \(viewModel.rsvpedOpportunityIds.contains(opportunity.id)))")
        return value
    }
    private var isFavoritedByCurrentUser: Bool {
         let value = viewModel.isFavorite(opportunityId: opportunity.id)
        print("[\(opportunity.name.prefix(15))] isFavoritedByCurrentUser CHECK: \(value) (ViewModel contains: \(viewModel.favoriteOpportunityIds.contains(opportunity.id)))")
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
        print("[\(opportunity.name.prefix(15))] isCurrentlyOccurring CHECK: \(value)")
        return value
    }

    // MARK: - Dynamic Row Background View (Simplified for Debugging)
    
        private var rowBackground: some View {
            let bgColor: Color // No longer optional

            if isCurrentlyOccurring {
               
                 bgColor = Color.yellow.opacity(0.20)
            } else if isLoggedInUser && isRsvpedByCurrentUser {
                bgColor = Color.green.opacity(0.15)
            } else if isLoggedInUser && isFavoritedByCurrentUser {
                bgColor = Color.red.opacity(0.15)
            } else {
                bgColor = Color(UIColor.secondarySystemGroupedBackground)
            }
            print("[\(opportunity.name.prefix(15))] rowBackground SELECTED: \(bgColor == .clear ? "Default (Clear)" : bgColor.description)")
            return bgColor
        }


    // MARK: - Body
    var body: some View {
        let _ = print("[\(opportunity.name.prefix(15))] BODY evaluated.")

        HStack(alignment: .top) {

            VStack(alignment: .leading, spacing: 5) {

                if shouldShowTags {
                    HStack(spacing: 5) {
                        if isCreatedByCurrentManager {
                            tagView(text: "Your Event", color: .indigo, label: "This is an event you created.")
                        }
                        if isRsvpedByCurrentUser && !isCurrentlyOccurring {
                            tagView(text: hasEventEnded ? "Attended" : "Attending",
                                    color: .green,
                                    label: hasEventEnded ? "You attended this past event." : "You are RSVP'd.")
                        }
                        
                    }
                    .padding(.bottom, 3)
                }
                Text(opportunity.name).font(.headline).lineLimit(1)

                if !opportunity.location.isEmpty {
                     HStack(spacing: 4) {
                         Image(systemName: "mappin.and.ellipse").font(.subheadline).foregroundColor(.secondary)
                         Text(opportunity.location).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                     }
                 }

                HStack(spacing: 4) {
                     Image(systemName: "clock").foregroundColor(.secondary).font(.caption)
                     Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) - \(opportunity.endDate, formatter: Self.timeOnlyFormatter)")
                         .font(.caption).foregroundColor(.secondary)
                     if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                         Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.caption2).foregroundColor(.gray)
                     }
                 }
                 .padding(.top, 2)

                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.checkmark.fill")
                        .font(.caption)
                        .foregroundColor(availabilityColor())
                    Text(availabilityText())
                        .font(.caption)
                        .foregroundColor(availabilityColor())
                        .fontWeight(opportunity.isFull ? .medium : .regular)
                }
                .padding(.top, 2)

             

            }

            Spacer()

           
            if isLoggedInUser && !hasEventEnded && !isCurrentlyOccurring && !isRsvpedByCurrentUser {
                Button { viewModel.toggleFavorite(opportunity: opportunity) } label: {
                    Image(systemName: isFavoritedByCurrentUser ? "heart.fill" : "heart")
                        .font(.title3).foregroundColor(isFavoritedByCurrentUser ? .red : .gray)
                        .frame(width: 44, height: 44, alignment: .center)
                }.buttonStyle(.plain)
                    .transition(.opacity)
                .animation(.default, value: isFavoritedByCurrentUser) }

        }
        .padding(.vertical, 8)
       
        .listRowBackground(
            rowBackground
        )
        .id("row_\(opportunity.id)_rsvp_\(isRsvpedByCurrentUser)_fav_\(isFavoritedByCurrentUser)_current_\(isCurrentlyOccurring)")
       
    }

    
    @ViewBuilder
    private func tagView(text: String, color: Color, label: String) -> some View {
        Text(text).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2)).foregroundColor(color).clipShape(Capsule())
            .accessibilityLabel(label)
    }

    // MARK: - Availability Helpers

    private func availabilityText() -> String {
        guard let max = opportunity.maxAttendees, max > 0 else {
            return "Unlimited spots"
        }

        let remaining = max - opportunity.attendeeCount
        if remaining > 0 {
            return "\(remaining) spot\(remaining == 1 ? "" : "s") available"
        } else {
            return "Event Full"
        }
    }

    private func availabilityColor() -> Color {
        guard let max = opportunity.maxAttendees, max > 0 else {
            return .secondary
        }

        let remaining = max - opportunity.attendeeCount
        if remaining > 0 {
            return .secondary
        } else {
            return .orange
        }
    }

}
