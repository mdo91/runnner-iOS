import AuthenticationServices
import CryptoKit
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import SwiftUI

final class AttestationFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? { AppAttestProvider(app: app) }
}
@MainActor final class AccountManager: ObservableObject {
  @Published var signedIn = false
  @Published var message: String?
  @Published var isWorking = false
  @Published var consent = UserDefaults.standard.string(forKey: "aiConsentVersion") == "2026-10-03"
  @Published var adultConfirmed = UserDefaults.standard.bool(forKey: "adultConfirmed")
  private var nonce: String?
  private var deleting = false
  private var listener: AuthStateDidChangeListenerHandle?
  static var configured: Bool { FirebaseApp.app() != nil }
  init() {
    if Self.configured {
      listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
        Task { @MainActor in self?.signedIn = user != nil }
      }
    }
  }
  func prepare(_ request: ASAuthorizationAppleIDRequest, deleting: Bool = false) {
    self.deleting = deleting
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      message = "Could not prepare secure sign-in."
      return
    }
    let nonce = bytes.map { String(format: "%02x", $0) }.joined()
    self.nonce = nonce
    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    request.requestedScopes = []
  }
  func finish(_ result: Result<ASAuthorization, Error>) async {
    guard Self.configured else {
      message = "Account services are not configured yet."
      return
    }
    isWorking = true
    defer {
      isWorking = false
      nonce = nil
    }
    do {
      let response = try result.get()
      guard let apple = response.credential as? ASAuthorizationAppleIDCredential,
        let data = apple.identityToken,
        let token = String(data: data, encoding: .utf8), let nonce
      else { throw AccountError.signIn }
      let credential = OAuthProvider.appleCredential(
        withIDToken: token, rawNonce: nonce, fullName: nil)
      if deleting {
        guard let user = Auth.auth().currentUser, let codeData = apple.authorizationCode,
          let code = String(data: codeData, encoding: .utf8)
        else { throw AccountError.signIn }
        try await user.reauthenticate(with: credential)
        try await Auth.auth().revokeToken(withAuthorizationCode: code)
        try await APIClient.deleteAccount()
        try? Auth.auth().signOut()
        setConsent(false)
        signedIn = false
        message =
          "Your cloud account and analysis data have been deleted. Health data remains on this device."
      } else {
        _ = try await Auth.auth().signIn(with: credential)
        message = nil
      }
    } catch {
      message =
        deleting
        ? "Account deletion could not finish. Sign in again to retry."
        : "Sign in was not completed. You can keep using your measured stats."
    }
  }
  func setConsent(_ value: Bool) {
    consent = value && adultConfirmed
    UserDefaults.standard.set(consent ? "2026-10-03" : nil, forKey: "aiConsentVersion")
    UserDefaults.standard.set(adultConfirmed, forKey: "adultConfirmed")
  }
  func signOut() {
    try? Auth.auth().signOut()
    signedIn = false
    setConsent(false)
  }
  enum AccountError: Error { case signIn }
}
