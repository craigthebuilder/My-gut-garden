//
//  AuthService.swift
//  MyGutGarden, auth state (SPEC §3: accounts required, email + Sign in with Apple).
//
//  Cloud-synced accounts so progress survives device changes. Holds the live
//  Supabase session; the access token is passed to the recognize Edge Function.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Observation

@MainActor
@Observable
final class AuthService {
    private(set) var session: SupabaseSession?
    private(set) var isBusy = false
    var errorMessage: String?

    private var currentNonce: String?

    var isConfigured: Bool { SupabaseConfig.isConfigured }
    var user: SupabaseUser? { session?.user }
    var isSignedIn: Bool { session?.accessToken.isEmpty == false }

    private var client: SupabaseClient? {
        guard isConfigured else { return nil }
        return SupabaseClient(baseURL: SupabaseConfig.baseURL, anonKey: SupabaseConfig.anonKey)
    }

    // MARK: - Email

    func signUp(email: String, password: String) async {
        // Guard empty credentials CLIENT-side: an empty email+password POST is
        // read by GoTrue as an anonymous sign-up, surfacing the confusing
        // "Anonymous sign-ins are disabled" 422 (owner report, 2026-07-10).
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { errorMessage = "Enter your email to create an account."; return }
        guard !password.isEmpty else { errorMessage = "Choose a password (at least 6 characters)."; return }
        await run {
            guard let client = self.client else { throw SupabaseError.notConfigured }
            self.session = try await client.signUp(email: e, password: password)
        }
    }

    func signIn(email: String, password: String) async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."; return
        }
        await run {
            guard let client = self.client else { throw SupabaseError.notConfigured }
            self.session = try await client.signIn(email: e, password: password)
        }
    }

    func signOut() {
        session = nil
        errorMessage = nil
    }

    /// Exchange the stored refresh token for a fresh access token. Returns the
    /// new access token on success, or nil if refresh is unavailable/failed (the
    /// caller then lets the original 401 propagate). Updates the live session so
    /// every subsequently-built Repository carries the fresh token.
    @discardableResult
    func refreshSession() async -> String? {
        guard let client, let refresh = session?.refreshToken, !refresh.isEmpty else { return nil }
        do {
            let renewed = try await client.refreshSession(refreshToken: refresh)
            self.session = renewed
            return renewed.accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Sign in with Apple

    /// Wire to `SignInWithAppleButton(onRequest:)`.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Wire to `SignInWithAppleButton(onCompletion:)`.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        await run {
            switch result {
            case let .failure(error):
                throw error
            case let .success(auth):
                guard
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    throw SupabaseError.server(status: -1, message: "missing Apple identity token")
                }
                guard let client = self.client else { throw SupabaseError.notConfigured }
                self.session = try await client.signInWithApple(idToken: idToken, nonce: self.currentNonce)
            }
        }
    }

    // MARK: - Helpers

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
