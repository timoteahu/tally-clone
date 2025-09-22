import Foundation

// MARK: - Recipient Habit Cache

/// Cache structure for recipient habit data
struct RecipientHabitCache: Codable {
    let activeHabits: [HabitWithAnalytics]
    let inactiveHabits: [HabitWithAnalytics]
    let summaryStats: RecipientSummaryStats?
    let lastUpdated: Date
    let cacheVersion: Int
    
    // Cache validity constants
    static let currentCacheVersion = 1
    static let freshDuration: TimeInterval = 5 * 60 // 5 minutes
    static let staleDuration: TimeInterval = 30 * 60 // 30 minutes
    static let expiredDuration: TimeInterval = 60 * 60 // 1 hour
    
    /// Check if cache is valid for the current version
    var isValidVersion: Bool {
        return cacheVersion == Self.currentCacheVersion
    }
    
    /// Get the age of the cache
    var age: TimeInterval {
        return Date().timeIntervalSince(lastUpdated)
    }
    
    /// Check cache freshness status
    var freshness: CacheFreshness {
        let cacheAge = age
        
        if !isValidVersion {
            return .invalid
        } else if cacheAge < Self.freshDuration {
            return .fresh
        } else if cacheAge < Self.staleDuration {
            return .stale
        } else if cacheAge < Self.expiredDuration {
            return .expired
        } else {
            return .ancient
        }
    }
    
    /// Check if cache should be used
    var isUsable: Bool {
        switch freshness {
        case .fresh, .stale, .expired:
            return true
        case .ancient, .invalid:
            return false
        }
    }
    
    /// Check if cache needs refresh
    var needsRefresh: Bool {
        switch freshness {
        case .fresh:
            return false
        case .stale, .expired, .ancient, .invalid:
            return true
        }
    }
}

// MARK: - Cache Freshness

enum CacheFreshness {
    case fresh   // 0-5 minutes: Use without refresh
    case stale   // 5-30 minutes: Use but refresh in background
    case expired // 30-60 minutes: Use with warning, force refresh
    case ancient // >60 minutes: Don't use
    case invalid // Wrong version: Don't use
}

// MARK: - Cache File Management

extension RecipientHabitCache {
    /// Get the cache file URL
    static var cacheFileURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("recipient_habits_cache.json")
    }
    
    /// Save cache to disk
    func saveToDisk() {
        guard let url = Self.cacheFileURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(self)
            try data.write(to: url)
            print("✅ [RecipientCache] Saved cache to disk")
        } catch {
            print("❌ [RecipientCache] Failed to save cache: \(error)")
        }
    }
    
    /// Load cache from disk
    static func loadFromDisk() -> RecipientHabitCache? {
        guard let url = cacheFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(RecipientHabitCache.self, from: data)
            
            print("📁 [RecipientCache] Loaded cache from disk (age: \(Int(cache.age))s, freshness: \(cache.freshness))")
            return cache
        } catch {
            print("❌ [RecipientCache] Failed to load cache: \(error)")
            return nil
        }
    }
    
    /// Clear cache from disk
    static func clearDiskCache() {
        guard let url = cacheFileURL else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
            print("🗑️ [RecipientCache] Cleared disk cache")
        } catch {
            print("❌ [RecipientCache] Failed to clear cache: \(error)")
        }
    }
}