import SwiftUI

// MARK: - Manager Profile View (Using List for Layout - Broken Down)

struct ManagerProfileView: View {
    
    var managerUserIdToView: String? = nil

    @StateObject private var viewModel = ManagerProfileViewModel()

    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var oppViewModel: OpportunityViewModel

    @State private var showingEditSheet = false
    @State private var profileUsername: String? = nil
    @State private var isLoadingUsername: Bool = false

    // MARK: - Computed Properties

    private var targetUserId: String? {
        managerUserIdToView ?? authViewModel.userSession?.uid
    }

    private var isViewingOwnProfile: Bool {
        guard let loggedInId = authViewModel.userSession?.uid, let targetId = targetUserId else { return false }
        return loggedInId == targetId
    }

    private var isLoggedInUser: Bool {
        authViewModel.userSession != nil && !(authViewModel.userSession?.isAnonymous ?? true)
    }

    private var now: Date { Date() }
    private var occurringOrFutureManagerOpportunities: [Opportunity] {
        guard let targetId = targetUserId else { return [] }
        return oppViewModel.opportunities
            .filter { $0.creatorUserId == targetId && $0.endDate > now }
            .sorted { $0.eventDate < $1.eventDate }
    }

    // MARK: - Helper Function for Row Backgrounds
    @ViewBuilder
    private func backgroundForRow(for opportunity: Opportunity) -> some View {
        if opportunity.isCurrentlyOccurring {
            AnimatedWaveBackgroundView(
                startTime: opportunity.eventDate,
                endTime: opportunity.endDate,
                baseColor: .mint
            )
        } else if isLoggedInUser && oppViewModel.isRsvped(opportunityId: opportunity.id) {
            Color.green.opacity(0.15)
        } else if isLoggedInUser && oppViewModel.isFavorite(opportunityId: opportunity.id) {
            AnimatedMeshBackgroundView(
                colors: [.red, .pink, .red.opacity(0.3)]
                        )
        } else {
            Color.clear
        }
    }


    // MARK: - Body
    var body: some View {
        List {
            profileHeaderSection
            
            profileInfoSection
            
            upcomingEventsSection
        }
        .listStyle(.grouped)
        .navigationTitle(profileUsername ?? (isLoadingUsername ? "Loading..." : "Manager Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isViewingOwnProfile && authViewModel.isManager {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingEditSheet = true } label: {
                        Label("Edit Profile", systemImage: "pencil.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditManagerProfileView()
                .environmentObject(viewModel)
                .environmentObject(authViewModel)
        }
        .task {
            guard let userId = targetUserId else {
                viewModel.errorMessage = "Could not load profile - user ID missing."
                return
            }
            print("ManagerProfileView .task for user ID: \(userId)")
            viewModel.fetchProfileData(userId: userId)
            await fetchProfileDisplayName(userId: userId)
        }
        .overlay {
            if viewModel.isLoading || isLoadingUsername {
                ProgressView("Loading Profile...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial.opacity(0.8))
            } else if let error = viewModel.errorMessage {
                ErrorOverlayView(message: error) { viewModel.errorMessage = nil } // Allow dismissal
            }
        }
        .refreshable {
            print("Refreshing Manager Profile...")
            guard let userId = targetUserId else { return }
            viewModel.fetchProfileData(userId: userId)
            await fetchProfileDisplayName(userId: userId)
           
        }
        .animation(.default, value: viewModel.bannerImageURL)
        .animation(.default, value: viewModel.logoImageURL)
        .animation(.default, value: occurringOrFutureManagerOpportunities)
        .animation(.default, value: oppViewModel.rsvpedOpportunityIds)
        .animation(.default, value: oppViewModel.favoriteOpportunityIds)
        .animation(.default, value: profileUsername)
    }


    // MARK: - Async Helper Function for Name Fetch
    func fetchProfileDisplayName(userId: String) async {
      
        guard profileUsername == nil || isLoadingUsername == false else { return }
        print("Fetching display name for profile: \(userId)")
        isLoadingUsername = true
        authViewModel.fetchUsername(for: userId) { fetchedName in
            Task { @MainActor in
                self.profileUsername = fetchedName ?? "Manager"
                self.isLoadingUsername = false
                print("Display name fetched: \(self.profileUsername ?? "nil")")
            }
        }
    }


    // MARK: - Extracted Section View Builders

    @ViewBuilder
    private var profileHeaderSection: some View {
        Section {
             EmptyView()
        } header: {
            
             VStack(alignment: .leading, spacing: 0) {
                 bannerAndLogoSection
                 Spacer()
                 Spacer()
                 managerNameSection.padding(.horizontal)
             }
            
             .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: -20))
        }
        .listRowBackground(Color(.systemGroupedBackground))
           
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var profileInfoSection: some View {
         let hasContactInfo = !viewModel.contactEmail.isEmpty || !viewModel.contactPhone.isEmpty || !viewModel.websiteURL.isEmpty
         let hasDescription = !viewModel.managerDescription.isEmpty
         if hasContactInfo || hasDescription || isViewingOwnProfile {
             Section {
                 if hasDescription || isViewingOwnProfile {
                     descriptionSection
                         .padding(.vertical, 5)
                 }
                 if hasContactInfo || isViewingOwnProfile {
                     contactInfoSection
                         .padding(.vertical, 5)
                 }
             } header: {
                  Text("Info").font(.headline).padding(.top)
             }
             .listRowSeparator(.hidden, edges: .top)
         }
    }

    @ViewBuilder
    private var upcomingEventsSection: some View {
        Section {
             if occurringOrFutureManagerOpportunities.isEmpty {
                  Text(isViewingOwnProfile ? "You have no upcoming events scheduled." : "This manager has no upcoming events.")
                     .foregroundColor(.secondary)
                     .padding(.vertical)
             } else {
                 ForEach(occurringOrFutureManagerOpportunities) { opportunity in
                     NavigationLink {
                         OpportunityDetailView(opportunity: opportunity)
                             .environmentObject(authViewModel)
                             .environmentObject(oppViewModel)
                     } label: {
                         OpportunityRowView(opportunity: opportunity)
                             .environmentObject(authViewModel)
                             .environmentObject(oppViewModel)
                     }
                     .buttonStyle(.plain)
                     .listRowBackground(backgroundForRow(for: opportunity)
                     .listRowInsets(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 15))
               )  }
             }
        } header: {
            Text("Upcoming Events")
                .font(.title2).fontWeight(.semibold)
                .padding(.top)
                .padding(.bottom, 5)
        }
    }


    // MARK: - Extracted Element View Builders (Internal Implementation Details)

    @ViewBuilder
    private var bannerAndLogoSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: viewModel.bannerImageURL)) { phase in
                switch phase {
                case .empty: Rectangle().fill(.thinMaterial).frame(height: 180).overlay(ProgressView())
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill).frame(height: 180).clipped()
                case .failure: Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 180).overlay(Image(systemName: "photo.fill").foregroundColor(.gray).imageScale(.large))
                @unknown default: EmptyView()
                }
            }.frame(height: 180)
            AsyncImage(url: URL(string: viewModel.logoImageURL)) { phase in
                 switch phase {
                 case .empty: Circle().fill(.thickMaterial).frame(width: 100, height: 100).overlay(ProgressView())
                 case .success(let image): image.resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 100).clipShape(Circle())
                 case .failure: Circle().fill(Color.secondary.opacity(0.4)).frame(width: 100, height: 100).overlay(Image(systemName: "building.2.crop.circle.fill").foregroundColor(.gray).font(.largeTitle))
                 @unknown default: EmptyView()
                 }
            }
            .frame(width: 100, height: 100)
            .background(Circle().fill(.background))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .offset(x: 20, y: 50)
        }
        .frame(height: 180 + 50)
    }

    @ViewBuilder
    private var managerNameSection: some View {
        HStack {
            Text(profileUsername ?? "")
                .font(.largeTitle).fontWeight(.bold)
                .redacted(reason: isLoadingUsername ? .placeholder : [])
            Spacer()
        }
        .padding(.leading, 5).padding(.top, 5)
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Text(viewModel.managerDescription.isEmpty ? (isViewingOwnProfile ? "Add a description in Edit Profile." : "No description provided.") : viewModel.managerDescription)
            .font(.body)
            .foregroundColor(viewModel.managerDescription.isEmpty ? .secondary : .primary)
    }

    @ViewBuilder
    private var contactInfoSection: some View {
        VStack(alignment: .leading) {
            if !viewModel.contactEmail.isEmpty { ContactRow(icon: "envelope.fill", text: viewModel.contactEmail, urlScheme: "mailto:") }
            if !viewModel.contactPhone.isEmpty { ContactRow(icon: "phone.fill", text: viewModel.contactPhone, urlScheme: "tel:") }
            if !viewModel.websiteURL.isEmpty { ContactRow(icon: "safari.fill", text: viewModel.websiteURL, urlScheme: nil) }
            if viewModel.contactEmail.isEmpty && viewModel.contactPhone.isEmpty && viewModel.websiteURL.isEmpty && isViewingOwnProfile {
                 Text("Add contact info in Edit Profile.").font(.callout).foregroundColor(.secondary).padding(.top, 5)
            }
        }
    }

}


// MARK: - Helper Views (Keep outside main struct, ensure accessible)

struct ContactRow: View {
    let icon: String
    let text: String
    let urlScheme: String?

    private var url: URL? {
        let scheme: String; let path: String
        if let explicitScheme = urlScheme { scheme = explicitScheme; path = text }
        else {
            let lower = text.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { scheme = ""; path = text }
            else { scheme = "https://"; path = text }
        }
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return URL(string: "\(scheme)\(encodedPath)")
    }

    var body: some View {
        if let validURL = url {
            Link(destination: validURL) {
                HStack {
                    Image(systemName: icon).frame(width: 25, alignment: .center).foregroundColor(.secondary)
                    Text(text).foregroundColor(.accentColor).lineLimit(1).truncationMode(.middle)
                }.padding(.vertical, 3)
            }
        } else {
            HStack {
                Image(systemName: icon).frame(width: 25, alignment: .center).foregroundColor(.secondary)
                Text(text).foregroundColor(.primary).lineLimit(1).truncationMode(.middle)
            }.padding(.vertical, 3)
        }
    }
}

struct ErrorOverlayView: View {
    let message: String
    var dismissAction: (() -> Void)? = nil

    var body: some View {
        VStack {
            Spacer()
            HStack { Image(systemName: "exclamationmark.triangle.fill"); Text(message) }
                .font(.caption).padding(12).foregroundColor(.white)
                .background(Color.red.opacity(0.85)).clipShape(Capsule())
                .padding(.bottom)
                .onTapGesture { dismissAction?() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.default, value: message)
    }
}

