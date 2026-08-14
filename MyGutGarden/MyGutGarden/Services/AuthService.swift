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
    private(set) var session: SupabaseSession? {
        didSet {
            if let session { SessionStore.save(session) } else { SessionStore.clear() }
        }
    }
    private(set) var isBusy = false
    var errorMessage: String?

    private var currentNonce: String?
    /// True only when the session came from the keychain this process — the
    /// one case where the access token predates the launch and needs an
    /// up-front refresh. A fresh sign-in's token is already new.
    private var needsLaunchRefresh = false

    init() {
        // Restore the persisted session so a cold launch lands signed-in.
        session = SessionStore.load()
        needsLaunchRefresh = session != nil
    }

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
        ProfileCache.clear()
    }

    /// Called once from the shell's launch task. A restored access token is
    /// usually expired, so mint a fresh one up front; a dead refresh token
    /// (revoked, account gone) drops to the sign-in gate, while a network
    /// failure keeps the stored session — Repository's 401→refresh path
    /// recovers the moment the backend is reachable again.
    func restoreOnLaunch() async {
        guard needsLaunchRefresh else { return }
        needsLaunchRefresh = false
        guard let client, let refresh = session?.refreshToken, !refresh.isEmpty else { return }
        do {
            session = try await client.refreshSession(refreshToken: refresh)
        } catch let SupabaseError.server(status, _) where status == 400 || status == 401 {
            session = nil
        } catch {
            // Offline or backend hiccup — keep the session, stay signed in.
        }
    }

    /// Full account deletion (App Store 5.1.1(v)) — calls the delete-account
    /// Edge Function (photos + auth user + cascaded rows), then signs out
    /// locally. Throws so the confirm UI can show what went wrong.
    func deleteAccount() async throws {
        guard let client, let token = session?.accessToken else {
            throw SupabaseError.notConfigured
        }
        isBusy = true
        defer { isBusy = false }
        try await client.deleteAccount(accessToken: token)
        session = nil
        errorMessage = nil
        ProfileCache.clear()
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
