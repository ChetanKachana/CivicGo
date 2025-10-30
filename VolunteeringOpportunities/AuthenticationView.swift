import SwiftUI

// MARK: - Authentication View (Google & Anonymous)
struct AuthenticationView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            VStack {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 10)

                Text("CivicGo")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            .padding(.bottom, 60)

            VStack(spacing: 20) {

                Button {
                                    authViewModel.signInWithGoogle()
                                } label: {
                                    HStack {
                                        Image("googleicon")
                                             .resizable().scaledToFit().frame(height: 30)
                                             .clipShape(Circle())

                                        Text("Sign in with Google")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 12)
                                    .background(Color.clear)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [.red, .yellow, .green, .blue]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 2
                                            )
                                            .opacity(75)
                                    )
                                }
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                Button {
                    authViewModel.signInAnonymously()
                } label: {
                    Text("Browse as Guest")
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)


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

            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
            

        }
        .onAppear {
            authViewModel.errorMessage = nil
        }
    }
}
