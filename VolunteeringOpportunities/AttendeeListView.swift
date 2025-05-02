import SwiftUI
import FirebaseFirestore // Needed for fetching user data

// MARK: - Attendee List View (with Attendance Tracking & Manager Remove)
// Displays the list of users who have RSVP'd to a specific opportunity.
// Allows managers who created the event to mark attendance during the event window
// and remove attendees.
struct AttendeeListView: View {
    // MARK: - Properties (Passed In)
    // These are constants initialized when the view is created
    let opportunityId: String
    let opportunityName: String
    let attendeeIds: [String]               // UIDs of RSVP'd users
    let isEventCreator: Bool                // Is the current user the creator?
    let isEventCurrentlyOccurring: Bool     // Is the event happening now?
    // initialAttendanceRecords is used only in init to set the @State var

    // MARK: - Environment & State
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: OpportunityViewModel // For calling recordAttendance & remove actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel // For manager check & current user ID

    // State variables manage the view's internal data and UI status
    @State private var attendeeDetails: [String: AttendeeInfo] = [:] // Dict [UID: AttendeeInfo] - starts empty
    @State private var attendanceRecords: [String: String] // Local copy initialized in init - starts with passed data
    @State private var isLoadingAttendees = false                 // Loading state for fetching attendee emails - starts false
    @State private var fetchError: String? = nil                   // Optional error message for fetching - starts nil
    @State private var attendeeToRemove: AttendeeInfo? = nil // For confirmation alert

    // Helper struct to hold fetched info for each attendee
    // Conforms to Identifiable (using UID) and Hashable for ForEach performance
    struct AttendeeInfo: Identifiable, Hashable {
        let id: String // UID serves as the identifiable ID
        let email: String? // Store fetched email (optional)
    }

    // MARK: - Computed Properties
    // Sort UIDs alphabetically for a consistent display order
    private var sortedAttendeeIds: [String] { attendeeIds.sorted() }

    // Creates an array of AttendeeInfo structs based on the sorted IDs and fetched details
    private var sortedAttendeeInfo: [AttendeeInfo] { sortedAttendeeIds.compactMap { attendeeDetails[$0] } }

    // Determines if the current user can actively take attendance
    private var canTakeAttendance: Bool { authViewModel.isManager && isEventCurrentlyOccurring }

    // Determines if the manager remove functionality should be active
    private var canManagerRemove: Bool { authViewModel.isManager }

    // MARK: - Initializer
    // Initializes all 'let' constants and the 'attendanceRecords' @State variable.
    init(opportunityId: String, opportunityName: String, attendeeIds: [String], isEventCreator: Bool, isEventCurrentlyOccurring: Bool, initialAttendanceRecords: [String : String]) {
        // Initialize 'let' constants passed from the parent view
        self.opportunityId = opportunityId
        self.opportunityName = opportunityName
        self.attendeeIds = attendeeIds
        self.isEventCreator = isEventCreator
        self.isEventCurrentlyOccurring = isEventCurrentlyOccurring

        // Initialize the @State variable `attendanceRecords` using the special underscore syntax
        // with the data passed in from the Opportunity object.
        _attendanceRecords = State(initialValue: initialAttendanceRecords)

        // All stored properties are now initialized.

        print("AttendeeListView initialized. Can take attendance: \(self.isEventCreator && self.isEventCurrentlyOccurring)")
    }


    // MARK: - Body
    var body: some View {
        NavigationView { // Embed in NavigationView for Title and Done button
            // Use the contentView computed property which handles conditional display logic
            contentView
                .navigationTitle("Attendees (\(attendeeIds.count))") // Display attendee count in title
                .navigationBarTitleDisplayMode(.inline) // Use inline style for shorter title bar
                .toolbar { // Add Done button to dismiss the sheet
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                // Use .task modifier to run async fetch when view appears
                .task {
                    await fetchAttendeeDetails()
                }
                // Optional: Add pull-to-refresh capability
                .refreshable {
                     await fetchAttendeeDetails()
                }
                // Display attendance update errors in an overlay at the bottom
                 .overlay(alignment: .bottom) {
                    errorOverlay // Use extracted computed property for the overlay
                 }
                 // Animate the appearance/disappearance of the error overlay
                 .animation(.default, value: viewModel.attendanceErrorMessage != nil || viewModel.removeAttendeeErrorMessage != nil)
                 // Confirmation Alert for removing attendee
                 .alert("Remove Attendee", isPresented: Binding(get: { attendeeToRemove != nil }, set: { if !$0 { attendeeToRemove = nil } })) {
                      confirmationAlertButtons // Use extracted alert buttons
                  } message: {
                      // Message shown in the alert, uses optional chaining
                      Text("Remove \(attendeeToRemove?.email ?? attendeeToRemove?.id.prefix(8).appending("...") ?? "this attendee") from '\(opportunityName)'? This cancels their RSVP and removes their attendance record.")
                  }

        } // End NavigationView
    } // End body

    // MARK: - Extracted View Builders

    /// Builds the main content view based on the current loading, error, empty, or data state.
    @ViewBuilder
    private var contentView: some View {
        if isLoadingAttendees {
            ProgressView("Loading Attendees...").padding(.top, 50).frame(maxHeight: .infinity)
        } else if let error = fetchError {
            ErrorStateView(message: "Error loading attendees: \(error)").frame(maxHeight: .infinity)
        } else if attendeeIds.isEmpty {
            EmptyStateView(message: "No attendees have RSVP'd yet.").frame(maxHeight: .infinity)
        } else {
            attendeeList // Use extracted computed property for the List
        }
    }

    /// Builds the List containing the optional header and rows for each attendee.
    private var attendeeList: some View {
        List {
            // Display a hint about attendance taking if applicable
            if isEventCreator && !isEventCurrentlyOccurring && !attendeeIds.isEmpty {
                 Text("Attendance can be recorded only during the event.")
                     .font(.caption).foregroundColor(.secondary).listRowSeparator(.hidden)
                     .listRowBackground(Color(.systemGroupedBackground)).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 5)
            }

            // Iterate over the sorted AttendeeInfo structs to create rows
            ForEach(sortedAttendeeInfo) { attendee in
                attendeeRow(for: attendee) // Use helper function to build each row
            }
            .onDelete(perform: canManagerRemove ? deleteAttendee : nil) // Enable swipe-to-delete for managers

        } // End List
        .listStyle(.plain) // Use plain style for a simple list appearance
    }


    /// Creates the view content for a single attendee row in the list. Includes Attendance controls.
    @ViewBuilder
    private func attendeeRow(for attendee: AttendeeInfo) -> some View {
        HStack(spacing: 12) { // Add spacing between elements
            // Attendee Information (Icon and Email/Placeholder)
            Image(systemName: "person.circle.fill").foregroundColor(.secondary).imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.email ?? "Email Unknown").font(.subheadline)//.fontWeight(.medium)
                if attendee.email == nil || attendee.email?.contains("Error") == true || attendee.email?.contains("Found") == true {
                    Text("ID: \(attendee.id.prefix(8))...").font(.caption2).foregroundColor(.gray)
                }
            }
            Spacer() // Pushes attendance controls to the right

            // Attendance Status/Buttons
            if canTakeAttendance {
                attendanceButtons(for: attendee.id) // Interactive buttons
            } else if let status = attendanceRecords[attendee.id] {
                attendanceStatusBadge(status: status) // Static badge
            }
        }
        .padding(.vertical, 6) // Add slight vertical padding within the row
        .opacity(viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee ? 0.6 : 1.0) // Visual cue during update
        .animation(.default, value: viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee)
    }

    /// Creates the "Here" and "Absent" buttons for recording attendance.
    @ViewBuilder
    private func attendanceButtons(for attendeeId: String) -> some View {
         HStack(spacing: 8) {
             Button { recordAttendance(attendeeId: attendeeId, status: attendanceRecords[attendeeId] == "present" ? nil : "present") } label: {
                 Image(systemName: "person.crop.circle.fill.badge.checkmark").padding(.horizontal, 10).padding(.vertical, 5).frame(minWidth: 40)
             }.buttonStyle(.borderedProminent).tint(attendanceRecords[attendeeId] == "present" ? .green : .gray)

             Button { recordAttendance(attendeeId: attendeeId, status: attendanceRecords[attendeeId] == "absent" ? nil : "absent") } label: {
                 Image(systemName: "person.crop.circle.fill.badge.xmark").padding(.horizontal, 10).padding(.vertical, 5).frame(minWidth: 40)
             }.buttonStyle(.borderedProminent).tint(attendanceRecords[attendeeId] == "absent" ? .red : .gray)
         }
         .disabled(viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee) // Disable during either operation
         .animation(.default, value: attendanceRecords[attendeeId])
     }


    /// Displays a static badge showing the recorded attendance status.
    @ViewBuilder
    private func attendanceStatusBadge(status: String) -> some View {
        Text(status.capitalized).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor(status).opacity(0.2)).foregroundColor(statusColor(status))
            .clipShape(Capsule())
    }

    /// Helper function to determine the color based on attendance status string.
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() { case "present": return .green; case "absent": return .red; default: return .gray }
    }

    /// Builds the error message overlay displayed at the bottom.
    @ViewBuilder
    private var errorOverlay: some View {
        let errorToShow = viewModel.removeAttendeeErrorMessage ?? viewModel.attendanceErrorMessage
        if let error = errorToShow {
             Text(error)
                 .font(.caption).foregroundColor(.white).padding(8)
                 .background(Color.black.opacity(0.7), in: Capsule())
                 .padding(.bottom)
                 .transition(.opacity.combined(with: .move(edge: .bottom)))
                 .onAppear { viewModel.clearErrorAfterDelay(viewModel.removeAttendeeErrorMessage != nil ? .removeAttendee : .attendance) }
         }
     }

     /// Builds the buttons for the confirmation alert when removing an attendee.
     @ViewBuilder
     private var confirmationAlertButtons: some View {
          Button("Remove Attendee", role: .destructive) {
               if let attendee = attendeeToRemove {
                    print("Manager confirmed removal of \(attendee.id)")
                    viewModel.managerRemoveAttendee(opportunityId: opportunityId, attendeeIdToRemove: attendee.id)
               }
               attendeeToRemove = nil // Dismiss alert
          }
          Button("Cancel", role: .cancel) { attendeeToRemove = nil } // Dismiss alert
     }


    // MARK: - Data Fetching & Actions

    /// Fetches details (email) for each attendee UID using async/await and TaskGroup.
    @MainActor
    private func fetchAttendeeDetails() async {
        guard !attendeeIds.isEmpty, !isLoadingAttendees else { return }
        isLoadingAttendees = true; fetchError = nil
        let db = Firestore.firestore(); print("Fetching details for \(attendeeIds.count) attendees...")
        var newDetails: [String: AttendeeInfo] = attendeeDetails; var encounteredError = false

        await withTaskGroup(of: (String, AttendeeInfo?).self) { group in
            for userId in attendeeIds {
                group.addTask {
                    do {
                        let doc = try await db.collection("users").document(userId).getDocument()
                        if doc.exists { return (userId, AttendeeInfo(id: userId, email: doc.data()?["email"] as? String)) }
                        else { print("User doc \(userId) not found."); return (userId, AttendeeInfo(id: userId, email: "User Not Found")) }
                    } catch { print("!!! Error fetching user doc \(userId): \(error)"); encounteredError = true; return (userId, AttendeeInfo(id: userId, email: "Fetch Error")) }
                }
            }
            for await (userId, info) in group { if let attendeeInfo = info { newDetails[userId] = attendeeInfo } }
        } // End TaskGroup

        self.attendeeDetails = newDetails
        if encounteredError { self.fetchError = "Could not load all attendee details." }
        self.isLoadingAttendees = false; print("Finished fetching attendee details. Count: \(newDetails.count)")
    }

    /// Updates local state optimistically and calls the ViewModel to record attendance status.
    private func recordAttendance(attendeeId: String, status: String?) {
        attendanceRecords[attendeeId] = status // Optimistic UI Update
        print("Optimistic UI update: Marked \(attendeeId) as \(status ?? "nil (cleared)")")
        viewModel.recordAttendance(opportunityId: opportunityId, attendeeId: attendeeId, status: status)
    }

    /// Initiates the process to remove an attendee via swipe-to-delete.
    private func deleteAttendee(at offsets: IndexSet) {
         let attendeesToDelete = offsets.map { sortedAttendeeInfo[$0] }
         if let attendee = attendeesToDelete.first {
              print("Swipe delete initiated for \(attendee.id)")
              attendeeToRemove = attendee // Trigger confirmation alert
         }
     }


    // MARK: - Helper Empty/Error Views (Defined inline for completeness)
    struct EmptyStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "person.3.sequence.fill").font(.system(size: 50)).foregroundColor(.secondary); Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding(); Spacer() }
        }
    }
     struct ErrorStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.largeTitle); Text(message).foregroundColor(.red).multilineTextAlignment(.center).padding(.top, 4); Spacer() }.padding()
        }
    }

} // End struct AttendeeListView
