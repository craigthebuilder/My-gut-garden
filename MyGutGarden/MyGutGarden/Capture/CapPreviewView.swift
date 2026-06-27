//
//  CapPreviewView.swift
//  MyGutGarden, Module B accept/retake/annotate preview (SPEC §4, Batch C).
//
//  After the user snaps (or picks the sample), the photo is shown full-bleed with
//  a top-left ✕ (retake) and a top-right ✓ (accept → analysis). Tapping the photo
//  opens a snapchat-style caption bar so the user can name foods the camera can't
//  see ("more onion not pictured", "ketchup under the bun"). That note is written
//  to `model.userAnnotation` and PROACTIVELY drives the recognition: it feeds a
//  second, text-only structured call server-side that returns only food IDs +
//  coarse tiers (never numbers, rule #2). Tokens only; no em dashes (rule #5).
//

import SwiftUI
import UIKit

struct CapPreviewScreen: View {
    @Environment(\.theme) private var theme
    @Bindable var model: CapCaptureModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            photo
            controls
        }
        // Tapping anywhere on the photo opens the caption bar.
        .contentShape(Rectangle())
        .onTapGesture { noteFocused = true }
    }

    @ViewBuilder
    private var photo: some View {
        if let data = model.stagedImage, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .accessibilityLabel("Your meal photo")
        } else {
            // Sample-meal / no-photo path still gets the accept/retake/annotate step.
            VStack(spacing: theme.metrics.space3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.colors.surface.opacity(0.85))
                Text("Sample meal")
                    .font(theme.typography.body(weight: .medium))
                    .foregroundStyle(theme.colors.surface.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Sample meal, no photo")
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            CapAnnotationOverlay(note: $model.userAnnotation, focused: $noteFocused)
        }
        .padding(theme.metrics.space4)
    }

    private var topBar: some View {
        HStack {
            circleButton(systemImage: "xmark", label: "Retake") { model.retake() }
            Spacer()
            circleButton(systemImage: "checkmark", label: "Use this photo") {
                noteFocused = false
                Task { await model.accept() }
            }
        }
    }

    private func circleButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.colors.surface)
                // Scrim disc over the photo, matching the design system's
                // black-scrim convention (DesignSystem/Overlays.swift).
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Snapchat-style caption bar

/// A single free-text line layered over the photo. Empty + unfocused shows an
/// inviting hint; the text drives the annotation re-prompt on accept.
struct CapAnnotationOverlay: View {
    @Environment(\.theme) private var theme
    @Binding var note: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: theme.metrics.space2) {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(theme.colors.primary)
            TextField("Add a note (e.g. extra onion not pictured)", text: $note, axis: .vertical)
                .focused(focused)
                .font(theme.typography.body())
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1...3)
                .submitLabel(.done)
            if !note.isEmpty {
                Button { note = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .accessibilityLabel("Clear note")
            }
        }
        .padding(theme.metrics.space3)
        .background(theme.colors.surface.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: theme.metrics.radiusMedium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Name any foods the camera cannot see; it sharpens the analysis.")
    }
}
