import Foundation
import BackgroundTasks
import SwiftUI

/**
 * BackgroundUpdateManager - Handles background app refresh to keep cache fresh
 * 
 * This manager:
 * 1. Registers background tasks when app launches
 * 2. Schedules background cache updates when app goes to background
 * 3. Updates cache silently when system allows background execution
 * 4. Ensures users always have fresh data when opening the app
 */
@MainActor
class BackgroundUpdateManager: ObservableObject {
    static let shared = BackgroundUpdateManager()
    
    // Background task identifier
    private let backgroundTaskIdentifier = "com.joyThief.cacheupdates"
    
    @Published var isBackgroundUpdateEnabled = false
    @Published var lastBackgroundUpdate: Date?
    
    private init() {
        loadBackgroundUpdateSettings()
        // Load last check times from UserDefaults
        lastDayChecked = UserDefaults.standard.object(forKey: "background_last_day_checked") as? Date
        lastWeekChecked = UserDefaults.standard.object(forKey: "background_last_week_checked") as? Date
    }
    
    // MARK: - Background Task Registration
    
    func registerBackgroundTasks() {
        // Register the background app refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundCacheUpdate(task: task as! BGAppRefreshTask)
        }
        
        print("🔄 [BackgroundUpdateManager] Registered background task: \(backgroundTaskIdentifier)")
    }
    
    // MARK: - Background Update Scheduling
    
    func scheduleBackgroundCacheUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ [BackgroundUpdateManager] Scheduled background cache update")
        } catch {
            print("❌ [BackgroundUpdateManager] Failed to schedule background update: \(error)")
        }
    }
    
    // MARK: - Background Update Execution
    
    private func handleBackgroundCacheUpdate(task: BGAppRefreshTask) {
        // Schedule the next background update
        scheduleBackgroundCacheUpdate()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⏰ [BackgroundUpdateManager] Background task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform cache update
        Task {
            let success = await performBackgroundCacheUpdate()
            await MainActor.run {
                self.lastBackgroundUpdate = Date()
                self.saveBackgroundUpdateSettings()
            }
            task.setTaskCompleted(success: success)
            print(success ? "✅ [BackgroundUpdateManager] Background cache update completed" : "❌ [BackgroundUpdateManager] Background cache update failed")
        }
    }
    
    private func performBackgroundCacheUpdate() async -> Bool {
        // Only update if user is authenticated
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            print("⚠️ [BackgroundUpdateManager] No auth token available for background update")
            return false
        }
        
        // Check if cache is still fresh
        if DataCacheManager.shared.isCacheValid() {
            print("✅ [BackgroundUpdateManager] Cache is still fresh, skipping background update")
            return true
        }
        
        // Use DataCacheManager's background sync
        await DataCacheManager.shared.performBackgroundSync(token: token)
        
        print("✅ [BackgroundUpdateManager] Successfully updated cache in background")
        return true
    }
    
    // MARK: - Settings Persistence
    
    private func loadBackgroundUpdateSettings() {
        let userDefaults = UserDefaults.standard
        isBackgroundUpdateEnabled = userDefaults.bool(forKey: "background_updates_enabled")
        lastBackgroundUpdate = userDefaults.object(forKey: "last_background_update") as? Date
        
        // Enable by default for new users
        if !userDefaults.bool(forKey: "has_set_background_preference") {
            isBackgroundUpdateEnabled = true
            userDefaults.set(true, forKey: "has_set_background_preference")
            userDefaults.set(true, forKey: "background_updates_enabled")
        }
    }
    
    private func saveBackgroundUpdateSettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isBackgroundUpdateEnabled, forKey: "background_updates_enabled")
        if let lastUpdate = lastBackgroundUpdate {
            userDefaults.set(lastUpdate, forKey: "last_background_update")
        }
    }
    
    // MARK: - User Controls
    
    func setBackgroundUpdatesEnabled(_ enabled: Bool) {
        isBackgroundUpdateEnabled = enabled
        saveBackgroundUpdateSettings()
        
        if enabled {
            scheduleBackgroundCacheUpdate()
            print("✅ [BackgroundUpdateManager] Background updates enabled")
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            print("🛑 [BackgroundUpdateManager] Background updates disabled")
        }
    }
    
    // MARK: - App Lifecycle Integration
    
    // Track last day/week check to avoid redundant resets
    private var lastDayChecked: Date?
    private var lastWeekChecked: Date?
    
    func handleAppDidEnterBackground() {
        guard isBackgroundUpdateEnabled else { return }
        scheduleBackgroundCacheUpdate()
    }
    
    // Check if we need to reset daily/weekly habit data
    private func checkAndResetHabitData() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        // Check if we've crossed into a new day
        if let lastDay = lastDayChecked {
            let lastDayStart = calendar.startOfDay(for: lastDay)
            if today > lastDayStart {
                print("📅 [BackgroundUpdateManager] New day detected, resetting daily habit data")
                DataCacheManager.shared.resetDailyHabitData()
                lastDayChecked = now
            }
        } else {
            // First launch
            lastDayChecked = now
        }
        
        // Check if we've crossed into a new week
        let currentWeekday = calendar.component(.weekday, from: now)
        if let lastWeek = lastWeekChecked {
            let lastWeekday = calendar.component(.weekday, from: lastWeek)
            // Sunday is weekday 1, check if we've passed Sunday since last check
            if (lastWeekday > 1 && currentWeekday == 1) || 
               (calendar.dateComponents([.weekOfYear], from: lastWeek, to: now).weekOfYear ?? 0 > 0) {
                print("📅 [BackgroundUpdateManager] New week detected, resetting weekly habit data")
                DataCacheManager.shared.resetWeeklyHabitData()
                lastWeekChecked = now
            }
        } else {
            // First launch
            lastWeekChecked = now
        }
        
        // Persist the check times
        UserDefaults.standard.set(lastDayChecked, forKey: "background_last_day_checked")
        UserDefaults.standard.set(lastWeekChecked, forKey: "background_last_week_checked")
    }
    
    func handleAppWillEnterForeground() {
        let cacheManager = DataCacheManager.shared
        let authManager  = AuthenticationManager.shared

        // If the app is currently running its preload flow, avoid triggering another one.
        if authManager.needsPreloading {
            print("⏭️ [BackgroundUpdateManager] App is already preloading – skip additional refresh check")
            return
        }
        
        // Check if we need to reset daily or weekly habit data
        checkAndResetHabitData()

        // Determine if the cache is stale (invalid) OR has not been synced recently ( > 3 h )
        let needsRefresh: Bool = {
            if !cacheManager.isCacheValid() { return true }
            guard let lastSync = cacheManager.lastSyncTime else { return true }
            // Treat cache as stale only if it hasn't synced for 3 hours
            return Date().timeIntervalSince(lastSync) > 3 * 60 * 60 // 3-hour threshold
        }()

        if needsRefresh {
            print("⚠️ [BackgroundUpdateManager] Cache deemed stale/old → trigger splash reload")
            // Flag SplashScreenView to run its preload sequence again
            authManager.needsPreloading = true
        } else {
            print("✅ [BackgroundUpdateManager] Cache still fresh, no splash reload needed")
        }
    }
} 