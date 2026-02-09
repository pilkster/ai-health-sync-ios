//
//  PairingView.swift
//  HealthSync
//
//  QR code pairing view for connecting CLI clients.
//  Generates and displays pairing QR codes with expiring tokens.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

/// Pairing view with QR code generation
struct PairingView: View {
    @Environment(ServiceContainer.self) private var services
    @State private var pairingData: PairingData?
    @State private var qrCodeImage: UIImage?
    @State private var timeRemaining: Int = 0
    @State private var timer: Timer?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let server = services.networkServer, server.state.isRunning {
                    if let qrImage = qrCodeImage {
                        qrCodeSection(qrImage)
                    } else {
                        generateSection
                    }
                } else {
                    serverOfflineSection
                }
                
                instructionsSection
            }
            .padding()
            .navigationTitle("Pairing")
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - QR Code Section
    
    private func qrCodeSection(_ image: UIImage) -> some View {
        VStack(spacing: 16) {
            // QR Code
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 4)
            
            // Expiry countdown
            VStack(spacing: 4) {
                if timeRemaining > 0 {
                    HStack {
                        Image(systemName: "clock")
                        Text("Expires in \(timeRemaining) seconds")
                    }
                    .font(.subheadline)
                    .foregroundColor(timeRemaining < 60 ? .orange : .secondary)
                    
                    ProgressView(value: Double(timeRemaining), total: 300)
                        .tint(timeRemaining < 60 ? .orange : .blue)
                        .frame(width: 200)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("QR code expired")
                            .foregroundColor(.red)
                    }
                    .font(.subheadline)
                }
            }
            
            // Regenerate button
            Button {
                generateNewPairingCode()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Generate New Code")
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Generate Section
    
    private var generateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Generate a QR code to pair your Mac")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("The code will expire after 5 minutes for security.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                generateNewPairingCode()
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Generate Pairing Code")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Server Offline Section
    
    private var serverOfflineSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Server Not Running")
                .font(.headline)
            
            Text("Start the server from the Server tab to generate a pairing code.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Instructions Section
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to pair")
                .font(.headline)
            
            InstructionRow(number: 1, text: "Install the healthsync CLI on your Mac")
            InstructionRow(number: 2, text: "Run: healthsync scan")
            InstructionRow(number: 3, text: "Point your Mac's camera at the QR code")
            InstructionRow(number: 4, text: "The CLI will automatically configure itself")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func generateNewPairingCode() {
        guard let server = services.networkServer,
              let security = services.securityService,
              let firstAddress = server.localAddresses.first else {
            return
        }
        
        // Generate pairing data
        let data = security.generatePairingData(host: firstAddress, port: 8443)
        pairingData = data
        
        // Generate QR code image
        if let qrString = try? data.toQRString() {
            qrCodeImage = generateQRCode(from: qrString)
        }
        
        // Start countdown timer
        timeRemaining = 300 // 5 minutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                qrCodeImage = nil
                pairingData = nil
            }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up the QR code
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

/// Instruction row component
struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    PairingView()
        .environment(ServiceContainer())
}
