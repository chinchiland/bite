import Foundation

/// Your answer to the one question photo estimates ask first: Bite's own estimates run on
/// Google's Gemini, whose terms are for people 18 and over. Asked once, the first time you scan
/// a meal without your own Claude key.
enum AgeAnswer: String {
    case unknown
    case adult
    case under

    private static let key = "scan.age"

    static var current: AgeAnswer {
        get { UserDefaults.standard.string(forKey: key).flatMap(AgeAnswer.init) ?? .unknown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// The session photo estimates need on Bite's server. Signed in with Apple for sharing, that one
/// is used; otherwise an anonymous one, made the first time you scan and kept in the Keychain. It
/// carries no name and no email: only a random id the daily ceilings count by.
@MainActor
final class ScanAccount {
    static let shared = ScanAccount()

    private static let sessionKey = "scan-session"

    /// A token that is good for a minute at least, made or refreshed as needed.
    func token() async throws -> String {
        if CommunityAccount.shared.isSignedIn, let token = try? await CommunityAccount.shared.validToken() {
            return token
        }
        let client = CommunityClient()
        if var session = stored {
            if session.expiresAt.timeIntervalSinceNow < 60 {
                guard let refreshed = try? await client.refresh(session.refreshToken) else {
                    forget()
                    return try await token()
                }
                session = refreshed
                store(session)
            }
            return session.accessToken
        }
        let session = try await client.signUpAnonymously()
        store(session)
        return session.accessToken
    }

    /// The server no longer knows the session: the next scan makes a new one.
    func forget() {
        Keychain.set(nil, for: Self.sessionKey)
    }

    private var stored: CommunitySession? {
        guard let json = Keychain.string(for: Self.sessionKey), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CommunitySession.self, from: data)
    }

    private func store(_ session: CommunitySession) {
        let json = (try? JSONEncoder().encode(session)).flatMap { String(data: $0, encoding: .utf8) }
        Keychain.set(json, for: Self.sessionKey)
    }
}

/// Photo estimates through Bite's own server, with no key to set up: the server asks Gemini 3.1
/// Flash-Lite and answers in the same shape Claude does. It keeps ceilings no honest use reaches
/// (a dozen a minute, eighty a day), so a script can't run up the bill.
struct BiteVision {
    enum Failure: LocalizedError, Equatable {
        case limit(String)
        case busy
        case unreadable

        var errorDescription: String? {
            switch self {
            case .limit("minute"):
                tr("That's a lot of photos in one minute. Give it a few seconds.")
            case .limit("day"):
                tr("That's a lot of photos for one day. Photo estimates are back tomorrow; barcodes and search work as usual.")
            case .limit:
                tr("Photo estimates are resting for a while. Barcodes and search work as usual.")
            case .busy:
                tr("Photo estimates are busy right now. Try again in a moment.")
            case .unreadable:
                tr("The estimate came back unreadable. Try again.")
            }
        }
    }

    var session: URLSession = .shared

    @MainActor
    func estimate(jpeg: Data, language: String, isLabel: Bool = false, retried: Bool = false) async throws -> MealEstimate {
        guard let base = CommunityServer.url,
              let url = URL(string: "functions/v1/estimate", relativeTo: base.appending(path: "/")) else { throw Failure.busy }
        let token = try await ScanAccount.shared.token()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CommunityServer.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jpeg": jpeg.base64EncodedString(),
            "language": language,
            "isLabel": isLabel,
        ])
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            guard let estimate = try? JSONDecoder().decode(MealEstimate.self, from: data) else { throw Failure.unreadable }
            return estimate.cleaned()
        case 401 where !retried:
            // The anonymous session was cleared on the server: one fresh one, one more try.
            ScanAccount.shared.forget()
            return try await estimate(jpeg: jpeg, language: language, isLabel: isLabel, retried: true)
        case 429:
            struct Answer: Decodable { let limit: String? }
            throw Failure.limit((try? JSONDecoder().decode(Answer.self, from: data))?.limit ?? "")
        default:
            throw Failure.busy
        }
    }
}

/// Every photo estimate goes through here: your own Claude key when you set one, otherwise Bite's
/// server. What needs you (the age question, a ceiling) comes back for the screen to show.
enum PhotoEstimator {
    enum Blocked: Error, Equatable {
        /// Asked once before Bite's own estimates.
        case needsAge
        /// Under 18: barcodes, search and saved foods only, unless a Claude key is set.
        case underAge
        /// No server in this build and no key: the key is the only way.
        case needsKey
    }

    @MainActor
    static func estimate(jpeg: Data, language: String, isLabel: Bool = false) async throws -> MealEstimate {
        let key = Keychain.string(for: Keychain.claudeKey) ?? ""
        if !key.isEmpty {
            return try await ClaudeVision(apiKey: key).estimate(jpeg: jpeg, language: language, isLabel: isLabel)
        }
        guard CommunityServer.isConfigured else { throw Blocked.needsKey }
        switch AgeAnswer.current {
        case .unknown: throw Blocked.needsAge
        case .under: throw Blocked.underAge
        case .adult: return try await BiteVision().estimate(jpeg: jpeg, language: language, isLabel: isLabel)
        }
    }
}
