import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation
import VisionKit

struct QRCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(BranchService.self) private var branchService
    
    @State private var selectedTab = 0 // 0: Your QR, 1: Scan QR, 2: Copy Link
    @State private var inviteLink: String?
    @State private var isGeneratingLink = false
    @State private var showingScanner = false
    @State private var showCopiedMessage = false
    @State private var scannedCode: String?
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Simple in-memory cache for invite links (valid for 5 minutes)
    @State private var cachedInviteLink: String?
    @State private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 0) {
                customHeader
                tabView
            }
        }
        .onAppear {
            loadInviteLink()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var customHeader: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text("add friends")
                .jtStyle(.title2)
                .fontWeight(.thin)
                .foregroundColor(.white)
            
            Spacer()
            
            // Invisible button for balance
            Button(action: {}) {
                Image(systemName: "chevron.left")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                    .foregroundColor(.clear)
                    .frame(width: 44, height: 44)
            }
            .disabled(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var tabView: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                QRTabButton(title: "your qr", icon: "qrcode", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                
                QRTabButton(title: "scan qr", icon: "camera.viewfinder", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                
                QRTabButton(title: "copy link", icon: "link", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Content
            TabView(selection: $selectedTab) {
                yourQRContent
                    .tag(0)
                
                scanQRContent
                    .tag(1)
                
                copyLinkContent
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
    }
    
    private var yourQRContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("share your qr code")
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.top, 32)
                
                if isGeneratingLink {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("making your qr code...")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(width: 250, height: 250)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                } else if let link = inviteLink {
                    VStack(spacing: 16) {
                        generateQRCode(from: link)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        
                        Text("others can scan this to add you")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.custom("EBGaramond-Regular", size: 40))
                            .foregroundColor(.orange)
                        Text("couldn't make qr code")
                            .jtStyle(.body)
                            .fontWeight(.medium)
                        Button(action: { loadInviteLink() }) {
                            Text("TRY AGAIN").jtStyle(.caption).fontWeight(.medium).foregroundColor(.blue)
                        }
                    }
                    .frame(width: 250, height: 250)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var scanQRContent: some View {
        VStack(spacing: 24) {
            Text("scan qr code")
                .jtStyle(.title3)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.top, 32)
            
            Text("scan someone's qr code to add them")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                checkCameraPermissionAndScan()
            }) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.custom("EBGaramond-Regular", size: 60))
                        .foregroundColor(.white)
                    
                    Text("open camera")
                        .jtStyle(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .frame(width: 200, height: 200)
                .background(Color.white.opacity(0.08))
                .cornerRadius(20)
            }
            
            if let scanned = scannedCode {
                Text(scanned)
                    .jtStyle(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 16)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingScanner) {
            QRCodeScannerView { code in
                handleScannedCode(code)
            }
        }
    }
    
    private var copyLinkContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("share your link")
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.top, 32)
                
                if isGeneratingLink {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("making your invite link...")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
                } else if let link = inviteLink {
                    VStack(spacing: 16) {
                        Text("your invite link")
                            .jtStyle(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            Text(link)
                                .jtStyle(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button(action: {
                                UIPasteboard.general.string = link
                                withAnimation {
                                    showCopiedMessage = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showCopiedMessage = false
                                    }
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        
                        if showCopiedMessage {
                            Text("copied!")
                                .jtStyle(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                        
                        Button(action: { shareInviteLink(link) }) {
                            Text("SHARE LINK").jtStyle(.caption).fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(12)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.custom("EBGaramond-Regular", size: 40))
                            .foregroundColor(.orange)
                        Text("couldn't make invite link")
                            .jtStyle(.body)
                            .fontWeight(.medium)
                        Button(action: { loadInviteLink() }) {
                            Text("TRY AGAIN").jtStyle(.caption).fontWeight(.medium).foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadInviteLink() {
        // Check cache first
        if let cached = cachedInviteLink,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            inviteLink = cached
            return
        }
        
        // Generate new link if no cache or expired
        generateInviteLink()
    }
    
    private func generateInviteLink() {
        guard let user = authManager.currentUser else { return }
        
        isGeneratingLink = true
        
        Task {
            do {
                let inviteLinkResponse = try await branchService.generateInviteLink(for: user)
                
                await MainActor.run {
                    inviteLink = inviteLinkResponse.url
                    cachedInviteLink = inviteLinkResponse.url
                    cacheTimestamp = Date()
                    isGeneratingLink = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingLink = false
                    errorMessage = "Failed to generate invite link: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func generateQRCode(from string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return Image(uiImage: UIImage(cgImage: cgimg))
            }
        }
        
        return Image(systemName: "xmark.circle")
    }
    
    private func checkCameraPermissionAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingScanner = true
                    } else {
                        errorMessage = "Camera access is required to scan QR codes"
                        showError = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Camera access is required to scan QR codes. Please enable it in Settings."
            showError = true
        @unknown default:
            errorMessage = "Camera access is required to scan QR codes"
            showError = true
        }
    }
    
    private func handleScannedCode(_ code: String) {
        scannedCode = code
        showingScanner = false
        
        // Process the scanned invite link
        if code.contains("jointally.app.link") || code.contains("tally.app") || code.contains("jointally.app") {
            // This is likely a Tally invite link - process it
            processInviteLink(code)
        } else {
            errorMessage = "This QR code doesn't appear to be a Tally invite link"
            showError = true
        }
    }
    
    private func processInviteLink(_ link: String) {
        print("🔍 [QRCodeView] Processing invite link: \(link)")
        
        // Use BranchService to handle the scanned link
        let handled = branchService.handleScannedBranchLink(link)
        
        if handled {
            print("✅ [QRCodeView] Branch successfully handled the invite link")
            
            // Show success message and dismiss after a brief delay
            scannedCode = "Invite processed successfully!"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss()
            }
        } else {
            print("❌ [QRCodeView] Branch failed to handle the invite link")
            errorMessage = "Failed to process invite link. Please try again."
            showError = true
        }
    }
    
    private func shareInviteLink(_ link: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        let inviterName = authManager.currentUser?.name ?? "a friend"
        
        // Generate a fun, random share blurb
        let templates: [String] = [
            "yo! \(inviterName) wants you on tally – tap the link and let's grow together 👉 \(link)",
            "🌱 \(inviterName) is building better habits on tally. join in here: \(link)",
            "join me (\(inviterName)) on tally to level-up our habits 💪 \(link)",
            "hey, it's \(inviterName)! come vibe on tally and keep each other accountable: \(link)",
            "quick! \(inviterName) challenged you to a habit streak on tally ✨ \(link)",
            "🥀 \(inviterName) thinks your habits suck – let's revive them on tally: \(link)"
        ]
        
        let message = templates.randomElement() ?? "join me on tally: \(link)"
        
        let activityViewController = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        
        // For iPad popover anchoring
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Present from the top-most VC to avoid double-presentation errors
        if let topVC = topMostViewController(from: window.rootViewController) {
            // Avoid presenting if something else is already being shown
            guard topVC.presentedViewController == nil else { return }
            topVC.present(activityViewController, animated: true)
        }
    }
    
    // Recursively find the top-most presented view controller
    private func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

// MARK: - Tab Button Component

struct QRTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.medium)
                Text(title)
                    .jtStyle(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
    }
}

// MARK: - QR Code Scanner View

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }
    
    class Coordinator: NSObject, QRScannerDelegate {
        let onCodeScanned: (String) -> Void
        
        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }
        
        func didScanCode(_ code: String) {
            onCodeScanned(code)
        }
        
        func didFailWithError(_ error: Error) {
            // Handle error if needed
        }
    }
}

protocol QRScannerDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didFailWithError(_ error: Error)
}

class QRScannerViewController: UIViewController {
    weak var delegate: QRScannerDelegate?
    
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    private func setupCaptureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.didFailWithError(error)
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            delegate?.didFailWithError(NSError(domain: "QRScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not add video input"]))
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            delegate?.didFailWithError(NSError(domain: "QRScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add metadata output"]))
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add viewfinder overlay
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        
        let centerSquareSize: CGFloat = 250
        let centerSquare = CGRect(
            x: (view.bounds.width - centerSquareSize) / 2,
            y: (view.bounds.height - centerSquareSize) / 2,
            width: centerSquareSize,
            height: centerSquareSize
        )
        
        let path = UIBezierPath(rect: overlayView.bounds)
        let centerPath = UIBezierPath(rect: centerSquare)
        path.append(centerPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
        
        view.addSubview(overlayView)
        
        // Add corner indicators
        let cornerSize: CGFloat = 20
        let cornerWidth: CGFloat = 3
        
        let corners: [(CGPoint, CGPoint)] = [
            // Top-left
            (CGPoint(x: centerSquare.minX, y: centerSquare.minY), CGPoint(x: centerSquare.minX + cornerSize, y: centerSquare.minY)),
            (CGPoint(x: centerSquare.minX, y: centerSquare.minY), CGPoint(x: centerSquare.minX, y: centerSquare.minY + cornerSize)),
            // Top-right
            (CGPoint(x: centerSquare.maxX, y: centerSquare.minY), CGPoint(x: centerSquare.maxX - cornerSize, y: centerSquare.minY)),
            (CGPoint(x: centerSquare.maxX, y: centerSquare.minY), CGPoint(x: centerSquare.maxX, y: centerSquare.minY + cornerSize)),
            // Bottom-left
            (CGPoint(x: centerSquare.minX, y: centerSquare.maxY), CGPoint(x: centerSquare.minX + cornerSize, y: centerSquare.maxY)),
            (CGPoint(x: centerSquare.minX, y: centerSquare.maxY), CGPoint(x: centerSquare.minX, y: centerSquare.maxY - cornerSize)),
            // Bottom-right
            (CGPoint(x: centerSquare.maxX, y: centerSquare.maxY), CGPoint(x: centerSquare.maxX - cornerSize, y: centerSquare.maxY)),
            (CGPoint(x: centerSquare.maxX, y: centerSquare.maxY), CGPoint(x: centerSquare.maxX, y: centerSquare.maxY - cornerSize))
        ]
        
        for (start, end) in corners {
            let cornerLine = CAShapeLayer()
            let cornerPath = UIBezierPath()
            cornerPath.move(to: start)
            cornerPath.addLine(to: end)
            cornerLine.path = cornerPath.cgPath
            cornerLine.strokeColor = UIColor.white.cgColor
            cornerLine.lineWidth = cornerWidth
            view.layer.addSublayer(cornerLine)
        }
        
        // Add instructions
        let instructionLabel = UILabel()
        instructionLabel.text = "Position QR code within the frame"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60)
        ])
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            delegate?.didScanCode(stringValue)
            dismiss(animated: true)
        }
    }
} 