import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var oppViewModel: OpportunityViewModel
    @State private var showAuthSheet = false
    @State private var showingUsernameAlert = false
    @State private var newUsername: String = ""

    private static var hoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = " hrs"; return formatter
    }()
    private static var historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short; return formatter
    }()
    private static var durationFormatter: NumberFormatter = {
         let formatter = NumberFormatter(); formatter.numberStyle = .decimal
         formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 1; return formatter
     }()


    private var attendedEvents: [Opportunity] {
        guard let userId = authViewModel.userSession?.uid,
              let user = authViewModel.userSession,
              !user.isAnonymous else { return [] }

        let attended = oppViewModel.opportunities.filter {
            $0.attendanceRecords?[userId] == "present"
        }
        return attended.sorted { $0.eventDate > $1.eventDate }
    }

    private var totalAttendedHours: Double {
        attendedEvents.reduce(0.0) { total, event in
            total + (event.durationHours ?? 0.0)
        }
    }

    private var formattedTotalHours: String {
        Self.hoursFormatter.string(from: NSNumber(value: totalAttendedHours)) ?? "0 hrs"
    }

    private var canEditUsername: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    var body: some View {
        List {
            Section {
                userInfoSection
            }
            .listRowInsets(EdgeInsets())

            if let user = authViewModel.userSession, !user.isAnonymous {
                Section {
                    Group {
                        if attendedEvents.isEmpty {
                            EmptyHistoryView()
                        } else {
                            ForEach(attendedEvents) { event in
                                NavigationLink {
                                    OpportunityDetailView(opportunity: event)
                                        .environmentObject(authViewModel)
                                        .environmentObject(oppViewModel)
                                } label: {
                                    attendedEventRow(for: event)
                                }
                            }
                        }
                    }
                } header: {
                    historyHeader
                }
            }

            if let errorMessage = authViewModel.errorMessage, !authViewModel.isLoading {
                 Section {
                     ErrorDisplay(message: errorMessage)
                 }
             }

        }
        .navigationTitle("Profile")
        .toolbar {
             if authViewModel.isManager {
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink {
                         ManagerProfileView()
                     } label: {
                         Label("View My Page", systemImage: "person.text.rectangle.fill")
                             .labelStyle(.iconOnly)
                     }
                     .accessibilityLabel("View My Manager Page")
                 }
                 ToolbarItem(placement: .navigationBarLeading) {
                     Image(systemName: "crown.fill")
                         .foregroundStyle(Color.indigo)
                     .accessibilityLabel("Organizer")
                 }
             }
        }
        .sheet(isPresented: $showAuthSheet) {
            authSheetContent
        }
        .alert("Edit Username", isPresented: $showingUsernameAlert) {
            usernameAlertContent
        } message: {
            Text("Please enter your new username (3-30 characters).")
        }
        .onChange(of: authViewModel.userSession) {
             dismissAuthSheetOnLogin($1)
        }
        .onAppear {
            authViewModel.errorMessage = nil
        }
    }


    @ViewBuilder private var userInfoSection: some View {
        VStack(spacing: 20) {
             if let user = authViewModel.userSession {
                 if user.isAnonymous {
                     anonymousUserContent
                 } else {
                     loggedInUserContent(user: user)
                 }
             } else {
                 disconnectedUserContent
             }
         }
         .padding(.vertical)
         .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func loggedInUserContent(user: User) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)

            HStack(alignment: .center, spacing: 4) {
                 Text(authViewModel.username?.nilIfEmpty ?? user.email?.components(separatedBy: "@").first ?? "User")
                    .font(.title2).fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.tail)

                 if canEditUsername {
                     Button {
                         newUsername = authViewModel.username ?? ""
                         showingUsernameAlert = true
                     } label: {
                         Image(systemName: "pencil.circle.fill")
                             .imageScale(.medium)
                             .foregroundColor(.secondary)
                     }.buttonStyle(.plain).accessibilityLabel("Edit Username")
                 }
            }

            if let email = user.email, !email.isEmpty {
                Text(email)
                    .font(.subheadline).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            if authViewModel.isManager {
                managerTag.padding(.top, 5)
            }
            Spacer().frame(height: 15)

            if authViewModel.isLoading && authViewModel.userSession?.uid == user.uid {
                ProgressView("Signing Out...")
            } else {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
                .buttonStyle(.bordered)
            }
        }
        .animation(.default, value: authViewModel.isManager)
    }

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
                authViewModel.errorMessage = nil
                showAuthSheet = true
            } label: {
                Text("Sign In / Options").padding(.horizontal, 5).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.blue).padding(.top, 10)
        }
    }

    private var disconnectedUserContent: some View {
        VStack(spacing: 15) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 80)).foregroundColor(.red)
            Text("Not Connected")
                .font(.title2).fontWeight(.medium)
            Text("Could not establish a user session. Please check connection or retry.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            if authViewModel.isLoading {
                ProgressView("Connecting...").padding(.top, 10)
            } else {
                Button { authViewModel.signInAnonymously() } label: {
                    Label("Retry Connection", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered).padding(.top, 10)
            }
        }
    }

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

    private var historyHeader: some View {
        HStack {
            Text("Attendance History")
            Spacer()
            Text(formattedTotalHours)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder private func attendedEventRow(for event: Opportunity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.name).font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "calendar").foregroundColor(.secondary).font(.caption)
                Text(event.eventDate, formatter: Self.historyDateFormatter)
                if let duration = event.durationHours, duration > 0,
                   let formattedDuration = Self.durationFormatter.string(from: NSNumber(value: duration)) {
                    Text("(\(formattedDuration) hr\(duration == 1.0 ? "" : "s"))")
                        .font(.caption2).foregroundColor(.gray)
                }
            }
            .font(.caption).foregroundColor(.secondary)
        }.padding(.vertical, 4)
    }

    private struct EmptyHistoryView: View {
        var body: some View {
            Text("You haven't been marked present at any events yet.")
                .foregroundColor(.secondary)
                .padding(.vertical)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private struct ErrorDisplay: View {
         let message: String
         var body: some View {
             HStack {
                 Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                 Text("Error: \(message)").foregroundColor(.red).font(.footnote)
             }
         }
    }

    private var authSheetContent: some View {
        AuthenticationView()
            .environmentObject(authViewModel)
            .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var usernameAlertContent: some View {
         TextField("Username (3-30 characters)", text: $newUsername)
             .autocapitalization(.none)
             .disableAutocorrection(true)
         Button("Save") {
             let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
             if !trimmed.isEmpty && trimmed.count >= 3 && trimmed.count <= 30 {
                 Task {
                     await authViewModel.updateUsername(newUsername: trimmed)
                 }
             } else {
                 authViewModel.errorMessage = "Username must be 3-30 characters."
             }
         }
         Button("Cancel", role: .cancel) {
             authViewModel.errorMessage = nil
         }
    }


    private func dismissAuthSheetOnLogin(_ newSession: User?) {
        let isLoggedIn = newSession != nil && !newSession!.isAnonymous
         if isLoggedIn && showAuthSheet {
             print("ProfileView detected successful login, dismissing auth sheet.")
             showAuthSheet = false
         }
    }

}

extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
    
}
