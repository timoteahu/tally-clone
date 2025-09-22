import Foundation

// MARK: - Recipient Cache Manager

/// Thread-safe cache manager for recipient habit data
actor RecipientCacheManager {
    // MARK: - Properties
    
    /// In-memory cache
    private var memoryCache: RecipientHabitCache?
    
    /// Memory cache validity (shorter than disk cache)
    private let memoryCacheDuration: TimeInterval = 5 * 60 // 5 minutes
    
    // MARK: - Cache Operations
    
    /// Get cached data (memory first, then disk)
    func getCachedData() -> RecipientHabitCache? {
        // Check memory cache first
        if let memCache = memoryCache,
           memCache.age < memoryCacheDuration,
           memCache.isValidVersion {
            print("💾 [RecipientCache] Using memory cache (age: \(Int(memCache.age))s)")
            return memCache
        }
        
        // Fall back to disk cache
        if let diskCache = RecipientHabitCache.loadFromDisk(),
           diskCache.isUsable {
            // Update memory cache from disk
            memoryCache = diskCache
            print("💿 [RecipientCache] Using disk cache (age: \(Int(diskCache.age))s)")
            return diskCache
        }
        
        print("❌ [RecipientCache] No usable cache found")
        return nil
    }
    
    /// Save data to both memory and disk cache
    func cacheData(activeHabits: [HabitWithAnalytics],
                   inactiveHabits: [HabitWithAnalytics],
                   summaryStats: RecipientSummaryStats?) {
        let cache = RecipientHabitCache(
            activeHabits: activeHabits,
            inactiveHabits: inactiveHabits,
            summaryStats: summaryStats,
            lastUpdated: Date(),
            cacheVersion: RecipientHabitCache.currentCacheVersion
        )
        
        // Update memory cache
        memoryCache = cache
        
        // Save to disk asynchronously
        Task.detached(priority: .background) {
            cache.saveToDisk()
        }
        
        print("✅ [RecipientCache] Cached \(activeHabits.count) active, \(inactiveHabits.count) inactive habits")
    }
    
    /// Clear all caches
    func clearCache() {
        memoryCache = nil
        RecipientHabitCache.clearDiskCache()
        print("🗑️ [RecipientCache] Cleared all caches")
    }
    
    /// Check if we have any cache
    func hasCache() -> Bool {
        return getCachedData() != nil
    }
    
    /// Get cache freshness status
    func getCacheFreshness() -> CacheFreshness? {
        return getCachedData()?.freshness
    }
    
    /// Check if cache needs refresh
    func needsRefresh() -> Bool {
        guard let cache = getCachedData() else {
            return true
        }
        return cache.needsRefresh
    }
}

// MARK: - Singleton Instance

extension RecipientCacheManager {
    /// Shared instance for the app
    static let shared = RecipientCacheManager()
}