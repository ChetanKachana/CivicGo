import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

// MARK: - Opportunity Detail View (Prevent RSVP/Delete Updates)
struct OpportunityDetailView: View {
    // MARK: - Properties
    let opportunity: Opportunity

    // MARK: - Environment & State
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var showingAttendeeListSheet = false

    @State private var organizerUsername: String? = nil
    @State private var isLoadingOrganizer = false

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
    private var canShowRsvpArea: Bool {
        isLoggedInUser && !opportunity.hasEnded
    }
    private var canPerformRsvp: Bool {
        isLoggedInUser &&
        !opportunity.hasEnded &&
        !opportunity.isCurrentlyOccurring &&
        !viewModel.isTogglingRsvp
    }
    private var canEditEvent: Bool {
            guard let currentUserId = authViewModel.userSession?.uid else { return false }
            return authViewModel.isManager &&
                   opportunity.creatorUserId == currentUserId &&
                   !opportunity.hasEnded
        }

        private var canDeleteEvent: Bool {
            guard let currentUserId = authViewModel.userSession?.uid else { return false }
            return authViewModel.isManager &&
                   opportunity.creatorUserId == currentUserId &&
                   !opportunity.hasEnded
        }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                eventNameAndOrganizerSection
                Divider()
                whenSection
                Divider()
                whereSection
                Divider()
                descriptionSection
                Divider()
                attendeeSection

                if canShowRsvpArea {
                     Divider()
                     rsvpButtonArea
                     if let rsvpError = viewModel.rsvpErrorMessage {
                          Text(rsvpError)
                              .font(.caption).foregroundColor(.red)
                              .frame(maxWidth: .infinity, alignment: .center)
                              .padding(.top, 4)
                     } else if opportunity.isCurrentlyOccurring {
                          Text("RSVP cannot be changed while the event is ongoing.")
                              .font(.caption).foregroundColor(.orange)
                              .frame(maxWidth: .infinity, alignment: .center)
                              .padding(.top, 4)
                     }
                }

                Divider()
                mapSection

            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
             if authViewModel.isManager {
                 managerToolbarItems
             }
         }
         .sheet(isPresented: $showingEditSheet) {
             CreateOpportunityView(opportunityToEdit: opportunity)
                  .environmentObject(viewModel).environmentObject(authViewModel)
         }
         .sheet(isPresented: $showingAttendeeListSheet) {
             AttendeeListView(
                 opportunityId: opportunity.id,
                 opportunityName: opportunity.name,
                 attendeeIds: opportunity.attendeeIds,
                 isEventCreator: opportunity.creatorUserId == authViewModel.userSession?.uid,
                 isEventCurrentlyOccurring: opportunity.isCurrentlyOccurring,
                 initialAttendanceRecords: opportunity.attendanceRecords ?? [:]
             )
             .environmentObject(viewModel).environmentObject(authViewModel)
         }
         .alert("Confirm Delete", isPresented: $showingDeleteConfirm) {
             Button("Delete", role: .destructive) { performDelete() }
             Button("Cancel", role: .cancel) {}
         } message: {
              Text("Are you sure you want to permanently delete '\(opportunity.name)'? This action cannot be undone.")
         }
         .onAppear {
             geocodeAddress()
             if isLoggedInUser { fetchOrganizerName() }
             viewModel.rsvpErrorMessage = nil
             viewModel.attendanceErrorMessage = nil
         }

    }

    // MARK: - Extracted View Builders

    @ViewBuilder private var eventNameAndOrganizerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(opportunity.name).font(.largeTitle).fontWeight(.bold).padding(.bottom, 2)
            if isLoggedInUser {
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

    private var whenSection: some View {
         VStack(alignment: .leading, spacing: 8) {
              Text(opportunity.eventDate, formatter: Self.fullDateFormatter).font(.title3).fontWeight(.semibold)
              HStack(spacing: 4) {
                  Image(systemName: "clock.fill").foregroundColor(.blue).frame(width: 20)
                  Text("\(opportunity.eventDate, formatter: Self.timeOnlyFormatter) to \(opportunity.endDate, formatter: Self.timeOnlyFormatter)").font(.body)
                  if let duration = opportunity.durationHours, duration > 0, let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                      Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))").font(.body).foregroundColor(.secondary)
                  }
              }
         }
    }

    @ViewBuilder private var whereSection: some View {
        if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
            Link(destination: url) {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20)
                    Text(opportunity.location).font(.body).foregroundColor(.accentColor).multilineTextAlignment(.leading)
                }
            }.buttonStyle(.plain)
        } else if !opportunity.location.isEmpty {
            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundColor(.red).frame(width: 20)
                Text(opportunity.location).font(.body).foregroundColor(.primary).multilineTextAlignment(.leading)
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading) {
            Text("Description").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
            Text(opportunity.description.isEmpty ? "No description provided." : opportunity.description)
                .font(.body)
                .foregroundColor(opportunity.description.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var attendeeSection: some View {
        HStack {
            Image(systemName: "person.3.fill").foregroundColor(.purple).frame(width: 25)
            Text("Attendees: \(opportunity.attendeeCount)")
            if let max = opportunity.maxAttendees, max > 0 {
                Text(" / \(max) Max")
            } else {
                Text(" (Unlimited)")
            }
            Spacer()
            if authViewModel.isManager && opportunity.attendeeCount > 0 {
                Button("View List") { showingAttendeeListSheet = true }
                    .font(.footnote).buttonStyle(.bordered).tint(.secondary)
            }
        }.font(.subheadline)
    }

    @ViewBuilder private var rsvpButtonArea: some View {
        VStack(spacing: 5) {
            HStack{
                Spacer()
                if viewModel.isTogglingRsvp {
                    ProgressView("Updating RSVP...").padding(.vertical, 10)
                } else {
                    if isRsvpedByCurrentUser {
                        Button { viewModel.toggleRSVP(opportunity: opportunity) } label: {
                            Label("Cancel RSVP", systemImage: "person.fill.xmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.red)
                        .disabled(!canPerformRsvp)
                        .accessibilityLabel("Cancel RSVP for \(opportunity.name)")
                        if !opportunity.isCurrentlyOccurring {
                            Text("You are attending!").font(.caption).foregroundColor(.green).padding(.top, 2)
                        }
                        
                    } else {
                        Button { viewModel.toggleRSVP(opportunity: opportunity) } label: {
                            Label("RSVP (I'm Going!)", systemImage: "person.fill.checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                        .disabled(opportunity.isFull || !canPerformRsvp)
                        .accessibilityLabel("RSVP for \(opportunity.name)")
                        if opportunity.isFull && !opportunity.isCurrentlyOccurring {
                            Text("Event is full.").font(.caption).foregroundColor(.orange).padding(.top, 2)
                        }
                    }
                }
                Spacer()
            }
        }.frame(maxWidth: .infinity)
         .animation(.default, value: viewModel.isTogglingRsvp)
         .animation(.default, value: isRsvpedByCurrentUser)
    }

    @ViewBuilder private var mapSection: some View {
         VStack(alignment: .leading) {
             Text("Location Map").font(.title3).fontWeight(.semibold).padding(.bottom, 4)
             if let url = mapsURL(for: opportunity.location), !opportunity.location.isEmpty {
                  Link(destination: url) { mapView }.buttonStyle(.plain)
             } else { mapView }
         }
    }

    @ViewBuilder private var mapView: some View {
        let isMapLinked = mapsURL(for: opportunity.location) != nil && !opportunity.location.isEmpty
        Group {
            if let region = coordinateRegion {
                Map(position: .constant(.region(region))) {
                     if let coord = mapMarkerCoordinate { Marker(opportunity.name, coordinate: coord) }
                }
                .overlay(alignment: .topTrailing) {
                     if isMapLinked { Image(systemName: "arrow.up.forward.app.fill").padding(5).font(.callout).foregroundStyle(.secondary).background(.ultraThinMaterial, in: Circle()).padding(6).accessibilityLabel("Open location in Maps") }
                }
                .allowsHitTesting(!isMapLinked)

            } else if let mapError = geocodingErrorMessage {
                HStack { Spacer(); Image(systemName: "exclamationmark.triangle").foregroundColor(.orange); Text("Map Error: \(mapError)").font(.caption).foregroundColor(.secondary); Spacer() }
                    .frame(alignment: .center)

            } else {
                HStack { Spacer(); ProgressView(); Text("Loading map...").font(.caption).foregroundColor(.secondary); Spacer() }
                    .frame(alignment: .center)
            }
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
    }

    private var managerToolbarItems: some ToolbarContent {
           ToolbarItemGroup(placement: .navigationBarTrailing) {
               if canEditEvent {
                   Button {
                       viewModel.errorMessage = nil; showingEditSheet = true
                   } label: {
                       Label("Edit", systemImage: "pencil.circle.fill")
                   }
                   .accessibilityLabel("Edit Opportunity")
               }

               if canDeleteEvent {
                   Button(role: .destructive) {
                        viewModel.errorMessage = nil; showingDeleteConfirm = true
                   } label: {
                        Label("Delete", systemImage: "trash.circle.fill")
                   }
                   .accessibilityLabel("Delete Opportunity")
               }
           }
       }

    // MARK: - Action Methods

    private func performDelete() {
        print("User confirmed delete for opportunity: \(opportunity.id)")
        viewModel.deleteOpportunity(opportunityId: opportunity.id)
        dismiss()
    }

    private func geocodeAddress() {
        coordinateRegion = nil; mapMarkerCoordinate = nil; geocodingErrorMessage = nil
        guard !opportunity.location.isEmpty else {
            self.geocodingErrorMessage = "Address is empty."
            print("Skipping geocoding: Address is empty.")
            return
        }
        print("Starting geocoding for address: \(opportunity.location)")
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(opportunity.location) { (placemarks, error) in
            DispatchQueue.main.async {
                if let error = error {
                    self.geocodingErrorMessage = error.localizedDescription
                    print("Geocoding failed: \(error.localizedDescription)")
                    return
                }
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    self.geocodingErrorMessage = "Address not found."
                    print("Geocoding failed: Address not found.")
                    return
                }
                let coordinate = location.coordinate
                self.mapMarkerCoordinate = coordinate
                self.coordinateRegion = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                print("Geocoding successful: \(coordinate.latitude), \(coordinate.longitude)")
            }
        }
    }

    private func mapsURL(for address: String) -> URL? {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !encodedAddress.isEmpty else { return nil }
         return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
    }

    private func fetchOrganizerName() {
            guard isLoggedInUser, let creatorId = opportunity.creatorUserId, !creatorId.isEmpty else { return }
            guard organizerUsername == nil && !isLoadingOrganizer else { return }

            print("Fetching organizer username for ID: \(creatorId)")
            isLoadingOrganizer = true
            let opportunityIdWhenFetchStarted = opportunity.id

            authViewModel.fetchUsername(for: creatorId) { fetchedName in
                 Task { @MainActor in
                     guard self.opportunity.id == opportunityIdWhenFetchStarted else {
                         print("Opportunity changed while fetching username, discarding result.")
                         self.isLoadingOrganizer = false
                         return
                     }

                     self.organizerUsername = fetchedName
                     self.isLoadingOrganizer = false
                     print("Organizer username fetch complete: \(fetchedName ?? "nil")")
                 }
            }
        }
}
