import Foundation

// Client for the RUNG competitive backend (rung-api.manticthink.com). The client never
// computes the leaderboard score — it submits the ordered words + timings and the server
// replays the run authoritatively (see server/).

struct BackendAccount: Codable, Equatable {
    let id: String
    let username: String?
    let display: String
    let friendCode: String
    let isAnonymous: Bool
    let currentStreak: Int
    let bestScore: Int
    let lastDay: Int?
}

struct AccountResponse: Codable { let token: String; let expiresAt: Int; let player: BackendAccount }
struct PlayerWrap: Codable { let player: BackendAccount }

struct RunStartResponse: Codable {
    let runId: String
    let runToken: String
    let dayIndex: Int
    let tiles: String
    let alreadyPlayed: Bool
}

struct RunEventDTO: Codable { let word: String; let t_ms: Int }

struct RunResultResponse: Codable {
    let dayIndex: Int
    let finalScore: Int
    let baseSum: Int
    let peakMultiplier: Double
    let wordCount: Int
    let banked: Bool
    let verified: Bool
    let duplicate: Bool
    let rank: Int
    let percentile: Double
    let playerCount: Int
}

struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let id: String
    let username: String?
    let display: String
    let score: Int
    var name: String { username ?? display }
}

struct LeaderboardMe: Codable, Equatable { let score: Int; let rank: Int; let percentile: Double }
struct LeaderboardResponse: Codable, Equatable {
    let scope: String
    let period: String
    let day: Int?
    let entries: [LeaderboardEntry]
    let me: LeaderboardMe?
}

enum BackendError: Error { case network; case server(Int, String); case decode }

final class Backend {
    static let baseURLString = "https://rung-api.manticthink.com"
    private let session = URLSession.shared

    private func send<R: Decodable>(_ path: String, method: String = "GET",
                                    token: String? = nil, bodyData: Data? = nil) async throws -> R {
        guard let url = URL(string: Backend.baseURLString + path) else { throw BackendError.network }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let bodyData {
            req.httpBody = bodyData
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.network }
        guard (200..<300).contains(http.statusCode) else {
            struct E: Decodable { let error: String? }
            let msg = (try? JSONDecoder().decode(E.self, from: data))?.error ?? "http \(http.statusCode)"
            throw BackendError.server(http.statusCode, msg)
        }
        do { return try JSONDecoder().decode(R.self, from: data) }
        catch { throw BackendError.decode }
    }

    private func enc<E: Encodable>(_ v: E) -> Data { (try? JSONEncoder().encode(v)) ?? Data("{}".utf8) }

    func registerAnon(deviceId: String) async throws -> AccountResponse {
        struct B: Encodable { let deviceId: String }
        return try await send("/v1/account", method: "POST", bodyData: enc(B(deviceId: deviceId)))
    }

    func signInApple(identityToken: String, nonce: String, deviceId: String) async throws -> AccountResponse {
        struct B: Encodable { let appleIdentityToken: String; let nonce: String; let deviceId: String }
        return try await send("/v1/account", method: "POST",
                              bodyData: enc(B(appleIdentityToken: identityToken, nonce: nonce, deviceId: deviceId)))
    }

    func runStart(token: String) async throws -> RunStartResponse {
        try await send("/v1/run/start", method: "POST", token: token, bodyData: Data("{}".utf8))
    }

    func submitRun(token: String, runId: String, runToken: String, dayIndex: Int,
                   events: [RunEventDTO], bankT_ms: Int?) async throws -> RunResultResponse {
        struct B: Encodable { let runId: String; let runToken: String; let dayIndex: Int; let events: [RunEventDTO]; let bankT_ms: Int? }
        return try await send("/v1/run", method: "POST", token: token,
                              bodyData: enc(B(runId: runId, runToken: runToken, dayIndex: dayIndex, events: events, bankT_ms: bankT_ms)))
    }

    func leaderboard(period: String, token: String?) async throws -> LeaderboardResponse {
        try await send("/v1/leaderboard?scope=global&period=\(period)", token: token)
    }

    func setUsername(token: String, username: String) async throws -> BackendAccount {
        struct B: Encodable { let username: String }
        let w: PlayerWrap = try await send("/v1/username", method: "PUT", token: token, bodyData: enc(B(username: username)))
        return w.player
    }

    func me(token: String) async throws -> BackendAccount {
        let w: PlayerWrap = try await send("/v1/me", token: token)
        return w.player
    }
}
