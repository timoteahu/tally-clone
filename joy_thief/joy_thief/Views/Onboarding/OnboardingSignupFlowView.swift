import SwiftUI
import UIKit

/// Multi-step sign-up used after the onboarding marketing copy.
/// 1. Phone – user enters phone number. We immediately send the verification code.
/// 2. Photos – user must capture an identity snapshot (face-detection camera) and can optionally add a profile picture (camera or library).
/// 3. Verify – user enters the SMS code and we complete sign-up.
struct OnboardingSignupFlowView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Binding var isPresenting: Bool // Binding used by parent to dismiss if needed (not used yet)

    // Pre-filled phone number passed from previous screen to avoid double entry
    var initialPhoneNumber: String? = nil

    // MARK: ‑ Collected data
    @State private var phoneNumber = ""
    @State private var name = ""
    @State private var verificationCode = ""
    @State private var identitySnapshotData: Data? = nil
    @State private var profilePhotoData: Data? = nil

    // MARK: ‑ Flow state
    private enum Step { case phone, verify, name, identitySnapshot, profilePhoto, completed }
    @State private var step: Step = .phone

    // MARK: ‑ UI state
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String?
    
    // Name validation state
    @State private var isCheckingName = false
    @State private var nameAvailable = true
    @State private var nameErrorMessage: String?

    // Photo pickers
    @State private var showingIdentitySnapshotCamera = false
    @State private var showingProfileImagePicker = false
    @State private var showingProfileCamera = false
    @State private var showingProfilePhotoLibrary = false
    @State private var tempProfileImage: UIImage?
    @State private var showingProfileCropper = false
    @State private var showingIdentitySnapshotPreview = false
    @State private var capturedIdentityImage: UIImage?

    // One-time init flag
    @State private var didInitialize = false

    // Name field edit mode
    @State private var editingName = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: step == .phone || step == .verify || step == .name ? 0 : 50) {
                stepContent
                primaryButton
            }
            .padding(.vertical, step == .phone || step == .verify || step == .name ? 0 : 40)
            .padding(.horizontal, step == .phone || step == .verify || step == .name || step == .identitySnapshot || step == .profilePhoto ? 0 : 24)
        }
        .fullScreenCover(isPresented: $showingIdentitySnapshotCamera) {
            FaceDetectionCameraView(capturedImage: $identitySnapshotData)
                .onDisappear {
                    if let data = identitySnapshotData, let image = UIImage(data: data) {
                        capturedIdentityImage = image
                        identitySnapshotData = nil
                        // Add a small delay to ensure fullScreenCover dismissal completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingIdentitySnapshotPreview = true
                        }
                    }
                }
        }
        .fullScreenCover(isPresented: $showingIdentitySnapshotPreview) {
            IdentitySnapshotPreviewView(
                image: capturedIdentityImage,
                isPresented: $showingIdentitySnapshotPreview,
                onSubmit: { image in
                    identitySnapshotData = image.jpegData(compressionQuality: 0.8)
                    capturedIdentityImage = nil
                },
                onRetake: {
                    capturedIdentityImage = nil
                    showingIdentitySnapshotCamera = true
                }
            )
        }
        .confirmationDialog("Select Profile Photo", isPresented: $showingProfileImagePicker) {
            Button("Take Photo") {
                showingProfileCamera = true
            }
            Button("Choose from Library") {
                showingProfilePhotoLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingProfileCamera) {
            CameraPicker(capturedImage: $tempProfileImage)
        }
        .sheet(isPresented: $showingProfilePhotoLibrary) {
            PhotoLibraryPicker(selectedImage: $tempProfileImage)
        }
        .onChange(of: tempProfileImage) { oldValue, newValue in
            if newValue != nil {
                // Add a small delay to ensure sheet dismissal completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingProfileCropper = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingProfileCropper) {
            if let image = tempProfileImage {
                ImageCropperView(originalImage: image, isPresented: $showingProfileCropper) { croppedImage in
                    // Ensure the image is properly oriented before converting to JPEG
                    if let jpegData = croppedImage.jpegData(compressionQuality: 0.8),
                       let reloadedImage = UIImage(data: jpegData) {
                        profilePhotoData = reloadedImage.jpegData(compressionQuality: 0.8)
                    }
                    tempProfileImage = nil
                }
            }
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .onAppear {
            // Initialize with passed phone number once to avoid double entry
            guard !didInitialize else { return }
            didInitialize = true
            if let initial = initialPhoneNumber, !initial.isEmpty {
                phoneNumber = initial
                // Automatically request code and move to next step
                Task {
                    await sendCode()
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? authManager.errorMessage ?? "An error occurred")
        }
    }

    // MARK: ‑ Sub-views

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .phone:
            VStack(spacing: 18) {
                Spacer().frame(height: 250)
                HStack(spacing: 2) {
                    CustomTextField(placeholder: "phone number", text: $phoneNumber, keyboardType: .phonePad)
                    if !phoneNumber.isEmpty {
                        Button(action: { Task { await sendCode() } }) {
                            Image(systemName: "arrow.right")
                                .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(width: 100, height: 44) // Larger hit area
                                .contentShape(Rectangle())
                                .padding(.trailing, 20)
                        }
                        .transition(.move(edge: .trailing))
                        .disabled(disablePrimaryButton)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: phoneNumber.isEmpty)
                Spacer()
            }
        case .verify:
            VStack(spacing: 18) {
                Spacer().frame(height: 250)
                VStack(spacing: 18) {
                    HStack(spacing: 2) {
                        OTPCodeField(code: $verificationCode)
                        if !verificationCode.isEmpty {
                            Button(action: { Task { await verifyCode() } }) {
                                Image(systemName: "arrow.right")
                                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(width: 100, height: 44) // Larger hit area
                                    .contentShape(Rectangle())
                                    .padding(.trailing, 20)
                            }
                            .transition(.move(edge: .trailing))
                            .disabled(disablePrimaryButton)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: verificationCode.isEmpty)
                    
                    // Back to phone number option
                    Button(action: { resetToPhoneNumber() }) {
                        Image(systemName: "arrow.left")
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 60, height: 44) // Larger hit area
                            .contentShape(Rectangle())
                    }
                    .padding(.top, 24)
                }
                Spacer()
            }
        case .name:
            VStack {
                Spacer().frame(height: 250)
                
                VStack(spacing: 18) {
                    HStack(spacing: 2) {
                        CustomTextField(placeholder: "username", text: $name)
                            .onChange(of: name) { oldValue, newValue in
                                // Filter out invalid characters in real-time
                                let validCharacterSet = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
                                let filteredString = String(newValue.unicodeScalars.filter { validCharacterSet.contains($0) })
                                
                                // Update name only if it changed after filtering
                                if filteredString != newValue {
                                    name = filteredString
                                }
                                
                                // Reset validation state when name changes
                                nameAvailable = true
                                nameErrorMessage = nil
                            }
                        if !name.isEmpty && !isCheckingName {
                            Button(action: { Task { await checkNameAndProceed() } }) {
                                Image(systemName: "arrow.right")
                                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(width: 100, height: 44) // Larger hit area
                                    .contentShape(Rectangle())
                                    .padding(.trailing, 20)
                            }
                            .transition(.move(edge: .trailing))
                            .disabled(disablePrimaryButton)
                        }
                        if isCheckingName {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                                .padding(.trailing, 80)
                                .padding(.vertical, 8)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: name.isEmpty)
                    
                    // Show name availability status
                    Group {
                        if let errorMessage = nameErrorMessage {
                            Text(errorMessage)
                                .font(.custom("EBGaramond-Regular", size: 14))
                                .foregroundColor(.red)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else if !name.isEmpty && !isCheckingName && !nameAvailable {
                            Text("This username is already taken")
                                .font(.custom("EBGaramond-Regular", size: 14))
                                .foregroundColor(.red)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: "\(nameErrorMessage ?? "")-\(nameAvailable)")
                    
                    // Back to verify option
                    Button(action: { withAnimation(.easeInOut) { step = .verify } }) {
                        Image(systemName: "arrow.left")
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.top, 24)
                }
                
                Spacer()
            }
        case .identitySnapshot:
            VStack(spacing: 20) {
                // Header with back button
                HStack {
                    Button(action: { withAnimation(.easeInOut) { step = .name } }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                Text("identity verification")
                    .font(.custom("EBGaramond-Regular", size: 24))
                    .foregroundColor(.white)
                
                Text("we need a photo of your face for security")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 30)
                
                // Identity snapshot (required)
                VStack(spacing: 12) {
                    photoCircle(imageData: identitySnapshotData,
                                placeholderIcon: "camera.viewfinder",
                                placeholderText: "capture",
                                size: 180) {
                        showingIdentitySnapshotCamera = true
                    }
                }
                
                Spacer().frame(height: 30)
            }
            
        case .profilePhoto:
            VStack(spacing: 20) {
                // Header with back button
                HStack {
                    Button(action: { withAnimation(.easeInOut) { step = .identitySnapshot } }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                Text("profile photo")
                    .font(.custom("EBGaramond-Regular", size: 24))
                    .foregroundColor(.white)
                
                Text("add a profile picture (optional)")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Spacer().frame(height: 30)
                
                // Profile photo (optional)
                VStack(spacing: 12) {
                    photoCircle(imageData: profilePhotoData,
                                placeholderIcon: "person.crop.circle",
                                placeholderText: "add photo",
                                size: 180) {
                        showingProfileImagePicker = true
                    }
                }
                
                Spacer().frame(height: 30)
                
                Button(action: { Task { await primaryAction() } }) {
                    Text("skip for now")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(minWidth: 150, minHeight: 44) // Bigger hit area
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                }
            }
        case .completed:
            VStack {
                Text("All set! 🎉")
                    .font(.custom("EBGaramond-Regular", size: 32))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        if step == .identitySnapshot || step == .profilePhoto || step == .completed {
            Button(action: { Task { await primaryAction() } }) {
                if isLoading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(primaryButtonTitle)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: 280, minHeight: 56) // Bigger button
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.15)))
            .disabled(disablePrimaryButton)
            .opacity(disablePrimaryButton ? 0.5 : 1)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .phone: return "Continue"
        case .verify: return "Continue"
        case .name: return "Continue"
        case .identitySnapshot: return "Continue"
        case .profilePhoto: return "Continue"
        case .completed: return "Done"
        }
    }

    private var disablePrimaryButton: Bool {
        if isLoading { return true }
        switch step {
        case .phone:
            return phoneNumber.isEmpty || phoneNumber.count < 6
        case .verify:
            return verificationCode.count < 6 || isLoading
        case .name:
            return name.isEmpty || isCheckingName || !nameAvailable
        case .identitySnapshot:
            return identitySnapshotData == nil
        case .profilePhoto:
            return false // Optional step, always enabled
        case .completed:
            return false
        }
    }

    // MARK: ‑ Actions

    private func primaryAction() async {
        switch step {
        case .phone:
            await sendCode()
        case .verify:
            await verifyCode()
        case .name:
            await checkNameAndProceed()
        case .identitySnapshot:
            // Move to profile photo step
            withAnimation(.easeInOut) { step = .profilePhoto }
        case .profilePhoto:
            await completeSignup()
        case .completed:
            isPresenting = false
        }
    }

    private func sendCode() async {
        isLoading = true
        defer { isLoading = false }
        
        // Reset state at start of each attempt
        await MainActor.run {
            showError = false
            errorMessage = nil
        }
        
        do {
            try await authManager.requestVerificationCode(phoneNumber: phoneNumber)
            await MainActor.run {
                withAnimation(.easeInOut) { step = .verify }
            }
        } catch {
            await MainActor.run {
                showError = true
                errorMessage = "there was an error in authenticating your phone number"
            }
        }
    }

    private func verifyCode() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.verifySignupCode(phoneNumber: phoneNumber, verificationCode: verificationCode)
            await MainActor.run { withAnimation(.easeInOut) { step = .name } }
        } catch {
            await MainActor.run {
                verificationCode = "" // Clear code on error so user can retry
                showError = true
                errorMessage = "there was an error in authenticating your phone number"
            }
        }
    }

    private func resetToPhoneNumber() {
        // Clear any local state first
        verificationCode = ""
        showError = false
        errorMessage = nil
        
        // Return to login flow to re-determine signup vs login
        // This will cause LoginView to switch back to LoginFlowView
        isPresenting = false
    }
    
    private func checkNameAndProceed() async {
        guard !name.isEmpty else { return }
        
        // Basic validation
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.count < 2 {
            await MainActor.run {
                nameAvailable = false
                nameErrorMessage = "username must be at least 2 characters"
            }
            return
        }
        
        if trimmedName.count > 30 {
            await MainActor.run {
                nameAvailable = false
                nameErrorMessage = "username must be 30 characters or less"
            }
            return
        }
        
        // Check for valid characters (letters, numbers, spaces, hyphens, underscores)
        let validCharacterSet = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        if trimmedName.rangeOfCharacter(from: validCharacterSet.inverted) != nil {
            await MainActor.run {
                nameAvailable = false
                nameErrorMessage = "username can only contain letters, numbers, spaces, hyphens, and underscores"
            }
            return
        }
        
        isCheckingName = true
        defer { isCheckingName = false }
        
        do {
            let available = try await authManager.checkNameAvailability(name: trimmedName)
            await MainActor.run {
                nameAvailable = available
                if available {
                    name = trimmedName // Update with trimmed version
                    withAnimation(.easeInOut) { step = .identitySnapshot }
                } else {
                    nameErrorMessage = "this username is already taken"
                }
            }
        } catch {
            await MainActor.run {
                nameAvailable = false
                nameErrorMessage = "Error checking name availability"
            }
        }
    }

    private var NameInputView: some View {
        Group {
            if editingName || name.isEmpty {
                CustomTextField(placeholder: "name", text: $name, keyboardType: .default)
                    .focused($nameFieldFocused)
                    .onAppear { nameFieldFocused = true }
                    .onSubmit { editingName = false }
                    .onChange(of: nameFieldFocused) { oldValue, newValue in
                        if !newValue { editingName = false }
                    }
                    .onChange(of: name) { oldValue, newValue in
                        // Filter out invalid characters in real-time
                        let validCharacterSet = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
                        let filteredString = String(newValue.unicodeScalars.filter { validCharacterSet.contains($0) })
                        
                        // Update name only if it changed after filtering
                        if filteredString != newValue {
                            name = filteredString
                        }
                    }
            } else {
                Button(action: { editingName = true }) {
                    HStack {
                        Text(name)
                            .font(.custom("EBGaramond-Regular", size: 17))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
    }

    private func completeSignup() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let imageToSendData = identitySnapshotData!
            guard let verificationImage = await AsyncImageLoader.loadImage(from: imageToSendData) else {
                errorMessage = "Failed to process verification image"
                showError = true
                return
            }
            
            let profileImage: UIImage?
            if let profileData = profilePhotoData {
                profileImage = await AsyncImageLoader.loadImage(from: profileData)
            } else {
                profileImage = nil
            }
            
            try await authManager.signUp(phoneNumber: phoneNumber,
                                         verificationCode: verificationCode,
                                         name: name,
                                         verificationImage: verificationImage,
                                         profileImage: profileImage)

            // Profile photo upload is now handled automatically by AuthManager.signUp() using the avatar system

            // FIXED: Start onboarding at state 0 instead of immediately completing it
            // This allows the user to go through the full onboarding experience
            print("🎭 [OnboardingSignupFlow] Starting onboarding flow - setting state to 0")
            await authManager.updateOnboardingState(to: 0)
            
            // Notify ContentView that signup just completed (for race condition protection)
            NotificationCenter.default.post(name: NSNotification.Name("SignupJustCompleted"), object: nil)
            
            // Small delay to ensure state propagates throughout the system
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

            // Clear onboarding phase cache to start fresh
            UserDefaults.standard.removeObject(forKey: "onboarding_phase_cache")
            
            step = .completed
            isPresenting = false // dismiss after signup; onboarding shown elsewhere
        } catch {
            await MainActor.run {
                showError = true
                if error.localizedDescription.contains("no_face_detected") {
                    errorMessage = "No face detected in the identity snapshot. Please upload a clear photo of your face."
                } else {
                    errorMessage = "there was an error in authenticating your phone number"
                }
            }
        }
    }

    private func photoLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.custom("EBGaramond-Regular", size: 15))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }

    private func photoCircle(imageData: Data?, placeholderIcon: String, placeholderText: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.green, lineWidth: 3))
            } else {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08)).frame(width: size, height: size)
                    VStack(spacing: 8) {
                        Image(systemName: placeholderIcon)
                            .font(.custom("EBGaramond-Regular", size: 28))
                            .foregroundColor(.white.opacity(0.7))
                        Text(placeholderText)
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    /// Dismisses the keyboard by resigning first responder status on the active control.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 