import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Binding var showLogin: Bool // To toggle back to Login

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = "" // Added confirmation
    @State private var showPassword: Bool = false
    @State private var showConfirmPassword: Bool = false

    // Basic validation
    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    var isValid: Bool {
        !email.isEmpty && passwordsMatch && password.count >= 6 // Firebase requires 6+ chars
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up").font(.title2).fontWeight(.semibold)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textContentType(.emailAddress)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

             HStack { // Password Field
                  if showPassword { TextField("Password", text: $password).textContentType(.newPassword) }
                  else { SecureField("Password (min 6 chars)", text: $password).textContentType(.newPassword) }
                  Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye").foregroundColor(.secondary) }
              }
              .padding()
              .background(Color(.systemGray6))
              .cornerRadius(10)

             HStack { // Confirm Password Field
                 if showConfirmPassword { TextField("Confirm Password", text: $confirmPassword).textContentType(.newPassword) }
                 else { SecureField("Confirm Password", text: $confirmPassword).textContentType(.newPassword) }
                 Button { showConfirmPassword.toggle() } label: { Image(systemName: showConfirmPassword ? "eye.slash" : "eye").foregroundColor(.secondary) }
             }
             .padding()
             .background(Color(.systemGray6))
             .cornerRadius(10)

             // Validation feedback
             if !password.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
                 Text("Passwords do not match.")
                     .foregroundColor(.red).font(.caption)
             }
             if !password.isEmpty && password.count < 6 {
                 Text("Password must be at least 6 characters.")
                    .foregroundColor(.red).font(.caption)
             }

            // Show general error message
            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // Loading / Sign Up Button
            if authViewModel.isLoading {
                ProgressView()
            } else {
                Button {
                    authViewModel.signUp(email: email, password: password)
                } label: {
                    Text("Sign Up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green) // Differentiate from login
                .disabled(!isValid) // Disable if not valid
            }

            // Toggle to Log In
            Button {
                authViewModel.errorMessage = nil // Clear error when switching
                showLogin = true
            } label: {
                HStack(spacing: 4) {
                    Text("Already have an account?")
                    Text("Log In").fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .padding(.top)
        }
    }
}
