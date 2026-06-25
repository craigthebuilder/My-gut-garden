//
//  CapCameraView.swift
//  MyGutGarden — Module B camera capture (AVFoundation).
//
//  Live capture on real hardware; graceful degradation everywhere else (the
//  Simulator has no camera). The capture screen always offers library + sample
//  fallbacks (see CapRootView), so a missing camera is never a dead end.
//
//  NOTE (owner/orchestrator gap): live camera needs `NSCameraUsageDescription`
//  in the app's Info.plist. The project generates its Info.plist
//  (GENERATE_INFOPLIST_FILE = YES) and Module B owns only Capture/, so add
//  `INFOPLIST_KEY_NSCameraUsageDescription` to the target build settings. The
//  library picker (PhotosUI) needs no usage string.
//

import SwiftUI
@preconcurrency import AVFoundation

// MARK: - Capture session controller

@MainActor
final class CapCameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.mygutgarden.capture.session")
    private var continuation: CheckedContinuation<Data, Error>?

    /// Hardware present and wired up. False on the Simulator → UI shows fallbacks.
    private(set) var isAvailable = false
    private var isConfigured = false

    /// Current camera permission. `.authorized` is required to start the session.
    var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Ask for camera access if not yet decided. Safe to call repeatedly.
    func requestAccessIfNeeded() async {
        guard authorization == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Build the input/output graph once. Leaves `isAvailable == false` when no
    /// capture device exists (Simulator) or access is denied.
    @discardableResult
    func configureIfNeeded() -> Bool {
        guard !isConfigured else { return isAvailable }
        guard authorization == .authorized || authorization == .notDetermined else { return false }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            isAvailable = false
            return false
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        isConfigured = true
        isAvailable = true
        return true
    }

    func start() {
        guard isAvailable else { return }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Capture a single still and return its JPEG data.
    func capturePhoto() async throws -> Data {
        guard isAvailable else { throw CapError.captureUnavailable }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if let error {
                self.continuation?.resume(throwing: error)
            } else if let data {
                self.continuation?.resume(returning: data)
            } else {
                self.continuation?.resume(throwing: CapError.captureFailed)
            }
            self.continuation = nil
        }
    }
}

// MARK: - Live preview

/// A thin `UIViewRepresentable` over `AVCaptureVideoPreviewLayer`.
struct CapCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
