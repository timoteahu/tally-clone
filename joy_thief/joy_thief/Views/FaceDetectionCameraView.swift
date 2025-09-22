import SwiftUI
import AVFoundation
import Vision
import UIKit

struct FaceDetectionCameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: Data?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> FaceDetectionCameraViewController {
        let controller = FaceDetectionCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: FaceDetectionCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, FaceDetectionCameraDelegate {
        let parent: FaceDetectionCameraView
        
        init(_ parent: FaceDetectionCameraView) {
            self.parent = parent
        }
        
        func didCapturePhoto(_ imageData: Data) {
            parent.capturedImage = imageData
            parent.dismiss()
        }
        
        func didCancelCapture() {
            parent.dismiss()
        }
    }
}

protocol FaceDetectionCameraDelegate: AnyObject {
    func didCapturePhoto(_ imageData: Data)
    func didCancelCapture()
}

class FaceDetectionCameraViewController: UIViewController {
    weak var delegate: FaceDetectionCameraDelegate?
    
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    // UI Elements
    private let captureButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let faceGuideOverlay = FaceGuideOverlayView()
    private let instructionLabel = UILabel()
    private let flashButton = UIButton(type: .system)
    
    // Face detection properties
    private var lastFaceObservation: VNFaceObservation?
    private var isFaceDetected = false
    private var isFlashEnabled = false
    private var isFaceAlignedWell = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        checkCameraPermission()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
            setupUI()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupCamera()
                        self.setupUI()
                    } else {
                        self.showPermissionDeniedAlert()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDeniedAlert()
        @unknown default:
            showPermissionDeniedAlert()
        }
    }
    
    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(title: "Camera Access Required", 
                                    message: "Please enable camera access in Settings to take profile photos.", 
                                    preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.delegate?.didCancelCapture()
        })
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        present(alert, animated: true)
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
    
    private func setupCamera() {
        captureSession.sessionPreset = .photo
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Front camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // Add photo output
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                
                // Enable high resolution capture using maxPhotoDimensions
                if let format = frontCamera.activeFormat.supportedMaxPhotoDimensions.last {
                    photoOutput.maxPhotoDimensions = format
                }
                
                if let connection = photoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90 // Portrait orientation
                    }
                }
            }
            
            // Add video data output for face detection
            if captureSession.canAddOutput(videoDataOutput) {
                captureSession.addOutput(videoDataOutput)
                videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
                
                if let connection = videoDataOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90 // Portrait orientation
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
            }
            
            // Setup preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Setup face guide overlay
        faceGuideOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(faceGuideOverlay)
        
        // Setup instruction label
        instructionLabel.text = "Position your face in the oval"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        instructionLabel.layer.cornerRadius = 8
        instructionLabel.layer.masksToBounds = true
        instructionLabel.numberOfLines = 2
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        // Setup capture button (initially disabled)
        captureButton.setImage(UIImage(systemName: "camera.circle.fill"), for: .normal)
        captureButton.tintColor = .white
        captureButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        captureButton.layer.cornerRadius = 35
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.isEnabled = false
        captureButton.alpha = 0.4
        view.addSubview(captureButton)
        
        // Setup cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        cancelButton.layer.cornerRadius = 8
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // Setup flash button
        flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        flashButton.layer.cornerRadius = 20
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        view.addSubview(flashButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Face guide overlay (centered, portrait oriented)
            faceGuideOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            faceGuideOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            faceGuideOverlay.widthAnchor.constraint(equalToConstant: 280),
            faceGuideOverlay.heightAnchor.constraint(equalToConstant: 350),
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Capture button
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Cancel button
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Flash button
            flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            flashButton.widthAnchor.constraint(equalToConstant: 40),
            flashButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func handleFaceDetectionResults(_ results: [Any]?) {
        DispatchQueue.main.async {
            guard let faces = results as? [VNFaceObservation] else {
                self.updateUIForNoFace()
                return
            }
            
            if let face = faces.first, faces.count == 1 {
                self.lastFaceObservation = face
                self.updateUIForFaceDetected(face)
            } else if faces.count > 1 {
                self.updateUIForMultipleFaces()
            } else {
                self.updateUIForNoFace()
            }
        }
    }
    
    private func updateUIForFaceDetected(_ face: VNFaceObservation) {
        isFaceDetected = true
        
        // Check if face is well-positioned (more lenient thresholds)
        let centerX = face.boundingBox.midX
        let centerY = face.boundingBox.midY
        let size = max(face.boundingBox.width, face.boundingBox.height)
        
        // More lenient positioning requirements
        if centerX > 0.25 && centerX < 0.75 && 
           centerY > 0.25 && centerY < 0.75 && 
           size > 0.15 && size < 0.8 {
            
            instructionLabel.text = "Perfect! Tap to capture"
            instructionLabel.backgroundColor = UIColor.green.withAlphaComponent(0.8)
            captureButton.tintColor = .green
            captureButton.isEnabled = true
            captureButton.alpha = 1.0
            isFaceAlignedWell = true
            faceGuideOverlay.setGuideState(.good)
        } else if size < 0.15 {
            instructionLabel.text = "Move closer to the camera"
            instructionLabel.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
            captureButton.tintColor = .orange
            captureButton.isEnabled = false
            captureButton.alpha = 0.4
            isFaceAlignedWell = false
            faceGuideOverlay.setGuideState(.adjusting)
        } else if size > 0.8 {
            instructionLabel.text = "Move back from the camera"
            instructionLabel.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
            captureButton.tintColor = .orange
            captureButton.isEnabled = false
            captureButton.alpha = 0.4
            isFaceAlignedWell = false
            faceGuideOverlay.setGuideState(.adjusting)
        } else {
            instructionLabel.text = "Center your face in the oval"
            instructionLabel.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
            captureButton.tintColor = .orange
            captureButton.isEnabled = false
            captureButton.alpha = 0.4
            isFaceAlignedWell = false
            faceGuideOverlay.setGuideState(.adjusting)
        }
    }
    
    private func updateUIForMultipleFaces() {
        isFaceDetected = false
        instructionLabel.text = "Show only one face"
        instructionLabel.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        captureButton.tintColor = .red
        captureButton.isEnabled = false
        captureButton.alpha = 0.4
        isFaceAlignedWell = false
        faceGuideOverlay.setGuideState(.error)
    }
    
    private func updateUIForNoFace() {
        isFaceDetected = false
        instructionLabel.text = "Position your face in the oval"
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        captureButton.tintColor = .white
        captureButton.isEnabled = false
        captureButton.alpha = 0.4
        isFaceAlignedWell = false
        faceGuideOverlay.setGuideState(.searching)
    }
    
    @objc private func capturePhoto() {
        guard isFaceAlignedWell else { return }
        
        let settings = AVCapturePhotoSettings()
        
        // Enable high resolution capture (this is set on the photo output, not settings)
        // High resolution is controlled by the photoOutput.isHighResolutionCaptureEnabled property
        
        // Set flash mode
        if isFlashEnabled {
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = .on
            }
        } else {
            if photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            } else if photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func cancelCapture() {
        delegate?.didCancelCapture()
    }
    
    @objc private func toggleFlash() {
        isFlashEnabled.toggle()
        
        let imageName = isFlashEnabled ? "bolt.fill" : "bolt.slash.fill"
        flashButton.setImage(UIImage(systemName: imageName), for: .normal)
        flashButton.tintColor = isFlashEnabled ? .yellow : .white
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FaceDetectionCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let detectFaceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let error = error {
                print("Face detection error: \(error)")
                return
            }
            self?.handleFaceDetectionResults(request.results)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([detectFaceRequest])
        } catch {
            print("Failed to perform face detection: \(error)")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension FaceDetectionCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Could not convert photo to image data")
            return
        }
        
        // Process and potentially crop the image around the detected face
        let processedImageData = processImageForProfilePhoto(image)
        delegate?.didCapturePhoto(processedImageData)
    }
    
    private func processImageForProfilePhoto(_ image: UIImage) -> Data {
        // If we have a detected face, crop around it with generous padding
        if let faceObservation = lastFaceObservation {
            let croppedImage = cropImageAroundFace(image, faceObservation: faceObservation)
            return croppedImage.jpegData(compressionQuality: 0.9) ?? image.jpegData(compressionQuality: 0.85)!
        }
        
        // Otherwise, just return the original image with good compression
        return image.jpegData(compressionQuality: 0.85)!
    }
    
    private func cropImageAroundFace(_ image: UIImage, faceObservation: VNFaceObservation) -> UIImage {
        let imageSize = image.size
        
        // Convert normalized coordinates to image coordinates
        // Note: Vision framework has origin at bottom-left, UIImage has origin at top-left
        let faceRect = CGRect(
            x: faceObservation.boundingBox.minX * imageSize.width,
            y: (1 - faceObservation.boundingBox.maxY) * imageSize.height,
            width: faceObservation.boundingBox.width * imageSize.width,
            height: faceObservation.boundingBox.height * imageSize.height
        )
        
        // Add generous padding around the face (100% on each side for 3x total size)
        let padding: CGFloat = 1.0
        let paddedWidth = faceRect.width * (1 + padding * 2)
        let paddedHeight = faceRect.height * (1 + padding * 2)
        
        // Center the crop around the face
        let cropRect = CGRect(
            x: max(0, faceRect.midX - paddedWidth / 2),
            y: max(0, faceRect.midY - paddedHeight / 2),
            width: min(paddedWidth, imageSize.width),
            height: min(paddedHeight, imageSize.height)
        )
        
        // Ensure we don't go outside image bounds
        let finalCropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))
        
        // Crop the image
        guard let cgImage = image.cgImage?.cropping(to: finalCropRect) else {
            return image
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Face Guide Overlay View
class FaceGuideOverlayView: UIView {
    enum GuideState {
        case searching
        case adjusting
        case good
        case error
    }
    
    private var guideState: GuideState = .searching
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setGuideState(_ state: GuideState) {
        guard guideState != state else { return }
        guideState = state
        
        // Animate the state change
        UIView.animate(withDuration: 0.3) {
            self.setNeedsDisplay()
        }
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Define the oval frame (slightly smaller than the view)
        let ovalRect = rect.insetBy(dx: 20, dy: 20)
        
        // Set line properties based on state
        let lineWidth: CGFloat = 3
        let dashPattern: [CGFloat]
        let color: UIColor
        
        switch guideState {
        case .searching:
            color = .white
            dashPattern = [10, 5]
        case .adjusting:
            color = .orange
            dashPattern = [8, 4]
        case .good:
            color = .green
            dashPattern = []
        case .error:
            color = .red
            dashPattern = [6, 3]
        }
        
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        
        if !dashPattern.isEmpty {
            context.setLineDash(phase: 0, lengths: dashPattern)
        }
        
        // Draw the oval guide
        context.addEllipse(in: ovalRect)
        context.strokePath()
        
        // Add corner guides for better framing
        drawCornerGuides(context: context, rect: ovalRect, color: color)
    }
    
    private func drawCornerGuides(context: CGContext, rect: CGRect, color: UIColor) {
        let cornerLength: CGFloat = 20
        let cornerOffset: CGFloat = 10
        
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(2)
        context.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
        
        // Top-left corner
        context.move(to: CGPoint(x: rect.minX - cornerOffset, y: rect.minY + cornerLength))
        context.addLine(to: CGPoint(x: rect.minX - cornerOffset, y: rect.minY - cornerOffset))
        context.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY - cornerOffset))
        
        // Top-right corner
        context.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY - cornerOffset))
        context.addLine(to: CGPoint(x: rect.maxX + cornerOffset, y: rect.minY - cornerOffset))
        context.addLine(to: CGPoint(x: rect.maxX + cornerOffset, y: rect.minY + cornerLength))
        
        // Bottom-left corner
        context.move(to: CGPoint(x: rect.minX - cornerOffset, y: rect.maxY - cornerLength))
        context.addLine(to: CGPoint(x: rect.minX - cornerOffset, y: rect.maxY + cornerOffset))
        context.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY + cornerOffset))
        
        // Bottom-right corner
        context.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY + cornerOffset))
        context.addLine(to: CGPoint(x: rect.maxX + cornerOffset, y: rect.maxY + cornerOffset))
        context.addLine(to: CGPoint(x: rect.maxX + cornerOffset, y: rect.maxY - cornerLength))
        
        context.strokePath()
    }
} 
