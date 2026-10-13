import Foundation

/// Where shared estimates live: a Supabase project (in Zurich). Empty until the project exists,
/// and while it is, nothing about sharing shows: dishes stay on this phone. `server/README.md`
/// says how to set it up.
enum CommunityServer {
    /// "https://<project>.supabase.co"
    static let url: URL? = nil
    /// The project's publishable (anon) key. Public by design: the database enforces every rule.
    static let anonKey = ""
    /// The community rules people accept before sharing, a short web page.
    static let rulesURL: URL? = nil

    static var isConfigured: Bool { url != nil && !anonKey.isEmpty }
}

/// A signed-in session on the community server.
struct CommunitySession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userID: String
    var expiresAt: Date
}

/// The community server over plain HTTPS: sign-in, the database functions, and the two
/// server functions for Apple's token and account deletion.
struct CommunityClient {
    enum Failure: Error, Equatable {
        case notConfigured
        case refused(Int, String?)
        case unreadable
    }

    var session: URLSession = .shared

    // MARK: Sign-in

    /// Trades Apple's identity token for a session on the server.
    func signIn(idToken: String, nonce: String) async throws -> CommunitySession {
        try await token(query: "grant_type=id_token", body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
    }

    func refresh(_ refreshToken: String) async throws -> CommunitySession {
        try await token(query: "grant_type=refresh_token", body: ["refresh_token": refreshToken])
    }

    private func token(query: String, body: [String: String]) async throws -> CommunitySession {
        struct Answer: Decodable {
            struct User: Decodable { let id: String }
            let accessToken: String
            let refreshToken: String
            let expiresIn: Double
            let user: User
        }
        let data = try await send(path: "auth/v1/token?\(query)", token: nil, body: try JSONEncoder().encode(body))
        guard let answer = try? CommunityRemote.decoder.decode(Answer.self, from: data) else { throw Failure.unreadable }
        return CommunitySession(
            accessToken: answer.accessToken,
            refreshToken: answer.refreshToken,
            userID: answer.user.id,
            expiresAt: Date.now.addingTimeInterval(answer.expiresIn)
        )
    }

    /// Your name as people see it, and that you accepted the rules. The server takes who you are
    /// from the token, never from what the app sends.
    func saveProfile(name: String, token: String) async throws {
        _ = try await send(path: "rest/v1/rpc/save_profile", token: token, body: try JSONEncoder().encode(["p_name": name]))
    }

    /// Apple's one-time code, kept by the server so deleting the account can revoke it.
    func sendAppleCode(_ code: String, token: String) async throws {
        _ = try await send(path: "functions/v1/apple-token", token: token, body: try JSONEncoder().encode(["code": code]))
    }

    func deleteAccount(token: String) async throws {
        _ = try await send(path: "functions/v1/delete-account", token: token, body: Data("{}".utf8))
    }

    // MARK: Dishes

    func share(_ share: CommunityRemote.Share, token: String) async throws -> CommunityRemote.Shared {
        let data = try await send(path: "rest/v1/rpc/share_estimate", token: token, body: try CommunityRemote.encoder.encode(share))
        guard let shared = try? CommunityRemote.decoder.decode(CommunityRemote.Shared.self, from: data) else { throw Failure.unreadable }
        return shared
    }

    /// Dishes near a point; signed out, everyone's visible ones.
    func dishesNear(latitude: Double, longitude: Double, radius: Int = 3000, token: String?) async throws -> [CommunityRemote.Dish] {
        let body: [String: Double] = ["p_latitude": latitude, "p_longitude": longitude, "p_radius": Double(radius)]
        let data = try await send(path: "rest/v1/rpc/dishes_near", token: token, body: try JSONEncoder().encode(body))
        guard let dishes = try? CommunityRemote.dishes(from: data) else { throw Failure.unreadable }
        return dishes
    }

    func setAgree(estimateID: String, agree: Bool, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["p_estimate": estimateID, "p_agree": agree])
        _ = try await send(path: "rest/v1/rpc/set_agree", token: token, body: body)
    }

    func rate(dishID: String, stars: Int?, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["p_dish": dishID, "p_stars": stars.map { $0 as Any } ?? NSNull()])
        _ = try await send(path: "rest/v1/rpc/rate_dish", token: token, body: body)
    }

    func report(dishID: String?, estimateID: String?, reason: String, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_dish": dishID.map { $0 as Any } ?? NSNull(),
            "p_estimate": estimateID.map { $0 as Any } ?? NSNull(),
            "p_reason": reason,
        ])
        _ = try await send(path: "rest/v1/rpc/report_content", token: token, body: body)
    }

    func hide(authorID: String, token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["p_author": authorID])
        _ = try await send(path: "rest/v1/rpc/hide_author", token: token, body: body)
    }

    // MARK: Requests

    private func send(path: String, token: String?, body: Data, headers: [String: String] = [:]) async throws -> Data {
        guard CommunityServer.isConfigured, let base = CommunityServer.url,
              let url = URL(string: path, relativeTo: base.appending(path: "/")) else { throw Failure.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CommunityServer.anonKey, forHTTPHeaderField: "apikey")
        // Only a signed-in person's token goes here: a publishable key is not a token, and
        // without one the server treats the request as a visitor's.
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.refused(status, String(data: data.prefix(300), encoding: .utf8))
        }
        return data
    }
}
