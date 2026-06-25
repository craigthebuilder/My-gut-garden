//
//  AuthService.swift
//  MyGutGarden — auth state (SPEC §3: accounts required, email + Sign in with Apple).
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
        await run {
            guard let client = self.client else { throw SupabaseError.notConfigured }
            self.session = try await client.signUp(email: email, password: password)
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            guard let client = self.client else { throw SupabaseError.notConfigured }
            self.session = try await client.signIn(email: email, password: password)
        }
    }

    func signOut() {
        session = nil
        errorMessage = nil
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
