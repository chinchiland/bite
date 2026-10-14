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
/// Flash-Lite and answers in the same shape Claude does. Menus and dishes typed in search go the
/// same way. It keeps ceilings no honest use reaches (a dozen a minute, eighty a day), so a script
/// can't run up the bill.
struct BiteVision {
    enum Failure: LocalizedError, Equatable {
        case limit(String)
        case busy
        case unreadable

        var errorDescription: String? {
            switch self {
            case .limit("minute"):
                tr("That's a lot of estimates in one minute. Give it a few seconds.")
            case .limit("day"):
                tr("That's a lot of estimates for one day. They're back tomorrow; barcodes and product search work as usual.")
            case .limit:
                tr("Estimates are resting for a while. Barcodes and product search work as usual.")
            case .busy:
                tr("Estimates are busy right now. Try again in a moment.")
            case .unreadable:
                tr("The estimate came back unreadable. Try again.")
            }
        }
    }

    var session: URLSession = .shared

    @MainActor
    func estimate(jpeg: Data, language: String, isLabel: Bool = false) async throws -> MealEstimate {
        let data = try await post(["kind": "plate", "jpeg": jpeg.base64EncodedString(), "language": language, "isLabel": isLabel])
        guard let estimate = try? JSONDecoder().decode(MealEstimate.self, from: data) else { throw Failure.unreadable }
        return estimate.cleaned()
    }

    /// Every dish on a menu's photo. A long menu is a long answer: up to a minute or so.
    @MainActor
    func menu(jpeg: Data, language: String) async throws -> MenuScan {
        let data = try await post(["kind": "menu", "jpeg": jpeg.base64EncodedString(), "language": language], timeout: 150)
        guard let menu = MenuScan.read(data) else { throw Failure.unreadable }
        return menu
    }

    /// One portion of a dish typed in search, as it is usually served.
    @MainActor
    func dish(named name: String, language: String) async throws -> TypicalDish {
        let data = try await post(["kind": "dish", "text": TypicalDish.cleanName(name), "language": language], timeout: 60)
        return try TypicalDish.read(data)
    }

    @MainActor
    private func post(_ body: [String: Any], timeout: TimeInterval = 90, retried: Bool = false) async throws -> Data {
        guard let base = CommunityServer.url,
              let url = URL(string: "functions/v1/estimate", relativeTo: base.appending(path: "/")) else { throw Failure.busy }
        let token = try await ScanAccount.shared.token()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CommunityServer.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            return data
        case 401 where !retried:
            // The anonymous session was cleared on the server: one fresh one, one more try.
            ScanAccount.shared.forget()
            return try await post(body, timeout: timeout, retried: true)
        case 429:
            struct Answer: Decodable { let limit: String? }
            throw Failure.limit((try? JSONDecoder().decode(Answer.self, from: data))?.limit ?? "")
        default:
            throw Failure.busy
        }
    }
}

/// Every estimate goes through here, a photo's, a menu's or a dish typed in search: your own
/// Claude key when you set one, otherwise Bite's server. What needs you (the age question, a
/// ceiling) comes back for the screen to show.
enum PhotoEstimator {
    enum Blocked: Error, Equatable {
        /// Asked once before Bite's own estimates.
        case needsAge
        /// Under 18: barcodes, search and saved foods only, unless a Claude key is set.
        case underAge
        /// No server in this build and no key: the key is the only way.
        case needsKey
    }

    private enum Road {
        case claude(ClaudeVision)
        case bite
    }

    /// The language estimates answer in: the reader's first.
    static var language: String { OpenFoodFacts.languages.first ?? "en" }

    @MainActor
    private static func road() throws -> Road {
        let key = Keychain.string(for: Keychain.claudeKey) ?? ""
        if !key.isEmpty { return .claude(ClaudeVision(apiKey: key)) }
        guard CommunityServer.isConfigured else { throw Blocked.needsKey }
        switch AgeAnswer.current {
        case .unknown: throw Blocked.needsAge
        case .under: throw Blocked.underAge
        case .adult: return .bite
        }
    }

    /// Whether an estimate can run for you at all: false under 18 without a key, where search
    /// would only offer something that says no.
    @MainActor
    static var isOpen: Bool {
        if !(Keychain.string(for: Keychain.claudeKey) ?? "").isEmpty { return true }
        return CommunityServer.isConfigured && AgeAnswer.current != .under
    }

    @MainActor
    static func estimate(jpeg: Data, language: String, isLabel: Bool = false) async throws -> MealEstimate {
        switch try road() {
        case .claude(let claude): return try await claude.estimate(jpeg: jpeg, language: language, isLabel: isLabel)
        case .bite: return try await BiteVision().estimate(jpeg: jpeg, language: language, isLabel: isLabel)
        }
    }

    @MainActor
    static func menu(jpeg: Data, language: String) async throws -> MenuScan {
        switch try road() {
        case .claude(let claude): return try await claude.menu(jpeg: jpeg, language: language)
        case .bite: return try await BiteVision().menu(jpeg: jpeg, language: language)
        }
    }

    @MainActor
    static func dish(named name: String, language: String) async throws -> TypicalDish {
        switch try road() {
        case .claude(let claude): return try await claude.dish(named: name, language: language)
        case .bite: return try await BiteVision().dish(named: name, language: language)
        }
    }
}

/// What a failed estimate asks of the screen: a question, a key to fix, or words to show.
enum EstimateTrouble: Equatable {
    /// Bite's own estimates ask once whether you're 18 or over.
    case needsAge
    case underAge
    case needsKey
    case keyRejected
    case failed(String)

    init(_ error: Error) {
        switch error {
        case let blocked as PhotoEstimator.Blocked:
            switch blocked {
            case .needsAge: self = .needsAge
            case .underAge: self = .underAge
            case .needsKey: self = .needsKey
            }
        case let failure as BiteVision.Failure:
            self = .failed(failure.errorDescription ?? String(localized: "Try again."))
        case is TypicalDish.Failure:
            self = .failed(tr("The estimate came back unreadable. Try again."))
        case let failure as ClaudeVision.Failure:
            switch failure {
            case .missingKey: self = .needsKey
            case .badKey: self = .keyRejected
            default: self = .failed(failure.errorDescription ?? String(localized: "Try again."))
            }
        default:
            self = .failed(String(localized: "Check your connection and try again."))
        }
    }
}
