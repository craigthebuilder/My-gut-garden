//
//  ContentView.swift
//  MyGutGarden — Phase 0 smoke dashboard.
//
//  Not a product screen — it exists to prove the Phase 0 spine end-to-end:
//  design tokens render from Theme.swift, the theme flips by mode, auth is
//  wired (email + Sign in with Apple), and a snap flows through the recognition
//  contract to joined attributes (offline via fixture, or live via the Edge
//  Function). Phase 1 replaces this with the real surfaces.
//

import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @State private var auth = AuthService()
    @State private var recognizer = RecognitionService()
    @State private var mode: AppMode = .thrive

    var body: some View {
        Dashboard(auth: auth, recognizer: recognizer, mode: $mode)
            .themed(for: mode)
    }
}

private struct Dashboard: View {
    @Environment(\.theme) private var theme
    let auth: AuthService
    let recognizer: RecognitionService
    @Binding var mode: AppMode

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                header
                modePicker
                tokenSample
                authCard
                recognitionCard
            }
            .padding(theme.metrics.space5)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("My Gut Garden")
                .font(theme.typography.display())
                .foregroundStyle(theme.colors.textPrimary)
            Text(mode == .thrive ? "Thrive — feed the invisible garden" : "Survive — symptoms in, insights out")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Text("Thrive").tag(AppMode.thrive)
            Text("Survive").tag(AppMode.survive)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Token sample (proves tokens render + flip by mode)

    private var tokenSample: some View {
        SmokeCard(theme: theme) {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("27 / 30 plants")
                    .font(theme.typography.data(28))
                    .foregroundStyle(theme.colors.primary)
                Text("3 to go before Sunday resets")
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
                HStack(spacing: theme.metrics.space2) {
                    swatch(theme.colors.primary)
                    swatch(theme.colors.secondary)
                    swatch(theme.colors.accent)
                }
            }
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: theme.metrics.radiusSmall)
            .fill(color)
            .frame(width: 36, height: 24)
    }

    // MARK: Auth

    private var authCard: some View {
        SmokeCard(theme: theme) {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("Account")
                    .font(theme.typography.title())
                    .foregroundStyle(theme.colors.textPrimary)

                if !auth.isConfigured {
                    Text("Running offline. Add your project ref + anon key in SupabaseConfig to enable accounts and the live pipeline.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                } else if let user = auth.user {
                    Text("Signed in as \(user.email ?? user.id)")
                        .font(theme.typography.body())
                        .foregroundStyle(theme.colors.textPrimary)
                    Button("Sign out") { auth.signOut() }
                        .foregroundStyle(theme.colors.primary)
                } else {
                    emailFields
                    HStack(spacing: theme.metrics.space3) {
                        Button("Sign in") {
                            Task { await auth.signIn(email: email, password: password) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Sign up") {
                            Task { await auth.signUp(email: email, password: password) }
                        }
                    }
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await auth.handleAppleCompletion(result) }
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusSmall))
                }

                if auth.isBusy { ProgressView() }
                if let error = auth.errorMessage {
                    Text(error)
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.error)
                }
            }
        }
    }

    private var emailFields: some View {
        VStack(spacing: theme.metrics.space2) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
        }
        .textFieldStyle(.roundedBorder)
    }

    // MARK: Recognition

    private var recognitionCard: some View {
        SmokeCard(theme: theme) {
            VStack(alignment: .leading, spacing: theme.metrics.space3) {
                Text("Snap a meal")
                    .font(theme.typography.title())
                    .foregroundStyle(theme.colors.textPrimary)
                Button {
                    Task { await recognizer.recognize(mode: mode, auth: auth) }
                } label: {
                    Label("Run recognition", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)

                if recognizer.isBusy { ProgressView() }
                if let error = recognizer.errorMessage {
                    Text(error).font(theme.typography.caption()).foregroundStyle(theme.colors.error)
                }
                if let response = recognizer.lastResponse {
                    insights(for: response)
                }
            }
        }
    }

    @ViewBuilder
    private func insights(for response: RecognitionResponse) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.space3) {
            // Allergy alerts are LOUD across both modes (SPEC §9).
            ForEach(response.allergyAlerts, id: \.foodName) { alert in
                Label("Contains \(alert.foodName) — flagged allergy", systemImage: "exclamationmark.triangle.fill")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.error)
            }

            if mode == .thrive {
                let t = FoodAttributeJoin.thriveInsights(response)
                line("Plants", "\(t.plantNames.count) — \(t.plantNames.joined(separator: ", "))")
                line("Rainbow", t.colorsHit.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))
                line("3 P's", "\(t.threePs.count)/3" + (t.threePs.allThree ? " ✓" : ""))
                line("Guilds fed", t.guildsFed.map(\.displayName).joined(separator: ", "))
            } else {
                let s = FoodAttributeJoin.surviveInsights(response)
                Text("FODMAP safety")
                    .font(theme.typography.body(weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                ForEach(s.safety, id: \.foodName) { entry in
                    HStack(spacing: theme.metrics.space2) {
                        Circle().fill(safetyColor(entry.safety)).frame(width: 12, height: 12)
                        Text("\(entry.foodName): \(entry.safety.rawValue)")  // label + shape, not color alone
                            .font(theme.typography.body())
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                }
            }

            // Hidden-ingredient prompts — "when unsure, flag it" (SPEC §4).
            ForEach(response.hiddenIngredientPrompts) { prompt in
                Text(prompt.prompt)
                    .font(theme.typography.caption())
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: theme.metrics.space2) {
            Text(label)
                .font(theme.typography.caption(weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textPrimary)
        }
    }

    private func safetyColor(_ safety: FodmapSafety) -> Color {
        switch safety {
        case .green: theme.colors.safetyGreen
        case .yellow: theme.colors.safetyYellow
        case .red: theme.colors.safetyRed
        }
    }
}

/// Themed surface card for the smoke screen (replaced by DesignSystem.Card at
/// consolidation). Renamed to avoid colliding with the shared `Card`.
private struct SmokeCard<Content: View>: View {
    let theme: any Theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.metrics.space4)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium))
            .shadow(color: .black.opacity(theme.metrics.shadowOpacity),
                    radius: theme.metrics.shadowRadius, y: 4)
    }
}

#Preview {
    ContentView()
}
