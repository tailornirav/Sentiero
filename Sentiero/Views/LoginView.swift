import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xlarge) {
                Spacer()
                
                // --- HEADER ---
                VStack(spacing: Theme.Spacing.medium) {
                                    
                                    // 1. The Native Apple Button (For Physical Devices)
                                    SignInWithAppleButton(
                                        onRequest: { request in
                                            AuthManager.shared.startAppleSignIn(request: request)
                                        },
                                        onCompletion: { result in
                                            handleAppleLogin(result: result)
                                        }
                                    )
                                    .signInWithAppleButtonStyle(.black)
                                    .frame(height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard, style: .continuous))
                                    
                                    // 2. The Simulator Bypass / Guest Mode
                                    Button(action: {
                                        isLoading = true
                                        errorMessage = ""
                                        Task {
                                            do {
                                                try await AuthManager.shared.signInAnonymously()
                                                print("SUCCESS: Authenticated as a secure Guest.")
                                            } catch {
                                                errorMessage = "Guest Error: \(error.localizedDescription)"
                                                isLoading = false
                                            }
                                        }
                                    }) {
                                        Text("Continue as Guest")
                                    }
                                    .buttonStyle(.plain)
                                    .primaryActionButton(backgroundColor: Theme.Colors.secondary)
                                    .opacity(isLoading ? 0.6 : 1.0)
                                    .disabled(isLoading)
                                }
                                .padding(.horizontal, Theme.Spacing.large)
                                .padding(.bottom, Theme.Spacing.xlarge)
            }
        }
    }
    
    // --- THE LOGIC ENGINE ---
    private func handleAppleLogin(result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = ""
        
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    do {
                        // Pass the secure token to our Firebase bridge
                        try await AuthManager.shared.authenticateWithFirebase(credential: appleIDCredential)
                        print("SUCCESS: Authenticated via Apple.")
                    } catch {
                        errorMessage = "Firebase Error: \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            }
        case .failure(let error):
            errorMessage = "Apple Auth Error: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
