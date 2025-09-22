import Foundation

class CommentCacheManager: ObservableObject {
    static let shared = CommentCacheManager()
    
    private var commentCache: [UUID: CachedComments] = [:]
    private var lastFetchTimes: [UUID: Date] = [:]
    private var commentCounts: [UUID: CommentCount] = [:]
    private let cacheQueue = DispatchQueue(label: "comment.cache.queue", qos: .utility)
    
    // Cache TTL configurations
    private let commentsTTL: TimeInterval = 300 // 5 minutes for background refresh
    private let staleThreshold: TimeInterval = 30 // 30 seconds - show cache but check for updates
    private let maxCacheSize = 100              // Maximum posts to cache
    
    private init() {
        setupCacheCleanup()
    }
    
    // MARK: - Data Structures
    
    struct CachedComments {
        let comments: [Comment]
        let timestamp: Date
        let version: Int // For cache invalidation
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > CommentCacheManager.shared.commentsTTL
        }
        
        var isStale: Bool {
            Date().timeIntervalSince(timestamp) > CommentCacheManager.shared.staleThreshold
        }
    }
    
    struct CommentCount {
        let total: Int
        let topLevel: Int
        let timestamp: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > CommentCacheManager.shared.commentsTTL
        }
    }
    
    // MARK: - Smart Cache-First API
    
    /// Smart comment loading: returns cached data immediately if available, 
    /// then checks for updates in background if cache is stale
    func getCommentsSmartCache(for postId: UUID) async -> [Comment] {
        print("🧠 [CommentCache] Smart loading comments for post \(postId.uuidString.prefix(8))")
        
        // Check cache first
        if let cached = getCachedComments(for: postId) {
            print("💾 [CommentCache] Using cached comments (\(cached.count) comments)")
            
            // If cache is stale but not expired, check for updates in background
            if let cachedData = commentCache[postId], cachedData.isStale && !cachedData.isExpired {
                print("🔄 [CommentCache] Cache is stale, checking for updates in background")
                Task.detached(priority: .utility) {
                    await self.refreshCommentsInBackground(for: postId)
                }
            }
            
            return cached
        }
        
        // No cache - fetch fresh from network
        print("🌐 [CommentCache] No cache found, fetching from network")
        return await fetchCommentsFromNetwork(for: postId)
    }
    
    /// Get cached comments for a post (returns nil if cache miss or expired)
    func getCachedComments(for postId: UUID) -> [Comment]? {
        return cacheQueue.sync {
            guard let cached = commentCache[postId],
                  !cached.isExpired else {
                return nil
            }
            
            print("💾 [CommentCache] Cache hit for post \(postId.uuidString.prefix(8)) - \(cached.comments.count) comments")
            return cached.comments
        }
    }
    
    /// Cache comments for a post
    func cacheComments(_ comments: [Comment], for postId: UUID) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let cached = CachedComments(
                comments: comments,
                timestamp: Date(),
                version: self.getNextVersion()
            )
            
            self.commentCache[postId] = cached
            self.lastFetchTimes[postId] = Date()
            
            // Cleanup if cache is getting too large
            self.cleanupOldEntries()
            
            print("💾 [CommentCache] Cached \(comments.count) comments for post \(postId.uuidString.prefix(8))")
        }
    }
    
    /// Check if cached comments are fresh (within stale threshold)
    func areCachedCommentsFresh(for postId: UUID) -> Bool {
        return cacheQueue.sync {
            guard let cached = commentCache[postId] else { return false }
            return !cached.isStale && !cached.isExpired
        }
    }
    
    /// Force refresh comments from network (ignoring cache)
    func forceRefreshComments(for postId: UUID) async -> [Comment] {
        print("🔄 [CommentCache] Force refreshing comments for post \(postId.uuidString.prefix(8))")
        invalidateCache(for: postId)
        return await fetchCommentsFromNetwork(for: postId)
    }
    
    // MARK: - Background Update Methods
    
    private func refreshCommentsInBackground(for postId: UUID) async {
        let freshComments = await fetchCommentsFromNetwork(for: postId)
        
        // Compare with cached version
        if let cachedComments = getCachedComments(for: postId) {
            let hasChanges = !areCommentsEqual(cachedComments, freshComments)
            
            if hasChanges {
                print("🔄 [CommentCache] Background refresh found changes for post \(postId.uuidString.prefix(8))")
                // Notify FeedManager of the changes
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .commentsUpdatedInBackground,
                        object: nil,
                        userInfo: ["postId": postId, "comments": freshComments]
                    )
                }
            } else {
                print("💾 [CommentCache] Background refresh: no changes detected")
                // Update timestamp to mark as fresh
                cacheComments(cachedComments, for: postId)
            }
        }
    }
    
    private func areCommentsEqual(_ comments1: [Comment], _ comments2: [Comment]) -> Bool {
        guard comments1.count == comments2.count else { return false }
        
        let ids1 = Set(comments1.map { $0.id })
        let ids2 = Set(comments2.map { $0.id })
        
        return ids1 == ids2
    }
    
    // MARK: - Network Fetching
    
    private func fetchCommentsFromNetwork(for postId: UUID) async -> [Comment] {
        do {
            let comments = try await performNetworkFetch(for: postId)
            cacheComments(comments, for: postId)
            return comments
        } catch {
            print("❌ [CommentCache] Network fetch failed: \(error)")
            // Return cached data if available, even if expired
            return getCachedCommentsIgnoringExpiry(for: postId) ?? []
        }
    }
    
    private func getCachedCommentsIgnoringExpiry(for postId: UUID) -> [Comment]? {
        return cacheQueue.sync {
            return commentCache[postId]?.comments
        }
    }
    
    private func performNetworkFetch(for postId: UUID) async throws -> [Comment] {
        guard let url = URL(string: "\(AppConfig.baseURL)/feed/comments/\(postId.uuidString)") else {
            throw CommentCacheError.invalidURL
        }
        
        guard let token = await AuthenticationManager.shared.storedAuthToken else {
            throw CommentCacheError.noAuthToken
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CommentCacheError.badResponse
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = DateFormatterManager.shared.parseISO8601Date(dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        
        return try decoder.decode([Comment].self, from: data)
    }
    
    // MARK: - Existing Methods (with improvements)
    
    /// Get cached comment count (fast path for UI display)
    func getCachedCommentCount(for postId: UUID) -> CommentCount? {
        return cacheQueue.sync {
            guard let count = commentCounts[postId],
                  !count.isExpired else {
                return nil
            }
            return count
        }
    }
    
    /// Cache comment count
    func cacheCommentCount(total: Int, topLevel: Int, for postId: UUID) {
        cacheQueue.async { [weak self] in
            let count = CommentCount(
                total: total,
                topLevel: topLevel,
                timestamp: Date()
            )
            self?.commentCounts[postId] = count
        }
    }
    
    /// Add a new comment to cache (optimistic update)
    func addCommentToCache(_ comment: Comment, for postId: UUID) {
        cacheQueue.async { [weak self] in
            guard let self = self,
                  var cached = self.commentCache[postId],
                  !cached.isExpired else {
                print("💾 [CommentCache] Cannot add comment - no valid cache for post \(postId.uuidString.prefix(8))")
                return
            }
            
            var updatedComments = cached.comments
            
            // Add comment in the right position based on threading
            if comment.parentComment != nil {
                // It's a reply - find the parent and insert after it
                if let parentIndex = updatedComments.firstIndex(where: { $0.id == comment.parentComment?.id }) {
                    // Find the right insertion point (after parent and its existing replies)
                    var insertIndex = parentIndex + 1
                    while insertIndex < updatedComments.count &&
                          updatedComments[insertIndex].parentComment != nil {
                        insertIndex += 1
                    }
                    updatedComments.insert(comment, at: insertIndex)
                } else {
                    // Parent not found, append at end
                    updatedComments.append(comment)
                }
            } else {
                // Top-level comment - add at end
                updatedComments.append(comment)
            }
            
            // Update cache with new comment
            self.commentCache[postId] = CachedComments(
                comments: updatedComments,
                timestamp: cached.timestamp,
                version: cached.version + 1
            )
            
            // Update count cache
            if let count = self.commentCounts[postId] {
                let newTopLevel = comment.parentComment == nil ? count.topLevel + 1 : count.topLevel
                self.commentCounts[postId] = CommentCount(
                    total: count.total + 1,
                    topLevel: newTopLevel,
                    timestamp: count.timestamp
                )
            }
            
            print("💾 [CommentCache] Added comment \(comment.id.uuidString.prefix(8)) to cache for post \(postId.uuidString.prefix(8))")
        }
    }
    
    /// Invalidate cache for a post (force refresh)
    func invalidateCache(for postId: UUID) {
        cacheQueue.async { [weak self] in
            self?.commentCache.removeValue(forKey: postId)
            self?.commentCounts.removeValue(forKey: postId)
            self?.lastFetchTimes.removeValue(forKey: postId)
            print("💾 [CommentCache] Invalidated cache for post \(postId.uuidString.prefix(8))")
        }
    }
    
    /// Check if comments need refresh based on TTL
    func needsRefresh(for postId: UUID) -> Bool {
        return cacheQueue.sync {
            guard let lastFetch = lastFetchTimes[postId] else {
                return true // Never fetched
            }
            
            return Date().timeIntervalSince(lastFetch) > commentsTTL
        }
    }
    
    // MARK: - Private Methods
    
    private func getNextVersion() -> Int {
        return Int(Date().timeIntervalSince1970)
    }
    
    private func cleanupOldEntries() {
        guard commentCache.count > maxCacheSize else { return }
        
        // Remove oldest entries
        let sortedEntries = lastFetchTimes.sorted { $0.value < $1.value }
        let toRemove = sortedEntries.prefix(commentCache.count - maxCacheSize)
        
        for (postId, _) in toRemove {
            commentCache.removeValue(forKey: postId)
            commentCounts.removeValue(forKey: postId)
            lastFetchTimes.removeValue(forKey: postId)
        }
        
        print("💾 [CommentCache] Cleaned up \(toRemove.count) old cache entries")
    }
    
    private func setupCacheCleanup() {
        // Periodic cleanup every 10 minutes
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.performPeriodicCleanup()
        }
    }
    
    private func performPeriodicCleanup() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let expiredCommentKeys = self.commentCache.compactMap { (key, value) in
                now.timeIntervalSince(value.timestamp) > self.commentsTTL ? key : nil
            }
            
            let expiredCountKeys = self.commentCounts.compactMap { (key, value) in
                now.timeIntervalSince(value.timestamp) > self.commentsTTL ? key : nil
            }
            
            for key in expiredCommentKeys {
                self.commentCache.removeValue(forKey: key)
                self.lastFetchTimes.removeValue(forKey: key)
            }
            
            for key in expiredCountKeys {
                self.commentCounts.removeValue(forKey: key)
            }
            
            if !expiredCommentKeys.isEmpty || !expiredCountKeys.isEmpty {
                print("💾 [CommentCache] Periodic cleanup: removed \(expiredCommentKeys.count) comment caches and \(expiredCountKeys.count) count caches")
            }
        }
    }
    
    // MARK: - Debug/Analytics
    
    func getCacheStats() -> (cached: Int, expired: Int, memoryUsage: Int) {
        return cacheQueue.sync {
            let cached = commentCache.count
            let expired = commentCache.values.filter { $0.isExpired }.count
            let memoryUsage = commentCache.values.reduce(0) { $0 + $1.comments.count }
            
            return (cached: cached, expired: expired, memoryUsage: memoryUsage)
        }
    }
    
    func printCacheStats() {
        let stats = getCacheStats()
        print("💾 [CommentCache] Stats - Cached: \(stats.cached), Expired: \(stats.expired), Total Comments: \(stats.memoryUsage)")
    }
}

// MARK: - Error Types

enum CommentCacheError: Error, LocalizedError {
    case invalidURL
    case noAuthToken
    case badResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for comments"
        case .noAuthToken:
            return "No authentication token"
        case .badResponse:
            return "Server error"
        case .decodingError:
            return "Failed to decode comments"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let commentsUpdatedInBackground = Notification.Name("commentsUpdatedInBackground")
} 