//
//  SupabaseClient.swift
//  MyGutGarden — minimal Supabase REST client (GoTrue auth + Edge Functions).
//
//  Phase-0 deliberately avoids an SPM dependency so the project builds from the
//  file-system-synchronized group with zero package setup. Phase 1 can swap in
//  supabase-swift if richer features are needed; the call sites here are small.
//

import Foundation

struct SupabaseUser: Codable, Sendable {
    let id: String
    let email: String?
}

// Field names map via the decoder's `.convertFromSnakeCase` strategy
// (access_token → accessToken). Do NOT add explicit snake_case CodingKeys here:
// combined with that strategy the key is transformed twice and never matches.
struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let user: SupabaseUser?
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case server(status: Int, message: String)
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Backend not configured. Add your Supabase project ref and anon key in SupabaseConfig."
        case let .server(status, message):
            return "Request failed (\(status)): \(message)"
        case .emailConfirmationRequired:
            return "Check your email to confirm your account, then sign in."
        }
    }
}

struct SupabaseClient {
    let baseURL: URL
    let anonKey: String

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func request(path: String, body: [String: Any], bearer: String) async throws -> (Data, HTTPURLResponse) {
        // String-concatenate (not appendingPathComponent, which would percent-
        // encode the "?" in "...token?grant_type=password" → a 404).
        guard let url = URL(string: baseURL.absoluteString + "/" + path) else {
            throw SupabaseError.server(status: -1, message: "bad URL for \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SupabaseError.server(status: -1, message: "no HTTP response")
        }
        return (data, http)
    }

    private func extractMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error"] {
                if let v = obj[key] as? String { return v }
            }
        }
        return String(data: data, encoding: .utf8) ?? "unknown error"
    }

    // MARK: - Auth (GoTrue)

    /// Email + password sign up. Returns a session, or throws
    /// `.emailConfirmationRequired` when the project requires confirmation.
    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let (data, http) = try await request(
            path: "auth/v1/signup",
            body: ["email": email, "password": password],
            bearer: anonKey
        )
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
        if let session = try? decoder.decode(SupabaseSession.self, from: data),
           !session.accessToken.isEmpty {
            return session
        }
        throw SupabaseError.emailConfirmationRequired
    }

    /// Email + password sign in (grant_type=password).
    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let (data, http) = try await request(
            path: "auth/v1/token?grant_type=password",
            body: ["email": email, "password": password],
            bearer: anonKey
        )
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    /// Sign in with Apple via the identity token (grant_type=id_token).
    func signInWithApple(idToken: String, nonce: String?) async throws -> SupabaseSession {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let (data, http) = try await request(
            path: "auth/v1/token?grant_type=id_token",
            body: body,
            bearer: anonKey
        )
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    // MARK: - Edge Functions

    /// Invoke the `recognize` Edge Function (SPEC §4 pipeline).
    func invokeRecognize(body: [String: Any], accessToken: String) async throws -> RecognitionResponse {
        let (data, http) = try await request(
            path: "functions/v1/recognize",
            body: body,
            bearer: accessToken
        )
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
        return try decoder.decode(RecognitionResponse.self, from: data)
    }
}
