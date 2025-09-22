//
//  DualCameraCapture.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//
import SwiftUI
import AVFoundation

// MARK: - Dual Camera Capture View
struct DualCameraCapture: View {
    @Binding var frontCameraImageData: Data?
    @Binding var rearCameraImageData: Data?
    @Binding var bothImagesComplete: Bool
    let startingCameraMode: SwipeableHabitCard.CameraMode
    
    @State private var currentCameraPosition: AVCaptureDevice.Position
    @State private var capturedImages: [AVCaptureDevice.Position: Data] = [:]
    @State private var isTransitioning = false
    @State private var shouldTriggerCapture = false
    @State private var autoCapturingSecond = false
    @State private var secondPhotoCountdown = 0
    @State private var currentFlashMode: AVCaptureDevice.FlashMode = .off
    @Environment(\.dismiss) private var dismiss

    @State private var activeSession: AVCaptureSession? 
    
    private func finishSession() {
        if let session = activeSession, session.isRunning {
            session.stopRunning()
        }
        dismiss()
    }
    
    init(frontCameraImageData: Binding<Data?>, rearCameraImageData: Binding<Data?>, bothImagesComplete: Binding<Bool>, startingCameraMode: SwipeableHabitCard.CameraMode) {
        self._frontCameraImageData = frontCameraImageData
        self._rearCameraImageData = rearCameraImageData
        self._bothImagesComplete = bothImagesComplete
        self.startingCameraMode = startingCameraMode
        self._currentCameraPosition = State(initialValue: startingCameraMode == .selfie ? .front : .back)
    }
    
    var body: some View {
        ZStack {
            // Camera view
            AutoCameraPickerView(
                cameraPosition: currentCameraPosition,
                onImageCaptured: { imageData in
                    handleImageCaptured(imageData: imageData, position: currentCameraPosition)
                },
                onCapturePhoto: {
                    // This will be triggered by the capture button
                },
                shouldTriggerCapture: $shouldTriggerCapture,
                isFlashEnabled: currentFlashMode,
                onSessionPrepared: { session in
                    activeSession = session
                }
            )
            
            // Camera transition overlay
            if isTransitioning {
                CameraTransitionView(
                    message: "Switching to \(currentCameraPosition == .front ? "front" : "rear") camera...",
                    cardWidth: UIScreen.main.bounds.width,
                    cardHeight: UIScreen.main.bounds.height
                )
                .transition(.opacity)
            }
            
            // Overlay UI
            VStack {
                // Top status bar
                HStack {
                    Button("Cancel") {
                        finishSession()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    // Flash button
                    Button(action: {
                        toggleFlash()
                    }) {
                        Image(systemName: flashIconName(for: currentFlashMode))
                            .font(.system(size: 20))
                            .foregroundColor(flashIconColor(for: currentFlashMode))
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    
                    Spacer()
                    
                    // Progress indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(capturedImages[.front] != nil ? Color.green : Color.white.opacity(0.5))
                            .frame(width: 12, height: 12)
                        
                        Circle()
                            .fill(capturedImages[.back] != nil ? Color.green : Color.white.opacity(0.5))
                            .frame(width: 12, height: 12)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Bottom instruction text and capture button
                VStack(spacing: 20) {
                    if isTransitioning {
                        Text("Switching camera...")
                            .jtStyle(.body)
                            .foregroundColor(.white)
                    } else if autoCapturingSecond {
                        VStack(spacing: 20) {
                            Text("switching camera...")
                                .font(.custom("EBGaramond-Regular", size: 18))
                                .foregroundColor(.white.opacity(0.7))
                                .textCase(.lowercase)
                            
                            if secondPhotoCountdown > 0 {
                                Text("\(secondPhotoCountdown)")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(.white.opacity(0.6))
                                    .transition(.opacity)
                            }
                        }
                    } else if capturedImages.count == 0 {
                        Text("take selfie (1/2)")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(.white.opacity(0.8))
                            .textCase(.lowercase)
                        Text("second photo will be taken automatically")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.lowercase)
                    } else if capturedImages.count == 1 {
                        Text("first photo captured")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(.green.opacity(0.8))
                            .textCase(.lowercase)
                        Text("switching to rear camera...")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.lowercase)
                    }
                    
                    // Capture button (only show for first photo)
                    if !isTransitioning && !autoCapturingSecond && capturedImages.count == 0 {
                        Button(action: {
                            // Enhanced haptic feedback for capture
                            HapticFeedbackManager.shared.heavyImpact()
                            capturePhoto()
                        }) {
                            ZStack {
                                // Simple capture button
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .stroke(Color.white.opacity(0.8), lineWidth: 3)
                                    .frame(width: 86, height: 86)
                                
                                if capturedImages.count > 0 {
                                    Text("\(capturedImages.count)/2")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .disabled(isTransitioning)
                        .scaleEffect(isTransitioning ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTransitioning)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color.black)
    }
    
    private func toggleFlash() {
        switch currentFlashMode {
        case .off:
            currentFlashMode = .on
        case .on:
            currentFlashMode = .auto
        case .auto:
            currentFlashMode = .off
        @unknown default:
            currentFlashMode = .off
        }
    }
    
    private func flashIconName(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off:
            return "bolt.slash.fill"
        case .on:
            return "bolt.fill"
        case .auto:
            return "bolt.badge.a.fill"
        @unknown default:
            return "bolt.slash.fill"
        }
    }
    
    private func flashIconColor(for mode: AVCaptureDevice.FlashMode) -> Color {
        switch mode {
        case .on:
            return .yellow
        case .auto:
            return .orange
        case .off:
            return .white
        @unknown default:
            return .white
        }
    }
    
    private func mirroredImageDataIfNeeded(_ data: Data, for position: AVCaptureDevice.Position) -> Data {
        guard position == .front,
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { return data }
        let mirrored = UIImage(cgImage: cgImage, scale: image.scale, orientation: .leftMirrored)
        return mirrored.jpegData(compressionQuality: 1.0) ?? data
    }

    private func handleImageCaptured(imageData: Data, position: AVCaptureDevice.Position) {
        print("🖼️ Image captured for \(position == .front ? "front" : "rear") camera - \(imageData.count) bytes")
        
        // Enhanced haptic feedback for successful capture
        HapticFeedbackManager.shared.mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticFeedbackManager.shared.lightImpact()
        }
        
        // Process and downscale image to reduce memory usage
        Task {
            if let processedData = await processAndDownscaleImage(imageData, for: position) {
                await MainActor.run {
                    // Store the processed image
                    capturedImages[position] = processedData
                    print("📊 Total images captured: \(capturedImages.count)/2 - Processed size: \(processedData.count) bytes")
                    checkIfBothImagesComplete()
                }
            } else {
                // Fallback: Use original image if processing fails
                await MainActor.run {
                    print("⚠️ Image processing failed for \(position == .front ? "front" : "rear") camera, using original image")
                    capturedImages[position] = imageData
                    print("📊 Total images captured: \(capturedImages.count)/2 - Original size: \(imageData.count) bytes")
                    checkIfBothImagesComplete()
                }
            }
        }
    }
    
    private func checkIfBothImagesComplete() {
        // Check if we have both images
        if capturedImages.count == 2 {
            print("🎉 Both images captured! Completing process...")
            // Both images captured - complete the process
            frontCameraImageData = capturedImages[.front]
            rearCameraImageData = capturedImages[.back]
            autoCapturingSecond = false
            bothImagesComplete = true
            
            // Clear captured images from memory after transferring to bindings
            capturedImages.removeAll()
            
            finishSession()
        } else {
            // Determine which camera to switch to next (use the one that has NOT been captured yet)
            let nextPosition: AVCaptureDevice.Position = capturedImages.keys.contains(.front) ? .back : .front
            print("🔄 Switching to \(nextPosition == .front ? "front" : "rear") camera for automatic second capture …")

            // Show transition animation
            withAnimation(.easeInOut(duration: 0.3)) {
                isTransitioning = true
            }

            // Update the picker to use the next camera after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                currentCameraPosition = nextPosition
                
                // Hide transition after camera switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isTransitioning = false
                    }
                }
            }

            // Start countdown before automatically triggering the second capture to give the camera time to initialise.
            autoCapturingSecond = true
            secondPhotoCountdown = 2
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                secondPhotoCountdown -= 1
                
                if secondPhotoCountdown == 0 {
                    timer.invalidate()
                    shouldTriggerCapture = true
                    autoCapturingSecond = false
                    HapticFeedbackManager.shared.lightImpact()
                }
            }
        }
    }
    
    private func capturePhoto() {
        print("📸 Capture button pressed, triggering photo capture")
        shouldTriggerCapture = true
    }

    private func switchCamera(to position: AVCaptureDevice.Position) {
        // Need an active session
        guard let session = activeSession else { return }

        // Stop the old stream
        if session.isRunning { session.stopRunning() }

        session.beginConfiguration()

        // Remove any existing video inputs
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter   { $0.device.hasMediaType(.video) }
            .forEach  { session.removeInput($0) }

        // Add the new camera input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video,
                                                position: position),
            let newInput = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(newInput)
        else {
            print("🚫 Could not switch to \(position) camera")
            session.commitConfiguration()
            session.startRunning()
            return
        }

        session.addInput(newInput)
        session.commitConfiguration()

        // Start session if it is not already running
        if !session.isRunning {
            session.startRunning()
        }
    }
    
    private func processAndDownscaleImage(_ imageData: Data, for position: AVCaptureDevice.Position) async -> Data? {
        // First mirror if needed for front camera (do this on main actor)
        let processedData = mirroredImageDataIfNeeded(imageData, for: position)
        
        return await Task.detached(priority: .userInitiated) {
            // Now process the already-mirrored data
            
            guard let image = UIImage(data: processedData) else {
                print("❌ Failed to create UIImage from data")
                return processedData
            }
            
            // Calculate new size (max 1920x1080 while maintaining aspect ratio)
            let maxSize: CGFloat = 1920
            let size = image.size
            var newSize = size
            
            if size.width > maxSize || size.height > maxSize {
                let aspectRatio = size.width / size.height
                if size.width > size.height {
                    newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
                } else {
                    newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
                }
            }
            
            // Only downscale if needed
            if newSize == size {
                print("✅ Image already optimal size: \(size)")
                // Still compress even if not resizing
                return image.jpegData(compressionQuality: 0.8) ?? processedData
            }
            
            // Downscale image using UIGraphicsImageRenderer for better memory efficiency
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resizedImage = renderer.image { context in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            
            // Compress to JPEG
            let compressionQuality: CGFloat = 0.8
            guard let compressedData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
                print("❌ Failed to compress image")
                return processedData
            }
            
            print("✅ Image downscaled from \(size) to \(newSize)")
            print("📉 Size reduced from \(imageData.count / 1024)KB to \(compressedData.count / 1024)KB")
            
            return compressedData
        }.value
    }
}


// MARK: - Auto Camera Picker View
struct AutoCameraPickerView: View {
    let cameraPosition: AVCaptureDevice.Position
    let onImageCaptured: (Data) -> Void
    let onCapturePhoto: () -> Void
    @Binding var shouldTriggerCapture: Bool
    let isFlashEnabled: AVCaptureDevice.FlashMode
    
    let onSessionPrepared: (AVCaptureSession) -> Void   // ← NEW

    @State private var captureSession = AVCaptureSession()
    @State private var photoOutput = AVCapturePhotoOutput()
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var photoCaptureDelegate: PhotoCaptureDelegate?
    
    // Dedicated serial queue for all capture-session work, per Apple's guidance.
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    init(
        cameraPosition: AVCaptureDevice.Position,
        onImageCaptured: @escaping (Data) -> Void,
        onCapturePhoto: @escaping () -> Void,
        shouldTriggerCapture: Binding<Bool>,
        isFlashEnabled: AVCaptureDevice.FlashMode,
        onSessionPrepared: @escaping (AVCaptureSession) -> Void = { _ in }   // ← default keeps old call-sites working
    ) {
        self.cameraPosition       = cameraPosition
        self.onImageCaptured      = onImageCaptured
        self.onCapturePhoto       = onCapturePhoto
        self._shouldTriggerCapture = shouldTriggerCapture
        self.isFlashEnabled       = isFlashEnabled
        self.onSessionPrepared    = onSessionPrepared
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraPreview(
                    session: captureSession,
                    cameraPosition: cameraPosition,
                    onImageCaptured: onImageCaptured
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                
                // Setup camera when view appears or position changes
                Color.clear
                    .onAppear {
                        setupCamera(for: cameraPosition)

                        if shouldTriggerCapture {
                            DispatchQueue.main.async {
                                capturePhoto()
                                shouldTriggerCapture = false
                            }
                        }
                    }
                    .onChange(of: cameraPosition) { oldValue, newValue in
                        print("📹 Camera position changed to: \(newValue == .front ? "front" : "rear")")
                        setupCamera(for: newValue)
                    }
                    .onChange(of: shouldTriggerCapture) { oldValue, newValue in
                        if newValue {
                            print("📷 Trigger received, attempting to capture photo")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                capturePhoto()
                                shouldTriggerCapture = false
                            }
                        }
                    }
            }
        }
    }
    
    private func setupCamera(for position: AVCaptureDevice.Position) {
        // All heavy-weight session work is moved off the main thread.
        sessionQueue.async {
            print("🎬 Setting up camera for \(position == .front ? "front" : "rear") camera")

            // Check camera permission (sync ‑ safe to run here)
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break // ok
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted { self.setupCamera(for: position) }
                }
                return
            default:
                print("❌ Camera permission denied/restricted")
                return
            }

            // Stop session while re-configuring to ensure input swap succeeds
            let wasRunning = self.captureSession.isRunning
            if wasRunning { self.captureSession.stopRunning() }

            self.captureSession.beginConfiguration()

            // Remove existing inputs
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }

            // Add camera input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: position),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else {
                print("❌ Could not add new camera input")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)

            // Add / keep photo output
            if !self.captureSession.outputs.contains(self.photoOutput) &&
                self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }

            self.captureSession.commitConfiguration()

            // Start session if it is not already running
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            // Notify UI on main thread that session is ready
            DispatchQueue.main.async {
                self.onSessionPrepared(self.captureSession)
            }

            print("📹 Capture session started ‑ running: \(self.captureSession.isRunning)")
        }
    }
    
    func capturePhoto() {
        sessionQueue.async {
            print("🎯 CapturePhoto called - session running: \(self.captureSession.isRunning)")
            guard self.captureSession.isRunning else {
                print("❌ Capture session not running")
                return
            }

            // Create and store the delegate to prevent deallocation
            self.photoCaptureDelegate = PhotoCaptureDelegate(onImageCaptured: self.onImageCaptured)

            let settings = AVCapturePhotoSettings()
            
            // Set flash mode based on the current flash setting
            if self.isFlashEnabled == .on {
                settings.flashMode = .on
            } else if self.isFlashEnabled == .auto {
                settings.flashMode = .auto
            } else if self.isFlashEnabled == .off {
                settings.flashMode = .off
            }
            
            print("📝 Creating capture settings with flash: \(settings.flashMode.rawValue) and triggering photo capture")
            self.photoOutput.capturePhoto(with: settings, delegate: self.photoCaptureDelegate!)
        }
    }
}

// MARK: - Camera Preview
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraPosition: AVCaptureDevice.Position
    let onImageCaptured: (Data) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - Photo Capture Delegate
class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let onImageCaptured: (Data) -> Void
    
    init(onImageCaptured: @escaping (Data) -> Void) {
        self.onImageCaptured = onImageCaptured
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("📷 Photo capture completed - error: \(error?.localizedDescription ?? "none")")
        guard let imageData = photo.fileDataRepresentation() else { 
            print("❌ Failed to get image data from photo")
            return 
        }
        print("✅ Successfully captured photo with \(imageData.count) bytes")
        DispatchQueue.main.async {
            self.onImageCaptured(imageData)
        }
    }
}
