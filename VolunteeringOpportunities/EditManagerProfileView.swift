import SwiftUI

struct EditManagerProfileView: View {
    @EnvironmentObject var viewModel: ManagerProfileViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss

    @State private var bannerURL: String = ""
    @State private var logoURL: String = ""
    @State private var description: String = ""
    @State private var contactEmail: String = ""
    @State private var contactPhone: String = ""
    @State private var websiteURL: String = ""

    private var canSaveChanges: Bool {
         !viewModel.isLoading
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Profile Images (Enter URLs)") {
                    TextField("Banner Image URL", text: $bannerURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Logo Image URL", text: $logoURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Note: Please provide direct URLs to hosted images (e.g., Imgur, Dropbox public link). Image uploading is not supported.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

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

                 if let error = viewModel.errorMessage {
                     Section {
                         Text("Error: \(error)")
                             .foregroundColor(.red)
                     }
                 }

                 if viewModel.isLoading {
                      Section {
                          HStack { Spacer(); ProgressView("Saving..."); Spacer() }
                      }
                  }

            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSaveChanges)
                }
            }
            .onAppear {
                bannerURL = viewModel.bannerImageURL
                logoURL = viewModel.logoImageURL
                description = viewModel.managerDescription
                contactEmail = viewModel.contactEmail
                contactPhone = viewModel.contactPhone
                websiteURL = viewModel.websiteURL
                 viewModel.errorMessage = nil
            }
             .onChange(of: viewModel.isLoading) { oldVal, newVal in
                 if oldVal == true && newVal == false && viewModel.errorMessage == nil {
                      dismiss()
                 }
             }

        }
    }

    private func saveChanges() {
        guard let userId = authViewModel.userSession?.uid else {
             viewModel.errorMessage = "Cannot save profile - user not found."
             return
        }

        let trimmedBanner = bannerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogo = logoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWebsite = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        viewModel.updateProfileData(userId: userId,
                                   bannerURL: trimmedBanner,
                                   logoURL: trimmedLogo,
                                   description: trimmedDesc,
                                   contactEmail: trimmedEmail,
                                   contactPhone: trimmedPhone,
                                   websiteURL: trimmedWebsite)
    }
}
