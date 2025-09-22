import SwiftUI
import UIKit

// MARK: – Onboarding Root
/// A full-screen onboarding sequence that replicates the splash screen's matte wave
/// background and shows a series of marketing lines with a typewriter effect.
/// After the last line ("please enter your phone number") has been shown it
/// transitions straight into the existing `MultiStepSignupView` so the user can
/// continue the sign-up flow.
struct OnboardingView: View {
    /// Current visual state of the onboarding flow
    private enum Phase: String, CaseIterable { 
        case terms, onboarding
        
        // Convert to raw value for UserDefaults storage
        var rawValue: String {
            switch self {
            case .terms: return "terms"
            case .onboarding: return "onboarding"
            }
        }
        
        // Initialize from raw value
        init?(rawValue: String) {
            switch rawValue {
            case "terms": self = .terms
            case "onboarding": self = .onboarding
            // Handle legacy values
            case "intro", "signup": self = .onboarding
            default: return nil
            }
        }
    }
    @State private var phase: Phase = .terms

    // Callback when onboarding is completed
    var onOnboardingComplete: (() -> Void)? 
    
    private let onboardingPhaseKey = "onboarding_phase_cache"
    
    private func savePhase(_ phase: Phase) {
        UserDefaults.standard.set(phase.rawValue, forKey: onboardingPhaseKey)
    }
    
    private func loadSavedPhase() -> Phase {
        guard let savedRawValue = UserDefaults.standard.string(forKey: onboardingPhaseKey),
              let savedPhase = Phase(rawValue: savedRawValue) else {
            return .terms // Default to terms if no cached phase
        }
        return savedPhase
    }
    
    private func clearPhaseCache() {
        UserDefaults.standard.removeObject(forKey: onboardingPhaseKey)
    }

    var body: some View {
        ZStack {
            // Unified gradient background used across the app
            AppBackground()

            switch phase {
            case .terms:
                TermsOfServiceGateView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        // Go to onboarding intro after TOS
                        phase = .onboarding
                        savePhase(.onboarding)
                    }
                }
                .transition(.opacity)

            case .onboarding:
                OnboardingIntroView(
                    // Start at state 2 (habit creation) to skip the intro text
                    onFinished: {
                        clearPhaseCache()
                        onOnboardingComplete?()
                    }, initialOnboardingState: 2
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Restore cached phase when view appears
            let savedPhase = loadSavedPhase()
            if savedPhase != phase {
                phase = savedPhase
            }
        }
    }
} 
