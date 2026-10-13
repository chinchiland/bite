import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// You on the community server: signed in with Apple only when you first share, agree or rate,
/// your name as people see it, and the way out. The session sits in the Keychain; nothing of
/// your food log is ever sent.
@MainActor
@Observable
final class CommunityAccount {
    static let shared = CommunityAccount()

    private static let sessionKey = "community-session"
    private static let nameKey = "community.name"

    private(set) var session: CommunitySession?
    /// The name people see, "Dylan T.", editable before sharing and in Settings.
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Self.nameKey) }
    }
    /// The raw nonce of the sign-in in progress; Apple only ever sees its hash.
    private var nonce = ""

    var isSignedIn: Bool { session != nil }

    init() {
        displayName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        if let json = Keychain.string(for: Self.sessionKey), let data = json.data(using: .utf8) {
            session = try? JSONDecoder().decode(CommunitySession.self, from: data)
        }
    }

    /// Fills in Apple's request: the name only, never an email, and a fresh nonce.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        nonce = Self.randomNonce()
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// Apple said yes: a session on the server, your name the first time, and Apple's code
    /// kept by the server for revoking later.
    func complete(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw CommunityClient.Failure.unreadable
        }
        let client = CommunityClient()
        let session = try await client.signIn(idToken: idToken, nonce: nonce)
        store(session)
        if displayName.isEmpty {
            let name = credential.fullName
            displayName = CommunityRemote.shortName(given: name?.givenName, family: name?.familyName)
        }
        if displayName.isEmpty { displayName = String(localized: "Someone") }
        try await client.saveProfile(userID: session.userID, name: displayName, token: session.accessToken)
        if let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
            try? await client.sendAppleCode(code, token: session.accessToken)
        }
    }

    /// A token that is still good, refreshed when it is about to run out.
    func validToken() async throws -> String {
        guard var current = session else { throw CommunityClient.Failure.refused(401, nil) }
        if current.expiresAt.timeIntervalSinceNow < 60 {
            current = try await CommunityClient().refresh(current.refreshToken)
            store(current)
        }
        return current.accessToken
    }

    /// Your new name, for what you share from now on and what you shared before.
    func rename(to name: String) async {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        guard let session, let token = try? await validToken() else { return }
        try? await CommunityClient().saveProfile(userID: session.userID, name: trimmed, token: token)
    }

    func signOut() {
        session = nil
        Keychain.set(nil, for: Self.sessionKey)
    }

    /// Everything you shared, and the account, gone from the server.
    func deleteAccount() async throws {
        let token = try await validToken()
        try await CommunityClient().deleteAccount(token: token)
        signOut()
        displayName = ""
    }

    private func store(_ session: CommunitySession) {
        self.session = session
        let json = (try? JSONEncoder().encode(session)).flatMap { String(data: $0, encoding: .utf8) }
        Keychain.set(json, for: Self.sessionKey)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
