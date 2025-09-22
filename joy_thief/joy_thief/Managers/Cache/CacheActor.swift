import Foundation

/// Thread-safe cache operations with memory + disk layers
actor CacheActor {
    private let fileManager: CacheFileManager
    private let cacheFilename = "friends_cache.json"
    
    // In-memory cache for fastest access
    private var memoryCache: FriendCache?
    private var memoryCacheTimestamp: Date?
    
    // Memory cache validity (5 minutes)
    private let memoryCacheValidityDuration: TimeInterval = 5 * 60
    
    init() {
        self.fileManager = CacheFileManager()
    }
    
    /// Load cache from disk or memory
    func loadCache() async -> FriendCache? {
        // First check memory cache
        if let memoryCache = memoryCache,
           let timestamp = memoryCacheTimestamp,
           Date().timeIntervalSince(timestamp) < memoryCacheValidityDuration {
            return memoryCache
        }
        
        // Fallback to disk cache
        do {
            let diskCache = try await fileManager.read(FriendCache.self, from: cacheFilename)
            
            if let cache = diskCache {
                // Update memory cache
                memoryCache = cache
                memoryCacheTimestamp = Date()
                return cache
            } else {
                print("📁 [CacheActor] No cache found on disk")
                return nil
            }
        } catch {
            print("❌ [CacheActor] Failed to load cache from disk: \(error)")
            return nil
        }
    }
    
    /// Save cache to both memory and disk
    func saveCache(_ cache: FriendCache) async throws {
        // Update memory cache immediately
        memoryCache = cache
        memoryCacheTimestamp = Date()
        
        // Save to disk asynchronously
        do {
            try await fileManager.writeAtomically(cache, to: cacheFilename)
        } catch {
            print("❌ [CacheActor] Failed to save cache to disk: \(error)")
            throw error
        }
    }
    
    /// Invalidate all cache layers
    func invalidateCache() async {
        memoryCache = nil
        memoryCacheTimestamp = nil
        
        do {
            try await fileManager.delete(filename: cacheFilename)
        } catch {
            print("❌ [CacheActor] Failed to delete cache file: \(error)")
        }
    }
    
    /// Get cache file size
    func getCacheSize() async -> Int64 {
        return await fileManager.getFileSize(filename: cacheFilename)
    }
    
    /// Clear all cache files (for compliance/privacy)
    func clearAllCache() async throws {
        memoryCache = nil
        memoryCacheTimestamp = nil
        
        try await fileManager.clearAllCache()
    }
    
    /// Get cache statistics
    func getCacheStats() async -> CacheStats {
        let diskSize = await getCacheSize()
        let memoryCache = self.memoryCache
        let memoryCacheAge = memoryCacheTimestamp?.timeIntervalSinceNow.magnitude
        
        return CacheStats(
            diskCacheSize: diskSize,
            hasMemoryCache: memoryCache != nil,
            memoryCacheAge: memoryCacheAge,
            lastDiskCacheDate: memoryCache?.lastFetchDate,
            diskCacheStalenessLevel: memoryCache?.stalenessLevel
        )
    }
}

/// Cache statistics for monitoring
struct CacheStats {
    let diskCacheSize: Int64
    let hasMemoryCache: Bool
    let memoryCacheAge: TimeInterval?
    let lastDiskCacheDate: Date?
    let diskCacheStalenessLevel: CacheStalenessLevel?
    
    var formattedDiskSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskCacheSize)
    }
} 
