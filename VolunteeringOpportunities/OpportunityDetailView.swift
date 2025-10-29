import SwiftUI
import MapKit       // For Map view
import CoreLocation // For CLGeocoder (address to coordinates)
import FirebaseFirestore // For Timestamp used in Preview mock data

// MARK: - Opportunity Detail View (Prevent RSVP/Delete Updates)
// Displays the full details of a selected volunteering opportunity.
// Includes organizer name (hidden for guests), map, RSVP, Edit/Delete, View Attendees.
// Prevents RSVP changes during the event and prevents deletion of past events.
struct OpportunityDetailView: View {
    // MARK: - Properties
    let opportunity: Opportunity

    // MARK: - Environment & State
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access opportunity actions and state
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access user role and fetchUsername action
    @Environment(\.dismiss) var dismiss                          // Action to dismiss the current view

    // State for presenting modals/alerts
    @State private var showingEditSheet = false             // Controls presentation of the edit sheet
    @State private var showingDeleteConfirm = false         // Controls presentation of the delete alert
    @State private var showingAttendeeListSheet = false     // Controls presentation of the attendee list sheet

    // State for Organizer Name
    @State private var organizerUsername: String? = nil      // Stores the fetched organizer username, starts nil
    @State private var isLoadingOrganizer = false           // Loading indicator for organizer name fetch, starts false

    // Map State Variables
    @State private var coordinateRegion: MKCoordinateRegion? = nil
    @State private var mapMarkerCoordinate: CLLocationCoordinate2D? = nil
    @State private var geocodingErrorMessage: String? = nil

    // MARK: - Formatters (Static)
    private static var fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter
    }()
    private static var timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter
    }()
    private static var durationFormatter: NumberFormatter = {
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter
     }()

    // MARK: - Computed Properties for State Checks
    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }
    private var isRsvpedByCurrentUser: Bool {
        viewModel.isRsvped(opportunityId: opportunity.id)
    }
    // Should the RSVP button/status area be visible at all?
    private var canShowRsvpArea: Bool {
        isLoggedInUser && !opportunity.hasEnded // Logged in and event hasn't ended
    }
    // Can the user actually interact with the RSVP/Cancel buttons?
    private var canPerformRsvp: Bool {
        isLoggedInUser &&                   // Must be logged in
        !opportunity.hasEnded &&            // Event must not have ended
        !opportunity.isCurrentlyOccurring && // Event must NOT be currently ongoing
        !viewModel.isTogglingRsvp           // Not already processing an RSVP toggle
    }
    // Can the event be EDITED by a manager? (Not if ended)
    private var canEditEvent: Bool {
            guard let currentUserId = authViewModel.userSession?.uid else { return false }
            return authViewModel.isManager && // Must be a manager
                   opportunity.creatorUserId == currentUserId && // Must be the creator
                   !opportunity.hasEnded // Event must not have ended
        }
        // --- END MODIFIED ---

        // --- MODIFIED: Can the event be DELETED by the current manager? ---
        private var canDeleteEvent: Bool {
            guard let currentUserId = authViewModel.userSession?.uid else { return false }
            return authViewModel.isManager && // Must be a manager
                   opportunity.creatorUserId == currentUserId && // Must be the creator
                   !opportunity.hasEnded // Event must not have ended
        }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { // Main content stack

                eventNameAndOrganizerSection // Extracted
                Divider()
                whenSection                  // Extracted
                Divider()
                whereSection                 // Extracted
                Divider()
                descriptionSection           // Extracted
                Divider()
                attendeeSection              // Extracted

                // --- RSVP Area (Conditional) ---
                // Shown if user is logged in and event hasn't ended
                if canShowRsvpArea {
                     Divider()
                     rsvpButtonArea // Buttons may be disabled based on `canPerformRsvp`
                     // Display RSVP-specific errors OR info message if ongoing
                     if let rsvpError = viewModel.rsvpErrorMessage {
                          // Show ViewModel errors first
                          Text(rsvpError)
                              .font(.caption).foregroundColor(.red)
                              .frame(maxWidth: .infinity, alignment: .center)
                              .padding(.top, 4)
                     } else if opportunity.isCurrentlyOccurring {
                         // Show info message if event is ongoing (RSVP buttons will be disabled)
                          Text("RSVP cannot be changed while the event is ongoing.")
                              .font(.caption).foregroundColor(.orange)
                              .frame(maxWidth: .infinity, alignment: .center)
                              .padding(.top, 4)
                     }
                }
                // --- End RSVP Area ---

                Divider()
                mapSection           // Extracted (Includes Link behavior)

            } // End Main VStack Content
            .padding() // Padding around the entire content stack
        } // End ScrollView
        .navigationTitle("Details") // Concise title
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { // Toolbar uses updated computed properties
             // Only show Edit/Delete toolbar items if the current user is a manager
             if authViewModel.isManager {
                 managerToolbarItems // Use extracted toolbar content property
             }
         }
         .sheet(isPresented: $showingEditSheet) { // --- Edit Sheet ---
             // Present CreateOpportunityView configured for editing *this* opportunity
             CreateOpportunityView(opportunityToEdit: opportunity)
                  .environmentObject(viewModel).environmentObject(authViewModel)
         }
         .sheet(isPresented: $showingAttendeeListSheet) { // --- Attendee List Sheet ---
             // Present the AttendeeListView
             AttendeeListView(
                 opportunityId: opportunity.id,
                 opportunityName: opportunity.name,
                 attendeeIds: opportunity.attendeeIds,
                 isEventCreator: opportunity.creatorUserId == authViewModel.userSession?.uid,
                 isEventCurrentlyOccurring: opportunity.isCurrentlyOccurring,
                 initialAttendanceRecords: opportunity.attendanceRecords ?? [:]
             )
             .environmentObject(viewModel).environmentObject(authViewModel) // Pass ViewModels
         }
         .alert("Confirm Delete", isPresented: $showingDeleteConfirm) { // --- Delete Alert ---
             Button("Delete", role: .destructive) { performDelete() } // Call delete action
             Button("Cancel", role: .cancel) {} // Standard cancel button
         } message: {
              Text("Are you sure you want to permanently delete '\(opportunity.name)'? This action cannot be undone.")
         }
         .onAppear { // Actions when view appears
             geocodeAddress() // Fetch map coordinates
             if isLoggedInUser { fetchOrganizerName() } // Fetch organizer name only if logged in
             // Clear action-specific errors when view appears
             viewModel.rsvpErrorMessage = nil
             viewModel.attendanceErrorMessage = nil
             // Keep general errorMessage if needed (e.g., if delete failed just before navigating back)
         }

    } // End body

    // MARK: - Extracted View Builders

    /// Section displaying Event Name and Organizer Name (Hides organizer info for guests)
    @ViewBuilder private var eventNameAndOrganizerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(opportunity.name).font(.largeTitle).fontWeight(.bold).padding(.bottom, 2)
            if isLoggedInUser { // Show organizer info only if the user is logged in
                if isLoadingOrganizer {
                    HStack(spacing: 5) { Text("Organized by:").font(.headline); ProgressView().scaleEffect(0.7).padding(.leading, -2) }.foregroundColor(.secondary)
                } else if let organizer = organizerUsername, !organizer.isEmpty {
                    Text("Organized by: \(organizer)").font(.headline).foregroundColor(.secondary)
                } else if let creatorId = opportunity.creatorUserId, !creatorId.isEmpty {
                    // Fallback if username fetch fails or field missing
                    Text("Organized by: User (\(creatorId.prefix(6))...)").font(.subheadline).foregroundColor(.gray)
                }
                // If creatorId is also nil/empty, nothing is shown for organizer
            }
        }
    }

    /// Displays Date, Time Range, and Duration.
    private var whenSection: some View {
         VStack(alignment: .leading, spacing: 8) {
              Text(opportunity.eventDate, formatter: Self.fullDateFormatter).font(.title3).fontWeight(.semibold)
              HStack(spacing: 4) {
                  Image(systemName: "clock.fill").foregroundColor(.blue).frame(width: 20)
                  Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) to \(opportunity.endDate, formatter: Self.timeOnlyFormatter)").font(.body)
                  // Display duration if valid
                  if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                      Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.body).foregroundColor(.secondary)
                  }
              }
         }
    }

    /// Displays Location (as a Link if possible).
    @ViewBuilder private var whereSection: some View {
        // Attempt to create URL for linking
        if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
            Link(destination: url) {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20)
                    Text(opportunity.location).font(.body).foregroundColor(.accentColor).multilineTextAlignment(.leading)
                }
            }.buttonStyle(.plain) // Use plain style for link appearance
        } else if !opportunity.location.isEmpty {
            // Display as plain text if location exists but URL failed or is empty
            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20)
                Text(opportunity.location).font(.body).foregroundColor(.primary).multilineTextAlignment(.leading)
            }
        }
        // If opportunity.location is empty, nothing is displayed for this section
    }

    /// Displays the Event Description.
    private var descriptionSection: some View {
        VStack(alignment: .leading) {
            Text("Description").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
            // Use a default message if description is empty
            Text(opportunity.description.isEmpty ? "No description provided." : opportunity.description)
                .font(.body)
                .foregroundColor(opportunity.description.isEmpty ? .secondary : .primary) // Gray out default text
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Displays Attendee Count/Limit and View List button for manager.
    private var attendeeSection: some View {
        HStack {
            Image(systemName: "person.3.fill").foregroundColor(.purple).frame(width: 25)
            Text("Attendees: \(opportunity.attendeeCount)") // Current count
            // Display max count or unlimited
            if let max = opportunity.maxAttendees, max > 0 {
                Text(" / \(max) Max")
            } else {
                Text(" (Unlimited)")
            }
            Spacer()
            // Show "View List" button only for managers AND if there are attendees
            if authViewModel.isManager && opportunity.attendeeCount > 0 {
                Button("View List") { showingAttendeeListSheet = true }
                    .font(.footnote).buttonStyle(.bordered).tint(.secondary)
            }
        }.font(.subheadline)
    }

    /// Displays the RSVP / Cancel RSVP Button area, using `canPerformRsvp`.
    @ViewBuilder private var rsvpButtonArea: some View {
        VStack(spacing: 5) {
            HStack{
                Spacer()
                if viewModel.isTogglingRsvp { // Loading state
                    ProgressView("Updating RSVP...").padding(.vertical, 10)
                } else { // Buttons based on RSVP status
                    if isRsvpedByCurrentUser { // --- Cancel Button ---
                        Button { viewModel.toggleRSVP(opportunity: opportunity) } label: {
                            Label("Cancel RSVP", systemImage: "person.fill.xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.red)
                        .disabled(!canPerformRsvp) // Disable based on computed property
                        .accessibilityLabel("Cancel RSVP for \(opportunity.name)")
                        // Show "You are attending" only if RSVP is possible (not ongoing)
                        if !opportunity.isCurrentlyOccurring {
                            Text("You are attending!").font(.caption).foregroundColor(.green).padding(.top, 2)
                        }
                        
                    } else { // --- RSVP Button ---
                        Button { viewModel.toggleRSVP(opportunity: opportunity) } label: {
                            Label("RSVP (I'm Going!)", systemImage: "person.fill.checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                        // Disable if full OR if cannot perform RSVP (e.g., ongoing)
                        .disabled(opportunity.isFull || !canPerformRsvp)
                        .accessibilityLabel("RSVP for \(opportunity.name)")
                        // Show "Event full" message only if full AND not ongoing
                        if opportunity.isFull && !opportunity.isCurrentlyOccurring {
                            Text("Event is full.").font(.caption).foregroundColor(.orange).padding(.top, 2)
                        }
                    }
                }
                Spacer()
            }
        }.frame(maxWidth: .infinity) // Center buttons horizontally
         .animation(.default, value: viewModel.isTogglingRsvp) // Animate loading state
         .animation(.default, value: isRsvpedByCurrentUser) // Animate button switch
    }

    /// Displays the Map section with interactive map or error/loading states.
    @ViewBuilder private var mapSection: some View {
         VStack(alignment: .leading) {
             Text("Location Map").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
             // Wrap map in Link if URL is valid
             if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
                  Link(destination: url) { mapView }.buttonStyle(.plain) // Link wraps map view
             } else { mapView } // Show map without link if no valid URL
         }
    }

    /// Builds the actual MapKit View, Loading, or Error state.
    @ViewBuilder private var mapView: some View {
        let isMapLinked = mapsURL(for: opportunity.location) != nil && !opportunity.location.isEmpty
        Group { // Group needed for conditional logic in @ViewBuilder
            if let region = coordinateRegion { // Map ready
                Map(position: .constant(.region(region))) {
                     if let coord = mapMarkerCoordinate { Marker(opportunity.name, coordinate: coord) }
                }
                .overlay(alignment: .topTrailing) { // Show link icon if map is tappable
                     if isMapLinked { Image(systemName: "arrow.up.forward.app.fill").padding(5).font(.callout).foregroundStyle(.secondary).background(.ultraThinMaterial, in: Circle()).padding(6).accessibilityLabel("Open location in Maps") }
                }
                .allowsHitTesting(!isMapLinked) // Disable map interaction ONLY if it's wrapped in a Link

            } else if let mapError = geocodingErrorMessage { // Error state
                HStack { Spacer(); Image(systemName: "exclamationmark.triangle").foregroundColor(.orange); Text("Map Error: \(mapError)").font(.caption).foregroundColor(.secondary); Spacer() }
                    .frame(alignment: .center) // Center error content

            } else { // Loading state
                HStack { Spacer(); ProgressView(); Text("Loading map...").font(.caption).foregroundColor(.secondary); Spacer() }
                    .frame(alignment: .center) // Center loading content
            }
        }
        .frame(height: 250) // Consistent height for map area
        .clipShape(RoundedRectangle(cornerRadius: 10)) // Rounded corners
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1)) // Border
    }

    /// Builds the Edit/Delete buttons for the toolbar (Managers only), disabling based on event state.
    private var managerToolbarItems: some ToolbarContent {
           ToolbarItemGroup(placement: .navigationBarTrailing) {
               // Edit Button - Show only if canEditEvent is true
               if canEditEvent { // <<< ADDED if condition
                   Button {
                       // Action remains the same
                       viewModel.errorMessage = nil; showingEditSheet = true
                   } label: {
                       Label("Edit", systemImage: "pencil.circle.fill")
                   }
                   // .disabled(!canEditEvent) // No longer needed if hiding
                   .accessibilityLabel("Edit Opportunity")
               }

               // Delete Button - Show only if canDeleteEvent is true
               if canDeleteEvent { // <<< ADDED if condition
                   Button(role: .destructive) {
                       // Action remains the same
                        viewModel.errorMessage = nil; showingDeleteConfirm = true
                   } label: {
                        Label("Delete", systemImage: "trash.circle.fill")
                   }
                   // .disabled(!canDeleteEvent) // No longer needed if hiding
                   .accessibilityLabel("Delete Opportunity")
               }
           }
       }

    // MARK: - Action Methods

    /// Calls the ViewModel to delete the opportunity and dismisses the view.
    private func performDelete() {
        // The guard in the Button action should prevent this if !canDeleteEvent
        print("User confirmed delete for opportunity: \(opportunity.id)")
        viewModel.deleteOpportunity(opportunityId: opportunity.id)
        // Consider dismissing only on success? For now, dismiss immediately.
        dismiss()
    }

    /// Converts the opportunity's address string into map coordinates.
    private func geocodeAddress() {
        // Reset state before starting
        coordinateRegion = nil; mapMarkerCoordinate = nil; geocodingErrorMessage = nil
        guard !opportunity.location.isEmpty else {
            self.geocodingErrorMessage = "Address is empty."
            print("Skipping geocoding: Address is empty.")
            return
        }
        print("Starting geocoding for address: \(opportunity.location)")
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(opportunity.location) { (placemarks, error) in
            // Ensure UI updates are on main thread
            DispatchQueue.main.async {
                if let error = error {
                    self.geocodingErrorMessage = error.localizedDescription
                    print("Geocoding failed: \(error.localizedDescription)")
                    return // Exit on error
                }
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    self.geocodingErrorMessage = "Address not found."
                    print("Geocoding failed: Address not found.")
                    return // Exit if no placemark found
                }
                let coordinate = location.coordinate
                self.mapMarkerCoordinate = coordinate // Set marker coordinate
                // Set map region centered on the coordinate
                self.coordinateRegion = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1000, // Zoom level (1km radius)
                    longitudinalMeters: 1000
                )
                print("Geocoding successful: \(coordinate.latitude), \(coordinate.longitude)")
            }
        }
    }

    /// Creates a URL for Apple Maps search, returning nil if encoding fails or address is empty.
    private func mapsURL(for address: String) -> URL? {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !encodedAddress.isEmpty else { return nil }
         return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
    }

    /// Fetches the organizer's username asynchronously.
    private func fetchOrganizerName() {
            // Ensure user is logged in and we have a creator ID
            guard isLoggedInUser, let creatorId = opportunity.creatorUserId, !creatorId.isEmpty else { return }
            // Avoid refetching if already loading or name is already fetched
            guard organizerUsername == nil && !isLoadingOrganizer else { return }

            print("Fetching organizer username for ID: \(creatorId)")
            isLoadingOrganizer = true
            let opportunityIdWhenFetchStarted = opportunity.id // Capture ID for safety check

            // Call the async fetch function from AuthViewModel
            // --- REMOVE [weak self] ---
            authViewModel.fetchUsername(for: creatorId) { fetchedName in
                 // --- Use Task @MainActor to update state ---
                 Task { @MainActor in
                     // 'self' here refers to the OpportunityDetailView struct instance
                     // at the time this closure is executed.

                     // Ensure the view is still displaying the same opportunity
                     // Accessing 'self.opportunity.id' is fine here.
                     guard self.opportunity.id == opportunityIdWhenFetchStarted else {
                         // If the opportunity changed while fetching, just stop loading and exit.
                         print("Opportunity changed while fetching username, discarding result.")
                         self.isLoadingOrganizer = false // Ensure loading stops
                         return
                     }

                     // Update state directly using self.
                     self.organizerUsername = fetchedName
                     self.isLoadingOrganizer = false
                     print("Organizer username fetch complete: \(fetchedName ?? "nil")")
                 } // --- End Task @MainActor ---
            } // --- End fetchUsername completion handler ---
        }
} // End struct OpportunityDetailView
