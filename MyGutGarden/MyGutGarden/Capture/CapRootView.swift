//
//  CapRootView.swift
//  MyGutGarden, Module B public entry point (SPEC §4, §11).
//
//  The snap flow: capture a meal (camera / library / sample) → recognize →
//  review & confirm → hand off to the mode-specific insight view. Composes the
//  shared DesignSystem and reads tokens from `@Environment(\.theme)` only, no
//  restyling, no hardcoded values (CLAUDE.md rule #5). The AppShell injects
//  `AppState`, the `RecognitionService`, the active theme, and the
//  `mealInsightPresenter`; Module B never imports C/E.
//

import SwiftUI
import PhotosUI

struct CapRootView: View {
    @Environment(\.theme) private var theme
    @Environment(\.mealInsightPresenter) private var insightPresenter
    // Food-status seams (default no-ops in Seams.swift / CapModels.swift). The
    // lead injects the real impls (Module E) in AppShell; Module B never imports E.
    @Environment(\.suspectCheckService) private var suspectCheckService
    @Environment(\.reintroFeelingAttacher) private var reintroFeelingAttacher
    @Environment(\.capReintroFeelingRecorder) private var capReintroFeelingRecorder

    @State private var model: CapCaptureModel
    @State private var camera = CapCameraController()

    init(appState: AppState, recognizer: RecognitionService) {
        _model = State(initialValue: CapCaptureModel(appState: appState, recognizer: recognizer))
    }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            content
        }
        .animation(.default, value: model.phase)
        .onAppear {
            model.configure(suspectCheck: suspectCheckService,
                            reintroAttacher: reintroFeelingAttacher,
                            reintroRecorder: capReintroFeelingRecorder)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .capture:
            CapCaptureScreen(model: model, camera: camera)
        case .preview:
            CapPreviewScreen(model: model)
        case .recognizing:
            CapRecognizingScreen()
        case .confirmed:
            CapResultScreen(model: model, presenter: insightPresenter)
        }
    }
}

// MARK: - Capture screen

private struct CapCaptureScreen: View {
    @Environment(\.theme) private var theme
    let model: CapCaptureModel
    let camera: CapCameraController

    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraAvailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.space5) {
                header
                cameraSurface
                fallbacks
                if let error = model.errorText { errorNote(error) }
            }
            .padding(theme.metrics.space5)
        }
        .task {
            await camera.requestAccessIfNeeded()
            cameraAvailable = camera.configureIfNeeded()
            camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.metrics.space2) {
            Text("Snap a meal")
                .font(theme.typography.display())
                .foregroundStyle(theme.colors.textPrimary)
            Text(model.mode == .thrive
                 ? "See what you're feeding, plants, colours, and the crews they grow."
                 : "Check a meal for FODMAP triggers before it's on your plate.")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cameraSurface: some View {
        Card {
            VStack(spacing: theme.metrics.space3) {
                ZStack {
                    if cameraAvailable {
                        CapCameraPreview(session: camera.session)
                    } else {
                        IllustrationPlaceholder(systemImage: "camera.fill")
                    }
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
                .accessibilityLabel(cameraAvailable ? "Camera preview" : "Camera unavailable")

                if cameraAvailable {
                    PrimaryButton(title: "Take photo", systemImage: "camera.fill") {
                        Task {
                            if let data = try? await camera.capturePhoto() {
                                model.stage(imageData: data)
                            }
                        }
                    }
                } else {
                    Text("No camera here, pick a photo or try the sample meal below.")
                        .font(theme.typography.caption())
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var fallbacks: some View {
        VStack(spacing: theme.metrics.space3) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                pickerLabel
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        model.stage(imageData: data)
                    }
                    pickerItem = nil
                }
            }

            SecondaryButton(title: "Use a sample meal", systemImage: "sparkles") {
                model.useSampleMeal()
            }
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: theme.metrics.space2) {
            Image(systemName: "photo.on.rectangle")
            Text("Choose from library").font(theme.typography.body(weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.metrics.space3)
        .foregroundStyle(theme.colors.primary)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous)
                .strokeBorder(theme.colors.primary.opacity(0.4), lineWidth: 1)
        )
    }

    private func errorNote(_ text: String) -> some View {
        Text(text)
            .font(theme.typography.caption())
            .foregroundStyle(theme.colors.error)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Recognizing (in-flight)

private struct CapRecognizingScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.metrics.space4) {
            ProgressView()
            Text("Reading your plate…")
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recognising your meal")
    }
}
