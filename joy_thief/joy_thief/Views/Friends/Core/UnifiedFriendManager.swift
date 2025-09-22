import Foundation
import SwiftUI

// MARK: - Extended Types for Unified System
struct UnifiedSentFriendRequest: Codable, Identifiable, Equatable {
    let id: String
    let receiverId: String
    let receiverName: String
    let receiverPhone: String
    let receiverAvatarVersion: Int?
    let receiverAvatarUrl80: String?
    let receiverAvatarUrl200: String?
    let receiverAvatarUrlOriginal: String?
    let message: String?
    let status: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case receiverId = "receiver_id"
        case receiverName = "receiver_name"
        case receiverPhone = "receiver_phone"
        case receiverAvatarVersion = "receiver_avatar_version"
        case receiverAvatarUrl80 = "receiver_avatar_url_80"
        case receiverAvatarUrl200 = "receiver_avatar_url_200"
        case receiverAvatarUrlOriginal = "receiver_avatar_url_original"
        case message
        case status
        case createdAt = "created_at"
    }
    
    static func == (lhs: UnifiedSentFriendRequest, rhs: UnifiedSentFriendRequest) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ReceivedFriendRequest: Codable, Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let senderPhone: String
    let senderAvatarVersion: Int?
    let senderAvatarUrl80: String?
    let senderAvatarUrl200: String?
    let senderAvatarUrlOriginal: String?
    let message: String?
    let status: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderPhone = "sender_phone"
        case senderAvatarVersion = "sender_avatar_version"
        case senderAvatarUrl80 = "sender_avatar_url_80"
        case senderAvatarUrl200 = "sender_avatar_url_200"
        case senderAvatarUrlOriginal = "sender_avatar_url_original"
        case message
        case status
        case createdAt = "created_at"
    }
    
    /// Convert to FriendRequestWithDetails for compatibility with existing UI components
    func toFriendRequestWithDetails() -> FriendRequestWithDetails {
        return FriendRequestWithDetails(
            id: self.id,
            senderId: self.senderId,
            receiverId: "", // Not used in received requests display
            status: FriendRequestStatus(rawValue: self.status) ?? .pending,
            message: (self.message?.isEmpty == false) ? self.message : nil,
            createdAt: self.createdAt,
            updatedAt: self.createdAt, // Use same timestamp
            senderName: self.senderName,
            senderPhone: self.senderPhone,
            receiverName: "", // Not used in received requests display
            receiverPhone: "", // Not used in received requests display
            senderAvatarVersion: self.senderAvatarVersion,
            senderAvatarUrl80: self.senderAvatarUrl80,
            senderAvatarUrl200: self.senderAvatarUrl200,
            senderAvatarUrlOriginal: self.senderAvatarUrlOriginal
        )
    }
}

struct ContactOnTally: Codable, Identifiable {
    let id = UUID()
    let userId: String
    let name: String
    let phoneNumber: String
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case phoneNumber = "phone_number"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
    }
}

// MARK: - UnifiedFriendManager
@MainActor
class UnifiedFriendManager: ObservableObject {
    static let shared = UnifiedFriendManager()
    
    // Unified data structure
    @Published var friends: [Friend] = []
    @Published var receivedRequests: [ReceivedFriendRequest] = []
    @Published var sentRequests: [UnifiedSentFriendRequest] = []
    @Published var contactsOnTally: [ContactOnTally] = []
    
    // Loading states
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var cacheStats: CacheStats?
    
    // NEW: Race condition prevention
    @Published var hasInitialDataLoaded = false
    private(set) var dataLoadingTask: Task<Void, Never>?
    
    // New architecture components
    private let cacheActor = CacheActor()
    private let contactMonitor = ContactMonitor()
    private var currentTask: Task<Void, Error>?
    
    private init() {
        // NEW ARCHITECTURE: Start with empty data, load only when tabs are visited
        print("📁 [UnifiedFriendManager] Initialized with empty data - tabs will load on demand")
        
        // Don't load immediately - wait for proper initialization sequence
        // Load friend requests from cache with proper async coordination
        scheduleInitialDataLoad()
    }
    
    /// Sort friends by last activity (most recent first)
    private func sortFriendsByActivity(_ friends: [Friend]) -> [Friend] {
        return friends.sorted { friend1, friend2 in
            // Handle nil lastActive values - friends with no activity go to the end
            guard let lastActive1 = friend1.lastActive else { return false }
            guard let lastActive2 = friend2.lastActive else { return true }
            
            // Parse ISO 8601 date strings and compare
            let formatter = ISO8601DateFormatter()
            guard let date1 = formatter.date(from: lastActive1),
                  let date2 = formatter.date(from: lastActive2) else {
                // If parsing fails, maintain original order
                return false
            }
            
            // Sort by most recent first
            return date1 > date2
        }
    }
    
    /// Schedule initial data loading with proper async coordination to prevent race conditions
    private func scheduleInitialDataLoad() {
        dataLoadingTask = Task { @MainActor in
            // Try to load from cache immediately
            await loadFriendRequestsFromCache()
            
            // If we still don't have data, use async notification pattern instead of sleep
            if receivedRequests.isEmpty && sentRequests.isEmpty {
                print("📁 [UnifiedFriendManager] No initial data found, will wait for data updates")
                // Data will be loaded when FriendRequestManager updates
            }
            
            hasInitialDataLoaded = true
            print("✅ [UnifiedFriendManager] Initial data loading completed")
        }
    }
    
    /// Load friend requests from cached data for immediate notification dot display
    private func loadFriendRequestsFromCache() async {
        // Check if FriendRequestManager has actual data before syncing
        let friendRequestManager = FriendRequestManager.shared
        
        // Only sync if there's actual data or if it's been long enough that we should accept empty state
        let hasReceivedRequests = !friendRequestManager.receivedRequests.isEmpty
        let hasSentRequests = !friendRequestManager.sentRequests.isEmpty
        let hasAnyData = hasReceivedRequests || hasSentRequests
        
        if hasAnyData {
            print("📁 [UnifiedFriendManager] Found cached friend request data, syncing...")
            refreshFromPreloadedManagers()
        } else {
            print("📁 [UnifiedFriendManager] No friend request data available yet")
        }
    }
    
    /// Load friend requests in background for notification dots (without full data refresh)
    func loadFriendRequestsInBackground(token: String) async {
        print("🔄 [UnifiedFriendManager] Loading friend requests in background for notification dots...")
        
        // Wait for initial data loading to complete to avoid race conditions
        _ = await dataLoadingTask?.value
        
        do {
            let requestsResponse = try await fetchRequestsOnly(token: token)
            
            await MainActor.run {
                // IMMEDIATE UI UPDATE: Apply new data for instant notification dot feedback
                let hadRequests = !self.receivedRequests.isEmpty
                
                self.receivedRequests = requestsResponse.receivedFriendRequests
                self.sentRequests = requestsResponse.sentFriendRequests
                self.hasInitialDataLoaded = true
                
                // Log notification dot status change
                let hasRequestsNow = !self.receivedRequests.isEmpty
                if hadRequests != hasRequestsNow {
                    print("🔴 [UnifiedFriendManager] Notification dot status changed: \(hadRequests) → \(hasRequestsNow)")
                }
                
                print("✅ [UnifiedFriendManager] Background friend requests loaded: \(requestsResponse.receivedFriendRequests.count) received, \(requestsResponse.sentFriendRequests.count) sent")
                
                // Force UI update for notification dots by posting a notification
                NotificationCenter.default.post(name: NSNotification.Name("FriendRequestsUpdated"), object: nil)
            }
        } catch {
            print("❌ [UnifiedFriendManager] Failed to load friend requests in background: \(error)")
            
            // On error, still try to sync from cache as fallback and mark as loaded
            await MainActor.run {
                self.refreshFromPreloadedManagers()
                self.hasInitialDataLoaded = true
            }
        }
    }
    
    /// Load data from cache on initialization (DISABLED for new architecture)
    private func loadFromCache() async {
        // DISABLED: We don't want to show cached data immediately anymore
        // Each tab will load its own data when visited
        print("📁 [UnifiedFriendManager] Cache loading disabled - using on-demand loading")
    }
    
    /// Update UI with cached data
    private func updateUIWithCache(_ cache: FriendCache) async {
        friends = sortFriendsByActivity(cache.friends)
        receivedRequests = cache.receivedRequests
        sentRequests = cache.sentRequests
        contactsOnTally = cache.contactsOnTally
        
        print("✅ [UnifiedFriendManager] Updated UI from cache:")
        print("   - Friends: \(cache.friends.count)")
        print("   - Received Requests: \(cache.receivedRequests.count)")
        print("   - Sent Requests: \(cache.sentRequests.count)")
        print("   - Contacts on Tally: \(cache.contactsOnTally.count)")
    }
    
    /// Update cache statistics for monitoring
    private func updateCacheStats() async {
        cacheStats = await cacheActor.getCacheStats()
    }
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    /// Trigger refresh if needed based on intelligent conditions (DISABLED for new architecture)
    func triggerRefreshIfNeeded(token: String) async {
        // NEW ARCHITECTURE: Don't use cache-based loading
        // Each tab loads its own data explicitly when visited
        print("📁 [UnifiedFriendManager] triggerRefreshIfNeeded disabled - using tab-specific loading")
        
        // No-op in the new architecture - tabs handle their own loading
    }
    
    /// Force refresh with loading indicator
    func forceRefresh(token: String) async {
        // Cancel any existing task
        currentTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                let contactNumbers = await contactMonitor.getContactPhoneNumbers()
                let unifiedData = try await fetchUnifiedFriendData(token: token, contactPhoneNumbers: contactNumbers)
                
                await MainActor.run {
                    self.updateUIWithData(unifiedData)
                    self.isLoading = false
                    self.errorMessage = nil
                }
                
                // Save to cache
                let currentContactsHash = await contactMonitor.getCurrentContactsHash()
                let newCache = FriendCache(
                    friends: unifiedData.friends,
                    receivedRequests: unifiedData.receivedFriendRequests,
                    sentRequests: unifiedData.sentFriendRequests,
                    contactsOnTally: unifiedData.contactsOnTally,
                    lastFetchDate: Date(),
                    contactsHash: currentContactsHash
                )
                
                try await cacheActor.saveCache(newCache)
                await updateCacheStats()
                
                print("✅ [UnifiedFriendManager] Force refresh completed and cached")
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        let errorType = NetworkErrorClassifier.classify(error)
                        self.handleNetworkError(errorType)
                        self.isLoading = false
                    }
                }
            }
        }
        
        // Wait for current task to complete (handle potential errors)
        do {
            _ = try await currentTask?.value
        } catch {
            // Task was cancelled or failed, which is expected behavior
            print("🔄 [UnifiedFriendManager] Task completed with result: \(error)")
        }
    }
    
    /// Background refresh without loading indicator
    private func backgroundRefresh(token: String, cache: FriendCache) async {
        currentTask = Task {
            do {
                let contactNumbers = await contactMonitor.getContactPhoneNumbers()
                let unifiedData = try await fetchUnifiedFriendData(token: token, contactPhoneNumbers: contactNumbers)
                
                await MainActor.run {
                    self.updateUIWithData(unifiedData)
                    self.errorMessage = nil
                }
                
                // Save to cache
                let currentContactsHash = await contactMonitor.getCurrentContactsHash()
                let newCache = FriendCache(
                    friends: unifiedData.friends,
                    receivedRequests: unifiedData.receivedFriendRequests,
                    sentRequests: unifiedData.sentFriendRequests,
                    contactsOnTally: unifiedData.contactsOnTally,
                    lastFetchDate: Date(),
                    contactsHash: currentContactsHash
                )
                
                try await cacheActor.saveCache(newCache)
                await updateCacheStats()
                
                print("✅ [UnifiedFriendManager] Background refresh completed and cached")
            } catch {
                if !Task.isCancelled {
                    let errorType = NetworkErrorClassifier.classify(error)
                    print("❌ [UnifiedFriendManager] Background refresh failed: \(errorType.userMessage)")
                    
                    // For background refresh, don't show error to user unless it's critical
                    if case .authentication = errorType {
                        await MainActor.run {
                            self.handleNetworkError(errorType)
                        }
                    }
                }
            }
        }
    }
    
    /// Check if contacts have changed since cache was created
    private func checkContactsChanged(cache: FriendCache) async -> Bool {
        // Only check if we have contacts permission
        guard await contactMonitor.hasContactsPermission() else {
            return false
        }
        
        return await contactMonitor.hasContactsChanged(since: cache.contactsHash)
    }
    
    /// Update UI with new data
    private func updateUIWithData(_ data: UnifiedFriendDataResponse) {
        friends = data.friends
        receivedRequests = data.receivedFriendRequests
        sentRequests = data.sentFriendRequests
        contactsOnTally = data.contactsOnTally
        
        print("✅ [UnifiedFriendManager] Updated UI with fresh data:")
        print("   - Friends: \(data.friends.count)")
        print("   - Received Requests: \(data.receivedFriendRequests.count)")
        print("   - Sent Requests: \(data.sentFriendRequests.count)")
        print("   - Contacts on Tally: \(data.contactsOnTally.count)")
    }
    
    /// Handle network errors with appropriate user messaging
    private func handleNetworkError(_ errorType: NetworkErrorType) {
        errorMessage = errorType.userMessage
        
        // Handle critical errors that require special action
        if case .authentication(let requiresReauth) = errorType, requiresReauth {
            // TODO: Trigger re-authentication flow
            print("🚨 [UnifiedFriendManager] Authentication required - should trigger re-auth flow")
        }
    }
    
    private func fetchUnifiedFriendData(token: String, contactPhoneNumbers: [String]?) async throws -> UnifiedFriendDataResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/relationships/unified") else {
            throw FriendDataError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include contact phone numbers in request body
        let requestBody = ContactMatchRequest(phoneNumbers: contactPhoneNumbers)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendDataError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ [UnifiedFriendManager] HTTP \(httpResponse.statusCode): \(responseString)")
            
            // Extract retry-after header if present
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            
            throw HTTPError(
                statusCode: httpResponse.statusCode,
                retryAfter: retryAfter,
                message: responseString
            )
        }
        
        let decodedResponse = try JSONDecoder().decode(UnifiedFriendDataResponse.self, from: data)
        
        // Debug log what we received
        print("📊 [UnifiedFriendManager] Received data:")
        print("   - Friends: \(decodedResponse.friends.count)")
        print("   - Received Requests: \(decodedResponse.receivedFriendRequests.count)")
        print("   - Sent Requests: \(decodedResponse.sentFriendRequests.count)")
        print("   - Contacts on Tally: \(decodedResponse.contactsOnTally.count)")
        if !decodedResponse.contactsOnTally.isEmpty {
            print("   - Contacts on Tally details: \(decodedResponse.contactsOnTally)")
        }
        
        return decodedResponse
    }
    
    // MARK: - Specific Data Loading Methods
    
    /// Load only friends data
    func refreshFriendsOnly(token: String) async {
        print("🔄 [UnifiedFriendManager] Loading friends only...")
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                let friendsResponse = try await fetchFriendsOnly(token: token)
                await MainActor.run {
                    // Debug: Print first friend's lastActive
                    if let firstFriend = friendsResponse.friends.first {
                        print("🔍 [UnifiedFriendManager] First friend: \(firstFriend.name), lastActive: \(firstFriend.lastActive ?? "nil")")
                    }
                    
                    self.friends = self.sortFriendsByActivity(friendsResponse.friends)
                    self.isLoading = false
                    print("✅ [UnifiedFriendManager] Friends only loaded: \(friendsResponse.friends.count) friends")
                }
            } catch {
                // Check if task was cancelled
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    print("🔄 [UnifiedFriendManager] Friends request was cancelled")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }
                
                let errorType = NetworkErrorClassifier.classify(error)
                await MainActor.run {
                    self.isLoading = false
                    self.handleNetworkError(errorType)
                }
                print("❌ [UnifiedFriendManager] Failed to load friends only: \(errorType.userMessage)")
                print("❌ [UnifiedFriendManager] Underlying error: \(error)")
            }
        }
        
        // Wait for current task to complete
        do {
            _ = try await currentTask?.value
        } catch {
            // Task was cancelled or failed
            print("🔄 [UnifiedFriendManager] Friends task completed with result: \(error)")
        }
    }
    
    /// Load only friend requests data
    func refreshRequestsOnly(token: String) async {
        print("🔄 [UnifiedFriendManager] Loading friend requests only...")
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                let requestsResponse = try await fetchRequestsOnly(token: token)
                
                await MainActor.run {
                    // Only update requests data, keep existing friends and contacts
                    self.receivedRequests = requestsResponse.receivedFriendRequests
                    self.sentRequests = requestsResponse.sentFriendRequests
                    self.isLoading = false
                    print("✅ [UnifiedFriendManager] Requests only loaded: \(requestsResponse.receivedFriendRequests.count) received, \(requestsResponse.sentFriendRequests.count) sent")
                }
            } catch {
                // Check if task was cancelled
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    print("🔄 [UnifiedFriendManager] Requests request was cancelled")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }
                
                let errorType = NetworkErrorClassifier.classify(error)
                await MainActor.run {
                    self.isLoading = false
                    self.handleNetworkError(errorType)
                }
                print("❌ [UnifiedFriendManager] Failed to load requests only: \(errorType.userMessage)")
                print("❌ [UnifiedFriendManager] Underlying error: \(error)")
            }
        }
        
        // Wait for current task to complete
        do {
            _ = try await currentTask?.value
        } catch {
            // Task was cancelled or failed
            print("🔄 [UnifiedFriendManager] Requests task completed with result: \(error)")
        }
    }
    
    /// Load unified recommendations (contacts + friend recommendations) for discover tab
    func refreshContactsOnly(token: String) async {
        print("🔄 [UnifiedFriendManager] Loading unified recommendations...")
        isLoading = true
        errorMessage = nil
        
        currentTask = Task {
            do {
                let contactNumbers = await contactMonitor.getContactPhoneNumbers()
                let unifiedResponse = try await fetchUnifiedRecommendations(token: token, contactPhoneNumbers: contactNumbers)
                
                await MainActor.run {
                    // Update both contacts and friend recommendations
                    self.contactsOnTally = unifiedResponse.contactsOnTally
                    self.isLoading = false
                    print("✅ [UnifiedFriendManager] Unified recommendations loaded:")
                    print("   - Contacts on Tally: \(unifiedResponse.contactsOnTally.count)")
                    print("   - Friend recommendations: \(unifiedResponse.friendRecommendations.count)")
                }
                
                // Also update the friend recommendations manager
                await MainActor.run {
                    FriendRecommendationsManager.shared.recommendations = unifiedResponse.friendRecommendations
                }
                
            } catch {
                // Check if task was cancelled
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    print("🔄 [UnifiedFriendManager] Unified recommendations request was cancelled")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }
                
                let errorType = NetworkErrorClassifier.classify(error)
                await MainActor.run {
                    self.isLoading = false
                    self.handleNetworkError(errorType)
                }
                print("❌ [UnifiedFriendManager] Failed to load unified recommendations: \(errorType.userMessage)")
                print("❌ [UnifiedFriendManager] Underlying error: \(error)")
            }
        }
        
        // Wait for current task to complete
        do {
            _ = try await currentTask?.value
        } catch {
            // Task was cancelled or failed
            print("🔄 [UnifiedFriendManager] Discover task completed with result: \(error)")
        }
    }
    
    private func fetchFriendsOnly(token: String) async throws -> FriendsOnlyResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/relationships/friends-only") else {
            throw FriendDataError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🌐 [UnifiedFriendManager] Making friends-only request to: \(url.absoluteString)")
        print("🔑 [UnifiedFriendManager] Using Bearer token: \(token.prefix(10))...")
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendDataError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ [UnifiedFriendManager] HTTP \(httpResponse.statusCode): \(responseString)")
            
            throw HTTPError(
                statusCode: httpResponse.statusCode,
                retryAfter: nil,
                message: responseString
            )
        }
        
        let friendsResponse = try JSONDecoder().decode(FriendsOnlyResponse.self, from: data)
        print("📊 [UnifiedFriendManager] Fetched friends only: \(friendsResponse.friends.count)")
        
        return friendsResponse
    }
    
    private func fetchRequestsOnly(token: String) async throws -> RequestsOnlyResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/relationships/requests-only") else {
            throw FriendDataError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🌐 [UnifiedFriendManager] Making requests-only request to: \(url.absoluteString)")
        print("🔑 [UnifiedFriendManager] Using Bearer token: \(token.prefix(10))...")
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendDataError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ [UnifiedFriendManager] HTTP \(httpResponse.statusCode): \(responseString)")
            
            throw HTTPError(
                statusCode: httpResponse.statusCode,
                retryAfter: nil,
                message: responseString
            )
        }
        
        let requestsResponse = try JSONDecoder().decode(RequestsOnlyResponse.self, from: data)
        print("📊 [UnifiedFriendManager] Fetched requests only: \(requestsResponse.receivedFriendRequests.count) received, \(requestsResponse.sentFriendRequests.count) sent")
        
        return requestsResponse
    }
    
    private func fetchUnifiedRecommendations(token: String, contactPhoneNumbers: [String]?) async throws -> UnifiedRecommendationsResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/relationships/unified-recommendations") else {
            throw FriendDataError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Include contact phone numbers in request body
        let requestBody = ContactMatchRequest(phoneNumbers: contactPhoneNumbers)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        print("🌐 [UnifiedFriendManager] Making unified-recommendations request to: \(url.absoluteString)")
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendDataError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "No response"
            print("❌ [UnifiedFriendManager] HTTP \(httpResponse.statusCode): \(responseString)")
            
            throw HTTPError(
                statusCode: httpResponse.statusCode,
                retryAfter: nil,
                message: responseString
            )
        }
        
        let unifiedResponse = try JSONDecoder().decode(UnifiedRecommendationsResponse.self, from: data)
        print("📊 [UnifiedFriendManager] Fetched unified recommendations:")
        print("   - Contacts on Tally: \(unifiedResponse.contactsOnTally.count)")
        print("   - Friend recommendations: \(unifiedResponse.friendRecommendations.count)")
        
        return unifiedResponse
    }
    
    /// Clear all cached data (for compliance/privacy)
    func clearCache() async {
        // Clear UI
        friends = []
        receivedRequests = []
        sentRequests = []
        contactsOnTally = []
        errorMessage = nil
        
        // Clear cache storage
        do {
            try await cacheActor.clearAllCache()
            await updateCacheStats()
            print("🧹 [UnifiedFriendManager] All cache cleared")
        } catch {
            print("❌ [UnifiedFriendManager] Failed to clear cache: \(error)")
        }
    }
    
    /// Get filtered friends based on search text
    func getFilteredFriends(searchText: String) -> [Friend] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter { friend in
            friend.name.lowercased().contains(searchText.lowercased()) ||
            friend.phoneNumber.lowercased().contains(searchText.lowercased())
        }
    }
    
    /// Get filtered contacts on Tally based on search text
    func getFilteredContactsOnTally(searchText: String) -> [ContactOnTally] {
        if searchText.isEmpty {
            return contactsOnTally
        }
        return contactsOnTally.filter { contact in
            contact.name.lowercased().contains(searchText.lowercased()) ||
            contact.phoneNumber.lowercased().contains(searchText.lowercased())
        }
    }
    
    /// Check if all sections are empty
    var allSectionsEmpty: Bool {
        return friends.isEmpty &&
               receivedRequests.isEmpty &&
               contactsOnTally.isEmpty
    }
    
    /// Legacy method for compatibility with PreloadManager
    /// In the new architecture, we apply cached friend request data to show notification dots
    func refreshFromPreloadedManagers() {
        let friendRequestManager = FriendRequestManager.shared
        
        print("📝 [UnifiedFriendManager] refreshFromPreloadedManagers called")
        print("   📊 FriendRequestManager state: \(friendRequestManager.receivedRequests.count) received, \(friendRequestManager.sentRequests.count) sent")
        print("   📊 Current UnifiedFriendManager state: \(receivedRequests.count) received, \(sentRequests.count) sent")
        
        // Always sync friend requests from FriendRequestManager (including empty state)
        // but log when we're syncing potentially stale/empty data
        
        // Convert and apply received requests (or empty array if none)
        let convertedReceivedRequests = friendRequestManager.receivedRequests.map { request in
            ReceivedFriendRequest(
                id: request.id,
                senderId: request.senderId,
                senderName: request.senderName,
                senderPhone: request.senderPhone,
                senderAvatarVersion: request.senderAvatarVersion,
                senderAvatarUrl80: request.senderAvatarUrl80,
                senderAvatarUrl200: request.senderAvatarUrl200,
                senderAvatarUrlOriginal: request.senderAvatarUrlOriginal,
                message: request.message,
                status: "pending",
                createdAt: request.createdAt
            )
        }
        
        // Convert and apply sent requests (or empty array if none)
        let convertedSentRequests = friendRequestManager.sentRequests.map { request in
            UnifiedSentFriendRequest(
                id: request.id,
                receiverId: request.receiverId,
                receiverName: request.receiverName,
                receiverPhone: request.receiverPhone,
                receiverAvatarVersion: nil,
                receiverAvatarUrl80: nil,
                receiverAvatarUrl200: nil,
                receiverAvatarUrlOriginal: nil,
                message: request.message,
                status: request.status,
                createdAt: ""  // SentFriendRequest doesn't have createdAt, use empty string
            )
        }
        
        // Only update if we're getting different data to avoid unnecessary UI updates
        let hasChanges = (convertedReceivedRequests.count != receivedRequests.count) ||
                        (convertedSentRequests.count != sentRequests.count)
        
        if hasChanges || !hasInitialDataLoaded {
            receivedRequests = convertedReceivedRequests
            sentRequests = convertedSentRequests
            
            if !hasInitialDataLoaded && (convertedReceivedRequests.isEmpty && convertedSentRequests.isEmpty) {
                print("⚠️ [UnifiedFriendManager] Synced empty data during initial load - possible race condition")
            } else {
                print("✅ [UnifiedFriendManager] Synced \(convertedReceivedRequests.count) received requests, \(convertedSentRequests.count) sent requests")
            }
        } else {
            print("📝 [UnifiedFriendManager] No changes detected, skipping sync")
        }
    }
    
    /// Force a refresh from PreloadManager data (for use after PreloadManager completes)
    func forceRefreshFromPreloadedData() {
        print("🔄 [UnifiedFriendManager] Force refreshing from PreloadManager data...")
        refreshFromPreloadedManagers()
        hasInitialDataLoaded = true
    }
}

// MARK: - Request Models
struct ContactMatchRequest: Codable {
    let phoneNumbers: [String]?
    
    enum CodingKeys: String, CodingKey {
        case phoneNumbers = "phone_numbers"
    }
}

struct UnifiedFriendDataResponse: Codable {
    let friends: [Friend]
    let receivedFriendRequests: [ReceivedFriendRequest]
    let sentFriendRequests: [UnifiedSentFriendRequest]
    let contactsOnTally: [ContactOnTally]
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case friends
        case receivedFriendRequests = "received_friend_requests"
        case sentFriendRequests = "sent_friend_requests"
        case contactsOnTally = "contacts_on_tally"
        case totalCount = "total_count"
    }
}

struct FriendsOnlyResponse: Codable {
    let friends: [Friend]
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case friends
        case totalCount = "total_count"
    }
}

struct DiscoverOnlyResponse: Codable {
    let contactsOnTally: [ContactOnTally]
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case contactsOnTally = "contacts_on_tally"
        case totalCount = "total_count"
    }
}

struct RequestsOnlyResponse: Codable {
    let receivedFriendRequests: [ReceivedFriendRequest]
    let sentFriendRequests: [UnifiedSentFriendRequest]
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case receivedFriendRequests = "received_friend_requests"
        case sentFriendRequests = "sent_friend_requests"
        case totalCount = "total_count"
    }
}

struct UnifiedRecommendationsResponse: Codable {
    let contactsOnTally: [ContactOnTally]
    let friendRecommendations: [FriendRecommendation]
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case contactsOnTally = "contacts_on_tally"
        case friendRecommendations = "friend_recommendations"
        case totalCount = "total_count"
    }
}

enum FriendDataError: Error {
    case invalidURL
    case networkError
    case serverError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
} 
