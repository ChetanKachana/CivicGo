import SwiftUI
// Removed FirebaseAuth import if not directly used here

// MARK: - Authentication View (Google & Anonymous)
// Provides options for Google Sign-In or browsing anonymously.
struct AuthenticationView: View {
    // EnvironmentObject to access shared authentication state and actions
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    // Removed @State private var showLogin

    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 for edge-to-edge feel if using background

            Spacer() // Pushes branding down slightly

            // --- App Branding Area ---
            VStack {
                Image(systemName: "person.3.sequence.fill") // Placeholder icon
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 10)

                Text("Volunteer Connect") // Replace with your app name
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 60) // More space below branding

            // --- Sign-In Options ---
            VStack(spacing: 20) { // Stack the buttons

                // --- Google Sign-In Button ---
                Button {
                    authViewModel.signInWithGoogle() // Call Google sign-in action
                } label: {
                    HStack {
                        // Use a standard Google logo if available (add as asset)
                        // Image("google_logo") // Example if you have the asset
                        //     .resizable().scaledToFit().frame(height: 22)
                        // Or use SF Symbol as placeholder
                        Image(systemName: "g.circle.fill")
                             .resizable().scaledToFit().frame(height: 22)
                             .foregroundColor(.white) // Make symbol white if button is colored

                        Text("Sign in with Google")
                            .fontWeight(.medium)
                            .foregroundColor(.white) // White text on colored button
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity) // Make button wide
                    .background(Color.blue) // Standard Google blue (or use custom)
                    .cornerRadius(8)
                }
                .shadow(radius: 2, y: 1) // Add subtle shadow

                // --- Anonymous Browsing Button ---
                Button {
                    authViewModel.signInAnonymously() // Call anonymous sign-in action
                } label: {
                    Text("Browse as Guest")
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered) // Use bordered style
                .tint(.secondary) // Secondary tint


                // --- Loading / Error Display Area ---
                // Show loading indicator or error message below buttons
                 if authViewModel.isLoading {
                     ProgressView()
                         .padding(.top, 20)
                 } else if let errorMessage = authViewModel.errorMessage {
                     Text(errorMessage)
                         .font(.caption)
                         .foregroundColor(.red)
                         .multilineTextAlignment(.center)
                         .padding(.horizontal)
                         .padding(.top, 15)
                 }

            } // End Sign-In Options VStack
            .padding(.horizontal, 40) // Add horizontal padding to button area

            Spacer() // Pushes buttons up from bottom edge
            Spacer() // Add more space at bottom

        } // End main VStack
        // Optional background
        // .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // Clear errors when view appears
        .onAppear {
            authViewModel.errorMessage = nil
        }
    } // End body
} // End struct AuthenticationView

