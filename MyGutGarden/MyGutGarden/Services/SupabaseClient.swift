//
//  SupabaseClient.swift
//  MyGutGarden, minimal Supabase REST client (GoTrue auth + Edge Functions).
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
    case invalidCredentials
    case accountExists
    case weakPassword(String)
    case emailRejected

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Backend not configured. Add your Supabase project ref and anon key in SupabaseConfig."
        case let .server(status, message):
            return "Request failed (\(status)): \(message)"
        case .emailConfirmationRequired:
            return "Check your email to confirm your account, then sign in."
        case .invalidCredentials:
            return "Incorrect email or password."
        case .accountExists:
            return "There's already an account for this email — use Sign in above (or Sign in with Apple, if that's how it was created)."
        case let .weakPassword(detail):
            return detail.isEmpty ? "That password is too short — use at least 6 characters." : detail
        case .emailRejected:
            return "That email address doesn't look deliverable — double-check it."
        }
    }
}

/// Shared sessions for all Supabase traffic. The default URLSession waits 60 s
/// of idle before failing — against an unreachable or paused backend every
/// surface would hang a full minute per call before its empty state settled
/// (and Today issues ~a dozen reads). Fail fast instead; the LLM-backed
/// function calls legitimately idle while the model works, so they get a
/// patient session.
enum SupabaseHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// For recognize/librarian invocations — the vision/generation call holds
    /// the connection silent for tens of seconds before responding.
    static let longRunning: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
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
        // Function invocations (recognize) idle while the model works — give
        // them the patient session; auth stays fail-fast.
        let session = path.hasPrefix("functions/") ? SupabaseHTTP.longRunning : SupabaseHTTP.session
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SupabaseError.server(status: -1, message: "no HTTP response")
        }
        return (data, http)
    }

    /// GoTrue's machine-readable `error_code` ("user_already_exists", …).
    private func extractErrorCode(_ data: Data) -> String {
        ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_code"] as? String) ?? ""
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
    /// GoTrue's realistic rejections map to actionable copy (owner report,
    /// 2026-07-09: a raw "Request failed (422)" reads as "signup is broken").
    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let (data, http) = try await request(
            path: "auth/v1/signup",
            body: ["email": email, "password": password],
            bearer: anonKey
        )
        guard (200..<300).contains(http.statusCode) else {
            switch extractErrorCode(data) {
            case "user_already_exists", "email_exists":
                throw SupabaseError.accountExists
            case "weak_password":
                throw SupabaseError.weakPassword(extractMessage(data))
            case "email_address_invalid", "email_address_not_authorized":
                throw SupabaseError.emailRejected
            default:
                throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
            }
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
            // GoTrue returns 400 (invalid_grant) for a wrong email/password. Surface
            // a clean, standard message instead of a raw "Request failed (400)".
            if http.statusCode == 400 || http.statusCode == 401 {
                throw SupabaseError.invalidCredentials
            }
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    /// Exchange a refresh token for a fresh session (grant_type=refresh_token).
    /// Used to recover transparently from an expired access token (JWT expired).
    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let (data, http) = try await request(
            path: "auth/v1/token?grant_type=refresh_token",
            body: ["refresh_token": refreshToken],
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

    /// Invoke the `delete-account` Edge Function: removes the caller's photos,
    /// auth user, and (by cascade) every user-table row. App Store 5.1.1(v).
    func deleteAccount(accessToken: String) async throws {
        let (data, http) = try await request(
            path: "functions/v1/delete-account",
            body: [:],
            bearer: accessToken
        )
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(status: http.statusCode, message: extractMessage(data))
        }
    }
}
