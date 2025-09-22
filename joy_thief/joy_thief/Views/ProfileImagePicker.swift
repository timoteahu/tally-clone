import SwiftUI
import PhotosUI

// Basic image picker for photo library selection only
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoLibraryPicker
        
        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                 didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Normalize the image orientation
                parent.selectedImage = image.normalizedImage()
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// Simple profile image picker with camera (NO face detection) and photo library options
struct SimpleProfileImagePicker: View {
    @Binding var selectedImage: Data?
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingActionSheet = true
    @State private var tempImage: UIImage?
    @State private var showingCropper = false
    
    var body: some View {
        Color.clear
            .confirmationDialog("Select Profile Photo", isPresented: $showingActionSheet) {
                Button("Take Photo") {
                    showingCamera = true
                }
                Button("Choose from Library") {
                    showingPhotoLibrary = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(capturedImage: $tempImage)
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                PhotoLibraryPicker(selectedImage: $tempImage)
            }
            .onChange(of: tempImage) { oldValue, newValue in
                if newValue != nil {
                    // Add a small delay to ensure sheet dismissal completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingCropper = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCropper) {
                if let image = tempImage {
                    ImageCropperView(originalImage: image, isPresented: $showingCropper) { croppedImage in
                        // Ensure the image is properly oriented before converting to JPEG
                        let normalizedImage = croppedImage.normalizedImage()
                        selectedImage = normalizedImage.jpegData(compressionQuality: 0.8)
                        tempImage = nil
                    }
                }
            }
    }
}

// Main profile image picker with face detection camera and photo library (for identity snapshots)
struct ProfileImagePicker: View {
    @Binding var selectedImage: Data?
    @State private var showingFaceDetectionCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingActionSheet = true
    @State private var tempImage: UIImage?
    @State private var showingCropper = false
    @State private var tempImageData: Data?
    
    var body: some View {
        Color.clear
            .confirmationDialog("Select Profile Photo", isPresented: $showingActionSheet) {
                Button("Take Photo") {
                    showingFaceDetectionCamera = true
                }
                Button("Choose from Library") {
                    showingPhotoLibrary = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showingFaceDetectionCamera) {
                FaceDetectionCameraView(capturedImage: $tempImageData)
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                PhotoLibraryPicker(selectedImage: $tempImage)
            }
            .onChange(of: tempImage) { oldValue, newValue in
                if newValue != nil {
                    // Add a small delay to ensure sheet dismissal completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingCropper = true
                    }
                }
            }
            .onChange(of: tempImageData) { oldValue, newValue in
                if let data = newValue, let image = UIImage(data: data) {
                    tempImage = image
                    tempImageData = nil
                    // Add a small delay to ensure sheet dismissal completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingCropper = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCropper) {
                if let image = tempImage {
                    ImageCropperView(originalImage: image, isPresented: $showingCropper) { croppedImage in
                        // Ensure the image is properly oriented before converting to JPEG
                        let normalizedImage = croppedImage.normalizedImage()
                        selectedImage = normalizedImage.jpegData(compressionQuality: 0.8)
                        tempImage = nil
                        tempImageData = nil
                    }
                }
            }
    }
}

// MARK: - Simple camera picker for taking a photo
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraDevice = .front // Prefer front camera for profile photos
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Normalize the image orientation
                parent.capturedImage = image.normalizedImage()
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Legacy alias for backward compatibility
// This ensures any remaining references continue to work
typealias SimpleImageSourcePicker = ProfileImagePicker 