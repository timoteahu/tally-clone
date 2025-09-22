//
//  CompactHealthVerificationView.swift
//  joy_thief
//
//  Health verification view with dual options: simple verification or photo sharing
//

import SwiftUI
import StoreKit

struct CompactHealthVerificationView: View {
    let habit: Habit
    let placeholderText: String
    let habitType: String
    @Binding var selfieImageData: Data?
    @Binding var contentImageData: Data?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    @Binding var isVerifying: Bool
    @Binding var firstImageTaken: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    let resetVerificationState: () -> Void
    let onBack: (() -> Void)? // closure to flip card back
    let onVerify: (() -> Void)? // Add the missing onVerify callback
    @ObservedObject var habitManager: HabitManager // Add habitManager to call markHabitAsVerified
    
    @State private var showThankYouAlert = false
    
    @StateObject private var verificationManager = HabitVerificationManager()
    
    // Cache UIImage instances to prevent recreation on re-renders
    @State private var cachedSelfieImage: UIImage?
    @State private var cachedContentImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // Back button at the top left, but moved further down
            HStack {
                Button(action: { onBack?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))
                        Text("back")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                    }
                    .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.top, cardHeight * 0.05)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Center all main content horizontally, with a small top margin
            VStack(alignment: .center, spacing: 0) {
                if hasPhotos {
                    photoPreviewView
                    .padding(.trailing, cardWidth * 0.1)
                } else {
                    verificationOptionsView
                        .padding(.trailing, cardWidth * 0.1) // Add right padding to push content left
                        .padding(.top, cardHeight * 0.02)
                }
            }
            .padding(.top, cardHeight * 0.025)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .alert("Thank you for verifying", isPresented: $showThankYouAlert) {
            Button("OK", role: .cancel) {
                // Record verification and check if we should show rating
                AppRatingManager.shared.recordVerification()
                AppRatingManager.shared.requestRatingIfAppropriate {
                    // Navigate to feed after rating popup (or immediately if not shown)
                    NotificationCenter.default.post(name: NSNotification.Name("navigateToFeed"), object: nil)
                }
            }
        }
        .onChange(of: selfieImageData) { _, newData in
            cachedSelfieImage = newData.flatMap { UIImage(data: $0) }
        }
        .onChange(of: contentImageData) { _, newData in
            cachedContentImage = newData.flatMap { UIImage(data: $0) }
        }
        .onAppear {
            // Initialize cached images on appear
            cachedSelfieImage = selfieImageData.flatMap { UIImage(data: $0) }
            cachedContentImage = contentImageData.flatMap { UIImage(data: $0) }
        }
    }
    
    // MARK: - Computed Properties
    
    private var hasPhotos: Bool {
        selfieImageData != nil && contentImageData != nil
    }
    
    private var healthDisplayName: String {
        switch habitType {
        case "health_steps": return "Steps"
        case "health_walking_running_distance": return "Distance"
        case "health_flights_climbed": return "Flights climbed"
        case "health_exercise_minutes": return "Exercise"
        case "health_cycling_distance": return "Cycling"
        case "health_sleep_hours": return "Sleep"
        case "health_calories_burned": return "Calories"
        case "health_mindful_minutes": return "Mindfulness"
        default: return "Health"
        }
    }
    
    // MARK: - Photo Preview View (matches CompactImageVerificationView exactly)
    
    private var photoPreviewView: some View {
        VStack(spacing: 0) {
            // Two-image layout side by side (exact same structure as CompactImageVerificationView)
            HStack(spacing: cardWidth * 0.02) {
                // Selfie image section
                VStack(spacing: cardHeight * 0.01) {
                    Text("selfie")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 2)
                    
                    Group {
                        if let cachedImage = cachedSelfieImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                .drawingGroup()
                                .animation(.easeInOut(duration: 0.2), value: cachedSelfieImage)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                
                // Content image sectionxf
                VStack(spacing: cardHeight * 0.01) {
                    Text("activity")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 2)
                    
                    Group {
                        if let cachedImage = cachedContentImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth * 0.42, height: cardHeight * 0.42)
                                .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardWidth * 0.03)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                .drawingGroup()
                                .animation(.easeInOut(duration: 0.2), value: cachedContentImage)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.horizontal, cardWidth * 0.02)
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Reduce vertical gap between images and buttons for better fit
            Spacer().frame(height: cardHeight * 0.04)
            
            // Action buttons at the bottom (exact same styling as CompactImageVerificationView)
            VStack(spacing: cardHeight * 0.015) {
                // Verify button
                Button(action: { 
                    Task { 
                        print("🔍 [HealthVerification] Starting verification with habitType: '\(habitType)'")
                        print("🔍 [HealthVerification] Habit ID: \(habit.id)")
                        await verifyWithBothImages(
                            habitType, 
                            getSuccessMessage(habitType)
                        ) 
                    } 
                }) {
                    Text(isVerifying ? "verifying..." : "verify")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                        .padding(.vertical, cardHeight * 0.02)
                        .padding(.horizontal, cardWidth * 0.15)
                        .background(Color.clear)
                        .overlay(
                        RoundedRectangle(cornerRadius: cardWidth * 0.015)
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(cardWidth * 0.015)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .disabled(isVerifying)
                
                Button(action: { 
                    resetVerificationState()
                }) {
                    HStack(spacing: cardWidth * 0.02) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                        Text("retake")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                    }
                    .padding(.horizontal, cardWidth * 0.15)
                    .background(Color.clear)
                    .foregroundColor(.white)
                    .cornerRadius(cardWidth * 0.015)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, cardWidth * 0.02)
            .padding(.bottom, cardHeight * 0.02)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Verification Options View (natural centering like CompactImageVerificationView)
    
    private var verificationOptionsView: some View {
        VStack(spacing: 0) {
            // Health goal achievement message (naturally centered in available space)
            VStack(spacing: cardHeight * 0.02) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: cardWidth * 0.12))
                    .foregroundColor(.white)
                    .opacity(0.9)
                
                Text("\(healthDisplayName) goal achieved!")
                    .font(.custom("EB Garamond", size: cardWidth * 0.07).weight(.medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Choose how to verify")
                    .font(.custom("EB Garamond", size: cardWidth * 0.045))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            // Space between message and buttons
            Spacer().frame(height: cardHeight * 0.04)
            
            // Verification options (exact same styling as other verification buttons)
            VStack(spacing: cardHeight * 0.015) {
                // Quick verify button (no photos) - This should NOT go through post preview
                Button(action: {
                    Task {
                        await verifyWithoutPhotos()
                    }
                }) {
                    Text(isVerifying ? "verifying..." : "verify quickly")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                        .padding(.vertical, cardHeight * 0.02)
                        .padding(.horizontal, cardWidth * 0.08)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: cardWidth * 0.015)
                                .stroke(Color.white, lineWidth: 1.5)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(cardWidth * 0.015)
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .disabled(isVerifying)
                
                // Photo verify button - This WILL go through post preview
                Button(action: {
                    cameraMode = .selfie
                    firstImageTaken = false
                    showingCamera = true
                }) {
                    HStack(spacing: cardWidth * 0.02) {
                        Text("verify with an optional photo!")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038)).fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: cardWidth * 0.04, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, cardWidth * 0.08)
                    .background(Color.clear)
                    .foregroundColor(.white)
                    .cornerRadius(cardWidth * 0.015)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .padding(.top, cardHeight * 0.02) // shift down
                }
                .disabled(isVerifying)
            }
            .padding(.horizontal, cardWidth * 0.02)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Helper Methods
    
    private func verifyWithoutPhotos() async {
        print("🔍 [HealthVerification] Starting quick verification (no photos) with habitType: '\(habitType)'")
        print("🔍 [HealthVerification] Habit ID: \(habit.id)")
        
        guard let token = getAuthToken() else {
            print("❌ No auth token available")
            return
        }
        
        isVerifying = true
        // Don't set defer here - we want to control when isVerifying becomes false
        
        do {
            let result = try await verificationManager.verifyHealthHabit(
                habitId: habit.id,
                token: token
            )
            
            if result.isVerified {
                print("✅ Health habit verified without photos - showing success animation")
                
                // CRITICAL: Call markHabitAsVerified FIRST (like other verification flows)
                await MainActor.run {
                    if let verification = result.verification {
                        habitManager.markHabitAsVerified(habitId: habit.id, verificationData: verification)
                    } else {
                        habitManager.markHabitAsVerified(habitId: habit.id)
                    }
                }
                
                // Play success haptic feedback
                HapticFeedbackManager.shared.playVerificationSuccess()
                
                // Keep isVerifying = true to show success animation, then delay the completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Set isVerifying to false to show "verified" state
                    self.isVerifying = false
                    
                    // Call onVerify callback to trigger cache update and make card disappear
                    self.onVerify?()
                    
                    // Show the thank you alert after the animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showThankYouAlert = true
                    }
                }
            } else {
                print("❌ Health habit verification failed")
                isVerifying = false
            }
        } catch {
            print("❌ Health habit verification error: \(error)")
            isVerifying = false
        }
    }
    
    private func getAuthToken() -> String? {
        return AuthenticationManager.shared.storedAuthToken
    }
} 