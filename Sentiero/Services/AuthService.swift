import Foundation
import FirebaseAuth
import Combine
import AuthenticationServices
import CryptoKit

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var currentUserID: String? = nil
    
    var currentNonce: String?
    
    /// Retain the handle so the listener stays registered (and silence the unused-result warning).
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    /// Used to detect account switches so shared UI state (tabs, plan stack) does not leak across users.
    private var lastObservedAuthUid: String?

    private init() {
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                guard let self else { return }
                let newUid = user?.uid
                if self.lastObservedAuthUid != nil, self.lastObservedAuthUid != newUid {
                    GlobalRouter.shared.resetForAccountChange()
                }
                self.lastObservedAuthUid = newUid
                self.isAuthenticated = user != nil
                self.currentUserID = newUid
            }
        }
    }
    
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess { fatalError("Unable to generate nonce.") }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }
    
    func startAppleSignIn(request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }
    
    
    func authenticateWithFirebase(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce else {
            throw URLError(.cannotDecodeRawData)
        }
        guard let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        self.currentUserID = result.user.uid
        self.isAuthenticated = true
    }
    
    func signInAnonymously() async throws {
            let result = try await Auth.auth().signInAnonymously()
            self.currentUserID = result.user.uid
            self.isAuthenticated = true
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.isAuthenticated = false
            self.currentUserID = nil
        } catch {
            print("Failed to sign out: \(error.localizedDescription)")
        }
    }
}
