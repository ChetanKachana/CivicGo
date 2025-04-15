import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Binding var showLogin: Bool // To toggle back to Sign Up

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Log In").font(.title2).fontWeight(.semibold)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textContentType(.emailAddress)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

            HStack { // Password Field with Show/Hide
                 if showPassword {
                     TextField("Password", text: $password)
                         .autocapitalization(.none)
                         .textContentType(.password) // Helps with autofill
                 } else {
                     SecureField("Password", text: $password)
                         .textContentType(.password)
                 }
                 Button {
                     showPassword.toggle()
                 } label: {
                     Image(systemName: showPassword ? "eye.slash" : "eye")
                         .foregroundColor(.secondary)
                 }
             }
             .padding()
             .background(Color(.systemGray6))
             .cornerRadius(10)


            // Show error message
            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // Loading / Sign In Button
            if authViewModel.isLoading {
                ProgressView()
            } else {
                Button {
                    authViewModel.signIn(email: email, password: password)
                } label: {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue) // Or your app's theme color
                .disabled(email.isEmpty || password.isEmpty)
            }

            // Toggle to Sign Up
            Button {
                authViewModel.errorMessage = nil // Clear error when switching
                showLogin = false
            } label: {
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                    Text("Sign Up").fontWeight(.semibold)
                }
                .font(.footnote)
            }
            .padding(.top)
        }
    }
}
