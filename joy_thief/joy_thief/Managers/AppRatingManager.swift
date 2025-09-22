import Foundation
import StoreKit

@MainActor
final class AppRatingManager: ObservableObject {
    static let shared = AppRatingManager()
    
    // MARK: - UserDefaults Keys
    private enum UserDefaultsKeys {
        static let lastRatingPromptDate = "lastRatingPromptDate"
        static let totalVerificationCount = "totalVerificationCount"
        static let hasUserRatedApp = "hasUserRatedApp"
        static let promptCount = "ratingPromptCount"
        static let appVersion = "lastRatedAppVersion"
    }
    
    // MARK: - Configuration
    private let minimumVerificationsBeforePrompt = 3
    private let daysBetweenPrompts = 7
    private let maximumPromptsPerVersion = 3
    
    // MARK: - Properties
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Increments the verification count and checks if rating should be shown
    func recordVerification() {
        let currentCount = userDefaults.integer(forKey: UserDefaultsKeys.totalVerificationCount)
        userDefaults.set(currentCount + 1, forKey: UserDefaultsKeys.totalVerificationCount)
    }
    
    /// Determines if the rating prompt should be shown
    func shouldShowRatingPrompt() -> Bool {
        // Debug mode - uncomment for testing
        // return true
        
        // Check if user has already rated this version
        if hasUserRatedCurrentVersion() {
            return false
        }
        
        // Check verification count
        let verificationCount = userDefaults.integer(forKey: UserDefaultsKeys.totalVerificationCount)
        if verificationCount < minimumVerificationsBeforePrompt {
            return false
        }
        
        // Check prompt count for this version
        let promptCount = userDefaults.integer(forKey: UserDefaultsKeys.promptCount)
        if promptCount >= maximumPromptsPerVersion {
            return false
        }
        
        // Check days since last prompt
        if let lastPromptDate = userDefaults.object(forKey: UserDefaultsKeys.lastRatingPromptDate) as? Date {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            if daysSinceLastPrompt < daysBetweenPrompts {
                return false
            }
        }
        
        return true
    }
    
    /// Shows the rating prompt if conditions are met
    @MainActor
    func requestRatingIfAppropriate(completion: @escaping () -> Void) {
        if shouldShowRatingPrompt() {
            // Record the prompt
            userDefaults.set(Date(), forKey: UserDefaultsKeys.lastRatingPromptDate)
            let currentPromptCount = userDefaults.integer(forKey: UserDefaultsKeys.promptCount)
            userDefaults.set(currentPromptCount + 1, forKey: UserDefaultsKeys.promptCount)
            
            // Show the rating prompt
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                
                // Small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SKStoreReviewController.requestReview(in: windowScene)
                    
                    // Call completion after a delay to allow the rating popup to appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        completion()
                    }
                }
            } else {
                // If we can't get the window scene, just continue
                completion()
            }
        } else {
            // If we shouldn't show rating, continue immediately
            completion()
        }
    }
    
    /// Marks that the user has rated the current version
    func markUserHasRated() {
        userDefaults.set(true, forKey: UserDefaultsKeys.hasUserRatedApp)
        if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            userDefaults.set(currentVersion, forKey: UserDefaultsKeys.appVersion)
        }
    }
    
    // MARK: - Private Methods
    
    private func hasUserRatedCurrentVersion() -> Bool {
        guard let ratedVersion = userDefaults.string(forKey: UserDefaultsKeys.appVersion),
              let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return false
        }
        
        return ratedVersion == currentVersion && userDefaults.bool(forKey: UserDefaultsKeys.hasUserRatedApp)
    }
    
    /// Reset rating data (useful for testing)
    func resetRatingData() {
        #if DEBUG
        userDefaults.removeObject(forKey: UserDefaultsKeys.lastRatingPromptDate)
        userDefaults.removeObject(forKey: UserDefaultsKeys.totalVerificationCount)
        userDefaults.removeObject(forKey: UserDefaultsKeys.hasUserRatedApp)
        userDefaults.removeObject(forKey: UserDefaultsKeys.promptCount)
        userDefaults.removeObject(forKey: UserDefaultsKeys.appVersion)
        #endif
    }
}