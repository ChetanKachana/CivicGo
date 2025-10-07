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

                Text("CivicGo") // Replace with your app name
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
                                        // Icon (Using SF Symbol as placeholder)
                                        Image("googleicon")
                                             .resizable().scaledToFit().frame(height: 30)
                                             .clipShape(Circle())
                                             // Color set by foregroundColor on HStack below

                                        Text("Sign in with Google")
                                            .fontWeight(.medium)
                                            // Color set by foregroundColor on HStack below
                                    }
                                    .foregroundColor(.secondary) // Set icon and text color to white
                                    .padding(.vertical, 12) // Vertical padding inside button
                                    .padding(.horizontal, 12) // Make button wide
                                    .background(Color.clear) // Set background to black
                                    .cornerRadius(8) // Round the corners of the background
                                    // --- Add the Gradient Border Overlay ---
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8) // Shape matching the background
                                            .stroke( // Apply stroke to the shape's border
                                                // Define the gradient
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.red, .yellow, .green, .blue]), // Your desired colors
                                                    startPoint: .leading, // Gradient direction: Left
                                                    endPoint: .trailing   // Gradient direction: Right
                                                ),
                                                lineWidth: 2
                                                    // Adjust border thickness as needed
                                            )
                                            .opacity(75)
                                    )
                                    // --- End Gradient Border Overlay ---
                                }
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1) // Optional subtle shadow

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
            Text("In partnership with The Youth Action Council")
                .font(.caption)
                .foregroundStyle(.secondary)

        } // End main VStack
        // Optional background
        // .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // Clear errors when view appears
        .onAppear {
            authViewModel.errorMessage = nil
        }
    } // End body
} // End struct AuthenticationView

