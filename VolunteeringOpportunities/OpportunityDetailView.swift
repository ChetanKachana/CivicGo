import SwiftUI
import MapKit       // For Map view
import CoreLocation // For CLGeocoder (address to coordinates)
import FirebaseFirestore // For Timestamp used in Preview mock data

// MARK: - Opportunity Detail View (Using .id for RSVP Refresh)
// Displays the full details of a selected volunteering opportunity.
// Includes organizer name (hidden for guests), map, RSVP, Edit/Delete, View Attendees.
// Uses .id() modifier driven by ViewModel counter to force RSVP UI refresh.
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
    @State private var showRefreshPrompt: Bool = false      // Controls presentation of the refresh prompt

    // State for Organizer Name
    @State private var organizerUsername: String? = nil      // Stores the fetched organizer username, starts nil
    @State private var isLoadingOrganizer = false           // Loading indicator for organizer name fetch, starts false

    // Removed localIsRsvped state

    // Map State Variables
    @State private var coordinateRegion: MKCoordinateRegion? = nil
    @State private var mapMarkerCoordinate: CLLocationCoordinate2D? = nil
    @State private var geocodingErrorMessage: String? = nil

    // MARK: - Formatters
    private static var fullDateFormatter: DateFormatter = { // For displaying the full date
        let formatter = DateFormatter(); formatter.dateStyle = .full; formatter.timeStyle = .none; return formatter }()
    private static var timeOnlyFormatter: DateFormatter = { // For displaying only the time
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short; return formatter }()
    private static var durationFormatter: NumberFormatter = { // For displaying duration
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter }()

    // MARK: - Computed Properties for State Checks
    private var isLoggedInUser: Bool { // Is user logged in and not anonymous?
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }
    // Read RSVP status directly from ViewModel
    private var isRsvpedByCurrentUser: Bool {
        viewModel.isRsvped(opportunityId: opportunity.id)
    }
    private var canShowRsvpArea: Bool { // Should the RSVP buttons be visible?
        isLoggedInUser && !opportunity.hasEnded
    }
    private var canPerformRsvp: Bool { // Can the user currently tap the RSVP/Cancel button?
        isLoggedInUser && !opportunity.hasEnded && !viewModel.isTogglingRsvp
    }
    // Determines if the Edit button should be enabled
    private var canEditEvent: Bool {
        authViewModel.isManager && !opportunity.hasEnded
    }

    // MARK: - Body
    var body: some View {
        ScrollView { // Allow content scrolling
            VStack(alignment: .leading, spacing: 20) { // Main content stack

                // --- Event Name and Organizer ---
                eventNameAndOrganizerSection // Extracted ViewBuilder property

                Divider() // Visual separator
                whenSection          // Extracted ViewBuilder property (Includes duration)
                Divider()
                whereSection         // Extracted ViewBuilder property (Includes Link)
                Divider()
                descriptionSection   // Extracted ViewBuilder property
                Divider()
                attendeeSection      // Extracted ViewBuilder property (Includes View List button)

                // --- RSVP Area (Conditional) ---
                if canShowRsvpArea { // Show only if user can potentially RSVP
                     Divider()
                     rsvpButtonArea // Extracted view uses isRsvpedByCurrentUser
                         // Apply .id() modifier to force redraw on trigger change
                         .id("rsvpArea_\(opportunity.id)_trigger_\(viewModel.rsvpStateUpdateTrigger)")
                     // Display RSVP-specific errors below the button area
                     if let rsvpError = viewModel.rsvpErrorMessage {
                          Text(rsvpError)
                              .font(.caption).foregroundColor(.red)
                              .frame(maxWidth: .infinity, alignment: .center) // Center error text
                              .padding(.top, 4)
                     }
                }
                // --- End RSVP Area ---

                Divider()
                mapSection           // Extracted ViewBuilder property (Includes Link)

                // --- General Error Display ---
                // Show errors related to delete/edit attempts if they occur
                 if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
                     ErrorDisplay(message: errorMessage) // Use helper view
                         .frame(maxWidth: .infinity, alignment: .center) // Center align error
                         .padding(.top)
                 }
                if showRefreshPrompt {
                    Divider()
                    refreshPromptButton
                }
                Spacer() // Push content up if scroll view has extra space

            } // End Main VStack Content
            .padding() // Padding around the entire content stack
        } // End ScrollView
        .navigationTitle("Details") // Concise title
        .navigationBarTitleDisplayMode(.inline)
        // --- Toolbar for Manager Actions ---
        .toolbar {
             // Only show Edit/Delete toolbar items if the current user is a manager
             if authViewModel.isManager {
                 managerToolbarItems // Use extracted toolbar content property
             }
         }
         // --- Modal Sheet for Editing ---
         .sheet(isPresented: $showingEditSheet) {
             // Present CreateOpportunityView configured for editing *this* opportunity
             CreateOpportunityView(opportunityToEdit: opportunity)
                  .environmentObject(viewModel).environmentObject(authViewModel)
         }
         // --- Modal Sheet for Attendee List ---
         .sheet(isPresented: $showingAttendeeListSheet) {
             // Present the AttendeeListView
             AttendeeListView(
                 opportunityId: opportunity.id, opportunityName: opportunity.name,
                 attendeeIds: opportunity.attendeeIds,
                 isEventCreator: opportunity.creatorUserId == authViewModel.userSession?.uid,
                 isEventCurrentlyOccurring: opportunity.isCurrentlyOccurring,
                 initialAttendanceRecords: opportunity.attendanceRecords ?? [:]
             )
             .environmentObject(viewModel).environmentObject(authViewModel) // Pass ViewModels
         }
         // --- Confirmation Dialog for Deleting ---
         .alert("Confirm Delete", isPresented: $showingDeleteConfirm) {
             Button("Delete", role: .destructive) { performDelete() } // Call delete action
             Button("Cancel", role: .cancel) {} // Standard cancel button
         } message: {
             Text("Are you sure you want to permanently delete '\(opportunity.name)'? This action cannot be undone.")
         }
         // --- End Manager Actions & Sheets ---
        .onAppear { // Actions when view appears
            // Removed initialization of localIsRsvped
            geocodeAddress() // Fetch map coordinates
            if isLoggedInUser { fetchOrganizerName() } // Fetch organizer name only if logged in
            // Clear errors on appear
            viewModel.errorMessage = nil
            viewModel.rsvpErrorMessage = nil
            viewModel.attendanceErrorMessage = nil
        }
        // Removed the .onChange(of: viewModel.rsvpedOpportunityIds) modifier

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
                    Text("Organized by: User (\(creatorId.prefix(6))...)").font(.subheadline).foregroundColor(.gray)
                }
            }
        }
    }

    /// Displays Date, Time Range, and Duration.
    private var whenSection: some View {
         VStack(alignment: .leading, spacing: 8) {
              Text(opportunity.eventDate, formatter: Self.fullDateFormatter).font(.title3).fontWeight(.semibold)
              HStack(spacing: 4) {
                  Image(systemName: "clock.fill")
                      .foregroundColor(.blue)
                      .frame(width: 20)
                  Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) to \(opportunity.endDate, formatter: Self.timeOnlyFormatter)").font(.body)
                  if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                      Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.body).foregroundColor(.secondary)
                  }
              }
         }
    }

    /// Displays Location (as a Link if possible).
    @ViewBuilder private var whereSection: some View {
        if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
            Link(destination: url) { HStack { Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20); Text(opportunity.location).font(.body).foregroundColor(.accentColor).multilineTextAlignment(.leading) } }.buttonStyle(.plain)
        } else if !opportunity.location.isEmpty {
            HStack { Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20); Text(opportunity.location).font(.body).foregroundColor(.primary).multilineTextAlignment(.leading) }
        }
        // Implicit EmptyView if location is empty
    }

    /// Displays the Event Description.
    private var descriptionSection: some View {
        VStack(alignment: .leading) {
            Text("Description").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
            Text(opportunity.description).font(.body).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Displays Attendee Count/Limit and View List button for manager.
    private var attendeeSection: some View {
        HStack {
            Image(systemName: "person.3.fill").foregroundColor(.purple).frame(width: 25)
            Text("Attendees: \(opportunity.attendeeCount)")
            if let max = opportunity.maxAttendees, max > 0 { Text(" / \(max) Max") } else { Text(" (Unlimited)") }
            Spacer()
            if authViewModel.isManager && opportunity.attendeeCount > 0 {
                Button("View List") { showingAttendeeListSheet = true }.font(.footnote).buttonStyle(.bordered).tint(.secondary)
            }
        }.font(.subheadline)
    }

    /// Displays the RSVP / Cancel RSVP Button area using the computed property isRsvpedByCurrentUser.
    @ViewBuilder private var rsvpButtonArea: some View {
        VStack(spacing: 5) {
            if viewModel.isTogglingRsvp { // Loading state
                ProgressView("Updating RSVP...").padding(.vertical, 10)
            } else { // Buttons based on RSVP status
                // Use computed property directly here
                if isRsvpedByCurrentUser { // Cancel Button
                    Button {
                        // Call toggleRSVP without completion handler
                        viewModel.toggleRSVP(opportunity: opportunity)
                    } label: { Label("Cancel RSVP", systemImage: "person.fill.xmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).tint(.red).disabled(!canPerformRsvp)
                        .accessibilityLabel("Cancel RSVP for \(opportunity.name)")
                    Text("You are attending!").font(.caption).foregroundColor(.green).padding(.top, 2)
                } else { // RSVP Button
                    Button {
                        // Call toggleRSVP without completion handler
                        viewModel.toggleRSVP(opportunity: opportunity)
                    } label: { Label("RSVP (I'm Going!)", systemImage: "person.fill.checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.green).disabled(opportunity.isFull || !canPerformRsvp) // Disable if full or loading
                        .accessibilityLabel("RSVP for \(opportunity.name)")
                    if opportunity.isFull { Text("Event is full.").font(.caption).foregroundColor(.orange).padding(.top, 2) } // Show if full
                }
            }
        }.frame(maxWidth: .infinity) // Center buttons horizontally
         .animation(.default, value: viewModel.isTogglingRsvp) // Animate loading state
         .animation(.default, value: isRsvpedByCurrentUser) // Animate button switch based on computed property
    }


    /// Displays the Map (as a Link if possible).
    @ViewBuilder private var mapSection: some View {
         VStack(alignment: .leading) {
             Text("Location Map").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
             if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
                  Link(destination: url) { mapView }.buttonStyle(.plain) // Link wraps map view
             } else { mapView } // Show map without link
         }
    }

    /// Builds the actual MapKit View, Loading, or Error state.
    @ViewBuilder private var mapView: some View {
        let isMapLinked = mapsURL(for: opportunity.location) != nil && !opportunity.location.isEmpty
        if let region = coordinateRegion { // Map ready
            Map(position: .constant(.region(region))) { if let coord = mapMarkerCoordinate { Marker(opportunity.name, coordinate: coord) } }
                .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                .overlay(alignment: .topTrailing) { if isMapLinked { Image(systemName: "arrow.up.forward.app.fill").padding(5).font(.callout).foregroundStyle(.secondary).background(.ultraThinMaterial, in: Circle()).padding(6).accessibilityLabel("Open location in Maps") } }
                .allowsHitTesting(!isMapLinked) // Disable interaction if map is wrapped in Link
        } else if let mapError = geocodingErrorMessage { // Error state
            HStack { Spacer(); Image(systemName: "exclamationmark.triangle").foregroundColor(.orange); Text("Map Error: \(mapError)").font(.caption).foregroundColor(.secondary); Spacer() }.frame(height: 250, alignment: .center)
        } else { // Loading state
            HStack { Spacer(); ProgressView(); Text("Loading map...").font(.caption).foregroundColor(.secondary); Spacer() }.frame(height: 250, alignment: .center)
        }
    }

    /// Builds the Edit/Delete buttons for the toolbar (Managers only), disabling Edit for past events.
    private var managerToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Edit Button
            Button { guard canEditEvent else { return }; viewModel.errorMessage = nil; showingEditSheet = true } label: { Label("Edit", systemImage: "pencil.circle.fill") }
                .disabled(!canEditEvent).accessibilityLabel(canEditEvent ? "Edit Opportunity" : "Cannot Edit Past Opportunity")
            // Delete Button
            Button(role: .destructive) { viewModel.errorMessage = nil; showingDeleteConfirm = true } label: { Label("Delete", systemImage: "trash.circle.fill") }
                .accessibilityLabel("Delete Opportunity")
        }
    }

    /// Builds the button prompting the user to refresh the list.
    @ViewBuilder
    private var refreshPromptButton: some View {
        Button {
            print("Manual refresh triggered from Detail View.")
            viewModel.fetchOpportunities() // Call the main fetch function in the ViewModel
            withAnimation { // Animate hiding the prompt
                showRefreshPrompt = false
            }
        } label: {
            Label("Refresh List to See Updates", systemImage: "arrow.clockwise")
                .font(.caption)
                .frame(maxWidth: .infinity) // Make button wide
        }
        .buttonStyle(.bordered) // Use less prominent style
        .tint(.secondary)
        .transition(.opacity.combined(with: .scale(scale: 0.9))) // Animate appearance
    }


    // MARK: - Action Methods

    /// Calls the ViewModel to delete the opportunity and dismisses the view.
    private func performDelete() {
        print("User confirmed delete for opportunity: \(opportunity.id)")
        viewModel.deleteOpportunity(opportunityId: opportunity.id)
        dismiss() // Dismiss immediately
    }

    /// Converts the opportunity's address string into map coordinates.
    private func geocodeAddress() {
        coordinateRegion = nil; mapMarkerCoordinate = nil; geocodingErrorMessage = nil
        guard !opportunity.location.isEmpty else { self.geocodingErrorMessage = "Address is empty."; return }
        print("Starting geocoding for address: \(opportunity.location)")
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(opportunity.location) { (placemarks, error) in
            DispatchQueue.main.async {
                if let error = error { self.geocodingErrorMessage = error.localizedDescription; print("Geocoding failed: \(error.localizedDescription)"); return }
                guard let placemark = placemarks?.first, let location = placemark.location else { self.geocodingErrorMessage = "Address not found."; print("Geocoding failed: Address not found."); return }
                let coordinate = location.coordinate; self.mapMarkerCoordinate = coordinate
                self.coordinateRegion = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                print("Geocoding successful: \(coordinate.latitude), \(coordinate.longitude)")
            }
        }
    }

    /// Creates a URL for Apple Maps search.
    private func mapsURL(for address: String) -> URL? {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), !encodedAddress.isEmpty else { return nil }
         return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
    }

    /// Fetches the organizer's username asynchronously when the view appears (if user logged in).
    private func fetchOrganizerName() {
        guard isLoggedInUser else { return }
        guard let creatorId = opportunity.creatorUserId, !creatorId.isEmpty else { organizerUsername = nil; isLoadingOrganizer = false; return }
        guard organizerUsername == nil && !isLoadingOrganizer else { return } // Avoid refetch
        print("Fetching organizer username for ID: \(creatorId)"); isLoadingOrganizer = true
        let opportunityIdWhenFetchStarted = opportunity.id
        authViewModel.fetchUsername(for: creatorId) { fetchedName in
             // Ensure the view hasn't navigated away before updating state
             guard self.opportunity.id == opportunityIdWhenFetchStarted else {
                 if self.isLoadingOrganizer { self.isLoadingOrganizer = false }; return
             }
            self.organizerUsername = fetchedName; self.isLoadingOrganizer = false // Update state
            print("Organizer username fetch complete: \(fetchedName ?? "nil")")
        }
    }

} // End struct OpportunityDetailView




// MARK: - Helper View for Error Display
struct ErrorDisplay: View {
    let message: String
    var body: some View { HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red); Text("Error: \(message)").foregroundColor(.red).font(.caption) } }
}

// Ensure Mock Data Setup exists if needed
#if DEBUG
// ... (Mock Opportunity struct/extensions including RSVP/Attendance fields) ...
// ... (MockFirebaseUser struct if needed for previews) ...
#endif
