import Foundation
import FirebaseFirestore
import Combine
import SwiftUI

@MainActor
class ManagerProfileViewModel: ObservableObject {

    // MARK: - Published Properties for Profile Data (URLs as Strings)
    @Published var bannerImageURL: String = ""
    @Published var logoImageURL: String = ""
    @Published var managerDescription: String = ""
    @Published var contactEmail: String = ""
    @Published var contactPhone: String = ""
    @Published var websiteURL: String = ""

    // MARK: - State Properties
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var profileListener: ListenerRegistration?
    private var managerUserId: String?

    // MARK: - Deinitialization
    deinit {
        print("ManagerProfileViewModel deinited. Removing listener.")
        profileListener?.remove()
    }

    // MARK: - Initialization
   

    // MARK: - Fetching Data
    func fetchProfileData(userId: String) {
        if profileListener != nil && managerUserId == userId && !isLoading {
            print("ManagerProfileViewModel: Listener already active for \(userId).")
            return
        }

        print("ManagerProfileViewModel: Fetching profile data for \(userId)...")
        isLoading = true
        errorMessage = nil
        managerUserId = userId

        profileListener?.remove()

        let docRef = db.collection("users").document(userId)

        profileListener = docRef.addSnapshotListener { [weak self] (documentSnapshot, error) in
           
             Task { @MainActor in
                 guard let self = self else { return }
                 self.isLoading = false

                 if let error = error {
                     print("!!! ManagerProfileViewModel: Listener Error: \(error.localizedDescription)")
                     self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
                     self.clearFields()
                     return
                 }

                 guard let document = documentSnapshot, document.exists else {
                     print("ManagerProfileViewModel: Document \(userId) does not exist.")
                     if self.errorMessage == nil { self.errorMessage = "Profile data not found." }
                     self.clearFields()
                     return
                 }

                 let data = document.data() ?? [:]

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
                 if self.errorMessage != nil && !(self.errorMessage?.contains("update") ?? false) {
                     self.errorMessage = nil
                 }
            }
        }
    }

    // MARK: - Updating Profile Data (Using URL Strings)

    
    func updateProfileData(userId: String,
                           bannerURL: String,
                           logoURL: String,
                           description: String,
                           contactEmail: String,
                           contactPhone: String,
                           websiteURL: String) {

        print("ManagerProfileViewModel: Updating profile for \(userId)...")
        Task { @MainActor in isLoading = true; errorMessage = nil }

       
        Task {
            let docRef = db.collection("users").document(userId)
            let dataToUpdate: [String: Any] = [
               
                "bannerImageURL": bannerURL.nilIfEmpty as Any,
                "logoImageURL": logoURL.nilIfEmpty as Any,
                "managerDescription": description.nilIfEmpty as Any,
                "contactEmail": contactEmail.nilIfEmpty as Any,
                "contactPhone": contactPhone.nilIfEmpty as Any,
                "websiteURL": websiteURL.nilIfEmpty as Any
            ]

            do {
                try await docRef.updateData(dataToUpdate)
                print("ManagerProfileViewModel: Firestore update successful.")
                Task { @MainActor in
                     self.isLoading = false
                     self.errorMessage = nil
                }
            } catch {
                
                print("!!! Firestore Update Error: \(error.localizedDescription)")
                 var specificErrorMessage = error.localizedDescription
                 if let firestoreError = error as NSError?, firestoreError.domain == FirestoreErrorDomain {
                      print("!!! Firestore Error Code: \(firestoreError.code)")
                      specificErrorMessage = "Firestore update failed (\(firestoreError.code)): \(error.localizedDescription)"
                 }

                 Task { @MainActor in
                     self.isLoading = false
                     self.errorMessage = "Failed to update profile: \(specificErrorMessage)"
                 }
            }
        }
    }

    // MARK: - Helper
   
    @MainActor
    private func clearFields() {
        bannerImageURL = ""
        logoImageURL = ""
        managerDescription = ""
        contactEmail = ""
        contactPhone = ""
        websiteURL = ""
    }
}


