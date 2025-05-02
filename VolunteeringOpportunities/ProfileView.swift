import SwiftUI
import FirebaseAuth // Needed for User type

// MARK: - Profile View (with Username Edit & Attendance History)
struct ProfileView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var oppViewModel: OpportunityViewModel
    @State private var showAuthSheet = false
    @State private var showingUsernameAlert = false
    @State private var newUsername: String = ""

    // MARK: - Formatters
    private static var hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = " hrs"; return formatter
    }()

    // MARK: - Computed Properties
    /// Filters opportunities user attended ("present").
    private var attendedEvents: [Opportunity] {
        guard let userId = authViewModel.userSession?.uid, let user = authViewModel.userSession, !user.isAnonymous else { return [] }
        let attended = oppViewModel.opportunities.filter { $0.attendanceRecords?[userId] == "present" }
        return attended.sorted { $0.eventDate > $1.eventDate }
    }
    /// Calculates total attended hours.
    private var totalAttendedHours: Double { attendedEvents.reduce(0.0) { $0 + ($1.durationHours ?? 0.0) } }
    /// Formats the total attended hours.
    private var formattedTotalHours: String { Self.hoursFormatter.string(from: NSNumber(value: totalAttendedHours)) ?? "0 hrs" }
    /// Determines if the edit username button should be shown
    private var canEditUsername: Bool { authViewModel.userSession != nil && !authViewModel.userSession!.isAnonymous }

    // MARK: - Body
    var body: some View {
        List {
            // Section 1: User Info / Actions
            Section { userInfoSection }
                .listRowInsets(EdgeInsets()).listRowBackground(Color(.systemGroupedBackground))

            // Section 2: Attendance History (Conditional)
            if let user = authViewModel.userSession, !user.isAnonymous {
                Section {
                    // Wrap conditional content in a Group or VStack to help compiler
                    Group {
                        if attendedEvents.isEmpty {
                            EmptyHistoryView()
                        } else {
                            // Corrected: Use ForEach directly here
                            ForEach(attendedEvents) { event in
                                NavigationLink {
                                    OpportunityDetailView(opportunity: event)
                                        .environmentObject(authViewModel)
                                        .environmentObject(oppViewModel)
                                } label: {
                                    // Corrected: Call the correct helper function name
                                    attendedEventRow(for: event)
                                }
                            }
                        }
                    } // End Group
                } header: { historyHeader } // Use extracted header
            } // End Attendance History Section

            // Section 3: General Errors
            if let errorMessage = authViewModel.errorMessage, !authViewModel.isLoading {
                 Section { ErrorDisplay(message: errorMessage) }
             }

        } // End List
        .navigationTitle("Profile")
        .sheet(isPresented: $showAuthSheet) { authSheetContent }
        .alert("Edit Username", isPresented: $showingUsernameAlert) { usernameAlertContent } message: { Text("Please enter your new username (3-30 characters).") }
        .onChange(of: authViewModel.userSession) { dismissAuthSheetOnLogin($1) }
        .onAppear { authViewModel.errorMessage = nil }
    } // End body


    // MARK: - Extracted View Builders

    /// Builds the top section containing user details and primary actions.
    @ViewBuilder private var userInfoSection: some View {
        VStack(spacing: 20) {
             if let user = authViewModel.userSession {
                 if user.isAnonymous { anonymousUserContent }
                 else { loggedInUserContent(user: user) }
             } else { disconnectedUserContent }
         }
         .padding(.vertical).frame(maxWidth: .infinity)
    }

    /// Builds the content displayed for logged-in (non-anonymous) users.
    private func loggedInUserContent(user: User) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 70)).foregroundColor(.green)
            HStack(alignment: .center, spacing: 4) {
                 // Use the nilIfEmpty helper (now internal/default access)
                 Text(authViewModel.username?.nilIfEmpty ?? user.email?.components(separatedBy: "@").first ?? "User")
                    .font(.title2).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                 if canEditUsername { // Show edit button only if allowed
                     Button { newUsername = authViewModel.username ?? ""; showingUsernameAlert = true } label: {
                         Image(systemName: "pencil.circle.fill").imageScale(.medium).foregroundColor(.secondary)
                     }.buttonStyle(.plain).accessibilityLabel("Edit Username")
                 }
            }
            if let email = user.email, !email.isEmpty { Text(email).font(.subheadline).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle) }
            if authViewModel.isManager { managerTag }
            Spacer().frame(height: 15)
            if authViewModel.isLoading && authViewModel.userSession?.uid == user.uid { ProgressView("Signing Out...") }
            else { Button("Sign Out", role: .destructive) { authViewModel.signOut() }.buttonStyle(.borderedProminent) }
        }
        .animation(.default, value: authViewModel.isManager)
    }

    /// Builds the content displayed for anonymous users.
    private var anonymousUserContent: some View {
        VStack(spacing: 15) {
            Image(systemName: "person.crop.circle.badge.questionmark.fill").font(.system(size: 80)).foregroundColor(.orange)
            Text("Browsing as Guest").font(.title2).fontWeight(.medium)
            Text("Sign in with Google to save favorites, RSVP, and view attendance history.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button { authViewModel.errorMessage = nil; showAuthSheet = true } label: { Text("Sign In / Options").padding(.horizontal, 30).padding(.vertical, 8) }
            .buttonStyle(.borderedProminent).tint(.blue).padding(.top, 10)
        }
    }

    /// Builds the content displayed when no user session exists (disconnected state).
    private var disconnectedUserContent: some View {
        VStack(spacing: 15) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 80)).foregroundColor(.red)
            Text("Not Connected").font(.title2).fontWeight(.medium)
            Text("Could not establish a user session. Please check connection.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            if authViewModel.isLoading { ProgressView("Connecting...").padding(.top, 10) }
            else { Button { authViewModel.signInAnonymously() } label: { Label("Retry Connection", systemImage: "arrow.clockwise") }.buttonStyle(.bordered).padding(.top, 10) }
        }
    }

    /// Builds the manager tag view with icon.
    private var managerTag: some View {
        HStack(spacing: 4){ Image(systemName: "crown.fill").foregroundStyle(.orange).imageScale(.small); Text("Manager").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 4).background(Color.orange.opacity(0.15)).foregroundColor(.orange).clipShape(Capsule()) }
        .transition(.scale.combined(with: .opacity))
    }

    /// Builds the header for the Attendance History section.
    private var historyHeader: some View {
        HStack { Text("Attendance History"); Spacer(); Text(formattedTotalHours).font(.subheadline.weight(.semibold)).foregroundColor(.secondary) }
    }

    /// Builds a row for the Attendance History list.
    @ViewBuilder private func attendedEventRow(for event: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.name).font(.headline)
            HStack(spacing: 4) { Image(systemName: "calendar").foregroundColor(.secondary).font(.caption); Text(event.eventDate, style: .date); Text("-"); Text(event.eventDate, style: .time); Text("to"); Text(event.endDate, style: .time) }
            .font(.caption).foregroundColor(.secondary)
            if !event.description.isEmpty && event.description != "No description provided." { Text(event.description).font(.footnote).foregroundColor(.gray).lineLimit(2).padding(.top, 2) }
        }.padding(.vertical, 4)
    }

    /// Builds the view shown when attendance history is empty.
    private struct EmptyHistoryView: View {
        var body: some View { Text("You haven't been marked present at any events yet.").foregroundColor(.secondary).padding(.vertical).frame(maxWidth: .infinity, alignment: .center) }
    }

    /// Builds the content for the Authentication sheet.
    private var authSheetContent: some View {
        AuthenticationView().environmentObject(authViewModel).presentationDetents([.medium, .large])
    }

    /// Builds the content (TextField, Buttons) for the username change alert.
    @ViewBuilder private var usernameAlertContent: some View {
         TextField("Username (3-30 characters)", text: $newUsername).autocapitalization(.none).disableAutocorrection(true)
         Button("Save") {
             let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
             if !trimmed.isEmpty && trimmed.count >= 3 && trimmed.count <= 30 { authViewModel.updateUsername(newUsername: trimmed) }
             else { authViewModel.errorMessage = "Username must be 3-30 characters." }
         }
         Button("Cancel", role: .cancel) { authViewModel.errorMessage = nil }
    }


    // MARK: - Helper Functions
    /// Dismisses the auth sheet if a non-anonymous session appears while it's shown.
    private func dismissAuthSheetOnLogin(_ newSession: User?) {
        let isLoggedIn = newSession != nil && !newSession!.isAnonymous
         if isLoggedIn && showAuthSheet { print("ProfileView detected successful login, dismissing auth sheet."); showAuthSheet = false }
    }

} // End struct ProfileView


// MARK: - Extracted Helper Views (If not in separate file)
// Making ErrorDisplay internal (default) or public if needed elsewhere



// MARK: - String Extension Helper
// Making nilIfEmpty internal (default) or public if needed elsewhere
extension String { // Removed fileprivate
    /// Returns nil if the string is empty, otherwise returns the string itself.
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}


