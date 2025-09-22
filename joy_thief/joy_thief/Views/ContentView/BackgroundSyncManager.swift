import SwiftUI
import Foundation

// MARK: - Background Sync Management
// Extracted from ContentView to keep sync logic separate

extension ContentView {
    
    // NEW: Threshold after which we consider the app "inactive" and force a data refresh (currently 3 hours)
    var inactivityRefreshThreshold: TimeInterval { 3 * 60 * 60 } // 3 hours

    func handleAppBecameActive() {
        // Only process if user is authenticated
        guard authManager.isAuthenticated,
              let userId = authManager.currentUser?.id,
              let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        // ENHANCED: Check for time-based updates when app becomes active
        let lastBackgroundTimeCopy = lastBackgroundTime
        let threshold = inactivityRefreshThreshold
        
        Task.detached(priority: .background) {
            
            // Check if we need to refresh weekly progress (for new weeks or long backgrounding)
            await HabitManager.shared.checkForNewWeekAndRefreshProgress(userId: userId, token: token)
            
            // Also check if we've been backgrounded for a significant time and need fresh data
            if let lastBackground = lastBackgroundTimeCopy,
               Date().timeIntervalSince(lastBackground) > threshold {
                
                // Refresh verification data if we've been away for a while
                await HabitManager.shared.refreshVerificationData(for: "all")
            }
            
            // IMMEDIATE: Refresh friend requests when app becomes active for up-to-date notification dots
            print("🔴 [ContentView] App became active, refreshing friend requests...")
            await UnifiedFriendManager.shared.loadFriendRequestsInBackground(token: token)
        }
    }
    
    func initializeBackgroundSync() {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        Task {
            // ENHANCED: Add delay before starting background sync timer to avoid sync during startup
            try? await Task.sleep(nanoseconds: 0)
            
            // Only start the timer for periodic background sync, don't perform immediate sync
            if !dataCacheManager.isBackgroundTimerActive {     // <-- NEW
                await dataCacheManager.startBackgroundSyncTimerOnly(token: token)
            }
            
            // IMMEDIATE: Load friend requests for notification dots as part of core preloading
            // This ensures red dots appear immediately on app start
            await loadFriendRequestsForNotificationDots(token: token)
            
            // Start periodic refresh timer for friend requests (every 2 minutes)
            startFriendRequestsPeriodicRefresh(token: token)
        }
    }
    
    /// Load friend requests immediately for notification dots (core preloading)
    func loadFriendRequestsForNotificationDots(token: String) async {
        print("🔴 [ContentView] Loading friend requests for immediate notification dots...")
        
        // Load friend requests directly for immediate UI feedback
        await UnifiedFriendManager.shared.loadFriendRequestsInBackground(token: token)
        print("✅ [ContentView] Friend requests loaded for notification dots")
        
        // Also sync from any cached data
        UnifiedFriendManager.shared.forceRefreshFromPreloadedData()
    }
    
    /// Start periodic refresh timer for friend requests to keep notification dots up-to-date
    func startFriendRequestsPeriodicRefresh(token: String) {
        Task {
            while !Task.isCancelled {
                // Wait 2 minutes before each refresh
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
                
                // Only refresh if user is still authenticated
                guard authManager.isAuthenticated,
                      let currentToken = AuthenticationManager.shared.storedAuthToken else {
                    print("🔴 [ContentView] User no longer authenticated, stopping friend requests refresh")
                    break
                }
                
                // Refresh friend requests in background
                print("🔄 [ContentView] Periodic friend requests refresh...")
                await UnifiedFriendManager.shared.loadFriendRequestsInBackground(token: currentToken)
            }
        }
    }

    func performQuickSync() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        guard let last = dataCacheManager.lastSync,
              Date().timeIntervalSince(last) > inactivityRefreshThreshold else {      // <-- 3-hour freshness window
            return
        }
        await dataCacheManager.performBackgroundSync(token: token)
    }
} 