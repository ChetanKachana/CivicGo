import SwiftUI
import FirebaseFirestore

// MARK: - Attendee List View (with Attendance Tracking & Manager Remove)
struct AttendeeListView: View {
    // MARK: - Properties (Passed In)
    let opportunityId: String
    let opportunityName: String
    let attendeeIds: [String]
    let isEventCreator: Bool
    let isEventCurrentlyOccurring: Bool

    // MARK: - Environment & State
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    @State private var attendeeDetails: [String: AttendeeInfo] = [:]
    @State private var attendanceRecords: [String: String]
    @State private var isLoadingAttendees = false
    @State private var fetchError: String? = nil
    @State private var attendeeToRemove: AttendeeInfo? = nil

    struct AttendeeInfo: Identifiable, Hashable {
        let id: String
        let email: String?
    }

    // MARK: - Computed Properties
    private var sortedAttendeeIds: [String] { attendeeIds.sorted() }

    private var sortedAttendeeInfo: [AttendeeInfo] { sortedAttendeeIds.compactMap { attendeeDetails[$0] } }

    private var canTakeAttendance: Bool { authViewModel.isManager && isEventCurrentlyOccurring }

    private var canManagerRemove: Bool { authViewModel.isManager }

    // MARK: - Initializer
    init(opportunityId: String, opportunityName: String, attendeeIds: [String], isEventCreator: Bool, isEventCurrentlyOccurring: Bool, initialAttendanceRecords: [String : String]) {
        self.opportunityId = opportunityId
        self.opportunityName = opportunityName
        self.attendeeIds = attendeeIds
        self.isEventCreator = isEventCreator
        self.isEventCurrentlyOccurring = isEventCurrentlyOccurring

        _attendanceRecords = State(initialValue: initialAttendanceRecords)

        print("AttendeeListView initialized. Can take attendance: \(self.isEventCreator && self.isEventCurrentlyOccurring)")
    }


    // MARK: - Body
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Attendees (\(attendeeIds.count))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    await fetchAttendeeDetails()
                }
                .refreshable {
                     await fetchAttendeeDetails()
                }
                 .overlay(alignment: .bottom) {
                    errorOverlay
                 }
                 .animation(.default, value: viewModel.attendanceErrorMessage != nil || viewModel.removeAttendeeErrorMessage != nil)
                 .alert("Remove Attendee", isPresented: Binding(get: { attendeeToRemove != nil }, set: { if !$0 { attendeeToRemove = nil } })) {
                      confirmationAlertButtons
                  } message: {
                      Text("Remove \(attendeeToRemove?.email ?? attendeeToRemove?.id.prefix(8).appending("...") ?? "this attendee") from '\(opportunityName)'? This cancels their RSVP and removes their attendance record.")
                  }

        }
    }

    // MARK: - Extracted View Builders

    @ViewBuilder
    private var contentView: some View {
        if isLoadingAttendees {
            ProgressView("Loading Attendees...").padding(.top, 50).frame(maxHeight: .infinity)
        } else if let error = fetchError {
            ErrorStateView(message: "Error loading attendees: \(error)").frame(maxHeight: .infinity)
        } else if attendeeIds.isEmpty {
            EmptyStateView(message: "No attendees have RSVP'd yet.").frame(maxHeight: .infinity)
        } else {
            attendeeList
        }
    }

    private var attendeeList: some View {
        List {
            if isEventCreator && !isEventCurrentlyOccurring && !attendeeIds.isEmpty {
                 Text("Attendance can be recorded only during the event.")
                     .font(.caption).foregroundColor(.secondary).listRowSeparator(.hidden)
                     .listRowBackground(Color(.systemGroupedBackground)).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 5)
            }

            ForEach(sortedAttendeeInfo) { attendee in
                attendeeRow(for: attendee)
            }
            .onDelete(perform: canManagerRemove ? deleteAttendee : nil)

        }
        .listStyle(.plain)
    }


    @ViewBuilder
    private func attendeeRow(for attendee: AttendeeInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill").foregroundColor(.secondary).imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.email ?? "Email Unknown").font(.subheadline)
                if attendee.email == nil || attendee.email?.contains("Error") == true || attendee.email?.contains("Found") == true {
                    Text("ID: \(attendee.id.prefix(8))...").font(.caption2).foregroundColor(.gray)
                }
            }
            Spacer()

            if canTakeAttendance {
                attendanceButtons(for: attendee.id)
            } else if let status = attendanceRecords[attendee.id] {
                attendanceStatusBadge(status: status)
            }
        }
        .padding(.vertical, 6)
        .opacity(viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee ? 0.6 : 1.0)
        .animation(.default, value: viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee)
    }

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
         .disabled(viewModel.isUpdatingAttendance || viewModel.isRemovingAttendee)
         .animation(.default, value: attendanceRecords[attendeeId])
     }


    @ViewBuilder
    private func attendanceStatusBadge(status: String) -> some View {
        Text(status.capitalized).font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor(status).opacity(0.2)).foregroundColor(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() { case "present": return .green; case "absent": return .red; default: return .gray }
    }

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

     @ViewBuilder
     private var confirmationAlertButtons: some View {
          Button("Remove Attendee", role: .destructive) {
               if let attendee = attendeeToRemove {
                    print("Manager confirmed removal of \(attendee.id)")
                    viewModel.managerRemoveAttendee(opportunityId: opportunityId, attendeeIdToRemove: attendee.id)
               }
               attendeeToRemove = nil
          }
          Button("Cancel", role: .cancel) { attendeeToRemove = nil }
     }


    // MARK: - Data Fetching & Actions

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
        }
        self.attendeeDetails = newDetails
        if encounteredError { self.fetchError = "Could not load all attendee details." }
        self.isLoadingAttendees = false; print("Finished fetching attendee details. Count: \(newDetails.count)")
    }

    private func recordAttendance(attendeeId: String, status: String?) {
        attendanceRecords[attendeeId] = status
        print("Optimistic UI update: Marked \(attendeeId) as \(status ?? "nil (cleared)")")
        viewModel.recordAttendance(opportunityId: opportunityId, attendeeId: attendeeId, status: status)
    }

    private func deleteAttendee(at offsets: IndexSet) {
         let attendeesToDelete = offsets.map { sortedAttendeeInfo[$0] }
         if let attendee = attendeesToDelete.first {
              print("Swipe delete initiated for \(attendee.id)")
              attendeeToRemove = attendee
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

}
