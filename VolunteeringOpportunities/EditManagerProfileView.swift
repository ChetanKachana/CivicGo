import SwiftUI
// Removed: import PhotosUI

struct EditManagerProfileView: View {
    @EnvironmentObject var viewModel: ManagerProfileViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss

    // Local state bound to TextFields, RE-ADD URL fields
    @State private var bannerURL: String = "" // <-- Re-added
    @State private var logoURL: String = ""   // <-- Re-added
    @State private var description: String = ""
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    @State private var websiteURL: String = ""

    // --- REMOVED: State for PhotosPicker ---
    // @State private var selectedBannerItem: PhotosPickerItem? = nil
    // @State private var selectedLogoItem: PhotosPickerItem? = nil

    // Simplified save check
    private var canSaveChanges: Bool {
         !viewModel.isLoading
    }

    var body: some View {
        NavigationView {
            Form {
                // --- REVERTED: Image URL TextFields ---
                Section("Profile Images (Enter URLs)") {
                    TextField("Banner Image URL", text: $bannerURL) // <-- Restored TextField
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Logo Image URL", text: $logoURL) // <-- Restored TextField
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Note: Please provide direct URLs to hosted images (e.g., Imgur, Dropbox public link). Image uploading is not supported.") // Updated note
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                // --- END REVERTED ---

                // --- REMOVED: Image Picker/Preview Sections and Progress ---

                Section("About") {
                    TextEditor(text: $description)
                        .frame(height: 150)
                }

                Section("Contact Information") {
                    TextField("Contact Email", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Contact Phone", text: $contactPhone)
                        .keyboardType(.phonePad)
                    TextField("Website URL", text: $websiteURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                // Error display
                 if let error = viewModel.errorMessage {
                     Section {
                         Text("Error: \(error)")
                             .foregroundColor(.red)
                     }
                 }

                 // Loading Indicator (Overall Save)
                 if viewModel.isLoading {
                      Section {
                          HStack { Spacer(); ProgressView("Saving..."); Spacer() }
                      }
                  }

            } // End Form
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() } // No need to reset image data
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSaveChanges)
                }
            }
            .onAppear {
                // Initialize local state with current ViewModel values
                bannerURL = viewModel.bannerImageURL // <-- Initialize restored state
                logoURL = viewModel.logoImageURL     // <-- Initialize restored state
                description = viewModel.managerDescription
                contactEmail = viewModel.contactEmail
                contactPhone = viewModel.contactPhone
                websiteURL = viewModel.websiteURL
                // Clear previous errors
                 viewModel.errorMessage = nil
                 // --- REMOVED: Reset selections ---
                 // viewModel.selectedBannerImageData = nil
                 // viewModel.selectedLogoImageData = nil
                 // selectedBannerItem = nil
                 // selectedLogoItem = nil
            }
             // Dismiss automatically on successful save
             .onChange(of: viewModel.isLoading) { oldVal, newVal in
                 // Simplified check (no upload states to worry about)
                 if oldVal == true && newVal == false && viewModel.errorMessage == nil {
                      dismiss()
                 }
             }
            // --- REMOVED: .onChange Modifiers for PhotosPicker ---

        } // End NavigationView
    }

    // --- REMOVED: Image Picker Section View Builders ---
    // @ViewBuilder private func imagePickerSection(...) ...
    // @ViewBuilder private func imagePreview(...) ...

    private func saveChanges() {
        guard let userId = authViewModel.userSession?.uid else {
             viewModel.errorMessage = "Cannot save profile - user not found."
             return
        }

        // Trim all local state fields
        let trimmedBanner = bannerURL.trimmingCharacters(in: .whitespacesAndNewlines) // <-- Use local state
        let trimmedLogo = logoURL.trimmingCharacters(in: .whitespacesAndNewlines)     // <-- Use local state
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWebsite = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Call the updated ViewModel function with URL parameters
        viewModel.updateProfileData(userId: userId,
                                   bannerURL: trimmedBanner, // <-- Pass local state
                                   logoURL: trimmedLogo,     // <-- Pass local state
                                   description: trimmedDesc,
                                   contactEmail: trimmedEmail,
                                   contactPhone: trimmedPhone,
                                   websiteURL: trimmedWebsite)
    }
}
