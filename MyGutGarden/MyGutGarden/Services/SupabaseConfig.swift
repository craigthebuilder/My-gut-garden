//
//  SupabaseConfig.swift
//  MyGutGarden, backend connection (SPEC §3).
//
//  TODO(owner): fill `projectRef` and `anonKey` from your Supabase project's
//  API settings. The anon key is a PUBLIC client key, RLS (20260625000002_rls.sql)
//  is what protects data, so it is safe to commit. The service-role key and the
//  Anthropic key NEVER live in the app (SPEC §3); they stay server-side.
//
//  Until filled, the app runs fully offline against bundled fixtures.
//

import Foundation

enum SupabaseConfig {
    /// e.g. "abcdefghijklmnop" → https://abcdefghijklmnop.supabase.co
    static let projectRef = "bdzfjflfkvzxeyojfbkk"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkemZqZmxma3Z6eGV5b2pmYmtrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzOTIxMTMsImV4cCI6MjA5Nzk2ODExM30.bMo7uqEtimBrJ2Ij7oeg-ekrTuBPQlpDGqe6eiN6fPI"

    static var baseURL: URL { URL(string: "https://\(projectRef).supabase.co")! }

    /// When false, AuthService is disabled and RecognitionService uses the
    /// bundled offline fixture so the app still runs end-to-end.
    static var isConfigured: Bool {
        !projectRef.hasPrefix("YOUR_") && !anonKey.hasPrefix("YOUR_")
    }
}
