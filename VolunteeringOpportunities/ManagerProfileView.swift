import SwiftUI

// MARK: - Manager Profile View (Using List for Layout - Broken Down)
// Displays Manager Details and Upcoming Events with dynamic row backgrounds for events.
// Uses List as the primary container and breaks down sections into computed properties.
struct ManagerProfileView: View {
    // Optional: ID of the manager whose profile to view.
    // If nil, defaults to the currently logged-in user (if they are a manager).
    var managerUserIdToView: String? = nil

    // StateObject for fetching/managing the specific profile data being viewed.
    @StateObject private var viewModel = ManagerProfileViewModel()

    // Environment objects for authentication state, current user info, and opportunity data.
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var oppViewModel: OpportunityViewModel // Needed for events list & background checks

    // State for controlling presentation of the edit sheet.
    @State private var showingEditSheet = false
    // State for storing the fetched display name of the profile being viewed.
    @State private var profileUsername: String? = nil
    // State to track if the username is currently being fetched.
    @State private var isLoadingUsername: Bool = false

    // MARK: - Computed Properties

    /// Determines the actual user ID whose profile should be fetched and displayed.
    private var targetUserId: String? {
        managerUserIdToView ?? authViewModel.userSession?.uid
    }

    /// Checks if the *currently logged-in* user is viewing their *own* manager profile.
    private var isViewingOwnProfile: Bool {
        guard let loggedInId = authViewModel.userSession?.uid, let targetId = targetUserId else { return false }
        return loggedInId == targetId
    }

    /// Checks if the current app user is logged in and not anonymous. Needed for background logic.
    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    /// Filters opportunities to show current/future events created by the manager whose profile is being viewed.
    private var now: Date { Date() }
    private var occurringOrFutureManagerOpportunities: [Opportunity] {
        guard let targetId = targetUserId else { return [] } // Ensure we have a target ID
        // Filter the main opportunity list from the shared ViewModel
        return oppViewModel.opportunities
            .filter { $0.creatorUserId == targetId && $0.endDate > now } // Match creator ID and ensure event hasn't ended
            .sorted { $0.eventDate < $1.eventDate } // Sort chronologically (upcoming first)
    }

    // MARK: - Helper Function for Row Backgrounds
    /// Determines the appropriate background view for an opportunity row based on its state.
    @ViewBuilder
    private func backgroundForRow(for opportunity: Opportunity) -> some View {
        // Priority: Occurring > Attending > Favorited > Default
        if opportunity.isCurrentlyOccurring {
            // Occurring: Animated Wave Background (Yellow)
            AnimatedWaveBackgroundView(
                startTime: opportunity.eventDate,
                endTime: opportunity.endDate,
                baseColor: .mint // Consistent yellow for occurring events
            )
        } else if isLoggedInUser && oppViewModel.isRsvped(opportunityId: opportunity.id) {
            // Attending Background (Green) - If manager RSVP'd to own event
            Color.green.opacity(0.15)
        } else if isLoggedInUser && oppViewModel.isFavorite(opportunityId: opportunity.id) {
             // Favorited Background (Red) - If manager favorited own event
            AnimatedMeshBackgroundView(
                colors: [.red, .pink, .red.opacity(0.3)]
                        )
        } else {
            // Default Background: Transparent (lets list style show through)
            Color.clear
        }
    }


    // MARK: - Body
    var body: some View {
        List {
            // --- Section 1: Profile Header ---
            profileHeaderSection

            // --- Section 2: Info (About & Contact) ---
            profileInfoSection

            // --- Section 3: Upcoming Events ---
            upcomingEventsSection
        }
        .listStyle(.grouped) // Apply grouped style for visual separation
        .navigationTitle(profileUsername ?? (isLoadingUsername ? "Loading..." : "Manager Profile")) // Dynamic title
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { // Toolbar for Edit button
             if isViewingOwnProfile && authViewModel.isManager { // Show only for own profile if manager
                 ToolbarItem(placement: .navigationBarTrailing) {
                     Button { showingEditSheet = true } label: {
                         Label("Edit Profile", systemImage: "pencil.circle.fill")
                     }
                 }
             }
        }
        .sheet(isPresented: $showingEditSheet) { // Sheet for editing profile
            EditManagerProfileView()
                .environmentObject(viewModel) // Pass the ManagerProfileViewModel
                .environmentObject(authViewModel)
        }
        .task { // Perform async actions when the view appears or targetUserId changes
            guard let userId = targetUserId else {
                viewModel.errorMessage = "Could not load profile - user ID missing."
                return
            }
            print("ManagerProfileView .task for user ID: \(userId)")
            viewModel.fetchProfileData(userId: userId)
            await fetchProfileDisplayName(userId: userId)
        }
         .overlay { // Loading/Error overlay
              if viewModel.isLoading || isLoadingUsername {
                  ProgressView("Loading Profile...")
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                      .background(.ultraThinMaterial.opacity(0.8))
              } else if let error = viewModel.errorMessage {
                  ErrorOverlayView(message: error) { viewModel.errorMessage = nil } // Allow dismissal
              }
          }
          .refreshable { // Enable pull-to-refresh
              print("Refreshing Manager Profile...")
              guard let userId = targetUserId else { return }
              // Re-fetch data on refresh action
              viewModel.fetchProfileData(userId: userId)
              await fetchProfileDisplayName(userId: userId)
              // Optional: Refresh global opportunities if needed
              // await oppViewModel.fetchOpportunities()
          }
         // Add animations for relevant state changes
         .animation(.default, value: viewModel.bannerImageURL)
         .animation(.default, value: viewModel.logoImageURL)
         .animation(.default, value: occurringOrFutureManagerOpportunities) // Animate list changes
         .animation(.default, value: oppViewModel.rsvpedOpportunityIds) // For background updates
         .animation(.default, value: oppViewModel.favoriteOpportunityIds) // For background updates
         .animation(.default, value: profileUsername) // Animate name changes
    } // End body


    // MARK: - Async Helper Function for Name Fetch
    /// Fetches the display name for the profile being viewed.
    func fetchProfileDisplayName(userId: String) async {
        // Avoid refetch if name already loaded or still loading
        guard profileUsername == nil || isLoadingUsername == false else { return }
        print("Fetching display name for profile: \(userId)")
        isLoadingUsername = true
        authViewModel.fetchUsername(for: userId) { fetchedName in
            Task { @MainActor in
                self.profileUsername = fetchedName ?? "Manager" // Use fallback "Manager"
                self.isLoadingUsername = false
                print("Display name fetched: \(self.profileUsername ?? "nil")")
            }
        }
    }


    // MARK: - Extracted Section View Builders

    /// Builds Section 1: Banner, Logo, and Name.
    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
             EmptyView() // Section content is empty, visuals are in the header
        } header: {
             // VStack containing the visual header elements
             VStack(alignment: .leading, spacing: 0) {
                 bannerAndLogoSection
                 Spacer()
                 Spacer()// ZStack for banner/logo overlap
                 managerNameSection.padding(.horizontal) // Name below logo area
             }
              // Space below the name in the header
             // Use negative insets to fight List padding and achieve edge-to-edge header
             .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: -20)) // Adjust as needed
        }
        // Match the List's background and hide the separator
        .listRowBackground(Color(.systemGroupedBackground))
           
        .listRowSeparator(.hidden)
    }

    /// Builds Section 2: About and Contact Information.
    @ViewBuilder
    private var profileInfoSection: some View {
         // Determine if there's content to show or if it's the owner's profile
         let hasContactInfo = !viewModel.contactEmail.isEmpty || !viewModel.contactPhone.isEmpty || !viewModel.websiteURL.isEmpty
         let hasDescription = !viewModel.managerDescription.isEmpty
         // Only create the Section if there's something to show OR it's the owner viewing
         if hasContactInfo || hasDescription || isViewingOwnProfile {
             Section {
                 // Conditionally include description row
                 if hasDescription || isViewingOwnProfile {
                     descriptionSection
                         .padding(.vertical, 5) // Padding within the row
                 }
                 // Conditionally include contact info row
                 if hasContactInfo || isViewingOwnProfile {
                     contactInfoSection
                         .padding(.vertical, 5) // Padding within the row
                 }
             } header: {
                  Text("Info").font(.headline).padding(.top) // Section header text
             }
             .listRowSeparator(.hidden, edges: .top) // Optional: hide separator above section
         }
         // If no content and not owner, this section won't appear
    }

    /// Builds Section 3: Upcoming Events List.
    @ViewBuilder
    private var upcomingEventsSection: some View {
        Section {
             if occurringOrFutureManagerOpportunities.isEmpty {
                  // Message when no upcoming events
                  Text(isViewingOwnProfile ? "You have no upcoming events scheduled." : "This manager has no upcoming events.")
                     .foregroundColor(.secondary)
                     .padding(.vertical) // Padding for the message row
             } else {
                 // List the events using ForEach
                 ForEach(occurringOrFutureManagerOpportunities) { opportunity in
                     NavigationLink { // Make entire row tappable for navigation
                         OpportunityDetailView(opportunity: opportunity)
                             .environmentObject(authViewModel)
                             .environmentObject(oppViewModel)
                     } label: {
                         // The visual content of the row
                         OpportunityRowView(opportunity: opportunity)
                             .environmentObject(authViewModel)
                             .environmentObject(oppViewModel)
                     }
                     .buttonStyle(.plain) // Use plain style for NavigationLink contents if needed
                     .listRowBackground(backgroundForRow(for: opportunity)) // Apply dynamic background
                     .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15)) // Standard padding for event rows
                 }
             }
        } header: {
            // Header for the events section
            Text("Upcoming Events")
                .font(.title2).fontWeight(.semibold)
                .padding(.top) // Add space above this header
                .padding(.bottom, 5)
        }
    }


    // MARK: - Extracted Element View Builders (Internal Implementation Details)

    /// Builds the ZStack containing banner and overlapping logo.
    @ViewBuilder
    private var bannerAndLogoSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner Image
            AsyncImage(url: URL(string: viewModel.bannerImageURL)) { phase in
                switch phase {
                case .empty: Rectangle().fill(.thinMaterial).frame(height: 180).overlay(ProgressView())
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill).frame(height: 180).clipped()
                case .failure: Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 180).overlay(Image(systemName: "photo.fill").foregroundColor(.gray).imageScale(.large))
                @unknown default: EmptyView()
                }
            }.frame(height: 180)

            // Logo Image (Overlapping)
            AsyncImage(url: URL(string: viewModel.logoImageURL)) { phase in
                 switch phase {
                 case .empty: Circle().fill(.thickMaterial).frame(width: 100, height: 100).overlay(ProgressView())
                 case .success(let image): image.resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 100).clipShape(Circle())
                 case .failure: Circle().fill(Color.secondary.opacity(0.4)).frame(width: 100, height: 100).overlay(Image(systemName: "building.2.crop.circle.fill").foregroundColor(.gray).font(.largeTitle))
                 @unknown default: EmptyView()
                 }
            }
            .frame(width: 100, height: 100)
            .background(Circle().fill(.background)) // Opaque background
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .offset(x: 20, y: 50) // Overlap offset
        }
        .frame(height: 180 + 50) // Total height including overlap
    }

    /// Builds the view displaying the Manager's Name.
    @ViewBuilder
    private var managerNameSection: some View {
        HStack {
            Text(profileUsername ?? "")
                .font(.largeTitle).fontWeight(.bold)
                .redacted(reason: isLoadingUsername ? .placeholder : [])
            Spacer()
        }
        .padding(.leading, 5).padding(.top, 5) // Indent and add space below
    }

    /// Builds the view displaying the "About" description section.
    @ViewBuilder
    private var descriptionSection: some View {
        // Uses a Text view to display description or prompt
        Text(viewModel.managerDescription.isEmpty ? (isViewingOwnProfile ? "Add a description in Edit Profile." : "No description provided.") : viewModel.managerDescription)
            .font(.body)
            .foregroundColor(viewModel.managerDescription.isEmpty ? .secondary : .primary)
    }

    /// Builds the view displaying the Contact Info section with tappable links.
    @ViewBuilder
    private var contactInfoSection: some View {
        // Uses a VStack to list ContactRow helpers
        VStack(alignment: .leading) {
            if !viewModel.contactEmail.isEmpty { ContactRow(icon: "envelope.fill", text: viewModel.contactEmail, urlScheme: "mailto:") }
            if !viewModel.contactPhone.isEmpty { ContactRow(icon: "phone.fill", text: viewModel.contactPhone, urlScheme: "tel:") }
            if !viewModel.websiteURL.isEmpty { ContactRow(icon: "safari.fill", text: viewModel.websiteURL, urlScheme: nil) }
            // Prompt for owner if no contact info exists
            if viewModel.contactEmail.isEmpty && viewModel.contactPhone.isEmpty && viewModel.websiteURL.isEmpty && isViewingOwnProfile {
                 Text("Add contact info in Edit Profile.").font(.callout).foregroundColor(.secondary).padding(.top, 5)
            }
        }
    }

} // End struct ManagerProfileView


// MARK: - Helper Views (Keep outside main struct, ensure accessible)

/// Helper View for displaying tappable contact information rows.
struct ContactRow: View {
    let icon: String
    let text: String
    let urlScheme: String?

    private var url: URL? {
        let scheme: String; let path: String
        if let explicitScheme = urlScheme { scheme = explicitScheme; path = text }
        else { // Handle website URLs
            let lower = text.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { scheme = ""; path = text }
            else { scheme = "https://"; path = text } // Default to https
        }
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return URL(string: "\(scheme)\(encodedPath)")
    }

    var body: some View {
        if let validURL = url {
            Link(destination: validURL) { // Make the row a link
                HStack {
                    Image(systemName: icon).frame(width: 25, alignment: .center).foregroundColor(.secondary)
                    Text(text).foregroundColor(.accentColor).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 3) // Padding within the tappable area
            }
        } else { // Fallback display if URL is invalid
            HStack {
                Image(systemName: icon).frame(width: 25, alignment: .center).foregroundColor(.secondary)
                Text(text).foregroundColor(.primary).lineLimit(1).truncationMode(.middle)
            }.padding(.vertical, 3)
        }
    }
}

/// Helper View for displaying error messages in an overlay
struct ErrorOverlayView: View {
    let message: String
    var dismissAction: (() -> Void)? = nil

    var body: some View {
        VStack {
            Spacer() // Pushes content to the bottom
            HStack { Image(systemName: "exclamationmark.triangle.fill"); Text(message) }
                .font(.caption).padding(12).foregroundColor(.white)
                .background(Color.red.opacity(0.85)).clipShape(Capsule())
                .padding(.bottom) // Padding from bottom edge
                .onTapGesture { dismissAction?() } // Allow tapping to dismiss
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Cover the screen
        .background(.ultraThinMaterial.opacity(0.1)) // Subtle dimming effect
        .transition(.opacity.combined(with: .move(edge: .bottom))) // Slide/fade animation
        .animation(.default, value: message) // Animate based on message presence/change
    }
}

// --- Ensure necessary structs/views are accessible: ---
// struct Opportunity: Identifiable, Equatable, Hashable { ... }
// struct OpportunityRowView: View { ... }
// struct AnimatedWaveBackgroundView: View { ... }
// struct WaveShape: Shape { ... }
// struct EditManagerProfileView: View { ... }
// class ManagerProfileViewModel: ObservableObject { ... }
