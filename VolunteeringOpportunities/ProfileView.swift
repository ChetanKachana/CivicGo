import SwiftUI
import FirebaseAuth // Needed for User type

// MARK: - Profile View (Manager Page Button in Toolbar)
struct ProfileView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var oppViewModel: OpportunityViewModel // Needed for displaying attended events
    @State private var showAuthSheet = false // For presenting the AuthenticationView
    @State private var showingUsernameAlert = false // For the username edit alert
    @State private var newUsername: String = "" // Temporary storage for username editing

    // MARK: - Formatters (Static for efficiency)
    // Formatter for displaying total hours
    private static var hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = " hrs"; return formatter
    }()
    // Formatter for event dates/times in history rows
    private static var historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short; return formatter
    }()
    // Formatter for event duration in history rows
    private static var durationFormatter: NumberFormatter = {
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter
     }()


    // MARK: - Computed Properties

    /// Filters opportunities the user attended (marked "present"). Sorted descending by date.
    private var attendedEvents: [Opportunity] {
        guard let userId = authViewModel.userSession?.uid,
              let user = authViewModel.userSession,
              !user.isAnonymous else { return [] } // Must be logged in non-anonymously

        // Filter opportunities where the user's ID is a key in attendanceRecords with value "present"
        let attended = oppViewModel.opportunities.filter {
            $0.attendanceRecords?[userId] == "present"
        }
        // Sort by event date, most recent first
        return attended.sorted { $0.eventDate > $1.eventDate }
    }

    /// Calculates total attended hours from the filtered list.
    private var totalAttendedHours: Double {
        attendedEvents.reduce(0.0) { total, event in
            total + (event.durationHours ?? 0.0) // Add duration, default to 0 if nil
        }
    }

    /// Formats the total attended hours for display.
    private var formattedTotalHours: String {
        Self.hoursFormatter.string(from: NSNumber(value: totalAttendedHours)) ?? "0 hrs"
    }

    /// Determines if the edit username button should be shown (logged in non-anonymously).
    private var canEditUsername: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    // MARK: - Body
    var body: some View {
        // Assumes ProfileView is already embedded in a NavigationView (e.g., by MainTabView)
        List {
            // Section 1: User Info / Actions - Placed in a header-like section
            Section {
                userInfoSection // Extracted VStack containing user details/buttons
            }
            // Use list modifiers to make it look like a custom header area
            .listRowInsets(EdgeInsets()) // Remove default padding
             // Match system background

            // Section 2: Attendance History (Conditional)
            // Show only for logged-in, non-anonymous users
            if let user = authViewModel.userSession, !user.isAnonymous {
                Section {
                    // Use a Group for conditional content within the section
                    Group {
                        if attendedEvents.isEmpty {
                            // Display message if no history exists
                            EmptyHistoryView()
                        } else {
                            // Iterate over attended events
                            ForEach(attendedEvents) { event in
                                // Navigate to the detail view for the attended event
                                NavigationLink {
                                    OpportunityDetailView(opportunity: event)
                                        .environmentObject(authViewModel)
                                        .environmentObject(oppViewModel)
                                } label: {
                                    // Display the row content for the event
                                    attendedEventRow(for: event)
                                }
                            }
                        }
                    } // End Group
                } header: {
                    // Custom header view for the history section
                    historyHeader
                }
            } // End Attendance History Section

            // Section 3: General Errors from AuthViewModel
            if let errorMessage = authViewModel.errorMessage, !authViewModel.isLoading {
                 Section {
                     // Display error messages using helper view
                     ErrorDisplay(message: errorMessage)
                 }
             }

        } // End List
        .navigationTitle("Profile") // Set the navigation bar title
        .toolbar { // Add toolbar items
             // Conditionally add the "View My Page" button for managers
             if authViewModel.isManager {
                 ToolbarItem(placement: .navigationBarTrailing) {
                     // NavigationLink itself acts as the button content
                     NavigationLink {
                         // Destination: The manager's own profile page
                         ManagerProfileView() // Uses environment objects inherited
                     } label: {
                         // Use an icon for the toolbar button
                         Label("View My Page", systemImage: "person.text.rectangle.fill") // Label used for accessibility
                             .labelStyle(.iconOnly) // Show only the icon visually
                     }
                     .accessibilityLabel("View My Manager Page") // Specific accessibility hint
                 }
                 ToolbarItem(placement: .navigationBarLeading) {
                     // NavigationLink itself acts as the button content
                     Image(systemName: "crown.fill")
                         .foregroundStyle(Color.indigo)
                     .accessibilityLabel("Organizer") // Specific accessibility hint
                 }
             }
        }
        .sheet(isPresented: $showAuthSheet) { // Sheet for Authentication
            authSheetContent
        }
        .alert("Edit Username", isPresented: $showingUsernameAlert) { // Alert for editing username
            usernameAlertContent
        } message: {
            Text("Please enter your new username (3-30 characters).") // Informative message
        }
        .onChange(of: authViewModel.userSession) { // Handle sheet dismissal on login
             dismissAuthSheetOnLogin($1)
        }
        .onAppear { // Clear errors when the view appears
            authViewModel.errorMessage = nil
        }
    } // End body


    // MARK: - Extracted View Builders

    /// Builds the top section containing user details and primary actions.
    @ViewBuilder private var userInfoSection: some View {
        VStack(spacing: 20) { // Add spacing between elements
             if let user = authViewModel.userSession {
                 // Display different content based on user type
                 if user.isAnonymous {
                     anonymousUserContent // View for guests
                 } else {
                     loggedInUserContent(user: user) // View for logged-in users
                 }
             } else {
                 // View for disconnected state (should be rare if auth listener works)
                 disconnectedUserContent
             }
         }
         .padding(.vertical) // Add vertical padding inside the section
         .frame(maxWidth: .infinity) // Ensure VStack takes full width
    }

    /// Builds the content displayed for logged-in (non-anonymous) users.
    @ViewBuilder
    private func loggedInUserContent(user: User) -> some View {
        VStack(spacing: 10) { // Spacing for logged-in user elements
            // User Avatar Placeholder
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 70)) // Large icon size
                .foregroundColor(.green) // Example color

            // Username and Edit Button Row
            HStack(alignment: .center, spacing: 4) {
                 // Display username (fetched or derived)
                 Text(authViewModel.username?.nilIfEmpty ?? user.email?.components(separatedBy: "@").first ?? "User")
                    .font(.title2).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.tail) // Prevent long names wrapping badly

                 // Edit button shown only if allowed
                 if canEditUsername {
                     Button {
                         newUsername = authViewModel.username ?? "" // Pre-fill alert field
                         showingUsernameAlert = true // Show the alert
                     } label: {
                         Image(systemName: "pencil.circle.fill")
                             .imageScale(.medium)
                             .foregroundColor(.secondary)
                     }.buttonStyle(.plain).accessibilityLabel("Edit Username") // Remove default button styling
                 }
            }

            // Display User Email
            if let email = user.email, !email.isEmpty {
                Text(email)
                    .font(.subheadline).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle) // Truncate long emails
            }

            // --- Manager Tag (Conditional) ---
            // Show only if the user has the manager role
            if authViewModel.isManager {
                managerTag.padding(.top, 5) // Add slight space above tag
            }
            // --- End Manager Tag ---

            // Space before the sign out button
            Spacer().frame(height: 15)

            // Sign Out Button or Loading Indicator
            if authViewModel.isLoading && authViewModel.userSession?.uid == user.uid { // Show progress only if signing out *this* user
                ProgressView("Signing Out...")
            } else {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut() // Call sign out action
                }
                .buttonStyle(.bordered) // Prominent style for sign out
            }
        }
        .animation(.default, value: authViewModel.isManager) // Animate manager tag appearance
    }

    /// Builds the content displayed for anonymous users (guests).
    private var anonymousUserContent: some View {
        VStack(spacing: 15) {
            Image(systemName: "person.crop.circle.badge.questionmark.fill")
                .font(.system(size: 80)).foregroundColor(.orange)
            Text("Browsing as Guest")
                .font(.title2).fontWeight(.medium)
            Text("Sign in with Google to save favorites, RSVP, and view attendance history.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button {
                authViewModel.errorMessage = nil // Clear errors before showing sheet
                showAuthSheet = true // Show the authentication view sheet
            } label: {
                Text("Sign In / Options").padding(.horizontal, 5).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.blue).padding(.top, 10)
        }
    }

    /// Builds the content displayed when no user session exists (e.g., network error on launch).
    private var disconnectedUserContent: some View {
        VStack(spacing: 15) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 80)).foregroundColor(.red)
            Text("Not Connected")
                .font(.title2).fontWeight(.medium)
            Text("Could not establish a user session. Please check connection or retry.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            // Show loading or retry button
            if authViewModel.isLoading {
                ProgressView("Connecting...").padding(.top, 10)
            } else {
                // Attempt anonymous sign-in as a retry mechanism
                Button { authViewModel.signInAnonymously() } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered).padding(.top, 10)
            }
        }
    }

    /// Builds the small "Manager" tag view with an icon.
    private var managerTag: some View {
        HStack(spacing: 4){
            
            Text("Manager")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.indigo.opacity(0.15))
                .foregroundColor(.indigo)
                .clipShape(Capsule())
        }
    }

    /// Builds the header for the Attendance History section, including total hours.
    private var historyHeader: some View {
        HStack {
            Text("Attendance History")
            Spacer()
            // Display total hours formatted
            Text(formattedTotalHours)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    /// Builds a single row view for the Attendance History list.
    @ViewBuilder private func attendedEventRow(for event: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.name).font(.headline) // Event name
            // Display date/time and duration
            HStack(spacing: 4) {
                Image(systemName: "calendar").foregroundColor(.secondary).font(.caption)
                // Format the event date and time using the specific history formatter
                Text(event.eventDate, formatter: Self.historyDateFormatter)
                // Conditionally display the duration if available and positive
                if let duration = event.durationHours, duration > 0,
                   let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) { // Use correct formatter
                    Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))") // Handle singular/plural hour(s)
                        .font(.caption2).foregroundColor(.gray)
                }
            }
            .font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 4) // Add padding within the row
    }

    /// Builds the view shown when attendance history is empty.
    private struct EmptyHistoryView: View {
        var body: some View {
            Text("You haven't been marked present at any events yet.")
                .foregroundColor(.secondary)
                .padding(.vertical) // Add padding
                .frame(maxWidth: .infinity, alignment: .center) // Center the text
        }
    }

    /// Helper View for displaying error messages in the list.
    private struct ErrorDisplay: View {
         let message: String
         var body: some View {
             HStack {
                 Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                 Text("Error: \(message)").foregroundColor(.red).font(.footnote)
             }
         }
    }

    /// Builds the content for the Authentication sheet.
    private var authSheetContent: some View {
        AuthenticationView()
            .environmentObject(authViewModel)
            .presentationDetents([.medium, .large]) // Allow sheet resizing
    }

    /// Builds the content (TextField, Buttons) for the username change alert.
    @ViewBuilder private var usernameAlertContent: some View {
         TextField("Username (3-30 characters)", text: $newUsername)
             .autocapitalization(.none)
             .disableAutocorrection(true)
         // Save Button
         Button("Save") {
             let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
             // Validate before calling async function
             if !trimmed.isEmpty && trimmed.count >= 3 && trimmed.count <= 30 {
                 Task { // Wrap async call in Task
                     await authViewModel.updateUsername(newUsername: trimmed)
                 }
             } else {
                 // Set error message directly if basic validation fails
                 authViewModel.errorMessage = "Username must be 3-30 characters."
             }
         }
         // Cancel Button
         Button("Cancel", role: .cancel) {
             authViewModel.errorMessage = nil // Clear error on cancel
         }
    }


    // MARK: - Helper Functions
    /// Dismisses the auth sheet if a non-anonymous session appears while it's shown.
    private func dismissAuthSheetOnLogin(_ newSession: User?) {
        let isLoggedIn = newSession != nil && !newSession!.isAnonymous
         if isLoggedIn && showAuthSheet {
             print("ProfileView detected successful login, dismissing auth sheet.")
             showAuthSheet = false // Dismiss the sheet
         }
    }

} // End struct ProfileView

// MARK: - String Extension Helper (Ensure defined only once in project)
extension String {
    /// Returns nil if the string is empty, otherwise returns the string itself.
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
    /// Returns a new string made by removing whitespace and newline characters
    /// from both ends of the receiver.
    
}
