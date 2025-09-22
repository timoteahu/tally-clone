import Foundation
import SwiftUI

/**
 * DataCacheManager - Intelligent Cache System for App Data
 * 
 * This manager implements a cache-first loading approach that dramatically improves app startup time:
 * 
 * VERIFICATION DATA CACHING:
 * - All verification data (verifiedHabitsToday, habitVerifications, weeklyVerifiedHabits) 
 *   is loaded from the /sync/delta endpoint and cached locally
 * - Cache is valid for 3 hours, preventing unnecessary network calls during shorter sessions
 * - Individual verification refresh calls (refreshVerificationData) only execute 
 *   when cache is stale, eliminating redundant API calls during startup
 * 
 * CACHE-FIRST FLOW:
 * 1. Load from cache instantly (< 50ms) for immediate UI population
 * 2. Background sync only occurs if cache is 15+ minutes old
 * 3. Fallback to network only if cache is completely missing/invalid
 * 
 * This approach reduces startup time from ~2-3 seconds to ~100-300ms for repeat app launches.
 */
class DataCacheManager: ObservableObject {
    @MainActor static let shared = DataCacheManager()
    /// True whenever the periodic background Task is active. Replaces the old flag that was never mutated.
    var isBackgroundTimerActive: Bool { periodicSyncTask != nil }
    
    // MARK: - Cache Configuration
    private let cacheExpirationMinutes: TimeInterval = 180 // Cache expires after 3 hours
    private let backgroundSyncInterval: TimeInterval = 5 * 60 // 5 minutes
    private let userDefaults = UserDefaults.standard
    
    // MARK: - NEW: User Activity Tracking
    private var lastUserInteraction: Date = Date()
    private let userActivityGracePeriod: TimeInterval = 30 // Don't sync if user was active in last 30 seconds
    private var isUserActivelyInteracting: Bool = false
    
    // MARK: - Cache Keys
    internal struct CacheKeys {
        static let habits = "habits"
        static let friends = "friends"
        static let friendsWithStripe = "friends_with_stripe"
        static let feedPosts = "feed_posts"
        static let paymentMethod = "payment_method"
        static let customHabitTypes = "custom_habit_types"
        static let availableHabitTypes = "available_habit_types"
        static let onboardingState = "onboarding_state"
        static let userProfile = "user_profile"
        static let weeklyProgress = "weekly_progress"
        static let verifiedHabitsToday = "verified_habits_today"
        static let habitVerifications = "habit_verifications"
        static let weeklyVerifiedHabits = "weekly_verified_habits"
        static let friendRequests = "friend_requests"
        static let stagedDeletions = "staged_deletions"
        static let contactsOnTally = "contacts_on_tally"
        
        // Metadata keys for cache validation
        static let lastSyncTimestamp = "last_sync_timestamp_v2"
        static let lastSyncHash = "last_sync_hash_v2"
        static let deltaTimestamp = "delta_timestamp_v2"
    }
    
    // MARK: - Configuration
    private let cacheValidityDuration: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - URLSession
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    // MARK: - Cache Analytics
    @Published var cacheHitRate: Double = 0.0
    private var totalRequests: Int = 0
    private var cacheHits: Int = 0
    
    // MARK: - Zero-Penalty Habit Count (Cache-Based with Optimization)
    
    // Cached count to avoid recalculation
    private var _cachedZeroPenaltyCount: Int?
    private var _lastHabitsHash: String?
    
    /// Get zero-penalty picture habit count with intelligent caching
    func getZeroPenaltyHabitCount() -> Int {
        // Check if we have a valid cached count
        if let cachedCount = _cachedZeroPenaltyCount,
           let currentHash = getHabitsHash(),
           currentHash == _lastHabitsHash {
            return cachedCount // Return cached value - no computation needed
        }
        
        // Recalculate only when habits have changed
        let newCount = calculateZeroPenaltyCount()
        _cachedZeroPenaltyCount = newCount
        _lastHabitsHash = getHabitsHash()
        
        return newCount
    }
    
    /// Calculate zero-penalty count (only called when cache is invalid)
    private func calculateZeroPenaltyCount() -> Int {
        guard let cachedData = loadCacheOnlyForStartup(),
              let habits = cachedData.habits else {
            return 0
        }
        
        // Optimized filtering - early return for better performance
        let pictureHabitTypes: Set<String> = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
        
        var count = 0
        for habit in habits {
            // Early continue for non-picture habits (most efficient)
            let isPictureHabit = pictureHabitTypes.contains(habit.habitType) || habit.habitType.hasPrefix("custom_")
            guard isPictureHabit else { continue }
            
            // Check zero-penalty status
            if habit.isZeroPenalty == true || habit.penaltyAmount == 0.0 {
                count += 1
                // Early exit if we already have 3+ (optimization for UI logic)
                if count >= 3 { break }
            }
        }
        
        return count
    }
    
    /// Generate habits hash for cache invalidation (lightweight)
    private func getHabitsHash() -> String? {
        guard let habits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) else {
            return nil
        }
        
        // Only hash picture habits for efficiency
        let pictureHabitTypes: Set<String> = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
        let relevantHabits = habits.filter { habit in
            pictureHabitTypes.contains(habit.habitType) || habit.habitType.hasPrefix("custom_")
        }
        
        // Create lightweight hash from relevant data only
        let hashString = relevantHabits.map { "\($0.id)_\($0.isZeroPenalty ?? false)_\($0.penaltyAmount)" }.joined(separator: "|")
        return String(hashString.hashValue)
    }
    
    /// Invalidate cached count when habits change (called from HabitManager)
    func invalidateZeroPenaltyCount() {
        _cachedZeroPenaltyCount = nil
        _lastHabitsHash = nil
        
        // Trigger UI updates
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    /// Update zero-penalty count when habits change (optimized)
    func updateZeroPenaltyCountAfterHabitChange() {
        // Invalidate cache to force recalculation on next access
        invalidateZeroPenaltyCount()
    }
    
    // MARK: - Cache Status
    
    
    // MARK: - Private Properties
    private(set) var lastSync: Date?
    private var periodicSyncTask: Task<Void, Never>?
    private var syncToken: String?
    
    private init() {
        loadLastSyncTime()
    }
    
    // MARK: - NEW: User Activity Tracking
    
    /// Call this whenever user interacts with weekly progress UI
    func trackUserInteraction() {
        lastUserInteraction = Date()
        isUserActivelyInteracting = true
        
        // Reset interaction flag after a delay
        Task {
            try? await Task.sleep(nanoseconds: UInt64(userActivityGracePeriod * 1_000_000_000))
            await MainActor.run {
                self.isUserActivelyInteracting = false
            }
        }
    }
    
    /// Check if user was recently active (to avoid sync interference)
    public var shouldSkipSyncDueToUserActivity: Bool {
        let timeSinceLastInteraction = Date().timeIntervalSince(lastUserInteraction)
        return isUserActivelyInteracting || timeSinceLastInteraction < userActivityGracePeriod
    }
    
    // MARK: - Public API
    
    
    /// Load data instantly from cache, then update in background
    func loadDataWithCacheFirst(token: String) async -> CachedAppData? {
        totalRequests += 1
        
        // Step 1: Load from cache instantly (should be < 50ms)
        let cachedData = loadFromCache()
        if let cachedData = cachedData {
            cacheHits += 1
            updateCacheHitRate()
            
            // Step 2: ENHANCED - Only sync if cache is over 1 hour old (much more aggressive)
            // This dramatically reduces unnecessary sync calls during startup
            if let lastSync = lastSyncTime,
               Date().timeIntervalSince(lastSync) > (cacheExpirationMinutes * 60 * 2) { // 1 hour instead of 15 minutes
                Task.detached(priority: .background) {
                    // Use background priority to avoid blocking startup
                    await self.performBackgroundSync(token: token)
                }
            }
            
            return cachedData
        }
        
        // Step 3: If no cache, do full load and cache it
        do {
            let preloadManager = await PreloadManager.shared
            let preloadedData = try await preloadManager.preloadAllAppData(token: token)
            let appData = convertToAppData(preloadedData)
            saveToCache(appData)
            return appData
        } catch {
            return nil
        }
    }
    
    /// ENHANCED: Load cache instantly without any sync (for ultra-fast startup)
    func loadCacheOnlyForStartup() -> CachedAppData? {
        
        // Load from cache instantly - no background sync at all
        let cachedData = loadFromCache()
        if let cachedData = cachedData {
            cacheHits += 1
            updateCacheHitRate()
            // Update timestamp to NOW so subsequent foreground checks consider it fresh.
            refreshCacheTimestamp()
            print("⚡ [DataCacheManager] Loaded cache in startup mode - no background sync")
            return cachedData
        }
        
        return nil
    }
    
    /// ENHANCED: Schedule deferred sync after UI has loaded
    func scheduleDeferredSync(token: String, afterDelay delay: TimeInterval = 2.0) {
        // ENHANCED: Prevent duplicate deferred sync tasks
        guard !isSyncing else {
            print("⏭️ [DataCacheManager] Sync already in progress, skipping deferred sync")
            return
        }
        
        Task.detached(priority: .background) {
            // Wait for UI to settlexf
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Check again if sync is needed and not already running
            let currentlySyncing = await MainActor.run { self.isSyncing }
            guard !currentlySyncing else {
                print("⏭️ [DataCacheManager] Sync started while waiting, skipping deferred sync")
                return
            }
            
            // Only sync if cache is getting old
            if let lastSync = self.lastSyncTime,
               Date().timeIntervalSince(lastSync) > (self.cacheExpirationMinutes * 60 * 0.5) {
                await self.performBackgroundSync(token: token)
            } else {
                print("⏭️ [DataCacheManager] Cache still fresh, skipping deferred sync")
            }
        }
    }
    
    /// Check if cached data is still fresh
    func isCacheValid() -> Bool {
        guard let lastSync = userDefaults.object(forKey: CacheKeys.lastSyncTimestamp) as? Date else {
            return false
        }
        
        let elapsed = Date().timeIntervalSince(lastSync)
        return elapsed < cacheExpirationMinutes * 60
    }
    
    /// Force refresh all data from server
    func forceRefresh(token: String) async -> CachedAppData? {
        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }
        
        do {
            let preloadManager = await PreloadManager.shared
            // Fetch the freshest data from the server
            let preloadedData = try await preloadManager.preloadAllAppData(token: token)
            
            // Update all in-memory managers FIRST so the UI reflects changes instantly
            await preloadManager.applyPreloadedDataToManagers(
                preloadedData,
                habitManager: HabitManager.shared,
                friendsManager: FriendsManager.shared,
                paymentManager: PaymentManager.shared,
                feedManager: FeedManager.shared,
                customHabitManager: CustomHabitManager.shared
            )
            
            // Persist the freshly fetched data to disk cache
            let appData = convertToAppData(preloadedData)
            saveToCache(appData)
            
            return appData
        } catch {
            print("Force refresh failed: \(error)")
            return nil
        }
    }
    
    /// Get delta changes since last sync (optimized for minimal data transfer)
    func getDeltaChanges(token: String, since: Date) async -> DeltaResponse? {
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/sync/delta") else {
                return nil
            }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Add If-Modified-Since header
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            request.setValue(formatter.string(from: since), forHTTPHeaderField: "If-Modified-Since")
            
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            
            if httpResponse.statusCode == 304 {
                // No changes since last sync
                return DeltaResponse.noChanges
            } else if httpResponse.statusCode == 200 {
                // Parse delta changes
                let deltaResponse = try JSONDecoder().decode(DeltaResponse.self, from: data)
                return deltaResponse
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    /// Clear all cached data (useful for logout)
    func clearCache() {
        let keys = [
            CacheKeys.habits, CacheKeys.friends, CacheKeys.feedPosts,
            CacheKeys.customHabitTypes, CacheKeys.paymentMethod,
            CacheKeys.userProfile, CacheKeys.weeklyProgress,
            CacheKeys.onboardingState, CacheKeys.availableHabitTypes,
            CacheKeys.lastSyncTimestamp, CacheKeys.lastSyncHash, CacheKeys.deltaTimestamp,
            // NEW: Clear verification cache keys
            CacheKeys.verifiedHabitsToday, CacheKeys.habitVerifications,
            CacheKeys.weeklyVerifiedHabits,
            CacheKeys.friendRequests, CacheKeys.stagedDeletions,
            CacheKeys.contactsOnTally
        ]
        
        keys.forEach { userDefaults.removeObject(forKey: $0) }
        
        // Reset metrics
        cacheHits = 0
        totalRequests = 0
        updateCacheHitRate()
        lastSyncTime = nil
    }
    
    /// Invalidate specific cache entries when data changes
    func invalidateHabitsCache() {
        userDefaults.removeObject(forKey: CacheKeys.habits)
        userDefaults.removeObject(forKey: CacheKeys.weeklyProgress)
    }
    
    func invalidateFriendsCache() {
        userDefaults.removeObject(forKey: CacheKeys.friends)
    }
    
    func invalidateFeedCache() {
        userDefaults.removeObject(forKey: CacheKeys.feedPosts)
    }
    
    func invalidateUserProfileCache() {
        userDefaults.removeObject(forKey: CacheKeys.userProfile)
    }
    
    /// Update user profile in cache (e.g., after avatar upload)
    func updateUserProfileInCache(_ userProfile: PreloadManager.UserProfileData) {
        // Load current cache or create minimal cache if none exists
        let currentCache = loadFromCache()
        
        // Create updated cache with new user profile
        let updatedCache = CachedAppData(
            habits: currentCache?.habits ?? [],
            friends: currentCache?.friends ?? [],
            friendsWithStripe: currentCache?.friendsWithStripe ?? [],
            feedPosts: currentCache?.feedPosts ?? [],
            customHabitTypes: currentCache?.customHabitTypes ?? [],
            paymentMethod: currentCache?.paymentMethod,
            userProfile: userProfile, // Update with new profile data
            weeklyProgress: currentCache?.weeklyProgress ?? [],
            onboardingState: currentCache?.onboardingState,
            availableHabitTypes: currentCache?.availableHabitTypes,
            verifiedHabitsToday: currentCache?.verifiedHabitsToday ?? [:],
            habitVerifications: currentCache?.habitVerifications ?? [:],
            weeklyVerifiedHabits: currentCache?.weeklyVerifiedHabits ?? [:],
            stagedDeletions: currentCache?.stagedDeletions ?? [:],
            contactsOnTally: currentCache?.contactsOnTally ?? []
        )
        
        // Save updated cache
        saveToCache(updatedCache)
        
        if currentCache == nil {
            print("✅ [DataCacheManager] Created new cache with user profile")
        } else {
            print("✅ [DataCacheManager] Updated user profile in cache with avatar URLs")
        }
    }
    
    /// Mark cache as stale to force refresh on next load
    func markCacheAsStale() {
        userDefaults.removeObject(forKey: CacheKeys.lastSyncTimestamp)
        lastSyncTime = nil
    }
    
    /// Invalidate verification cache when data changes
    func invalidateVerificationCache() {
        userDefaults.removeObject(forKey: CacheKeys.verifiedHabitsToday)
        userDefaults.removeObject(forKey: CacheKeys.habitVerifications)
        userDefaults.removeObject(forKey: CacheKeys.weeklyVerifiedHabits)
    }
    
    /// Save data to cache - made public for external access
    func saveToCache(_ data: CachedAppData) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Save each data type to cache
        saveCachedData(data.habits, key: CacheKeys.habits)
        saveCachedData(data.friends, key: CacheKeys.friends)
        saveCachedData(data.friendsWithStripe, key: CacheKeys.friendsWithStripe)
        saveCachedData(data.feedPosts, key: CacheKeys.feedPosts)
        saveCachedData(data.customHabitTypes, key: CacheKeys.customHabitTypes)
        saveCachedData(data.paymentMethod, key: CacheKeys.paymentMethod)
        saveCachedData(data.userProfile, key: CacheKeys.userProfile)
        saveCachedData(data.weeklyProgress, key: CacheKeys.weeklyProgress)
        saveCachedData(data.availableHabitTypes, key: CacheKeys.availableHabitTypes)
        
        // NEW: Save verification data to cache
        saveCachedData(data.verifiedHabitsToday, key: CacheKeys.verifiedHabitsToday)
        saveCachedData(data.habitVerifications, key: CacheKeys.habitVerifications)
        saveCachedData(data.weeklyVerifiedHabits, key: CacheKeys.weeklyVerifiedHabits)
        
        if let onboardingState = data.onboardingState {
            userDefaults.set(onboardingState, forKey: CacheKeys.onboardingState)
        }
        
        // Update metadata
        let now = Date()
        userDefaults.set(now, forKey: CacheKeys.lastSyncTimestamp)
        Task { @MainActor in
            lastSyncTime = now
        }
        
        // Force the user defaults to be written to disk immediately to avoid data loss
        // when the user force-quits the app shortly after first launch. Without an
        // explicit synchronise the system may postpone the write, which caused the
        // splash screen to re-appear on the very next launch because no valid
        // cache timestamp had been persisted yet.
        userDefaults.synchronize()
        
        let _ = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    // MARK: - Cache Operations
    
    private func loadFromCache() -> CachedAppData? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check if cache is valid first
        guard isCacheValid() else {
            return nil
        }
        
        // Ensure lastSyncTime is populated (it may be nil if app started from cold launch and we haven't synced yet)
        if lastSyncTime == nil {
            lastSyncTime = userDefaults.object(forKey: CacheKeys.lastSyncTimestamp) as? Date
        }
        
        // Load all cached data with explicit type casting
        let habits: [PreloadManager.HabitData]? = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self)
        let friends: [PreloadManager.FriendData]? = loadCachedData(key: CacheKeys.friends, type: [PreloadManager.FriendData].self)
        let friendsWithStripe: [PreloadManager.FriendWithStripeData]? = loadCachedData(key: CacheKeys.friendsWithStripe, type: [PreloadManager.FriendWithStripeData].self)
        let feedPosts: [PreloadManager.FeedPostData]? = loadCachedData(key: CacheKeys.feedPosts, type: [PreloadManager.FeedPostData].self)
        let customHabitTypes: [PreloadManager.CustomHabitTypeData]? = loadCachedData(key: CacheKeys.customHabitTypes, type: [PreloadManager.CustomHabitTypeData].self)
        let paymentMethod: PreloadManager.PaymentMethodData? = loadCachedData(key: CacheKeys.paymentMethod, type: PreloadManager.PaymentMethodData.self)
        let userProfile: PreloadManager.UserProfileData? = loadCachedData(key: CacheKeys.userProfile, type: PreloadManager.UserProfileData.self)
        let weeklyProgress: [PreloadManager.WeeklyProgressData]? = loadCachedData(key: CacheKeys.weeklyProgress, type: [PreloadManager.WeeklyProgressData].self)
        let onboardingState = userDefaults.object(forKey: CacheKeys.onboardingState) as? Int
        
        // Load verification data from cache with explicit types
        let verifiedHabitsToday: [String: Bool]? = loadVerifiedHabitsToday()
        let habitVerifications: [String: [CachedHabitVerification]]? = loadHabitVerifications()
        let weeklyVerifiedHabits: [String: [String: Bool]]? = loadWeeklyVerifiedHabits()
        
        // Load availableHabitTypes from cache
        let availableHabitTypes: PreloadManager.AvailableHabitTypesData? = loadCachedData(key: CacheKeys.availableHabitTypes, type: PreloadManager.AvailableHabitTypesData.self)
        
        // Load staged deletions from cache with explicit type
        let stagedDeletions: [String: StagedDeletionInfo]? = loadStagedDeletions()
        
        // Load contacts on tally from cache with explicit type
        let contactsOnTally: [PreloadManager.ContactOnTallyData]? = loadCachedData(key: CacheKeys.contactsOnTally, type: [PreloadManager.ContactOnTallyData].self)
        
        let _ = CFAbsoluteTimeGetCurrent() - startTime
        
        return CachedAppData(
            habits: habits,
            friends: friends,
            friendsWithStripe: friendsWithStripe,
            feedPosts: feedPosts,
            customHabitTypes: customHabitTypes,
            paymentMethod: paymentMethod,
            userProfile: userProfile,
            weeklyProgress: weeklyProgress,
            onboardingState: onboardingState,
            availableHabitTypes: availableHabitTypes,
            verifiedHabitsToday: verifiedHabitsToday,
            habitVerifications: habitVerifications,
            weeklyVerifiedHabits: weeklyVerifiedHabits,
            stagedDeletions: stagedDeletions,
            contactsOnTally: contactsOnTally
        )
    }
    
    private func loadCachedData<T: Codable>(key: String, type: T.Type) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    
    /// Generic method to save Codable data to UserDefaults
    private func saveCachedData<T: Codable>(_ data: T?, key: String) {
        if let data = data {
            do {
                let encoder = JSONEncoder()
                let encodedData = try encoder.encode(data)
                userDefaults.set(encodedData, forKey: key)
            } catch {
                print("❌ [DataCacheManager] Error encoding data for key \(key): \(error)")
            }
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    // MARK: - Specialized Loading Methods
    
    private func loadVerifiedHabitsToday() -> [String: Bool]? {
        guard let data = userDefaults.data(forKey: CacheKeys.verifiedHabitsToday) else { return nil }
        return try? JSONDecoder().decode([String: Bool].self, from: data)
    }
    
    private func loadHabitVerifications() -> [String: [CachedHabitVerification]]? {
        guard let data = userDefaults.data(forKey: CacheKeys.habitVerifications) else { return nil }
        return try? JSONDecoder().decode([String: [CachedHabitVerification]].self, from: data)
    }
    
    private func loadWeeklyVerifiedHabits() -> [String: [String: Bool]]? {
        guard let data = userDefaults.data(forKey: CacheKeys.weeklyVerifiedHabits) else { return nil }
        return try? JSONDecoder().decode([String: [String: Bool]].self, from: data)
    }
    
    private func loadStagedDeletions() -> [String: StagedDeletionInfo]? {
        guard let data = userDefaults.data(forKey: CacheKeys.stagedDeletions) else { return nil }
        return try? JSONDecoder().decode([String: StagedDeletionInfo].self, from: data)
    }
    
    // MARK: - Background Sync
    
    func startBackgroundSync(token: String) async {
        syncToken = token
        await setupBackgroundSync()
        await performBackgroundSync(token: token)       // immediate first run
    }
    
    /// ENHANCED: Start background sync timer only, without immediate sync
    func startBackgroundSyncTimerOnly(token: String) async {
        guard periodicSyncTask == nil else {
            print("⏭️ Background sync already active")
            return
        }
        syncToken = token
        await setupBackgroundSync()          // uses the new async loop
    }
    
    func stopBackgroundSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        syncToken = nil
        print("🛑 [DataCacheManager] Background sync stopped")
    }

    
    func performBackgroundSync(token: String) async {
        // NEW: Skip sync if user is actively interacting with the app
        if shouldSkipSyncDueToUserActivity {
            print("👤 [DataCacheManager] Skipping background sync - user is actively interacting")
            return
        }
        
        // NOTE: Removed the eager reset of `verifiedHabitsToday` here because it caused a brief
        // UI flicker where habits that had already been verified earlier in the day would momentarily
        // re-appear as incomplete while the sync was in-flight. Instead we now keep the existing
        // verification state until fresh data arrives. If the backend ever needs to revoke a
        // verification, the updated payload will override the old value when `processVerificationData(_:)`
        // completes.
        
        defer { lastSync = Date() }
        guard !isSyncing else {
            print("⏭️ [DataCacheManager] Sync already in progress, skipping")
            return 
        }
        
        print("🔄 [DataCacheManager] Starting background sync...")
        await MainActor.run {
            isSyncing = true
        }
        defer { 
            Task { @MainActor in
                isSyncing = false
            }
            print("✅ [DataCacheManager] Background sync completed")
        }
        
        // Try delta sync first if we have a valid last sync time
        if let lastSync = lastSyncTime, isCacheValid() {
            print("🔄 [DataCacheManager] Attempting delta sync from: \(lastSync)")
            if let deltaChanges = await getDeltaChanges(token: token, since: lastSync) {
                await applyDeltaChanges(deltaChanges, token: token)
                return
            } else {
                print("⚠️ [DataCacheManager] Delta sync failed, falling back to full refresh")
            }
        } else {
            print("🔄 [DataCacheManager] No valid cache or last sync time, performing full refresh")
        }
        
        // Fallback to full refresh if delta sync fails or no cache
        // NEW: Only do full refresh if user isn't actively using weekly progress features
        if !shouldSkipSyncDueToUserActivity {
            _ = await forceRefresh(token: token)
        } else {
            print("👤 [DataCacheManager] Skipping full refresh - user is actively interacting")
        }
    }
    
    private func setupBackgroundSync() async {
        // 1️⃣ Cancel any existing loop
        periodicSyncTask?.cancel()
        
        // 2️⃣ Spin up a new detached loop
        periodicSyncTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            
            // Convert seconds ➜ nanoseconds once for efficiency
            let nanos = UInt64(self.backgroundSyncInterval * 1_000_000_000)
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                await self.performPeriodicBackgroundSync()
            }
        }
        
        print("⏰ [DataCacheManager] Background sync *task* started (interval \(backgroundSyncInterval)s)")
    }
    
    private func performPeriodicBackgroundSync() async {
        guard let token = syncToken else { 
            print("⚠️ [DataCacheManager] No sync token available for periodic sync")
            return 
        }
        
        // NEW: Enhanced logging and user activity check
        let timeSinceLastInteraction = Date().timeIntervalSince(lastUserInteraction)
        if shouldSkipSyncDueToUserActivity {
            print("👤 [DataCacheManager] Skipping periodic sync - user active \(Int(timeSinceLastInteraction))s ago")
            return
        }
        
        print("⏰ [DataCacheManager] Performing periodic background sync")
        await performBackgroundSync(token: token)
    }
    
    private func applyDeltaChanges(_ changes: DeltaResponse, token: String) async {
        // Only apply changes if there are any
        if changes.hasChanges {
            print("📦 [DataCacheManager] Applying delta changes...")
            
            // NEW: Use smart delta application instead of full refresh
            await applySmartDeltaChanges(changes, token: token)
        } else {
            print("✅ [DataCacheManager] No changes to apply")
            // Update last sync time even if no changes
            let now = Date()
            userDefaults.set(now, forKey: CacheKeys.lastSyncTimestamp)
            await MainActor.run {
                lastSyncTime = now
            }
        }
    }
    
    /// NEW: Smart delta application that preserves user interactions
    private func applySmartDeltaChanges(_ changes: DeltaResponse, token: String) async {
        // If user is actively interacting, only apply non-disruptive updates
        if shouldSkipSyncDueToUserActivity {
            print("👤 [DataCacheManager] User is active - applying minimal delta changes only")
            
            // Only update cache, don't refresh managers to avoid UI disruption
            let now = Date()
            userDefaults.set(now, forKey: CacheKeys.lastSyncTimestamp)
            await MainActor.run {
                lastSyncTime = now
            }
            return
        }
        
        // If user is not active, apply full delta changes as before
        print("📦 [DataCacheManager] User is inactive - applying full delta changes")
        _ = await forceRefresh(token: token)
    }
    
    // MARK: - Utilities
    
    private func convertToAppData(_ preloadedData: PreloadManager.PreloadedData) -> CachedAppData {
        // Convert habitVerifications from VerificationData to CachedHabitVerification
        let convertedHabitVerifications = preloadedData.habitVerifications?.mapValues { verificationDataArray in
            verificationDataArray.map { verificationData in
                CachedHabitVerification(
                    id: verificationData.id,
                    habitId: verificationData.habitId,
                    userId: verificationData.userId,
                    verificationType: verificationData.verificationType,
                    verifiedAt: verificationData.verifiedAt,
                    status: verificationData.status,
                    verificationResult: verificationData.verificationResult,
                    imageUrl: verificationData.imageUrl,
                    selfieImageUrl: verificationData.selfieImageUrl,
                    imageVerificationId: verificationData.imageVerificationId,
                    imageFilename: verificationData.imageFilename,
                    selfieImageFilename: verificationData.selfieImageFilename,
                    verificationImageData: nil, // Image data will be loaded separately
                    selfieImageData: nil // Selfie image data will be loaded separately
                )
            }
        }
        
        return CachedAppData(
            habits: preloadedData.habits,
            friends: preloadedData.friends,
            friendsWithStripe: preloadedData.friendsWithStripe,
            feedPosts: preloadedData.feedPosts,
            customHabitTypes: preloadedData.customHabitTypes,
            paymentMethod: preloadedData.paymentMethod,
            userProfile: preloadedData.userProfile,
            weeklyProgress: preloadedData.weeklyProgress,
            onboardingState: preloadedData.onboardingState,
            availableHabitTypes: preloadedData.availableHabitTypes,
            verifiedHabitsToday: preloadedData.verifiedHabitsToday,
            habitVerifications: convertedHabitVerifications,
            weeklyVerifiedHabits: preloadedData.weeklyVerifiedHabits,
            stagedDeletions: preloadedData.stagedDeletions,
            contactsOnTally: preloadedData.contactsOnTally
        )
    }
    
    private func loadLastSyncTime() {
        lastSyncTime = userDefaults.object(forKey: CacheKeys.lastSyncTimestamp) as? Date
    }
    
    private func updateCacheHitRate() {
        let rate = totalRequests > 0 ? Double(cacheHits) / Double(totalRequests) : 0.0
        Task { @MainActor in
            cacheHitRate = rate
        }
    }
    
    deinit {
        // Ensure any detached background task is cancelled on deallocation
        periodicSyncTask?.cancel()
    }
    
    // MARK: - Cache Invalidation
    
    func invalidateWeeklyProgressCache() {
        // Clear weekly progress related cache entries using correct key names
        userDefaults.removeObject(forKey: CacheKeys.weeklyProgress)
        // Preserve the global timestamp to avoid unnecessary splash reloads
        refreshCacheTimestamp()
        
        print("🗑️ [DataCacheManager] Invalidated weekly progress cache")
    }
    
    func invalidateAllCache() {
        // Clear all cache entries
        clearCache()
        print("🗑️ [DataCacheManager] Invalidated all cache")
    }
    
    // MARK: - NEW: Smart Cache Update Methods
    
    /// Update habits cache with new habit instead of invalidating
    func updateHabitsCache(with newHabit: Habit) {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        
        // Convert new habit to HabitData format - match exact field order
        let newHabitData = PreloadManager.HabitData(
            id: newHabit.id,
            name: newHabit.name,
            recipientId: newHabit.recipientId,
            habitType: newHabit.habitType,
            weekdays: newHabit.isDailyHabit ? newHabit.weekdays : nil, // Only set for daily habits
            penaltyAmount: newHabit.penaltyAmount,
            userId: newHabit.userId,
            createdAt: newHabit.createdAt,
            updatedAt: newHabit.updatedAt,
            studyDurationMinutes: newHabit.studyDurationMinutes,
            screenTimeLimitMinutes: newHabit.screenTimeLimitMinutes,
            restrictedApps: newHabit.restrictedApps,
            alarmTime: newHabit.alarmTime,
            isPrivate: newHabit.isPrivate,
            customHabitTypeId: newHabit.customHabitTypeId,
            habitScheduleType: newHabit.habitScheduleType,
            weeklyTarget: newHabit.weeklyTarget,
            weekStartDay: newHabit.weekStartDay,
            commitTarget: newHabit.commitTarget,
            todayCommitCount: newHabit.todayCommitCount,
            currentWeekCommitCount: newHabit.currentWeekCommitCount,
            todayGamingHours: nil,  // Gaming hours are fetched separately
            dailyLimitHours: newHabit.dailyLimitHours,
            hourlyPenaltyRate: newHabit.hourlyPenaltyRate,
            healthTargetValue: newHabit.healthTargetValue,
            healthTargetUnit: newHabit.healthTargetUnit,
            healthDataType: newHabit.healthDataType,
            isZeroPenalty: newHabit.isZeroPenalty
        )
        
        // Add new habit to cached habits
        currentHabits.append(newHabitData)
        
        // Save updated habits back to cache
        saveCachedData(currentHabits, key: CacheKeys.habits)
        
        // Keep cache timestamp valid
        refreshCacheTimestamp()
        
        print("✅ [DataCacheManager] Added new habit '\(newHabit.name)' to cache")
    }
    
    /// Update habits cache when habit is modified
    func updateExistingHabitInCache(with updatedHabit: Habit) {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        
        // Find and update the habit
        if let index = currentHabits.firstIndex(where: { $0.id == updatedHabit.id }) {
            let updatedHabitData = PreloadManager.HabitData(
                id: updatedHabit.id,
                name: updatedHabit.name,
                recipientId: updatedHabit.recipientId,
                habitType: updatedHabit.habitType,
                weekdays: updatedHabit.isDailyHabit ? updatedHabit.weekdays : nil, // Only set for daily habits
                penaltyAmount: updatedHabit.penaltyAmount,
                userId: updatedHabit.userId,
                createdAt: updatedHabit.createdAt,
                updatedAt: updatedHabit.updatedAt,
                studyDurationMinutes: updatedHabit.studyDurationMinutes,
                screenTimeLimitMinutes: updatedHabit.screenTimeLimitMinutes,
                restrictedApps: updatedHabit.restrictedApps,
                alarmTime: updatedHabit.alarmTime,
                isPrivate: updatedHabit.isPrivate,
                customHabitTypeId: updatedHabit.customHabitTypeId,
                habitScheduleType: updatedHabit.habitScheduleType,
                weeklyTarget: updatedHabit.weeklyTarget,
                weekStartDay: updatedHabit.weekStartDay,
                commitTarget: updatedHabit.commitTarget,
                todayCommitCount: updatedHabit.todayCommitCount,
                currentWeekCommitCount: updatedHabit.currentWeekCommitCount,
                todayGamingHours: nil,  // Gaming hours are fetched separately
                dailyLimitHours: updatedHabit.dailyLimitHours,
                hourlyPenaltyRate: updatedHabit.hourlyPenaltyRate,
                healthTargetValue: updatedHabit.healthTargetValue,
                healthTargetUnit: updatedHabit.healthTargetUnit,
                healthDataType: updatedHabit.healthDataType,
                isZeroPenalty: updatedHabit.isZeroPenalty
            )
            
            currentHabits[index] = updatedHabitData
            
            // Save updated habits back to cache
            saveCachedData(currentHabits, key: CacheKeys.habits)
            
            // Keep cache timestamp valid
            refreshCacheTimestamp()
            
            print("✅ [DataCacheManager] Updated habit '\(updatedHabit.name)' in cache")
        } else {
            print("⚠️ [DataCacheManager] Habit '\(updatedHabit.name)' not found in cache for update")
        }
    }
    
    /// Remove habit from cache when deleted
    func removeHabitFromCache(habitId: String) {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        
        // Check if the habit being removed was a zero-penalty picture habit
        let removedHabit = currentHabits.first { $0.id == habitId }
        let wasZeroPenaltyPictureHabit: Bool
        if let habit = removedHabit {
            let pictureHabitTypes = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
            let isPictureHabit = pictureHabitTypes.contains(habit.habitType) || habit.habitType.hasPrefix("custom_")
            let isZeroPenalty = habit.isZeroPenalty == true || habit.penaltyAmount == 0.0
            wasZeroPenaltyPictureHabit = isPictureHabit && isZeroPenalty
        } else {
            wasZeroPenaltyPictureHabit = false
        }
        
        // Remove the habit
        currentHabits.removeAll { $0.id == habitId }
        
        // Save updated habits back to cache
        saveCachedData(currentHabits, key: CacheKeys.habits)
        
        // Update zero-penalty count if needed
        if wasZeroPenaltyPictureHabit {
            updateZeroPenaltyCountAfterHabitChange()
        }
        
        print("✅ [DataCacheManager] Removed habit with ID '\(habitId)' from cache")
    }
    
    /// Update GitHub commit count in cache
    func updateHabitCommitCount(habitId: String, count: Int) {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        
        // Find and update the habit
        if let index = currentHabits.firstIndex(where: { $0.id == habitId }) {
            let oldHabit = currentHabits[index]
            
            // Create new habit with updated commit count
            let updatedHabit = PreloadManager.HabitData(
                id: oldHabit.id,
                name: oldHabit.name,
                recipientId: oldHabit.recipientId,
                habitType: oldHabit.habitType,
                weekdays: oldHabit.weekdays,
                penaltyAmount: oldHabit.penaltyAmount,
                userId: oldHabit.userId,
                createdAt: oldHabit.createdAt,
                updatedAt: oldHabit.updatedAt,
                studyDurationMinutes: oldHabit.studyDurationMinutes,
                screenTimeLimitMinutes: oldHabit.screenTimeLimitMinutes,
                restrictedApps: oldHabit.restrictedApps,
                alarmTime: oldHabit.alarmTime,
                isPrivate: oldHabit.isPrivate,
                customHabitTypeId: oldHabit.customHabitTypeId,
                habitScheduleType: oldHabit.habitScheduleType,
                weeklyTarget: oldHabit.weeklyTarget,
                weekStartDay: oldHabit.weekStartDay,
                commitTarget: oldHabit.commitTarget,
                todayCommitCount: count,  // Updated value
                currentWeekCommitCount: oldHabit.currentWeekCommitCount,
                todayGamingHours: oldHabit.todayGamingHours,
                dailyLimitHours: oldHabit.dailyLimitHours,
                hourlyPenaltyRate: oldHabit.hourlyPenaltyRate,
                healthTargetValue: oldHabit.healthTargetValue,
                healthTargetUnit: oldHabit.healthTargetUnit,
                healthDataType: oldHabit.healthDataType,
                isZeroPenalty: oldHabit.isZeroPenalty
            )
            
            currentHabits[index] = updatedHabit
            
            // Save updated habits back to cache
            saveCachedData(currentHabits, key: CacheKeys.habits)
            
            // Keep cache timestamp valid
            refreshCacheTimestamp()
            
            print("✅ [DataCacheManager] Updated commit count for habit '\(habitId)': \(count)")
        }
    }
    
    /// Update gaming hours in cache
    func updateHabitGamingHours(habitId: String, hours: Double) {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        
        // Find and update the habit
        if let index = currentHabits.firstIndex(where: { $0.id == habitId }) {
            let oldHabit = currentHabits[index]
            
            // Create new habit with updated gaming hours
            let updatedHabit = PreloadManager.HabitData(
                id: oldHabit.id,
                name: oldHabit.name,
                recipientId: oldHabit.recipientId,
                habitType: oldHabit.habitType,
                weekdays: oldHabit.weekdays,
                penaltyAmount: oldHabit.penaltyAmount,
                userId: oldHabit.userId,
                createdAt: oldHabit.createdAt,
                updatedAt: oldHabit.updatedAt,
                studyDurationMinutes: oldHabit.studyDurationMinutes,
                screenTimeLimitMinutes: oldHabit.screenTimeLimitMinutes,
                restrictedApps: oldHabit.restrictedApps,
                alarmTime: oldHabit.alarmTime,
                isPrivate: oldHabit.isPrivate,
                customHabitTypeId: oldHabit.customHabitTypeId,
                habitScheduleType: oldHabit.habitScheduleType,
                weeklyTarget: oldHabit.weeklyTarget,
                weekStartDay: oldHabit.weekStartDay,
                commitTarget: oldHabit.commitTarget,
                todayCommitCount: oldHabit.todayCommitCount,
                currentWeekCommitCount: oldHabit.currentWeekCommitCount,
                todayGamingHours: hours,  // Updated value
                dailyLimitHours: oldHabit.dailyLimitHours,
                hourlyPenaltyRate: oldHabit.hourlyPenaltyRate,
                healthTargetValue: oldHabit.healthTargetValue,
                healthTargetUnit: oldHabit.healthTargetUnit,
                healthDataType: oldHabit.healthDataType,
                isZeroPenalty: oldHabit.isZeroPenalty
            )
            
            currentHabits[index] = updatedHabit
            
            // Save updated habits back to cache
            saveCachedData(currentHabits, key: CacheKeys.habits)
            
            // Keep cache timestamp valid
            refreshCacheTimestamp()
            
            print("✅ [DataCacheManager] Updated gaming hours for habit '\(habitId)': \(hours)")
        }
    }
    
    /// Reset daily habit data (commit counts and gaming hours) at end of day
    func resetDailyHabitData() {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        var habitsUpdated = false
        
        // Reset daily data for each habit
        for (index, habit) in currentHabits.enumerated() {
            var needsUpdate = false
            var updatedCommitCount: Int? = habit.todayCommitCount
            var updatedGamingHours: Double? = habit.todayGamingHours
            
            // Reset GitHub commit count for daily habits
            if habit.habitType == "github_commits" && habit.habitScheduleType != "weekly" {
                updatedCommitCount = 0
                needsUpdate = true
            }
            
            // Reset gaming hours for daily gaming habits
            if (habit.habitType == "league_of_legends" || habit.habitType == "valorant") && habit.habitScheduleType != "weekly" {
                updatedGamingHours = 0
                needsUpdate = true
            }
            
            if needsUpdate {
                // Create new habit with reset values
                let updatedHabit = PreloadManager.HabitData(
                    id: habit.id,
                    name: habit.name,
                    recipientId: habit.recipientId,
                    habitType: habit.habitType,
                    weekdays: habit.weekdays,
                    penaltyAmount: habit.penaltyAmount,
                    userId: habit.userId,
                    createdAt: habit.createdAt,
                    updatedAt: habit.updatedAt,
                    studyDurationMinutes: habit.studyDurationMinutes,
                    screenTimeLimitMinutes: habit.screenTimeLimitMinutes,
                    restrictedApps: habit.restrictedApps,
                    alarmTime: habit.alarmTime,
                    isPrivate: habit.isPrivate,
                    customHabitTypeId: habit.customHabitTypeId,
                    habitScheduleType: habit.habitScheduleType,
                    weeklyTarget: habit.weeklyTarget,
                    weekStartDay: habit.weekStartDay,
                    commitTarget: habit.commitTarget,
                    todayCommitCount: updatedCommitCount,
                    currentWeekCommitCount: habit.currentWeekCommitCount,
                    todayGamingHours: updatedGamingHours,
                    dailyLimitHours: habit.dailyLimitHours,
                    hourlyPenaltyRate: habit.hourlyPenaltyRate,
                    healthTargetValue: habit.healthTargetValue,
                    healthTargetUnit: habit.healthTargetUnit,
                    healthDataType: habit.healthDataType,
                    isZeroPenalty: habit.isZeroPenalty
                )
                
                currentHabits[index] = updatedHabit
                habitsUpdated = true
            }
        }
        
        if habitsUpdated {
            // Save updated habits back to cache
            saveCachedData(currentHabits, key: CacheKeys.habits)
            refreshCacheTimestamp()
            print("🔄 [DataCacheManager] Reset daily habit data (commit counts and gaming hours)")
        }
    }
    
    /// Reset weekly habit data at end of week
    func resetWeeklyHabitData() {
        // Load current habits from cache
        var currentHabits = loadCachedData(key: CacheKeys.habits, type: [PreloadManager.HabitData].self) ?? []
        var habitsUpdated = false
        
        // Reset weekly data for each habit
        for (index, habit) in currentHabits.enumerated() {
            var needsUpdate = false
            var updatedCommitCount: Int? = habit.todayCommitCount
            var updatedGamingHours: Double? = habit.todayGamingHours
            
            // Reset GitHub commit count for weekly habits
            if habit.habitType == "github_commits" && habit.habitScheduleType == "weekly" {
                updatedCommitCount = 0
                needsUpdate = true
            }
            
            // Reset gaming hours for weekly gaming habits
            if (habit.habitType == "league_of_legends" || habit.habitType == "valorant") && habit.habitScheduleType == "weekly" {
                updatedGamingHours = 0
                needsUpdate = true
            }
            
            if needsUpdate {
                // Create new habit with reset values
                let updatedHabit = PreloadManager.HabitData(
                    id: habit.id,
                    name: habit.name,
                    recipientId: habit.recipientId,
                    habitType: habit.habitType,
                    weekdays: habit.weekdays,
                    penaltyAmount: habit.penaltyAmount,
                    userId: habit.userId,
                    createdAt: habit.createdAt,
                    updatedAt: habit.updatedAt,
                    studyDurationMinutes: habit.studyDurationMinutes,
                    screenTimeLimitMinutes: habit.screenTimeLimitMinutes,
                    restrictedApps: habit.restrictedApps,
                    alarmTime: habit.alarmTime,
                    isPrivate: habit.isPrivate,
                    customHabitTypeId: habit.customHabitTypeId,
                    habitScheduleType: habit.habitScheduleType,
                    weeklyTarget: habit.weeklyTarget,
                    weekStartDay: habit.weekStartDay,
                    commitTarget: habit.commitTarget,
                    todayCommitCount: updatedCommitCount,
                    currentWeekCommitCount: habit.currentWeekCommitCount,
                    todayGamingHours: updatedGamingHours,
                    dailyLimitHours: habit.dailyLimitHours,
                    hourlyPenaltyRate: habit.hourlyPenaltyRate,
                    healthTargetValue: habit.healthTargetValue,
                    healthTargetUnit: habit.healthTargetUnit,
                    healthDataType: habit.healthDataType,
                    isZeroPenalty: habit.isZeroPenalty
                )
                
                currentHabits[index] = updatedHabit
                habitsUpdated = true
            }
        }
        
        if habitsUpdated {
            // Save updated habits back to cache
            saveCachedData(currentHabits, key: CacheKeys.habits)
            refreshCacheTimestamp()
            print("🔄 [DataCacheManager] Reset weekly habit data (commit counts and gaming hours)")
        }
    }
    
    /// Refresh cache timestamp without invalidating data (keeps cache valid)
    func refreshCacheTimestamp() {
        let now = Date()
        userDefaults.set(now, forKey: CacheKeys.lastSyncTimestamp)
        Task { @MainActor in
            lastSyncTime = now
        }
        print("🔄 [DataCacheManager] Refreshed cache timestamp to keep cache valid")
    }
    
    /// Update friends with Stripe Connect cache with new data
    func updateFriendsWithStripeCache(_ updatedFriendsWithStripe: [PreloadManager.FriendWithStripeData]) async {
        // Update the cache with the new friends data
        saveCachedData(updatedFriendsWithStripe, key: CacheKeys.friendsWithStripe)
        
        // Keep cache timestamp valid
        refreshCacheTimestamp()
        
        print("✅ [DataCacheManager] Updated friends with Stripe cache with \(updatedFriendsWithStripe.count) friends")
    }
    
    /// Cache staged deletion data
    func cacheStagedDeletions(_ stagedDeletions: [String: StagedDeletionInfo]?) {
        if let stagedDeletions = stagedDeletions {
        saveCachedData(stagedDeletions, key: CacheKeys.stagedDeletions)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.stagedDeletions)
        }
    }
    
    /// Cache contacts on tally data
    func cacheContactsOnTally(_ contactsOnTally: [PreloadManager.ContactOnTallyData]?) {
        if let contactsOnTally = contactsOnTally {
            saveCachedData(contactsOnTally, key: CacheKeys.contactsOnTally)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.contactsOnTally)
        }
    }
    
    /// Get cached staged deletion data
    func getCachedStagedDeletions() -> [String: StagedDeletionInfo] {
        return loadStagedDeletions() ?? [:]
    }
    
    /// Check if a specific habit is scheduled for deletion
    func isHabitScheduledForDeletion(_ habitId: String) -> StagedDeletionInfo? {
        let stagedDeletions = getCachedStagedDeletions()
        return stagedDeletions[habitId]
    }
    
    /// Update staged deletion status for a specific habit (for when user restores)
    func updateStagedDeletionStatus(for habitId: String, deleted: Bool) {
        var stagedDeletions = getCachedStagedDeletions()
        
        if deleted {
            // Mark as deleted/restored by removing from cache
            stagedDeletions.removeValue(forKey: habitId)
        }
        
        saveCachedData(stagedDeletions, key: CacheKeys.stagedDeletions)
        print("✅ [DataCacheManager] Updated staged deletion status for habit \(habitId): deleted=\(deleted)")
    }
    
    // MARK: - Feed Cache Update Methods
    
    /// Add new feed post to cache when verification creates a post
    func addFeedPostToCache(_ newPost: PreloadManager.FeedPostData) {
        // Load current feed posts from cache
        var currentPosts = loadCachedData(key: CacheKeys.feedPosts, type: [PreloadManager.FeedPostData].self) ?? []
        
        // Add new post at the beginning (newest first)
        currentPosts.insert(newPost, at: 0)
        
        // Limit cache size to prevent memory bloat (keep last 50 posts)
        if currentPosts.count > 50 {
            currentPosts = Array(currentPosts.prefix(50))
        }
        
        // Save updated posts back to cache
        saveCachedData(currentPosts, key: CacheKeys.feedPosts)
        
        // Keep cache timestamp valid
        refreshCacheTimestamp()
        
        print("✅ [DataCacheManager] Added new feed post from verification to cache (total: \(currentPosts.count) posts)")
    }
    
    /// Update feed cache only if posts actually changed (prevents unnecessary invalidation)
    func updateFeedCacheIfChanged(_ newPosts: [PreloadManager.FeedPostData]) {
        let currentPosts = loadCachedData(key: CacheKeys.feedPosts, type: [PreloadManager.FeedPostData].self) ?? []
        
        // Check if posts actually changed
        let postsChanged = newPosts.count != currentPosts.count || 
                          !newPosts.elementsEqual(currentPosts) { post1, post2 in
                              post1.postId == post2.postId && 
                              post1.createdAt == post2.createdAt
                          }
        
        if postsChanged {
            saveCachedData(newPosts, key: CacheKeys.feedPosts)
            refreshCacheTimestamp()
            print("🔄 [DataCacheManager] Feed posts changed, updated cache")
        } else {
            print("✅ [DataCacheManager] Feed posts unchanged, kept cache")
        }
    }
    
    /// Incrementally sync the feed cache with the latest data from the backend.
    /// - Important: Instead of blindly overwriting everything, this method now calculates the minimal
    ///   set of changes (additions, removals, and updates) and only mutates those, preserving
    ///   unchanged posts for efficiency and log clarity.
    func updateFeedCacheWithFreshData(_ newPosts: [PreloadManager.FeedPostData]) {
        var currentPosts = loadCachedData(key: CacheKeys.feedPosts, type: [PreloadManager.FeedPostData].self) ?? []

        // Quick maps for look-ups by postId
        let currentMap = Dictionary(uniqueKeysWithValues: currentPosts.map { ($0.postId, $0) })
        let newMap     = Dictionary(uniqueKeysWithValues: newPosts.map { ($0.postId, $0) })

        var added   = 0
        var updated = 0
        var removed = 0

        // 1️⃣ Add or update posts that exist in the new fetch
        for post in newPosts {
            if let existing = currentMap[post.postId] {
                // Check if any meaningful field changed (caption, createdAt, streak, comments count)
                let isChanged = existing.caption != post.caption ||
                                existing.createdAt != post.createdAt ||
                                existing.streak != post.streak ||
                                existing.comments.count != post.comments.count

                if isChanged {
                    // Replace the existing entry at its current index to keep order stable
                    if let idx = currentPosts.firstIndex(where: { $0.postId == post.postId }) {
                        currentPosts[idx] = post
                        updated += 1
                    }
                }
            } else {
                // New post – insert at the beginning to respect backend ordering (newest first)
                currentPosts.insert(post, at: 0)
                added += 1
            }
        }

        // 2️⃣ Remove posts that disappeared from the backend response
        for post in currentPosts where newMap[post.postId] == nil {
            currentPosts.removeAll { $0.postId == post.postId }
            removed += 1
        }

        // 3️⃣ Enforce max cache size (oldest last)
        if currentPosts.count > 50 {
            currentPosts = Array(currentPosts.prefix(50))
        }

        // 4️⃣ Persist only if anything actually changed
        if added > 0 || updated > 0 || removed > 0 {
            saveCachedData(currentPosts, key: CacheKeys.feedPosts)
            refreshCacheTimestamp()
            print("📱 [DataCacheManager] Feed cache synced (added: \(added), updated: \(updated), removed: \(removed), total: \(currentPosts.count))")
        } else {
            // Nothing changed – keep timestamp the same to avoid unnecessary churn
            print("✅ [DataCacheManager] Feed cache already up-to-date – no changes detected")
        }
    }
    
    /// Update cache for a single post with its comments (granular update)
    func updateIndividualPostCache(_ post: PreloadManager.FeedPostData) {
        // Load current feed posts from cache
        var currentPosts = loadCachedData(key: CacheKeys.feedPosts, type: [PreloadManager.FeedPostData].self) ?? []
        
        // Find and update the specific post
        if let index = currentPosts.firstIndex(where: { $0.postId == post.postId }) {
            currentPosts[index] = post
            
            // Save updated posts back to cache
            saveCachedData(currentPosts, key: CacheKeys.feedPosts)
            refreshCacheTimestamp()
            
            print("💾 [DataCacheManager] Updated individual post cache for post \(post.postId.prefix(8)) with \(post.comments.count) comments")
        } else {
            print("⚠️ [DataCacheManager] Post \(post.postId.prefix(8)) not found in cache for individual update")
        }
    }
    
    // MARK: - Weekly Progress Cache Update Methods
    
    /// Update weekly progress cache for a specific habit when verified
    func updateWeeklyProgressCache(for habitId: String, incrementCompletion: Bool = true) {
        // NEW: Track user interaction with weekly progress
        trackUserInteraction()
        
        // Load current weekly progress from cache
        var currentWeeklyProgress = loadCachedData(key: CacheKeys.weeklyProgress, type: [PreloadManager.WeeklyProgressData].self) ?? []
        
        // Find the progress data for this habit
        if let index = currentWeeklyProgress.firstIndex(where: { $0.habitId == habitId }) {
            let currentProgress = currentWeeklyProgress[index]
            
            // Only increment if we're adding a new completion
            let newCompletions = incrementCompletion ? currentProgress.currentCompletions + 1 : currentProgress.currentCompletions
            let isComplete = newCompletions >= currentProgress.targetCompletions
            
            // Update the progress data
            let updatedProgress = PreloadManager.WeeklyProgressData(
                habitId: currentProgress.habitId,
                currentCompletions: newCompletions,
                targetCompletions: currentProgress.targetCompletions,
                isWeekComplete: isComplete,
                weekStartDate: currentProgress.weekStartDate,
                weekEndDate: currentProgress.weekEndDate,
                dataTimestamp: nil // Local cache update, no server timestamp
            )
            
            currentWeeklyProgress[index] = updatedProgress
            
            // Save updated progress back to cache
            saveCachedData(currentWeeklyProgress, key: CacheKeys.weeklyProgress)
            
            // Keep cache timestamp valid
            refreshCacheTimestamp()
            
            print("✅ [DataCacheManager] Updated weekly progress for habit '\(habitId)': \(newCompletions)/\(currentProgress.targetCompletions), complete: \(isComplete)")
        } else {
            print("⚠️ [DataCacheManager] Weekly progress not found for habit '\(habitId)' in cache")
        }
    }
    
    /// Update weekly progress cache with fresh data from server
    func updateWeeklyProgressCacheWithFreshData(_ freshProgressData: [PreloadManager.WeeklyProgressData]) {
        // NEW: Only update if user isn't actively interacting
        if shouldSkipSyncDueToUserActivity {
            print("👤 [DataCacheManager] Skipping fresh data update - user is actively interacting")
            return
        }
        
        // NEW: Smart merging with existing cache data to preserve recent local changes
        let currentWeeklyProgress = loadCachedData(key: CacheKeys.weeklyProgress, type: [PreloadManager.WeeklyProgressData].self) ?? []
        var mergedProgress: [PreloadManager.WeeklyProgressData] = []
        
        // Create lookup maps for efficiency
        let currentProgressMap = Dictionary(uniqueKeysWithValues: currentWeeklyProgress.map { ($0.habitId, $0) })
        let freshProgressMap = Dictionary(uniqueKeysWithValues: freshProgressData.map { ($0.habitId, $0) })
        
        // Merge server data with existing cache data intelligently
        let allHabitIds = Set(currentProgressMap.keys).union(Set(freshProgressMap.keys))
        
        for habitId in allHabitIds {
            let existingProgress = currentProgressMap[habitId]
            let serverProgress = freshProgressMap[habitId]
            
            if let existing = existingProgress, let server = serverProgress {
                // Both exist - choose the more recent or higher completion count
                if existing.currentCompletions > server.currentCompletions && 
                   existing.dataTimestamp == nil { // Local data is ahead and was user-generated
                    print("📊 [DataCacheManager] Preserving local progress for habit '\(habitId)': local=\(existing.currentCompletions), server=\(server.currentCompletions)")
                    mergedProgress.append(existing)
                } else {
                    print("📊 [DataCacheManager] Using server progress for habit '\(habitId)': local=\(existing.currentCompletions), server=\(server.currentCompletions)")
                    mergedProgress.append(server)
                }
            } else if let server = serverProgress {
                // Only server data exists
                mergedProgress.append(server)
            } else if let existing = existingProgress {
                // Only local data exists - keep it
                mergedProgress.append(existing)
            }
        }
        
        saveCachedData(mergedProgress, key: CacheKeys.weeklyProgress)
        refreshCacheTimestamp()
        print("📊 [DataCacheManager] Smart merged weekly progress cache with fresh server data (\(mergedProgress.count) total habits)")
    }
    
    /// Comprehensive update method for weekly habit verification
    func updateCacheForWeeklyHabitVerification(habitId: String, verificationData: HabitVerification? = nil) {
        // NEW: Track user interaction with weekly habit verification
        trackUserInteraction()
        
        // 1. Update verification status
        updateVerificationDataInCache(habitId: habitId, isVerified: true)
        
        // 2. Update weekly progress
        updateWeeklyProgressCache(for: habitId, incrementCompletion: true)
        
        // 3. Update habit verifications if data provided
        if let verification = verificationData {
            updateHabitVerificationsCache(habitId: habitId, verification: verification)
        }
        
        // 4. Ensure cache timestamp remains valid to prevent unnecessary refreshes
        refreshCacheTimestamp()
        
        print("🎯 [DataCacheManager] Completed comprehensive cache update for weekly habit '\(habitId)'")
    }
    
    /// NEW: Safe method for external weekly progress updates that respects user activity
    func safeUpdateWeeklyProgressFromServer(_ freshProgressData: [PreloadManager.WeeklyProgressData]) {
        // If user is actively interacting, defer the update
        if shouldSkipSyncDueToUserActivity {
            print("👤 [DataCacheManager] Deferring server progress update - user is active")
            
            // Schedule update for later when user is not active
            Task.detached(priority: .background) {
                // Wait for user to finish interacting
                try? await Task.sleep(nanoseconds: UInt64(self.userActivityGracePeriod * 2 * 1_000_000_000))
                
                await MainActor.run {
                    // Double-check user is still not active
                    if !self.shouldSkipSyncDueToUserActivity {
                        self.updateWeeklyProgressCacheWithFreshData(freshProgressData)
                    }
                }
            }
            return
        }
        
        // User is not active, safe to update immediately
        updateWeeklyProgressCacheWithFreshData(freshProgressData)
    }
    
    /// Update verification data in cache when a habit is verified
    func updateVerificationDataInCache(habitId: String, isVerified: Bool, date: String? = nil) {
        let targetDate = date ?? {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: Date())
        }()
        
        // Update verifiedHabitsToday cache
        var currentVerifiedToday = loadCachedData(key: CacheKeys.verifiedHabitsToday, type: [String: Bool].self) ?? [:]
        
        // Only update if this is for today
        let todayString = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: Date())
        }()
        
        if targetDate == todayString {
            currentVerifiedToday[habitId] = isVerified
            saveCachedData(currentVerifiedToday, key: CacheKeys.verifiedHabitsToday)
        }
        
        // Update weeklyVerifiedHabits cache
        var currentWeeklyVerified = loadCachedData(key: CacheKeys.weeklyVerifiedHabits, type: [String: [String: Bool]].self) ?? [:]
        
        if currentWeeklyVerified[targetDate] == nil {
            currentWeeklyVerified[targetDate] = [:]
        }
        currentWeeklyVerified[targetDate]?[habitId] = isVerified
        
        saveCachedData(currentWeeklyVerified, key: CacheKeys.weeklyVerifiedHabits)
        
        // Keep cache timestamp valid
        refreshCacheTimestamp()
        
        print("✅ [DataCacheManager] Updated verification data for habit '\(habitId)' on '\(targetDate)': \(isVerified)")
    }
    
    /// Update verification data cache and daily habits as well
    func updateCacheForDailyHabitVerification(habitId: String, verificationData: HabitVerification? = nil) {
        // 1. Update verification status
        updateVerificationDataInCache(habitId: habitId, isVerified: true)
        
        // 2. Update habit verifications if data provided
        if let verification = verificationData {
            updateHabitVerificationsCache(habitId: habitId, verification: verification)
        }
        
        // 3. Ensure cache timestamp remains valid to prevent unnecessary refreshes
        refreshCacheTimestamp()
        
        print("📸 [DataCacheManager] Completed cache update for daily habit '\(habitId)'")
    }
    
    /// Update habit verifications cache with new verification data
    private func updateHabitVerificationsCache(habitId: String, verification: HabitVerification) {
        var currentHabitVerifications = loadCachedData(key: CacheKeys.habitVerifications, type: [String: [CachedHabitVerification]].self) ?? [:]
        
        // Convert HabitVerification to CachedHabitVerification
        let cachedVerification = CachedHabitVerification(
            id: verification.id,
            habitId: verification.habitId,
            userId: verification.userId,
            verificationType: verification.verificationType,
            verifiedAt: verification.verifiedAt,
            status: verification.status,
            verificationResult: verification.verificationResult,
            imageUrl: verification.imageUrl,
            selfieImageUrl: verification.selfieImageUrl,
            imageVerificationId: verification.imageVerificationId,
            imageFilename: verification.imageFilename,
            selfieImageFilename: verification.selfieImageFilename,
            verificationImageData: nil, // Image data loaded separately
            selfieImageData: nil // Selfie image data loaded separately
        )
        
        if currentHabitVerifications[habitId] == nil {
            currentHabitVerifications[habitId] = []
        }
        currentHabitVerifications[habitId]?.append(cachedVerification)
        
        saveCachedData(currentHabitVerifications, key: CacheKeys.habitVerifications)
        
        print("✅ [DataCacheManager] Added verification data to cache for habit '\(habitId)'")
    }
    
    
    // MARK: - Missing Cache Methods
    
    /// Cache habits data
    func cacheHabits(_ habits: [PreloadManager.HabitData]?) {
        if let habits = habits {
            saveCachedData(habits, key: CacheKeys.habits)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.habits)
        }
    }
    
    /// Cache friends data  
    func cacheFriends(_ friends: [PreloadManager.FriendData]?) {
        if let friends = friends {
            saveCachedData(friends, key: CacheKeys.friends)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.friends)
        }
    }
    
    /// Cache friends with Stripe data
    func cacheFriendsWithStripe(_ friends: [PreloadManager.FriendWithStripeData]?) {
        if let friends = friends {
            saveCachedData(friends, key: CacheKeys.friendsWithStripe)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.friendsWithStripe)
        }
    }
    
    /// Get cached friends with Stripe data
    func getCachedFriendsWithStripe() -> [PreloadManager.FriendWithStripeData]? {
        return loadCachedData(key: CacheKeys.friendsWithStripe, type: [PreloadManager.FriendWithStripeData].self)
    }
    
    /// Cache feed posts data
    func cacheFeedPosts(_ posts: [PreloadManager.FeedPostData]?) {
        if let posts = posts {
            saveCachedData(posts, key: CacheKeys.feedPosts)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.feedPosts)
        }
    }
    
    /// Cache custom habit types data
    func cacheCustomHabitTypes(_ types: [PreloadManager.CustomHabitTypeData]?) {
        if let types = types {
            saveCachedData(types, key: CacheKeys.customHabitTypes)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.customHabitTypes)
        }
    }
    
    /// Cache weekly progress data
    func cacheWeeklyProgress(_ progress: [PreloadManager.WeeklyProgressData]?) {
        if let progress = progress {
            saveCachedData(progress, key: CacheKeys.weeklyProgress)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.weeklyProgress)
        }
    }
    
    /// Cache verified habits today data
    func cacheVerifiedHabitsToday(_ verifiedHabits: [String: Bool]?) {
        if let verifiedHabits = verifiedHabits {
            saveCachedData(verifiedHabits, key: CacheKeys.verifiedHabitsToday)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.verifiedHabitsToday)
        }
    }
    
    /// Cache habit verifications data
    func cacheHabitVerifications(_ verifications: [String: [PreloadManager.VerificationData]]?) {
        if let verifications = verifications {
            // Convert VerificationData to CachedHabitVerification for caching
            let convertedVerifications = verifications.mapValues { verificationDataArray in
                verificationDataArray.map { verificationData in
                    CachedHabitVerification(
                        id: verificationData.id,
                        habitId: verificationData.habitId,
                        userId: verificationData.userId,
                        verificationType: verificationData.verificationType,
                        verifiedAt: verificationData.verifiedAt,
                        status: verificationData.status,
                        verificationResult: verificationData.verificationResult,
                        imageUrl: verificationData.imageUrl,
                        selfieImageUrl: verificationData.selfieImageUrl,
                        imageVerificationId: verificationData.imageVerificationId,
                        imageFilename: verificationData.imageFilename,
                        selfieImageFilename: verificationData.selfieImageFilename,
                        verificationImageData: nil,
                        selfieImageData: nil
                    )
                }
            }
            saveCachedData(convertedVerifications, key: CacheKeys.habitVerifications)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.habitVerifications)
        }
    }
    
    /// Cache weekly verified habits data
    func cacheWeeklyVerifiedHabits(_ weeklyVerified: [String: [String: Bool]]?) {
        if let weeklyVerified = weeklyVerified {
            saveCachedData(weeklyVerified, key: CacheKeys.weeklyVerifiedHabits)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.weeklyVerifiedHabits)
        }
    }
    
    /// Cache friend requests data
    func cacheFriendRequests(_ friendRequests: PreloadManager.FriendRequestsData?) {
        if let friendRequests = friendRequests {
            saveCachedData(friendRequests, key: CacheKeys.friendRequests)
        } else {
            userDefaults.removeObject(forKey: CacheKeys.friendRequests)
        }
    }
}

// MARK: - Data Models

struct CachedAppData {
    let habits: [PreloadManager.HabitData]?
    let friends: [PreloadManager.FriendData]?
    let friendsWithStripe: [PreloadManager.FriendWithStripeData]?
    let feedPosts: [PreloadManager.FeedPostData]?
    let customHabitTypes: [PreloadManager.CustomHabitTypeData]?
    let paymentMethod: PreloadManager.PaymentMethodData?
    let userProfile: PreloadManager.UserProfileData?
    let weeklyProgress: [PreloadManager.WeeklyProgressData]?
    let onboardingState: Int?
    
    // Add the missing availableHabitTypes field
    let availableHabitTypes: PreloadManager.AvailableHabitTypesData?
    
    // NEW: Add verification data to cached app data
    let verifiedHabitsToday: [String: Bool]?
    let habitVerifications: [String: [CachedHabitVerification]]?
    let weeklyVerifiedHabits: [String: [String: Bool]]?
    
    // NEW: Add staged deletions with proper type
    let stagedDeletions: [String: StagedDeletionInfo]?
    
    // NEW: Add contacts on tally
    let contactsOnTally: [PreloadManager.ContactOnTallyData]?
}

struct DeltaResponse: Codable {
    let habitsChanged: [String]? // Array of habit IDs that changed
    let friendsChanged: [String]? // Array of friend IDs that changed
    let feedPostsChanged: [String]? // Array of post IDs that changed
    let userProfileChanged: Bool?
    let lastModified: String?
    
    var hasChanges: Bool {
        return !(habitsChanged?.isEmpty ?? true) ||
               !(friendsChanged?.isEmpty ?? true) ||
               !(feedPostsChanged?.isEmpty ?? true) ||
               (userProfileChanged == true)
    }
    
    static let noChanges = DeltaResponse(
        habitsChanged: nil,
        friendsChanged: nil,
        feedPostsChanged: nil,
        userProfileChanged: false,
        lastModified: nil
    )
}

// MARK: - Shared Data Models

struct StagedDeletionInfo: Codable {
    let scheduledForDeletion: Bool
    let effectiveDate: String
    let userTimezone: String
    let stagingId: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case scheduledForDeletion = "scheduled_for_deletion"
        case effectiveDate = "effective_date"
        case userTimezone = "user_timezone"
        case stagingId = "staging_id"
        case createdAt = "created_at"
    }
}

// NEW: Cacheable version of HabitVerification
struct CachedHabitVerification: Codable {
    let id: String
    let habitId: String
    let userId: String
    let verificationType: String
    let verifiedAt: String
    let status: String
    let verificationResult: Bool?
    let imageUrl: String?
    let selfieImageUrl: String?
    let imageVerificationId: String?
    let imageFilename: String?
    let selfieImageFilename: String?
    let verificationImageData: Data? // Cache the actual image data too
    let selfieImageData: Data? // Cache selfie image data too
    
    enum CodingKeys: String, CodingKey {
        case id, habitId = "habit_id", userId = "user_id"
        case verificationType = "verification_type", verifiedAt = "verified_at"
        case status, verificationResult = "verification_result"
        case imageUrl = "image_url", selfieImageUrl = "selfie_image_url"
        case imageVerificationId = "image_verification_id"
        case imageFilename = "image_filename", selfieImageFilename = "selfie_image_filename"
        case verificationImageData, selfieImageData
    }
} 
