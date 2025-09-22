import SwiftUI
import Foundation

// MARK: - Onboarding Helpers
// Extracted from ContentView to keep onboarding logic separate

extension ContentView {
    
    // Helper function to get the most reliable onboarding state
    func getEffectiveOnboardingState() -> Int? {
        
        // First, try to use cached onboarding state (available immediately on startup)
        if let cachedState = authManager.cachedOnboardingState {
            return cachedState
        }
        
        // If no currentUser yet but we're authenticated, try startup cached state
        if authManager.currentUser == nil && authManager.isAuthenticated {
            if let startupState = authManager.startupCachedOnboardingState {
                return startupState
            }
        }
        
        // Fall back to current user's onboarding state (from backend)
        if let userState = authManager.currentUser?.onboardingState {
            return userState
        }
        
        return nil
    }
    
    // Helper function to determine if onboarding intro should be shown
    func shouldShowOnboardingIntro() -> Bool {
        guard let state = getEffectiveOnboardingState() else {
            return false
        }
        
        guard state <= 4 else {
            return false
        }
        
        // Protection against race condition: don't show onboarding intro if signup was just completed
        let timeSinceSignup = recentSignupCompletionTime?.timeIntervalSinceNow ?? -999
        let shouldSuppressOnboarding = timeSinceSignup > -5.0 // within last 5 seconds
        
        if shouldSuppressOnboarding {
            return false
        } else {
            return true
        }
    }
} 