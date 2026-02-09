//
//  QRScanner.swift
//  HealthSyncCLI
//
//  QR code scanner using AVFoundation for pairing.
//  Opens a camera window to scan the QR code from the iOS app.
//

import Foundation
import AVFoundation
import AppKit
import CoreImage

/// QR code scanner for pairing
final class QRScanner: NSObject, @unchecked Sendable {
    /// Capture session
    private var captureSession: AVCaptureSession?
    
    /// Preview layer
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Window for camera preview
    private var window: NSWindow?
    
    /// Completion handler
    private var completion: ((PairingData?) -> Void)?
    
    /// Whether scanning is complete
    private var isComplete = false
    
    /// Scan a QR code using the camera
    /// - Returns: Pairing data if successful
    func scan() async throws -> PairingData? {
        // Check for camera permission
        let authorized = await requestCameraPermission()
        guard authorized else {
            throw ScanError.cameraNotAuthorized
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                self?.startScanning { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    /// Request camera access permission
    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    /// Start the camera scanning session
    private func startScanning(completion: @escaping (PairingData?) -> Void) {
        self.completion = completion
        
        // Create capture session
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Get camera device
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("❌ No camera available")
            completion(nil)
            return
        }
        
        // Create input
        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            print("❌ Failed to create camera input")
            completion(nil)
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Create metadata output for QR codes
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        
        self.captureSession = session
        
        // Create preview window
        createPreviewWindow(with: session)
        
        // Start capture
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    /// Create a window to show the camera preview
    private func createPreviewWindow(with session: AVCaptureSession) {
        let windowRect = NSRect(x: 0, y: 0, width: 400, height: 400)
        
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Scan QR Code"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Create preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        
        let contentView = NSView(frame: windowRect)
        contentView.wantsLayer = true
        contentView.layer?.addSublayer(previewLayer)
        
        // Add instruction label
        let label = NSTextField(labelWithString: "Point camera at QR code\nPress Escape to cancel")
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 10, width: 400, height: 40)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        label.drawsBackground = true
        contentView.addSubview(label)
        
        window.contentView = contentView
        self.previewLayer = previewLayer
        self.window = window
        
        // Handle window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.stopScanning()
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Stop scanning and close window
    private func stopScanning() {
        guard !isComplete else { return }
        isComplete = true
        
        captureSession?.stopRunning()
        captureSession = nil
        
        window?.close()
        window = nil
        
        completion?(nil)
    }
    
    /// Handle successful QR code scan
    private func handleScannedCode(_ code: String) {
        guard !isComplete else { return }
        isComplete = true
        
        captureSession?.stopRunning()
        captureSession = nil
        
        window?.close()
        window = nil
        
        // Parse the QR code data
        guard let data = code.data(using: .utf8) else {
            completion?(nil)
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let pairingData = try decoder.decode(PairingData.self, from: data)
            completion?(pairingData)
        } catch {
            print("❌ Failed to parse QR code: \(error)")
            completion?(nil)
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension QRScanner: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let stringValue = object.stringValue else {
            return
        }
        
        // Play a sound to indicate success
        NSSound.beep()
        
        handleScannedCode(stringValue)
    }
}

/// Scan errors
enum ScanError: LocalizedError {
    case cameraNotAuthorized
    case cameraNotAvailable
    case scanFailed
    
    var errorDescription: String? {
        switch self {
        case .cameraNotAuthorized:
            return "Camera access not authorized. Grant permission in System Preferences."
        case .cameraNotAvailable:
            return "No camera available on this Mac."
        case .scanFailed:
            return "Failed to scan QR code."
        }
    }
}
