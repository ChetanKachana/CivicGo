import Foundation
import FirebaseFirestore
import Combine
import SwiftUI // Keep for @MainActor, @Published etc.

@MainActor // Ensure UI updates are on main thread by default for this class
class ManagerProfileViewModel: ObservableObject {

    // MARK: - Published Properties for Profile Data (URLs as Strings)
    @Published var bannerImageURL: String = ""
    @Published var logoImageURL: String = ""
    @Published var managerDescription: String = ""
    @Published var contactEmail: String = ""
    @Published var contactPhone: String = ""
    @Published var websiteURL: String = ""

    // MARK: - State Properties
    @Published var isLoading: Bool = false // Overall loading state (fetch, save)
    @Published var errorMessage: String? = nil

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var profileListener: ListenerRegistration?
    private var managerUserId: String? // Store the ID we are listening to

    // MARK: - Deinitialization
    deinit {
        print("ManagerProfileViewModel deinited. Removing listener.")
        profileListener?.remove()
    }

    // MARK: - Initialization
    // Default initializer is sufficient

    // MARK: - Fetching Data
    func fetchProfileData(userId: String) {
        // Avoid redundant listeners for the same user
        if profileListener != nil && managerUserId == userId && !isLoading {
            print("ManagerProfileViewModel: Listener already active for \(userId).")
            return
        }

        print("ManagerProfileViewModel: Fetching profile data for \(userId)...")
        isLoading = true
        errorMessage = nil
        managerUserId = userId // Store the ID

        // Remove old listener if user changes or refetching
        profileListener?.remove()

        let docRef = db.collection("users").document(userId)

        profileListener = docRef.addSnapshotListener { [weak self] (documentSnapshot, error) in
             // Ensure updates run on MainActor (listener callback might not be)
             Task { @MainActor in
                 guard let self = self else { return }
                 self.isLoading = false // Stop overall loading once data/error arrives

                 if let error = error {
                     print("!!! ManagerProfileViewModel: Listener Error: \(error.localizedDescription)")
                     self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
                     self.clearFields() // Clear fields on error
                     return
                 }

                 guard let document = documentSnapshot, document.exists else {
                     print("ManagerProfileViewModel: Document \(userId) does not exist.")
                     // Only set error if one isn't already set (e.g., from a failed update)
                     if self.errorMessage == nil { self.errorMessage = "Profile data not found." }
                     self.clearFields() // Clear fields if doc doesn't exist
                     return
                 }

                 let data = document.data() ?? [:] // Get data or empty dict

                 // Update published properties directly from Firestore data
                 let newBannerURL = data["bannerImageURL"] as? String ?? ""
                 if self.bannerImageURL != newBannerURL { self.bannerImageURL = newBannerURL }

                 let newLogoURL = data["logoImageURL"] as? String ?? ""
                 if self.logoImageURL != newLogoURL { self.logoImageURL = newLogoURL }

                 let newDesc = data["managerDescription"] as? String ?? ""
                 if self.managerDescription != newDesc { self.managerDescription = newDesc }

                 let newEmail = data["contactEmail"] as? String ?? ""
                 if self.contactEmail != newEmail { self.contactEmail = newEmail }

                 let newPhone = data["contactPhone"] as? String ?? ""
                 if self.contactPhone != newPhone { self.contactPhone = newPhone }

                 let newWebsite = data["websiteURL"] as? String ?? ""
                 if self.websiteURL != newWebsite { self.websiteURL = newWebsite }

                 print("ManagerProfileViewModel: Profile data updated via listener.")
                 // Clear general error on successful data load, preserving update errors
                 if self.errorMessage != nil && !(self.errorMessage?.contains("update") ?? false) {
                     self.errorMessage = nil
                 }
            }
        }
    }

    // MARK: - Updating Profile Data (Using URL Strings)

    /// Updates the manager's profile fields in Firestore using string URLs provided from the UI.
    func updateProfileData(userId: String,
                           bannerURL: String,    // URL provided as String
                           logoURL: String,      // URL provided as String
                           description: String,
                           contactEmail: String,
                           contactPhone: String,
                           websiteURL: String) {

        print("ManagerProfileViewModel: Updating profile for \(userId)...")
        Task { @MainActor in isLoading = true; errorMessage = nil }

        // No image upload logic needed

        // --- Update Firestore Directly with Provided URLs and Text ---
        Task { // Keep background task for Firestore write consistency
            let docRef = db.collection("users").document(userId)
            let dataToUpdate: [String: Any] = [
                // Use the URLs passed directly from the Edit View's state
                "bannerImageURL": bannerURL.nilIfEmpty as Any, // Use helper to store nil if empty
                "logoImageURL": logoURL.nilIfEmpty as Any,     // Use helper to store nil if empty
                "managerDescription": description.nilIfEmpty as Any,
                "contactEmail": contactEmail.nilIfEmpty as Any,
                "contactPhone": contactPhone.nilIfEmpty as Any,
                "websiteURL": websiteURL.nilIfEmpty as Any
            ]

            do {
                // Use updateData to only modify specified fields
                try await docRef.updateData(dataToUpdate)
                print("ManagerProfileViewModel: Firestore update successful.")
                // --- SUCCESS ---
                Task { @MainActor in
                     self.isLoading = false
                     self.errorMessage = nil // Clear any previous error
                     // Listener will reflect the changes shortly
                }
            } catch {
                // --- HANDLE FIRESTORE ERROR ---
                print("!!! Firestore Update Error: \(error.localizedDescription)")
                 // Attempt to get more specific Firestore error info if needed
                 var specificErrorMessage = error.localizedDescription
                 if let firestoreError = error as NSError?, firestoreError.domain == FirestoreErrorDomain {
                      print("!!! Firestore Error Code: \(firestoreError.code)")
                      // Add specific FirestoreErrorCode checks here if desired
                      specificErrorMessage = "Firestore update failed (\(firestoreError.code)): \(error.localizedDescription)"
                 }

                 Task { @MainActor in
                     self.isLoading = false
                     self.errorMessage = "Failed to update profile: \(specificErrorMessage)"
                 }
            }
        } // End background Task
    }

    // MARK: - Helper
    /// Clears displayed profile fields (called on error or if doc doesn't exist)
    /// Needs @MainActor as it modifies @Published vars.
    @MainActor
    private func clearFields() {
        bannerImageURL = ""
        logoImageURL = ""
        managerDescription = ""
        contactEmail = ""
        contactPhone = ""
        websiteURL = ""
        // No image data to clear
    }
}


