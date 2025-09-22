import Foundation
import UIKit
import Kingfisher

class FeedManager: ObservableObject {
    static let shared = FeedManager()
    
    @Published var feedPosts: [FeedPost] = []
    @Published var errorMessage: String?
    @Published var hasInitialized = false // Track if feed has been initialized from cache
    // This flag is internal-only and not used by any UI. Removing the `@Published` wrapper
    // prevents unnecessary SwiftUI view updates (and the visible flicker of the first
    // feed card) each time the background refresh toggles this value.
    private var isRefreshing = false // Track if currently refreshing to prevent double calls
    @Published var isLoadingMore = false // Track if loading more posts (pagination)
    
    private let urlSession = URLSession.shared
    private var refreshTimer: Timer?
    // Poll the feed every 60 seconds while the app is in the foreground to reduce server load
    private let refreshInterval: TimeInterval = 60.0
    
    // Request deduplication
    private var activeRefreshTask: Task<Void, Never>? = nil
    private var activeCommentsRefreshTasks: [String: Task<Void, Never>] = [:]
    private var lastRefreshTime: Date?
    // Allow manual/other refreshes as often as every 10s
    private let minRefreshInterval: TimeInterval = 10.0
    
    // Pagination support
    private var currentPage = 0
    private let pageSize = 20 // Load 20 posts at a time
    private var hasMorePosts = true
    
    // Callback for when new posts are detected
    var onNewPostsDetected: ((Int) -> Void)?
    
    // MARK: - Basic Comment Caching Integration
    private var commentCache: [UUID: CachedComments] = [:]
    private var commentsLastFetched: [UUID: Date] = [:]
    private let commentsTTL: TimeInterval = 300.0 // 5 minutes
    private let staleThreshold: TimeInterval = 10.0 // 10 seconds - more aggressive for development
    
    // Thread-safe access to comment cache
    private let cacheQueue = DispatchQueue(label: "feedmanager.cache.queue", qos: .utility)
    
    // MARK: - Simple Cache Data Structure
    struct CachedComments {
        let comments: [Comment]
        let timestamp: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300.0 // 5 minutes
        }
        
        var isStale: Bool {
            Date().timeIntervalSince(timestamp) > 10.0 // 10 seconds - more aggressive for development
        }
    }
    
    private init() {
        // Initialize with periodic refresh
        setupPeriodicRefresh()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    // MARK: - Periodic Refresh Setup
    
    private func setupPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performSilentRefresh()
            }
        }
        
        print("🔄 [FeedManager] Started periodic feed refresh every \(refreshInterval)s")
    }
    
    // MARK: - Feed Management (Cache + Polling)
    
    // Feed is now cache + polling driven - regular network fetching
    // Data comes from:
    // 1. Cache (instant load)
    // 2. Periodic polling for updates
    
    // MARK: - Helper Methods
    
    /// Convert FeedPost array to cache format
    private func convertPostsToCacheFormat(_ posts: [FeedPost]) -> [PreloadManager.FeedPostData] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        return posts.compactMap { post in
            // Convert comments to cache format instead of discarding them
            let cacheComments = post.comments.compactMap { comment -> PreloadManager.CommentData? in
                let parentCommentId: String?
                if let parentComment = comment.parentComment {
                    parentCommentId = parentComment.id.uuidString
                } else {
                    parentCommentId = nil
                }
                
                return PreloadManager.CommentData(
                    id: comment.id.uuidString,
                    content: comment.content,
                    createdAt: dateFormatter.string(from: comment.createdAt),
                    userId: comment.userId.uuidString,
                    userName: comment.userName,
                    userAvatarUrl80: comment.userAvatarUrl80,
                    userAvatarUrl200: comment.userAvatarUrl200,
                    userAvatarUrlOriginal: comment.userAvatarUrlOriginal,
                    userAvatarVersion: comment.userAvatarVersion,
                    isEdited: comment.isEdited,
                    parentComment: parentCommentId
                )
            }
            
            return PreloadManager.FeedPostData(
                postId: post.postId.uuidString,
                caption: post.caption,
                createdAt: dateFormatter.string(from: post.createdAt),
                isPrivate: post.isPrivate,
                imageUrl: post.imageUrl,
                selfieImageUrl: post.selfieImageUrl,
                contentImageUrl: post.contentImageUrl,
                userId: post.userId.uuidString,
                userName: post.userName,
                userAvatarUrl80: post.userAvatarUrl80,
                userAvatarUrl200: post.userAvatarUrl200,
                userAvatarUrlOriginal: post.userAvatarUrlOriginal,
                userAvatarVersion: post.userAvatarVersion,
                streak: post.streak,
                habitType: post.habitType,
                habitName: post.habitName,
                penaltyAmount: post.penaltyAmount,
                comments: cacheComments, // Preserve comments instead of empty array
                habitId: post.habitId
            )
        }
    }
    
    // Removed redundant wrapper methods - use updateCacheEfficiently directly
    
    /// Reload feed posts from cache
    @MainActor private func reloadFromCache() async {
        guard AuthenticationManager.shared.storedAuthToken != nil else { return }
        
        if let cachedData = DataCacheManager.shared.loadCacheOnlyForStartup(),
           let feedPostsData = cachedData.feedPosts {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            feedPosts = feedPostsData.compactMap { postData in
                print("DEBUG: FeedManager - Processing postData.habitType: \(postData.habitType ?? "nil") for Post ID: \(postData.postId)")
                guard let postId = UUID(uuidString: postData.postId),
                      let userId = UUID(uuidString: postData.userId),
                      let createdAt = dateFormatter.date(from: postData.createdAt) else {
                    return nil
                }
                
                let comments = postData.comments.compactMap { commentData -> Comment? in
                    guard let commentId = UUID(uuidString: commentData.id),
                          let commentUserId = UUID(uuidString: commentData.userId),
                          let commentCreatedAt = dateFormatter.date(from: commentData.createdAt) else {
                        return nil
                    }
                    
                    var parentComment: ParentComment? = nil
                    if let parentId = commentData.parentComment,
                       let parent = postData.comments.first(where: { $0.id == parentId }),
                       let parentUUID = UUID(uuidString: parent.id),
                       let parentUserId = UUID(uuidString: parent.userId),
                       let parentCreatedAt = dateFormatter.date(from: parent.createdAt) {
                        parentComment = ParentComment(
                            id: parentUUID,
                            content: parent.content,
                            createdAt: parentCreatedAt,
                            userId: parentUserId,
                            userName: parent.userName,
                            userAvatarUrl80: parent.userAvatarUrl80,
                            userAvatarUrl200: parent.userAvatarUrl200,
                            userAvatarUrlOriginal: parent.userAvatarUrlOriginal,
                            userAvatarVersion: parent.userAvatarVersion,
                            isEdited: parent.isEdited
                        )
                    }
                    
                    return Comment(
                        id: commentId,
                        content: commentData.content,
                        createdAt: commentCreatedAt,
                        userId: commentUserId,
                        userName: commentData.userName,
                        userAvatarUrl80: commentData.userAvatarUrl80,
                        userAvatarUrl200: commentData.userAvatarUrl200,
                        userAvatarUrlOriginal: commentData.userAvatarUrlOriginal,
                        userAvatarVersion: commentData.userAvatarVersion,
                        isEdited: commentData.isEdited,
                        parentComment: parentComment
                    )
                }
                
                // 🔧 CRITICAL FIX: Organize comments after loading from cache to ensure proper structure
                let organizedComments = organizeCommentsFlattened(comments)
                
                // Build the FeedPost, then enrich with current-user avatar URLs (in case cache lacks them)
                let rawPost = FeedPost(
                    postId: postId,
                    habitId: postData.habitId,
                    caption: postData.caption,
                    createdAt: createdAt,
                    isPrivate: postData.isPrivate,
                    imageUrl: postData.imageUrl,
                    selfieImageUrl: postData.selfieImageUrl,
                    contentImageUrl: postData.contentImageUrl,
                    userId: userId,
                    userName: postData.userName,
                    userAvatarUrl80: postData.userAvatarUrl80,
                    userAvatarUrl200: postData.userAvatarUrl200,
                    userAvatarUrlOriginal: postData.userAvatarUrlOriginal,
                    userAvatarVersion: postData.userAvatarVersion,
                    streak: postData.streak,
                    habitType: postData.habitType,
                    habitName: postData.habitName,
                    penaltyAmount: postData.penaltyAmount,
                    comments: organizedComments
                )
                
                // 🆕 NEW: Populate comment cache with existing comments from loaded posts
                if !organizedComments.isEmpty {
                    updateCommentCache(postId: postId, comments: organizedComments)
                    print("💾 [FeedManager] Populated comment cache for post \(postId.uuidString.prefix(8)) with \(organizedComments.count) comments")
                }
                
                // Inject avatar URLs if this is the current user and the cache entry is missing them.
                return enrichWithCurrentUserAvatarIfNeeded(rawPost)
            }
        }
    }
    
    /// Add a new comment to a specific post and update cache
    @MainActor func addComment(_ comment: Comment, to postId: UUID) {
        print("💬 [FeedManager] Adding comment \(comment.id.uuidString.prefix(8)) to post \(postId.uuidString.prefix(8))")
        print("💬 [FeedManager] Comment details:")
        print("   - Content: \(comment.content)")
        print("   - User: \(comment.userName)")
        print("   - Parent: \(comment.parentComment?.userName ?? "None (top-level)")")
        
        // Find the post and add the comment
        if let postIndex = feedPosts.firstIndex(where: { $0.postId == postId }) {
            let updatedPost = feedPosts[postIndex]
            var updatedComments = updatedPost.comments
            
            print("💬 [FeedManager] Post found. Current comments count: \(updatedComments.count)")
            
            // 🔧 CRITICAL FIX: Check if comment already exists to prevent duplicates
            if !updatedComments.contains(where: { $0.id == comment.id }) {
                // Simply append the new comment
                updatedComments.append(comment)
                
                print("💬 [FeedManager] Comment added. Comments count before organization: \(updatedComments.count)")
                
                // Sort to maintain proper order: top-level comments first, then replies chronologically
                let organizedComments = organizeCommentsFlattened(updatedComments)
                
                print("💬 [FeedManager] Comments count after organization: \(organizedComments.count)")
                
                // Verify we didn't lose any comments during organization
                if organizedComments.count != updatedComments.count {
                    print("❌ [FeedManager] WARNING: Lost comments during organization! \(updatedComments.count) -> \(organizedComments.count)")
                    // Debug: Print which comments are missing
                    let originalIds = Set(updatedComments.map { $0.id })
                    let organizedIds = Set(organizedComments.map { $0.id })
                    let missingIds = originalIds.subtracting(organizedIds)
                    print("❌ [FeedManager] Missing comment IDs: \(missingIds.map { $0.uuidString.prefix(8) })")
                } else {
                    print("✅ [FeedManager] All comments preserved during organization")
                }
                
                // 🔧 OPTIMIZED: Use helper method to create updated post
                let newPost = createUpdatedPost(from: updatedPost, withComments: organizedComments)
                
                // Update the posts array
                feedPosts[postIndex] = newPost
                
                // 🔧 OPTIMIZED: Single efficient cache update
                updateCacheEfficiently(feedPosts)
                
                // 🆕 NEW: Update comment cache with the new comment
                updateCommentCache(postId: postId, comments: organizedComments)
                
                // 🆕 NEW: Notify observers that comments were updated
                NotificationCenter.default.post(
                    name: .commentsUpdated,
                    object: nil,
                    userInfo: ["postId": postId.uuidString, "comments": organizedComments]
                )
                
                print("✅ [FeedManager] Added comment to post \(postId.uuidString.prefix(8)) and updated cache")
            } else {
                print("⚠️ [FeedManager] Comment \(comment.id.uuidString.prefix(8)) already exists in post")
            }
        } else {
            print("❌ [FeedManager] Post \(postId.uuidString.prefix(8)) not found for adding comment")
        }
    }
    
    // Find the post and add the comment to it
    @MainActor func addCommentToPost(postId: UUID, comment: Comment) {
        if let postIndex = feedPosts.firstIndex(where: { $0.postId == postId }) {
            var updatedComments = feedPosts[postIndex].comments
            
            // Simply append the new comment
            updatedComments.append(comment)
            
            // Sort to maintain proper order: top-level comments first, then replies chronologically  
            updatedComments = organizeCommentsFlattened(updatedComments)
            
            // 🔧 OPTIMIZED: Use helper method to create updated post
            let newPost = createUpdatedPost(from: feedPosts[postIndex], withComments: updatedComments)
            
            // Update the feedPosts array
            feedPosts[postIndex] = newPost
            
            // 🔧 OPTIMIZED: Single efficient cache update
            updateCacheEfficiently(feedPosts)
            
            // 🆕 NEW: Update comment cache with the new comment
            updateCommentCache(postId: postId, comments: updatedComments)
            
            // 🆕 NEW: Notify observers that comments were updated
            NotificationCenter.default.post(
                name: .commentsUpdated,
                object: nil,
                userInfo: ["postId": postId.uuidString, "comments": updatedComments]
            )
            
            print("💬 [FeedManager] Added comment to post \(postId) and updated cache")
        }
    }
    
    /// 🔧 NEW: Helper method to create updated posts efficiently
    private func createUpdatedPost(from original: FeedPost, withComments comments: [Comment]) -> FeedPost {
        return FeedPost(
            postId: original.postId,
            habitId: original.habitId,
            caption: original.caption,
            createdAt: original.createdAt,
            isPrivate: original.isPrivate,
            imageUrl: original.imageUrl,
            selfieImageUrl: original.selfieImageUrl,
            contentImageUrl: original.contentImageUrl,
            userId: original.userId,
            userName: original.userName,
            userAvatarUrl80: original.userAvatarUrl80,
            userAvatarUrl200: original.userAvatarUrl200,
            userAvatarUrlOriginal: original.userAvatarUrlOriginal,
            userAvatarVersion: original.userAvatarVersion,
            streak: original.streak,
            habitType: original.habitType,
            habitName: original.habitName,
            penaltyAmount: original.penaltyAmount,
            comments: comments
        )
    }
    
    // MARK: - Periodic Refresh
    
    func performSilentRefresh() async {
        // Prevent multiple concurrent refreshes
        if isRefreshing {
            print("🔄 [FeedManager] Refresh already in progress, skipping")
            return
        }
        
        // Rate limiting - don't refresh too frequently
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < minRefreshInterval {
            print("🔄 [FeedManager] Rate limited - last refresh too recent")
            return
        }
        
        // Cancel any existing refresh task
        activeRefreshTask?.cancel()
        
        // Create new refresh task
        activeRefreshTask = Task {
            await performActualRefresh()
        }
        
        await activeRefreshTask?.value
    }
    
    private func performActualRefresh() async {
        // Optimized refresh strategy - use since parameter for efficiency
        let baseFeedURLString = "\(AppConfig.baseURL)/feed/"
        var feedURLString: String
        var usingSinceParameter = false
        
        // Use since parameter for delta updates to reduce data transfer
        if !feedPosts.isEmpty, let latestPost = feedPosts.first {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let sinceDate = latestPost.createdAt.addingTimeInterval(-300) // 5 minutes buffer to catch updates
            feedURLString = baseFeedURLString + "?since=\(formatter.string(from: sinceDate))"
            usingSinceParameter = true
        } else {
            // Initial load - fetch full feed
            feedURLString = baseFeedURLString
        }
        
        print("🔄 [FeedManager] Refresh URL: \(feedURLString)")
        
        guard let url = URL(string: feedURLString) else { 
            print("❌ [FeedManager] Invalid refresh URL: \(feedURLString)")
            return 
        }
        guard let token = await AuthenticationManager.shared.storedAuthToken else { 
            print("❌ [FeedManager] No auth token for refresh")
            return 
        }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            
            // 🔧 ENHANCED: Add detailed response debugging before attempting to decode
            print("🔄 [FeedManager] Refresh response status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print("🔄 [FeedManager] Refresh response headers: \((response as? HTTPURLResponse)?.allHeaderFields ?? [:])")
            
            // Always log the raw response to see what we're getting
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔄 [FeedManager] Raw refresh response: \(responseString)")
            }
            
            // 🔧 ENHANCED: Check response status BEFORE attempting to decode
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeedError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ [FeedManager] Refresh failed with status \(httpResponse.statusCode)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    throw FeedError.serverError(detail)
                }
                throw FeedError.serverError("HTTP \(httpResponse.statusCode)")
            }
            
            // 🔧 ENHANCED: Try to decode with better error handling
            // 🔧 CRITICAL FIX: Use the same decoding pattern as comments (no convertFromSnakeCase)
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
            
            let fetchedPosts: [FeedPost]
            do {
                fetchedPosts = try decoder.decode([FeedPost].self, from: data)
                print("✅ [FeedManager] Successfully decoded \(fetchedPosts.count) posts from refresh")
            } catch let decodingError as DecodingError {
                print("❌ [FeedManager] Decoding error during refresh: \(decodingError)")
                
                // 🔧 NEW: Try to provide more detailed error information
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ [FeedManager] Missing key '\(key.stringValue)' at path: \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("❌ [FeedManager] Type mismatch for type \(type) at path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("❌ [FeedManager] Value not found for type \(type) at path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("❌ [FeedManager] Data corrupted at path: \(context.codingPath) - \(context.debugDescription)")
                @unknown default:
                    print("❌ [FeedManager] Unknown decoding error: \(decodingError)")
                }
                
                // 🔧 NEW: If we were using since parameter and got a decoding error, try full refresh
                if usingSinceParameter {
                    print("🔄 [FeedManager] Delta refresh failed, falling back to full refresh")
                    await MainActor.run {
                        self.isRefreshing = false
                    }
                    // Recursively call full refresh
                    await performFullFeedRefresh(token: token)
                    return
                }
                
                // 🔧 NEW: Otherwise, fallback to empty array
                print("🔄 [FeedManager] Using empty array as fallback for refresh decoding error")
                fetchedPosts = []
            } catch {
                print("❌ [FeedManager] General error during refresh decoding: \(error)")
                
                // 🔧 NEW: If we were using since parameter and got any error, try full refresh
                if usingSinceParameter {
                    print("🔄 [FeedManager] Delta refresh failed, falling back to full refresh")
                    await MainActor.run {
                        self.isRefreshing = false
                    }
                    await performFullFeedRefresh(token: token)
                    return
                }
                
                fetchedPosts = []
            }
            
            // 🔧 IMPROVED: Enhanced merge strategy that properly handles updates
            // Create a map of existing posts for efficient lookup
            var existingPostsMap: [UUID: FeedPost] = [:]
            for post in feedPosts {
                existingPostsMap[post.postId] = post
            }
            
            var hasNewPosts = false
            var hasUpdatedPosts = false
            var newPostCount = 0
            
            // Process each fetched post
            for fetchedPost in fetchedPosts {
                if let existingPost = existingPostsMap[fetchedPost.postId] {
                    // Post exists - check if it was updated
                    let wasUpdated = !arePostsContentEqual(existingPost, fetchedPost)
                    if wasUpdated {
                        existingPostsMap[fetchedPost.postId] = fetchedPost
                        hasUpdatedPosts = true
                        print("🔄 [FeedManager] Updated existing post \(fetchedPost.postId.uuidString.prefix(8))")
                    }
                } else {
                    // New post - add it
                    existingPostsMap[fetchedPost.postId] = fetchedPost
                    hasNewPosts = true
                    newPostCount += 1
                    print("🆕 [FeedManager] Added new post \(fetchedPost.postId.uuidString.prefix(8))")
                }
            }
            
            // Only proceed if there are actual changes
            guard hasNewPosts || hasUpdatedPosts else {
                await MainActor.run {
                    isRefreshing = false
                    lastRefreshTime = Date()
                }
                print("🔄 [FeedManager] Refresh completed - no changes detected")
                return
            }
            
            // Convert back to sorted array (newest first)
            var mergedPosts = Array(existingPostsMap.values).sorted { $0.createdAt > $1.createdAt }
            
            // Remove posts older than 24 hours to keep the feed lean
            let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
            let originalCount = mergedPosts.count
            mergedPosts = mergedPosts.filter { $0.createdAt >= cutoffDate }
            
            if originalCount != mergedPosts.count {
                print("🗑️ [FeedManager] Pruned \(originalCount - mergedPosts.count) feed post(s) older than 24h")
            }
            
            let previousCount = feedPosts.count
            
            // Capture values before MainActor.run to avoid concurrent access
            let postsToCache = mergedPosts
            let existingPostIds = Set(existingPostsMap.keys)
            let hasNewPostsFlag = hasNewPosts
            let hasUpdatedPostsFlag = hasUpdatedPosts
            let newPostCountFinal = newPostCount
            let mergedPostsCount = mergedPosts.count
            
            await MainActor.run {
                self.feedPosts = postsToCache
                
                // Single efficient cache update
                self.updateCacheEfficiently(postsToCache)
                
                // 🆕 NEW: Update comment cache for all posts with comments
                for post in postsToCache {
                    if !post.comments.isEmpty {
                        self.updateCommentCache(postId: post.postId, comments: post.comments)
                    }
                }
                
                // Background avatar prefetching for new/updated content
                let postsCopy = postsToCache
                Task.detached(priority: .background) {
                    await self.prefetchAvatars(from: postsCopy)
                }
                
                // Handle new post notifications
                if hasNewPostsFlag && previousCount > 0 {
                    let currentUserId = AuthenticationManager.shared.currentUser?.id ?? ""
                    let friendPosts = fetchedPosts.filter { 
                        $0.userId.uuidString != currentUserId && 
                        !existingPostIds.contains($0.postId) 
                    }
                    
                    self.onNewPostsDetected?(mergedPostsCount)
                    
                    if !friendPosts.isEmpty {
                        if friendPosts.count == 1, let post = friendPosts.first {
                            let habitName = HabitManager.shared.habits.first(where: { $0.id == post.habitId })?.name ?? "a habit"
                            NotificationManager.shared.showSingleFeedPostNotification(authorName: post.userName, habitName: habitName)
                        } else {
                            NotificationManager.shared.showFeedUpdateNotification(count: friendPosts.count)
                        }
                    }
                }
                
                // Update tracking variables
                self.lastRefreshTime = Date()
                self.isRefreshing = false
                
                let changeDescription = [
                    hasNewPostsFlag ? "\(newPostCountFinal) new" : nil,
                    hasUpdatedPostsFlag ? "updates" : nil
                ].compactMap { $0 }.joined(separator: ", ")
                
                print("✅ [FeedManager] Refresh completed: \(changeDescription) (\(mergedPostsCount) total posts)")
            }
        } catch {
            // 🔧 NEW: If we were using since parameter and got a network/other error, try full refresh
            if usingSinceParameter {
                print("🔄 [FeedManager] Delta refresh failed with error, falling back to full refresh: \(error)")
                await MainActor.run {
                    self.isRefreshing = false
                }
                await performFullFeedRefresh(token: token)
                return
            }
            
            await MainActor.run {
                isRefreshing = false
                lastRefreshTime = Date()
            }
            print("❌ [FeedManager] Refresh failed: \(error)")
            
            // 🔧 NEW: Add specific error handling for common issues
            if let urlError = error as? URLError {
                print("❌ [FeedManager] Network error during refresh: \(urlError.localizedDescription)")
            } else if let feedError = error as? FeedError {
                print("❌ [FeedManager] Feed error during refresh: \(feedError.localizedDescription)")
            } else {
                print("❌ [FeedManager] Unknown error during refresh: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Manual Refresh (User-initiated)
    
    /// Manual refresh that can be called from UI with proper loading states
    func manualRefresh() async {
        // Don't allow manual refresh if already refreshing
        if isRefreshing {
            print("🔄 [FeedManager] Manual refresh blocked - already refreshing")
            return
        }
        
        await performSilentRefresh()
    }
    
    /// Force a full feed refresh after adding a new friend
    /// This ensures we get all posts from the new friend, not just recent ones
    func refreshAfterNewFriend() async {
        print("🔄 [FeedManager] Force refreshing feed after new friend added")
        
        // Increased delay to ensure server has processed the new friendship
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        guard let token = await AuthenticationManager.shared.storedAuthToken else { return }
        
        // Clear rate limiting to ensure refresh happens
        lastRefreshTime = nil
        
        // Cancel any existing refresh task
        activeRefreshTask?.cancel()
        
        // Clear any cached feed data to force a complete refresh
        await MainActor.run {
            // Temporarily clear feed posts to ensure fresh data
            self.feedPosts = []
        }
        
        // Create new refresh task for FULL feed fetch (no since parameter)
        activeRefreshTask = Task {
            await performFullFeedRefresh(token: token)
        }
        
        await activeRefreshTask?.value
    }
    
    /// Perform a full feed refresh without using the since parameter
    private func performFullFeedRefresh(token: String) async {
        let feedURLString = "\(AppConfig.baseURL)/feed/"
        guard let url = URL(string: feedURLString) else { return }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            
            // 🔧 ENHANCED: Check response status BEFORE attempting to decode
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeedError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    throw FeedError.serverError(detail)
                }
                throw FeedError.serverError("HTTP \(httpResponse.statusCode)")
            }
            
            // 🔧 ENHANCED: Use the same robust decoding logic as refresh
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
            let fetchedPosts = try decoder.decode([FeedPost].self, from: data)
            
            print("🔄 [FeedManager] Full refresh fetched \(fetchedPosts.count) posts")
            
            // Log unique user IDs in the feed for debugging
            let uniqueUserIds = Set(fetchedPosts.map { $0.userId.uuidString })
            print("📊 [FeedManager] Posts from \(uniqueUserIds.count) unique users")
            
            // Get current user's friends list for debugging
            if let currentUserId = await AuthenticationManager.shared.currentUser?.id {
                let friendIds = FriendsManager.shared.preloadedFriends.map { $0.friendId }
                print("👥 [FeedManager] Current user has \(friendIds.count) friends")
                
                // Check if feed includes posts from all friends
                let friendsWithPosts = uniqueUserIds.intersection(Set(friendIds))
                let friendsWithoutPosts = Set(friendIds).subtracting(uniqueUserIds).subtracting([currentUserId])
                
                if !friendsWithoutPosts.isEmpty {
                    print("⚠️ [FeedManager] No posts found from \(friendsWithoutPosts.count) friend(s)")
                }
                print("✅ [FeedManager] Found posts from \(friendsWithPosts.count) friend(s)")
            }
            
            await MainActor.run {
                // Replace entire feed with fresh data
                self.feedPosts = fetchedPosts
                
                // Update cache
                self.updateCacheEfficiently(fetchedPosts)
                
                // 🆕 NEW: Update comment cache for all posts with comments
                for post in fetchedPosts {
                    if !post.comments.isEmpty {
                        self.updateCommentCache(postId: post.postId, comments: post.comments)
                    }
                }
                
                // Background avatar prefetching
                let postsCopy = fetchedPosts
                Task.detached(priority: .background) {
                    await self.prefetchAvatars(from: postsCopy)
                }
                
                // Update tracking variables
                self.lastRefreshTime = Date()
                self.isRefreshing = false
                
                print("✅ [FeedManager] Full feed refresh completed with \(fetchedPosts.count) posts")
            }
        } catch {
            await MainActor.run {
                isRefreshing = false
                lastRefreshTime = Date()
            }
            print("❌ [FeedManager] Full refresh failed: \(error)")
        }
    }
    
    // MARK: - Load More Posts (Pagination)
    
    /// Load more posts for pagination
    func loadMorePosts() async {
        guard !isLoadingMore && hasMorePosts else { return }
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        // Implement pagination logic here if backend supports it
        // For now, this is a placeholder for future implementation
        
        await MainActor.run {
            isLoadingMore = false
        }
    }
    
    // MARK: - Timer Management
    
    func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        // Cancel any active refresh tasks
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        
        // Cancel all active comment refresh tasks
        cacheQueue.async {
            for task in self.activeCommentsRefreshTasks.values {
                task.cancel()
            }
            self.activeCommentsRefreshTasks.removeAll()
        }
        
        print("⏹️ [FeedManager] Stopped refresh timer and cancelled all active tasks")
    }
    
    func pausePeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("⏸️ [FeedManager] Paused periodic refresh")
    }
    
    func resumePeriodicRefresh() {
        // Only resume if we don't already have a timer
        guard refreshTimer == nil else {
            print("⏸️ [FeedManager] Refresh timer already running")
            return
        }
        
        setupPeriodicRefresh()
        print("▶️ [FeedManager] Resumed periodic refresh")
    }
    
    // MARK: - Cleanup Methods
    
    /// Clean up any cancelled or completed tasks
    private func cleanupTasks() {
        // Remove completed comment refresh tasks
        cacheQueue.async {
            self.activeCommentsRefreshTasks = self.activeCommentsRefreshTasks.filter { _, task in
                !task.isCancelled
            }
        }
        
        // Clean up completed refresh task
        if let task = activeRefreshTask, task.isCancelled {
            activeRefreshTask = nil
        }
    }
    
    /// Reset all state (useful for logout or app restart)
    func resetState() {
        stopPeriodicRefresh()
        
        feedPosts.removeAll()
        errorMessage = nil
        hasInitialized = false
        isRefreshing = false
        isLoadingMore = false
        lastRefreshTime = nil
        currentPage = 0
        hasMorePosts = true
        
        print("🔄 [FeedManager] Reset all state")
    }
    
    // MARK: - Helper Methods
    
    /// 🔧 NEW: Centralized robust user ID comparison to handle potential format differences
    @MainActor private func isPostFromCurrentUser(_ post: FeedPost) -> Bool {
        guard let current = AuthenticationManager.shared.currentUser else { return false }
        
        let currentUserId = current.id
        let postUserIdString = post.userId.uuidString
        
        return currentUserId == postUserIdString ||
               currentUserId.lowercased() == postUserIdString.lowercased() ||
               currentUserId.replacingOccurrences(of: "-", with: "") == postUserIdString.replacingOccurrences(of: "-", with: "")
    }
    
    private func createRequest(url: URL, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func handleNetworkResponse<T: Codable>(_ data: Data, _ response: URLResponse, expecting: T.Type) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FeedError.serverError(detail)
            }
            throw FeedError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // Configure date decoder using the optimized DateFormatterManager
        let decoder = JSONDecoder.configuredForAPI()
        
        // Add debug logging to see what we're receiving
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Received JSON response: \(jsonString)")
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    
    private func arePostsEqual(_ posts1: [FeedPost], _ posts2: [FeedPost]) -> Bool {
        // Compare ordering *and* critical visible attributes so edits (like caption changes)
        // trigger a UI refresh.
        guard posts1.count == posts2.count else { return false }
        for (post1, post2) in zip(posts1, posts2) {
            if post1.postId != post2.postId { return false }
            if post1.caption != post2.caption { return false }
            if post1.selfieImageUrl != post2.selfieImageUrl { return false }
            if post1.contentImageUrl != post2.contentImageUrl { return false }
        }
        return true
    }
    
    /// 🔧 NEW: Efficiently compare individual posts for content changes
    private func arePostsContentEqual(_ post1: FeedPost, _ post2: FeedPost) -> Bool {
        return post1.postId == post2.postId &&
               post1.caption == post2.caption &&
               post1.selfieImageUrl == post2.selfieImageUrl &&
               post1.contentImageUrl == post2.contentImageUrl &&
               post1.comments.count == post2.comments.count &&
               post1.streak == post2.streak &&
               post1.userAvatarUrl80 == post2.userAvatarUrl80 &&
               post1.userAvatarUrl200 == post2.userAvatarUrl200 &&
               post1.userAvatarUrlOriginal == post2.userAvatarUrlOriginal
    }
    
    /// 🔧 NEW: Single efficient cache update method that replaces multiple redundant calls
    @MainActor private func updateCacheEfficiently(_ posts: [FeedPost]) {
        let cacheFormatPosts = convertPostsToCacheFormat(posts)
        DataCacheManager.shared.updateFeedCacheWithFreshData(cacheFormatPosts)
        print("💾 [FeedManager] Efficiently updated cache with \(posts.count) posts")
    }
    
    // MARK: - Comments-Only Refresh (Efficient)
    
    /// Refresh comments for all current posts without reloading posts themselves
    func refreshCommentsOnly() async {
        print("💬 [FeedManager] Refreshing comments only for \(feedPosts.count) posts")
        
        guard !feedPosts.isEmpty else {
            print("💬 [FeedManager] No posts to refresh comments for")
            return
        }
        
        // Extract post IDs to refresh comments for
        let postIds = feedPosts.map { $0.postId.uuidString }
        
        await performCommentsRefresh(for: postIds)
    }
    
    /// Refresh comments for a single specific post
    func refreshCommentsForPost(postId: UUID) async {
        print("🔄 [FeedManager] Refreshing comments for single post: \(postId.uuidString.prefix(8))")
        
        // Check if we have this post
        guard feedPosts.contains(where: { $0.postId == postId }) else {
            print("⚠️ [FeedManager] Post not found in current feed: \(postId.uuidString.prefix(8))")
            return
        }
        
        // Use the new smart cache system
        await forceRefreshCommentsForPost(postId: postId)
    }
    
    /// Refresh comments for all posts when comments view is first opened
    func refreshAllCommentsOnViewOpen() async {
        print("💬 [FeedManager] Refreshing comments for ALL posts when comments view opens")
        
        guard !feedPosts.isEmpty else {
            print("💬 [FeedManager] No posts to refresh comments for")
            return
        }
        
        // Use the bulk refresh for all posts
        let postIds = feedPosts.map { $0.postId.uuidString }
        await performCommentsRefresh(for: postIds)
    }
    
    /// Refresh comments for specific posts
    private func performCommentsRefresh(for postIds: [String]) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/feed/comments/get") else { 
            print("❌ [FeedManager] Invalid URL for comments refresh")
            return 
        }
        guard let token = await AuthenticationManager.shared.storedAuthToken else {
            print("❌ [FeedManager] No auth token for comments refresh")
            return 
        }
        
        print("💬 [FeedManager] Requesting comments for post IDs: \(postIds)")
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Send post IDs to get comments for
            let requestBody = ["post_ids": postIds]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Debug log the request body
            if let bodyData = request.httpBody,
               let bodyString = String(data: bodyData, encoding: .utf8) {
                print("💬 [FeedManager] Request body: \(bodyString)")
            }
            
            let (data, response) = try await urlSession.data(for: request)
            
            // Handle response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeedError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw FeedError.badStatusCode(httpResponse.statusCode)
            }
            
            // Debug log the response
            if let responseString = String(data: data, encoding: .utf8) {
                print("💬 [FeedManager] Comments response: \(responseString)")
            }
            
            // Create custom decoder for comments without convertFromSnakeCase to avoid conflicts
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
            
            let commentsResponse = try decoder.decode([String: [Comment]].self, from: data)
            
            await MainActor.run {
                updateCommentsForPosts(commentsResponse)
            }
            
            print("✅ [FeedManager] Comments refreshed for \(commentsResponse.keys.count) posts")
            
        } catch {
            print("❌ [FeedManager] Failed to refresh comments: \(error)")
        }
    }
    
    /// Refresh comments for a single post (optimized)
    private func performSinglePostCommentsRefresh(for postId: String) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/feed/comments/\(postId)") else { 
            print("❌ [FeedManager] Invalid URL for single post comments refresh")
            return 
        }
        guard let token = await AuthenticationManager.shared.storedAuthToken else { 
            print("❌ [FeedManager] No auth token for single post comments refresh")
            return 
        }
        
        print("💬 [FeedManager] Requesting comments for single post: \(postId)")
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await urlSession.data(for: request)
            
            // Handle response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeedError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw FeedError.badStatusCode(httpResponse.statusCode)
            }
            
            // Debug log the response
            if let responseString = String(data: data, encoding: .utf8) {
                print("💬 [FeedManager] Single post comments response: \(responseString)")
            }
            
            // Create custom decoder for comments without convertFromSnakeCase to avoid conflicts
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
            
            let comments = try decoder.decode([Comment].self, from: data)
            
            await MainActor.run {
                updateCommentsForSinglePost(postId: postId, comments: comments)
            }
            
            print("✅ [FeedManager] Comments refreshed for single post: \(postId.prefix(8))")
            
        } catch {
            print("❌ [FeedManager] Failed to refresh single post comments: \(error)")
        }
    }
    
    /// Update comments for posts based on server response
    @MainActor private func updateCommentsForPosts(_ commentsData: [String: [Comment]]) {
        var updatedPosts = feedPosts
        var hasChanges = false
        
        for (index, post) in feedPosts.enumerated() {
            let postIdString = post.postId.uuidString
            
            if let newComments = commentsData[postIdString] {
                print("💬 [FeedManager] Processing comments update for post \(postIdString.prefix(8)): \(post.comments.count) -> \(newComments.count)")
                
                // 🔧 ENHANCED: Merge strategy that preserves recent local additions
                var mergedComments = newComments
                
                // Check if we have any very recent comments (added within last 30 seconds) that aren't in the server response
                let recentCutoff = Date().addingTimeInterval(-30)
                let recentLocalComments = post.comments.filter { comment in
                    comment.createdAt > recentCutoff && !newComments.contains(where: { $0.id == comment.id })
                }
                
                if !recentLocalComments.isEmpty {
                    print("💬 [FeedManager] Found \(recentLocalComments.count) recent local comments to preserve")
                    mergedComments.append(contentsOf: recentLocalComments)
                }
                
                // Re-organize the merged comments to ensure proper structure
                let organizedComments = organizeCommentsFlattened(mergedComments)
                
                // 🆕 ENHANCED: More thorough comparison that detects content changes
                let commentsChanged = hasCommentsChanged(old: post.comments, new: organizedComments)
                
                if commentsChanged {
                    // 🔧 OPTIMIZED: Use helper method to create updated post
                    let updatedPost = createUpdatedPost(from: post, withComments: organizedComments)
                    
                    updatedPosts[index] = updatedPost
                    hasChanges = true
                    
                    // 🆕 CRITICAL: Update comment cache with fresh backend data
                    self.updateCommentCache(postId: post.postId, comments: organizedComments)
                    
                    // 🆕 NEW: Notify observers that comments were updated
                    NotificationCenter.default.post(
                        name: .commentsUpdated,
                        object: nil,
                        userInfo: ["postId": postIdString, "comments": organizedComments]
                    )
                    
                    print("💬 [FeedManager] Updated comments for post \(postIdString.prefix(8)): \(post.comments.count) → \(organizedComments.count)")
                } else {
                    print("💬 [FeedManager] No changes detected for post \(postIdString.prefix(8))")
                    // 🆕 NEW: Even if no changes, update cache timestamp to mark as fresh
                    self.updateCommentCache(postId: post.postId, comments: post.comments)
                }
            }
        }
        
        if hasChanges {
            feedPosts = updatedPosts
            // 🔧 OPTIMIZED: Single efficient cache update
            updateCacheEfficiently(feedPosts)
            
            // 🆕 NEW: Notify observers of comment updates
            for (postIdString, newComments) in commentsData {
                NotificationCenter.default.post(
                    name: .commentsUpdated,
                    object: nil,
                    userInfo: ["postId": postIdString, "comments": newComments]
                )
            }
            
            // 🚀 Prefetch avatars for all new/updated comments so they appear instantly
            Task { @MainActor in
                let allComments = updatedPosts.flatMap { $0.comments }
                await self.prefetchAvatars(fromComments: allComments)
            }
            print("✅ [FeedManager] Comments refresh completed with changes and cache updated")
        } else {
            print("✅ [FeedManager] Comments refresh completed - no changes detected")
        }
    }
    
    /// Update comments for a single post
    @MainActor private func updateCommentsForSinglePost(postId: String, comments: [Comment]) {
        if let postIndex = feedPosts.firstIndex(where: { $0.postId.uuidString == postId }) {
            // 🆕 ENHANCED: Use improved comparison logic
            let existingComments = feedPosts[postIndex].comments
            let commentsChanged = hasCommentsChanged(old: existingComments, new: comments)
            
            if commentsChanged {
                // 🔧 OPTIMIZED: Use helper method to create updated post
                let updatedPost = createUpdatedPost(from: feedPosts[postIndex], withComments: comments)
                
                // Update the feedPosts array
                feedPosts[postIndex] = updatedPost
                
                // 🔧 OPTIMIZED: Single efficient cache update
                updateCacheEfficiently(feedPosts)
                
                // 🆕 CRITICAL: Update comment cache with fresh backend data
                if let postUUID = UUID(uuidString: postId) {
                    self.updateCommentCache(postId: postUUID, comments: comments)
                }
                
                // 🆕 NEW: Notify observers that comments were updated
                NotificationCenter.default.post(
                    name: .commentsUpdated,
                    object: nil,
                    userInfo: ["postId": postId, "comments": comments]
                )
                
                // Prefetch avatars for the freshly loaded comments (background)
                Task { @MainActor in
                    await self.prefetchAvatars(fromComments: comments)
                }
                print("💬 [FeedManager] Updated comments for single post: \(postId.prefix(8)) (\(existingComments.count) → \(comments.count))")
            } else {
                print("💬 [FeedManager] No comment changes detected for post: \(postId.prefix(8))")
                // 🆕 NEW: Even if no changes, update cache timestamp to mark as fresh
                if let postUUID = UUID(uuidString: postId) {
                    self.updateCommentCache(postId: postUUID, comments: existingComments)
                }
            }
        } else {
            print("⚠️ [FeedManager] Post not found for comment update: \(postId.prefix(8))")
        }
    }
    
    // MARK: - Enhanced Comment Comparison
    
    /// 🆕 NEW: Enhanced comparison that detects content changes, not just ID differences
    private func hasCommentsChanged(old: [Comment], new: [Comment]) -> Bool {
        // Quick count check first
        guard old.count == new.count else {
            print("💬 [FeedManager] Comment count changed: \(old.count) → \(new.count)")
            return true
        }
        
        // Create maps for efficient lookup
        let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let _ = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        // Check if any comment IDs are different
        let oldIds = Set(old.map { $0.id })
        let newIds = Set(new.map { $0.id })
        if oldIds != newIds {
            print("💬 [FeedManager] Comment IDs changed")
            return true
        }
        
        // Check if any comment content changed
        for comment in new {
            guard let oldComment = oldMap[comment.id] else {
                print("💬 [FeedManager] New comment found: \(comment.id.uuidString.prefix(8))")
                return true
            }
            
            // Compare content, edit status, and other important fields
            if oldComment.content != comment.content ||
               oldComment.isEdited != comment.isEdited ||
               oldComment.userName != comment.userName ||
               oldComment.userAvatarUrl80 != comment.userAvatarUrl80 ||
               oldComment.userAvatarUrl200 != comment.userAvatarUrl200 ||
               oldComment.userAvatarUrlOriginal != comment.userAvatarUrlOriginal {
                print("💬 [FeedManager] Comment content changed for: \(comment.id.uuidString.prefix(8))")
                return true
            }
            
            // Compare parent comment if it exists
            if let oldParent = oldComment.parentComment, let newParent = comment.parentComment {
                if oldParent.id != newParent.id || 
                   oldParent.content != newParent.content ||
                   oldParent.userName != newParent.userName {
                    print("💬 [FeedManager] Parent comment changed for: \(comment.id.uuidString.prefix(8))")
                    return true
                }
            } else if oldComment.parentComment != nil || comment.parentComment != nil {
                // One has parent, other doesn't
                print("💬 [FeedManager] Parent comment structure changed for: \(comment.id.uuidString.prefix(8))")
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Avatar Enrichment Helper

    /// Some endpoints (e.g. verification preview) omit avatar URLs for the current
    /// user.  This helper patches the `FeedPost` so the UI never shows a placeholder.
    @MainActor private func enrichWithCurrentUserAvatarIfNeeded(_ post: FeedPost) -> FeedPost {
        guard let current = AuthenticationManager.shared.currentUser else { 
            print("🔧 [FeedManager] No current user available for post \(post.postId.uuidString.prefix(8)), no enrichment")
            return post 
        }
        
        // 🔧 ENHANCED: More robust user ID comparison with better debug logging
        let currentUserId = current.id
        let postUserIdString = post.userId.uuidString
        
        print("🔧 [FeedManager] Comparing user IDs for post \(post.postId.uuidString.prefix(8)):")
        print("   - currentUser.id: '\(currentUserId)' (type: \(type(of: currentUserId)))")
        print("   - post.userId.uuidString: '\(postUserIdString)' (type: \(type(of: postUserIdString)))")
        
        // Try multiple comparison strategies to handle potential format differences
        let isCurrentUserPost = currentUserId == postUserIdString ||
                               currentUserId.lowercased() == postUserIdString.lowercased() ||
                               currentUserId.replacingOccurrences(of: "-", with: "") == postUserIdString.replacingOccurrences(of: "-", with: "")
        
        guard isCurrentUserPost else { 
            print("🔧 [FeedManager] Post \(post.postId.uuidString.prefix(8)) is not from current user, no enrichment needed")
            return post 
        }
        
        print("✅ [FeedManager] Post \(post.postId.uuidString.prefix(8)) IS from current user, checking for avatar enrichment")

        // 🔧 ENHANCED: More robust URL checking
        let hasValidURL: (String?) -> Bool = { str in
            guard let s = str?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !s.isEmpty && s != "null" && s != "nil"
        }
        
        // Check if we already have at least one valid avatar URL
        if hasValidURL(post.userAvatarUrl80) || hasValidURL(post.userAvatarUrl200) || hasValidURL(post.userAvatarUrlOriginal) {
            print("🔧 [FeedManager] Post \(post.postId.uuidString.prefix(8)) already has valid avatar URLs, no enrichment needed")
            return post // Already has avatar URLs, no enrichment needed
        }

        // 🔧 ENHANCED: Build fallback URLs with priority for higher quality images
        let fallback80 = current.avatarUrl80 ?? current.avatarUrl200 ?? current.profilePhotoUrl
        let fallback200 = current.avatarUrl200 ?? current.avatarUrl80 ?? current.profilePhotoUrl  
        let fallbackOrig = current.avatarUrlOriginal ?? current.avatarUrl200 ?? current.avatarUrl80 ?? current.profilePhotoUrl

        print("🔧 [FeedManager] Enriching post \(post.postId.uuidString.prefix(8)) with avatar URLs:")
        print("   - fallback80: \(fallback80 ?? "nil")")
        print("   - fallback200: \(fallback200 ?? "nil")")
        print("   - fallbackOrig: \(fallbackOrig ?? "nil")")

        // 🔧 OPTIMIZED: Create new post with enriched avatar data
        let enrichedPost = FeedPost(
            postId: post.postId,
            habitId: post.habitId,
            caption: post.caption,
            createdAt: post.createdAt,
            isPrivate: post.isPrivate,
            imageUrl: post.imageUrl,
            selfieImageUrl: post.selfieImageUrl,
            contentImageUrl: post.contentImageUrl,
            userId: post.userId,
            userName: post.userName,
            userAvatarUrl80: fallback80,
            userAvatarUrl200: fallback200,
            userAvatarUrlOriginal: fallbackOrig,
            userAvatarVersion: current.avatarVersion ?? post.userAvatarVersion,
            streak: post.streak,
            habitType: post.habitType,
            habitName: post.habitName,
            penaltyAmount: post.penaltyAmount,
            comments: post.comments
        )
        
        print("✅ [FeedManager] Enriched post \(post.postId.uuidString.prefix(8)) with current user avatar URLs")
        return enrichedPost
    }
    
    // Helper to decide if comments need refreshing - now uses smart cache
    @MainActor func commentsNeedRefresh(for postId: UUID) -> Bool {
        return !isCommentCacheFresh(for: postId)
    }
    
    // MARK: - Basic Comment Cache Management
    
    private func isCommentCacheFresh(for postId: UUID) -> Bool {
        return cacheQueue.sync {
            guard let cached = commentCache[postId] else { return false }
            return !cached.isExpired
        }
    }
    
    private func getCommentsFromCache(for postId: UUID) -> [Comment]? {
        return cacheQueue.sync {
            guard let cached = commentCache[postId] else { return nil }
            return cached.isStale ? nil : cached.comments
        }
    }
    
    private func updateCommentCache(postId: UUID, comments: [Comment]) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.commentCache[postId] = CachedComments(comments: comments, timestamp: Date())
            self.commentsLastFetched[postId] = Date()
            print("💾 [FeedManager] Updated comment cache for post \(postId.uuidString.prefix(8))")
        }
    }
    
    // MARK: - Smart Comment Loading API
    
    /// Load comments using smart caching - returns cached data immediately if available,
    /// then checks for updates in background if needed
    func getCommentsSmartCache(for postId: UUID) async -> [Comment] {
        print("🧠 [FeedManager] Smart loading comments for post \(postId.uuidString.prefix(8))")
        
        // Check cache first
        let cached = cacheQueue.sync { commentCache[postId] }
        if let cached = cached, !cached.isExpired {
            print("💾 [FeedManager] Using cached comments (\(cached.comments.count) comments)")
            
            // If cache is stale but not expired, check for updates in background
            if cached.isStale {
                print("🔄 [FeedManager] Cache is stale, checking for updates in background")
                Task.detached(priority: .utility) {
                    await self.refreshCommentsInBackground(for: postId)
                }
            }
            
            return cached.comments
        }
        
        // 🆕 NEW: Check for existing comments in the current post before network fetch
        let existingComments = feedPosts.first(where: { $0.postId == postId })?.comments ?? []
        if !existingComments.isEmpty {
            print("💾 [FeedManager] No cache but found existing post comments (\(existingComments.count) comments)")
            // Cache them for future use
            updateCommentCache(postId: postId, comments: existingComments)
            return existingComments
        }
        
        // No cache and no existing comments - fetch fresh from network
        print("🌐 [FeedManager] No cache or existing comments found, fetching from network")
        return await fetchCommentsFromNetwork(for: postId)
    }
    
    /// Check if we have fresh cached comments for a post
    func hasFreshCachedComments(for postId: UUID) -> Bool {
        return cacheQueue.sync {
            guard let cached = commentCache[postId] else { return false }
            return !cached.isStale && !cached.isExpired
        }
    }
    
    /// Force refresh comments for a post (ignoring cache)
    func forceRefreshCommentsForPost(postId: UUID) async {
        print("🔄 [FeedManager] Force refreshing comments for post \(postId.uuidString.prefix(8))")
        let freshComments = await fetchCommentsFromNetwork(for: postId)
        
        await MainActor.run {
            updateCommentsForSinglePost(postId: postId.uuidString, comments: freshComments)
        }
    }
    
    /// When opening comments sheet, use smart cache but also check for fresh data
    func loadCommentsForSheet(postId: UUID) async -> [Comment] {
        print("💾 [CommentSheet] Loading comments for sheet - post \(postId.uuidString.prefix(8))")
        
        // 🆕 NEW: First check if we have existing comments in the current post
        let existingComments = feedPosts.first(where: { $0.postId == postId })?.comments ?? []
        
        // If we have existing comments and no cache, populate the cache first
        let hasCache = cacheQueue.sync { commentCache[postId] != nil }
        if !existingComments.isEmpty && !hasCache {
            updateCommentCache(postId: postId, comments: existingComments)
            print("💾 [FeedManager] Initialized comment cache with \(existingComments.count) existing comments")
            return existingComments
        }
        
        // First, get from smart cache (immediate response)
        let cachedComments = await getCommentsSmartCache(for: postId)
        
        // If we got comments from cache, return them
        if !cachedComments.isEmpty {
            print("💾 [FeedManager] Using cached comments for sheet (\(cachedComments.count) comments)")
            return cachedComments
        }
        
        // If cache is empty but we have existing comments, use those
        if !existingComments.isEmpty {
            print("💾 [FeedManager] Cache empty, using existing post comments (\(existingComments.count) comments)")
            updateCommentCache(postId: postId, comments: existingComments)
            return existingComments
        }
        
        // No existing comments - check for updates from network
        print("🔄 [FeedManager] No existing comments, fetching from network")
        let freshComments = await fetchCommentsFromNetwork(for: postId)
        
        // Update FeedManager state with fresh comments
        await MainActor.run {
            updateCommentsForSinglePost(postId: postId.uuidString, comments: freshComments)
        }
        
        return freshComments
    }
    
    // MARK: - Network Fetching
    
    private func fetchCommentsFromNetwork(for postId: UUID) async -> [Comment] {
        do {
            let comments = try await performNetworkFetch(for: postId)
            updateCommentCache(postId: postId, comments: comments)
            return comments
        } catch {
            print("❌ [FeedManager] Network fetch failed: \(error)")
            // Return cached data if available, even if expired
            return cacheQueue.sync { commentCache[postId]?.comments ?? [] }
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
    
    private func refreshCommentsInBackground(for postId: UUID) async {
        let freshComments = await fetchCommentsFromNetwork(for: postId)
        
        // Compare with cached version using enhanced comparison
        let cachedComments = cacheQueue.sync { commentCache[postId]?.comments }
        if let cachedComments = cachedComments {
            let hasChanges = hasCommentsChanged(old: cachedComments, new: freshComments)
            
            if hasChanges {
                print("🔄 [FeedManager] Background refresh found changes for post \(postId.uuidString.prefix(8))")
                await MainActor.run {
                    updateCommentsForSinglePost(postId: postId.uuidString, comments: freshComments)
                    // 🆕 NEW: Notify observers that comments were updated
                    NotificationCenter.default.post(
                        name: .commentsUpdated,
                        object: nil,
                        userInfo: ["postId": postId.uuidString, "comments": freshComments]
                    )
                }
            } else {
                print("🔄 [FeedManager] Background refresh found no changes for post \(postId.uuidString.prefix(8))")
                // Still update cache timestamp to keep it fresh
                updateCommentCache(postId: postId, comments: freshComments)
            }
        } else {
            // No cached version, just update with fresh data
            print("🔄 [FeedManager] Background refresh with no existing cache for post \(postId.uuidString.prefix(8))")
            await MainActor.run {
                updateCommentsForSinglePost(postId: postId.uuidString, comments: freshComments)
            }
        }
    }
    
    // 🆕 DEPRECATED: Use hasCommentsChanged instead for better detection
    private func areCommentsEqual(_ comments1: [Comment], _ comments2: [Comment]) -> Bool {
        return !hasCommentsChanged(old: comments1, new: comments2)
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
    
    // MARK: - Avatar Prefetching
    
    /// Pre-loads avatar images for all distinct authors in the supplied posts.
    /// This minimises on-scroll stalls and ensures `CachedAvatarView` finds the
    /// bitmaps in either the Kingfisher cache or `AvatarImageStore`.
    @MainActor
    private func prefetchAvatars(from posts: [FeedPost]) async {
        // Collect unique avatar URL strings (prefer small, then medium, then original)
        let uniqueStrings: Set<String> = Set(posts.compactMap { post in
            post.userAvatarUrl80 ?? post.userAvatarUrl200 ?? post.userAvatarUrlOriginal
        }.filter { !$0.isEmpty })

        guard !uniqueStrings.isEmpty else { return }

        for string in uniqueStrings {
            guard let url = URL(string: string) else { continue }

            // 1️⃣ If already in shared store → nothing to do.
            if AvatarImageStore.shared.image(for: string) != nil {
                continue
            }

            // 2️⃣ Try memory cache.
            if let mem = ImageCache.default.retrieveImageInMemoryCache(forKey: string) {
                AvatarImageStore.shared.set(mem, for: string)
                continue
            }

            // 3️⃣ Try disk cache (async).
            if let disk = try? await ImageCache.default.retrieveImageInDiskCache(forKey: string) {
                // Promote to mem + shared store
                _ = try? await ImageCache.default.store(disk, forKey: string)
                AvatarImageStore.shared.set(disk, for: string)
                continue
            }

            // 4️⃣ Finally, prefetch over network with low priority.
            let options: KingfisherOptionsInfo = [
                .cacheOriginalImage,
                .transition(.none),
                .downloadPriority(0.2) // low priority so it doesn't block visible images
            ]

            do {
                let result = try await KingfisherManager.shared.retrieveImage(with: url, options: options).image
                AvatarImageStore.shared.set(result, for: string)
            } catch {
                print("⚠️ [FeedManager] Avatar prefetch failed for \(string): \(error)")
            }
        }
    }
    
    /// Prefetches avatar images for a collection of comments. Mirrors the logic used for
    /// post authors, but pulls the URLs from each `Comment` so every commenter's profile
    /// picture is ready the moment the sheet opens.
    @MainActor
    private func prefetchAvatars(fromComments comments: [Comment]) async {
        // Gather the best available URL for each commenter (small → medium → original)
        let uniqueStrings: Set<String> = Set(comments.compactMap { comment in
            comment.userAvatarUrl80 ?? comment.userAvatarUrl200 ?? comment.userAvatarUrlOriginal
        }.filter { !$0.isEmpty })

        guard !uniqueStrings.isEmpty else { return }

        for string in uniqueStrings {
            guard let url = URL(string: string) else { continue }

            // 1️⃣ Shared in-memory store
            if AvatarImageStore.shared.image(for: string) != nil { continue }

            // 2️⃣ Try Kingfisher memory cache
            if let mem = ImageCache.default.retrieveImageInMemoryCache(forKey: string) {
                AvatarImageStore.shared.set(mem, for: string)
                continue
            }

            // 3️⃣ Try disk cache (async)
            if let disk = try? await ImageCache.default.retrieveImageInDiskCache(forKey: string) {
                _ = try? await ImageCache.default.store(disk, forKey: string) // promote to mem
                AvatarImageStore.shared.set(disk, for: string)
                continue
            }

            // 4️⃣ Network fetch with very low priority so visible work is not blocked
            let options: KingfisherOptionsInfo = [
                .cacheOriginalImage,
                .transition(.none),
                .downloadPriority(0.15)
            ]

            do {
                let img = try await KingfisherManager.shared.retrieveImage(with: url, options: options).image
                AvatarImageStore.shared.set(img, for: string)
            } catch {
                print("⚠️ [FeedManager] Comment-avatar prefetch failed for \(string): \(error)")
            }
        }
    }

    // MARK: - Current User Avatar Update

    /// Propagate new avatar URLs to all feed posts authored by the current user so
    /// they update instantly when the user changes their profile picture.
    @MainActor
    func updateCurrentUserAvatar(avatarVersion: Int?, avatarUrl80: String?, avatarUrl200: String?, avatarUrlOriginal: String?) {
        guard AuthenticationManager.shared.currentUser != nil else { return }

        // Create a new array so that `@Published` emits a fresh value and SwiftUI updates
        var updatedPosts: [FeedPost] = []
        updatedPosts.reserveCapacity(feedPosts.count)
        var hasChanges = false

        for post in feedPosts {
            if isPostFromCurrentUser(post) {
                // 🔧 OPTIMIZED: Check if avatar actually changed before creating new post
                let avatarChanged = post.userAvatarUrl80 != avatarUrl80 ||
                                  post.userAvatarUrl200 != avatarUrl200 ||
                                  post.userAvatarUrlOriginal != avatarUrlOriginal ||
                                  post.userAvatarVersion != avatarVersion
                
                if avatarChanged {
                    let newPost = FeedPost(
                        postId: post.postId,
                        habitId: post.habitId,
                        caption: post.caption,
                        createdAt: post.createdAt,
                        isPrivate: post.isPrivate,
                        imageUrl: post.imageUrl,
                        selfieImageUrl: post.selfieImageUrl,
                        contentImageUrl: post.contentImageUrl,
                        userId: post.userId,
                        userName: post.userName,
                        userAvatarUrl80: avatarUrl80 ?? post.userAvatarUrl80,
                        userAvatarUrl200: avatarUrl200 ?? post.userAvatarUrl200,
                        userAvatarUrlOriginal: avatarUrlOriginal ?? post.userAvatarUrlOriginal,
                        userAvatarVersion: avatarVersion ?? post.userAvatarVersion,
                        streak: post.streak,
                        habitType: post.habitType,
                        habitName: post.habitName,
                        penaltyAmount: post.penaltyAmount,
                        comments: post.comments
                    )
                    updatedPosts.append(newPost)
                    hasChanges = true
                } else {
                    updatedPosts.append(post)
                }
            } else {
                updatedPosts.append(post)
            }
        }

        guard hasChanges else { return }

        // Assigning a new array triggers the `@Published` change notification.
        feedPosts = updatedPosts

        print("🖼️ [FeedManager] Updated avatar URLs for current user's posts - triggering UI refresh")

        // 🔧 OPTIMIZED: Cache new avatar images efficiently
        let avatarURLs = [avatarUrl80, avatarUrl200, avatarUrlOriginal].compactMap { $0 }.filter { !$0.isEmpty }
        
        Task.detached(priority: .userInitiated) {
            await self.cacheAvatarVariants(avatarURLs)
        }

        // 🔧 OPTIMIZED: Single efficient cache update
        updateCacheEfficiently(feedPosts)
    }
    
    /// 🔧 NEW: Efficiently cache avatar variants
    private func cacheAvatarVariants(_ avatarURLs: [String]) async {
        // First check existing caches
        for urlString in avatarURLs {
            if await AvatarImageStore.shared.image(for: urlString) != nil {
                continue // already cached
            }
            if let memCached = ImageCache.default.retrieveImageInMemoryCache(forKey: urlString) {
                await AvatarImageStore.shared.set(memCached, for: urlString)
                continue
            }
        }
        
        // If no images found in cache, fetch the primary URL and cache it under all variants
        if let primaryURL = avatarURLs.first,
           await AvatarImageStore.shared.image(for: primaryURL) == nil {
            guard let url = URL(string: primaryURL) else { return }
            let options: KingfisherOptionsInfo = [.cacheOriginalImage, .downloadPriority(0.6)]
            if let img = try? await KingfisherManager.shared.retrieveImage(with: url, options: options).image {
                await MainActor.run {
                    // Cache under all variant URLs
                    for urlString in avatarURLs {
                        AvatarImageStore.shared.set(img, for: urlString)
                    }
                }
            }
        }
    }
    
    /// Update the caption for a specific post and refresh cache
    @MainActor func updatePostCaption(postId: UUID, newCaption: String) {
        if let postIndex = feedPosts.firstIndex(where: { $0.postId == postId }) {
            let currentPost = feedPosts[postIndex]
            
            // 🔧 OPTIMIZED: Use helper method to create updated post with new caption
            let updatedPost = FeedPost(
                postId: currentPost.postId,
                habitId: currentPost.habitId,
                caption: newCaption,
                createdAt: currentPost.createdAt,
                isPrivate: currentPost.isPrivate,
                imageUrl: currentPost.imageUrl,
                selfieImageUrl: currentPost.selfieImageUrl,
                contentImageUrl: currentPost.contentImageUrl,
                userId: currentPost.userId,
                userName: currentPost.userName,
                userAvatarUrl80: currentPost.userAvatarUrl80,
                userAvatarUrl200: currentPost.userAvatarUrl200,
                userAvatarUrlOriginal: currentPost.userAvatarUrlOriginal,
                userAvatarVersion: currentPost.userAvatarVersion,
                streak: currentPost.streak,
                habitType: currentPost.habitType,
                habitName: currentPost.habitName,
                penaltyAmount: currentPost.penaltyAmount,
                comments: currentPost.comments
            )
            
            // Update the feedPosts array
            feedPosts[postIndex] = updatedPost
            
            // 🔧 OPTIMIZED: Single efficient cache update
            updateCacheEfficiently(feedPosts)
            
            print("✏️ [FeedManager] Updated caption for post \(postId.uuidString.prefix(8))")
        } else {
            print("⚠️ [FeedManager] Post not found for caption update: \(postId.uuidString.prefix(8))")
        }
    }
    
    /// Insert a new post into the feed (or update it if it already exists) and refresh the caches immediately
    @MainActor func insertOrUpdatePost(_ post: FeedPost) async {
        // 🔧 ENHANCED: More robust avatar enrichment for current user posts
        let processedPost = enrichWithCurrentUserAvatarIfNeeded(post)
        
        // 🔧 CRITICAL FIX: Cache avatar IMMEDIATELY before inserting post so UI can display it instantly
        if let current = AuthenticationManager.shared.currentUser, isPostFromCurrentUser(processedPost) {
            await cacheAvatarImmediately(for: processedPost, currentUser: current)
        }
        
        // Check whether the post is already in the feed
        if let index = feedPosts.firstIndex(where: { $0.postId == processedPost.postId }) {
            // Update the existing post to ensure we have the latest data
            feedPosts[index] = processedPost
            print("🆕 [FeedManager] Updated existing post \(processedPost.postId.uuidString.prefix(8)) in feed")
        } else {
            // Insert the brand-new post at the beginning so it appears at the top of the feed
            feedPosts.insert(processedPost, at: 0)
            print("🆕 [FeedManager] Inserted new post \(processedPost.postId.uuidString.prefix(8)) into feed (total now: \(feedPosts.count))")
        }
        
        // 🔧 OPTIMIZED: Single efficient cache update instead of multiple redundant calls
        updateCacheEfficiently(feedPosts)
        
        // 🔧 BACKGROUND: Additional avatar caching for future use
        if let current = AuthenticationManager.shared.currentUser, isPostFromCurrentUser(processedPost) {
            // Background task for additional avatar caching
            Task.detached(priority: .background) {
                await self.cacheUserAvatarForPost(processedPost, currentUser: current)
            }
        }
        
        // 🚀 Prefetch all images for immediate display
        Task.detached(priority: .userInitiated) {
            await self.prefetchAvatars(from: [processedPost])
        }
    }
    
    /// 🔧 NEW: Immediate synchronous avatar caching for instant display
    @MainActor private func cacheAvatarImmediately(for post: FeedPost, currentUser: User) async {
        let postAvatarURLs = [post.userAvatarUrl80, post.userAvatarUrl200, post.userAvatarUrlOriginal]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        guard !postAvatarURLs.isEmpty else {
            print("⚠️ [FeedManager] No post avatar URLs to cache")
            return
        }
        
        let userAvatarURLs = [currentUser.avatarUrl80, currentUser.avatarUrl200, currentUser.avatarUrlOriginal, currentUser.profilePhotoUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        // Find existing cached image from any user avatar URL (synchronously)
        var cachedImage: UIImage?
        
        // First check AvatarImageStore (fastest)
        for url in userAvatarURLs {
            if let img = AvatarImageStore.shared.image(for: url) {
                cachedImage = img
                print("🖼️ [FeedManager] Found cached avatar in AvatarImageStore for: \(url)")
                break
            }
        }
        
        // Then check Kingfisher memory cache
        if cachedImage == nil {
            for url in userAvatarURLs {
                if let img = ImageCache.default.retrieveImageInMemoryCache(forKey: url) {
                    cachedImage = img
                    print("🖼️ [FeedManager] Found cached avatar in Kingfisher memory cache for: \(url)")
                    break
                }
            }
        }
        
        // If we found a cached image, store it under ALL post and user avatar URLs IMMEDIATELY
        if let img = cachedImage {
            // Cache under all post avatar URLs
            for url in postAvatarURLs {
                AvatarImageStore.shared.set(img, for: url)
                print("🖼️ [FeedManager] Immediately cached avatar for new post URL: \(url)")
            }
            
            // Also cache under all user avatar URLs for consistency
            for url in userAvatarURLs {
                AvatarImageStore.shared.set(img, for: url)
                // Also populate Kingfisher memory cache for faster subsequent access
                try? await ImageCache.default.store(img, forKey: url, toDisk: false)
            }
            
            print("✅ [FeedManager] Avatar cached immediately for new post display under \(postAvatarURLs.count + userAvatarURLs.count) URLs")
        } else {
            print("⚠️ [FeedManager] No cached avatar found for immediate display")
            
            // Try to find ANY cached avatar using a broader search, including disk cache (synchronous attempt)
            var fallbackImage: UIImage?
            
            // Check disk cache synchronously for any user avatar URL
            for url in userAvatarURLs {
                // Try synchronous disk retrieval (this might block briefly but ensures we get an image)
                if let diskImg = try? await ImageCache.default.retrieveImageInDiskCache(forKey: url, options: [.loadDiskFileSynchronously]) {
                    fallbackImage = diskImg
                    print("🖼️ [FeedManager] Found fallback avatar in disk cache for: \(url)")
                    break
                }
            }
            
            if let img = fallbackImage {
                // Cache this fallback image everywhere
                for url in postAvatarURLs + userAvatarURLs {
                    AvatarImageStore.shared.set(img, for: url)
                    try? await ImageCache.default.store(img, forKey: url, toDisk: false) // Promote to memory
                }
                print("🖼️ [FeedManager] Used fallback disk cached avatar for immediate display")
            }
        }
    }
    
    /// 🔧 NEW: Optimized avatar caching for immediate display
    private func cacheUserAvatarForPost(_ post: FeedPost, currentUser: User) async {
        let postAvatarURLs = [post.userAvatarUrl80, post.userAvatarUrl200, post.userAvatarUrlOriginal]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        let userAvatarURLs = [currentUser.avatarUrl80, currentUser.avatarUrl200, currentUser.avatarUrlOriginal, currentUser.profilePhotoUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        // Find existing cached image from any user avatar URL
        var cachedImage: UIImage?
        for url in userAvatarURLs {
            if let img = await AvatarImageStore.shared.image(for: url) {
                cachedImage = img
                break
            }
            if let img = ImageCache.default.retrieveImageInMemoryCache(forKey: url) {
                cachedImage = img
                break
            }
        }
        
        // If we found a cached image, store it under all post avatar URLs
        if let img = cachedImage {
            await MainActor.run {
                for url in postAvatarURLs {
                    AvatarImageStore.shared.set(img, for: url)
                }
                print("🖼️ [FeedManager] Cached avatar for immediate display on new post")
            }
        } else if let primaryURL = postAvatarURLs.first, let url = URL(string: primaryURL) {
            // No cached image found, fetch it with high priority
            do {
                let options: KingfisherOptionsInfo = [
                    .cacheOriginalImage,
                    .downloadPriority(0.8), // High priority for immediate display
                    .transition(.none)
                ]
                let img = try await KingfisherManager.shared.retrieveImage(with: url, options: options).image
                
                await MainActor.run {
                    // Cache under all URL variants for the user
                    for urlString in postAvatarURLs + userAvatarURLs {
                        AvatarImageStore.shared.set(img, for: urlString)
                    }
                    print("🖼️ [FeedManager] Fetched and cached avatar for new post")
                }
            } catch {
                print("⚠️ [FeedManager] Failed to fetch avatar for new post: \(error)")
            }
        }
    }
    
    // MARK: - Comment Organization
    
    /// Organize comments using proper tree structure (no path compression)
    private func organizeCommentsFlattened(_ comments: [Comment]) -> [Comment] {
        guard !comments.isEmpty else { return [] }
        
        return PerformanceMonitor.shared.track(PerformanceMonitor.Operation.commentOrganization) {
            print("🔧 [FeedManager] Organizing \(comments.count) comments with TREE structure")
        
        // Build parent-to-children mapping
        var childrenByParent: [UUID: [Comment]] = [:]
        var topLevelComments: [Comment] = []
        
        // Categorize comments by their direct parent relationship
        for comment in comments {
            if let parentComment = comment.parentComment {
                // This is a reply - add to parent's children list
                let parentId = parentComment.id
                if childrenByParent[parentId] == nil {
                    childrenByParent[parentId] = []
                }
                childrenByParent[parentId]!.append(comment)
                print("🔧 [FeedManager] Comment \(comment.id.uuidString.prefix(8)) -> child of \(parentId.uuidString.prefix(8))")
            } else {
                // This is a top-level comment
                topLevelComments.append(comment)
                print("🔧 [FeedManager] Comment \(comment.id.uuidString.prefix(8)) -> top-level")
            }
        }
        
        print("🔧 [FeedManager] Found \(topLevelComments.count) top-level, \(childrenByParent.count) parents with children")
        
        // Sort top-level comments chronologically
        let sortedTopLevel = topLevelComments.sorted { $0.createdAt < $1.createdAt }
        
        // Iteratively build the flat list maintaining tree order using a stack
        var organizedComments: [Comment] = []
        
        // Stack to track comments to process along with their depth
        struct CommentNode {
            let comment: Comment
            let depth: Int
        }
        
        // Initialize stack with top-level comments in reverse order (so they're processed in correct order)
        var stack: [CommentNode] = sortedTopLevel.reversed().map { CommentNode(comment: $0, depth: 0) }
        
        // Process comments iteratively
        while !stack.isEmpty {
            let node = stack.removeLast()
            organizedComments.append(node.comment)
            print("🔧 [FeedManager] Added comment \(node.comment.id.uuidString.prefix(8)) at depth \(node.depth)")
            
            // Add direct children to stack (in reverse order for correct processing)
            if let children = childrenByParent[node.comment.id] {
                let sortedChildren = children.sorted { $0.createdAt < $1.createdAt }
                print("🔧 [FeedManager] Comment \(node.comment.id.uuidString.prefix(8)) has \(children.count) direct children")
                
                // Add in reverse order so they're popped in correct order
                for child in sortedChildren.reversed() {
                    stack.append(CommentNode(comment: child, depth: node.depth + 1))
                }
            }
        }
        
        print("🔧 [FeedManager] Final result: \(organizedComments.count) comments in tree order")
        
        // Verify no comments were lost
        let inputIds = Set(comments.map { $0.id })
        let outputIds = Set(organizedComments.map { $0.id })
        if inputIds != outputIds {
            let missingIds = inputIds.subtracting(outputIds)
            let extraIds = outputIds.subtracting(inputIds)
            print("❌ [FeedManager] ID mismatch!")
            print("❌ [FeedManager] Missing IDs: \(missingIds.map { $0.uuidString.prefix(8) })")
            print("❌ [FeedManager] Extra IDs: \(extraIds.map { $0.uuidString.prefix(8) })")
        } else {
            print("✅ [FeedManager] All comments preserved in tree structure")
        }
        
        return organizedComments
        }
    }
}

// MARK: - Feed Error Types

enum FeedError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationRequired
    case serverError(String)
    case badStatusCode(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationRequired:
            return "Authentication required"
        case .serverError(let message):
            return message
        case .badStatusCode(let code):
            return "Bad status code: \(code)"
        }
    }
} 

// MARK: - Notification Names

extension Notification.Name {
    /// 🆕 NEW: Notification sent when comments are updated from backend
    static let commentsUpdated = Notification.Name("commentsUpdated")
}
