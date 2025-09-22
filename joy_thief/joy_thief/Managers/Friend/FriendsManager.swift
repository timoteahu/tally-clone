import Foundation

class FriendsManager: ObservableObject {
    static let shared = FriendsManager()
    
    @Published var preloadedFriends: [Friend] = []
    @Published var preloadedFriendsWithStripeConnect: [Friend] = []
    
    private var reloadTimer: Timer?
    private let reloadInterval: TimeInterval = 300 // 5 minutes
    
    // Track if we're currently loading to prevent duplicate calls
    private var isLoadingFriendsWithStripe = false
    private var friendsWithStripeTask: Task<Void, Error>?
    
    // Track load requests to deduplicate multiple UI calls
    private var pendingLoadCount = 0
    private let loadCoordinator = DispatchQueue(label: "com.joythief.friendsmanager.loadcoordinator")
    
    // MARK: - Optimized URLSession Configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // Increased timeout for friends requests
        config.timeoutIntervalForResource = 60.0  // Increased resource timeout
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    // Cache management for friends with Stripe
    private var lastStripeLoadTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Removed periodic reload - using unified caching strategy instead
        // Background reloading now handled by DataCacheManager and PreloadManager
    }
    
    // Removed setupPeriodicReload() - background sync handled elsewhere
    
    func reloadFriends() async {
        guard let userId = await AuthenticationManager.shared.currentUser?.id,
              let token       = await AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        do {
            let friends = try await getFriends(userId: userId, token: token)
            await MainActor.run {
                self.preloadedFriends = friends
            }
        } catch {
            print("Error reloading friends: \(error)")
        }
    }
    
    // Public method for external calls (used by InviteAcceptanceView)
    func fetchFriends() async {
        await reloadFriends()
    }
    
    func addFriend(userId: String, friendId: String, token: String) async throws {
        // Use FriendRequestManager to send a friend request instead of creating direct friendship
        let friendRequestManager = await FriendRequestManager.shared
        
        do {
            _ = try await friendRequestManager.sendFriendRequest(to: friendId, message: "Friend request via add", token: token)
            // Note: No need to update friends list here since it's just a request, not an accepted friendship
        } catch {
            throw error
        }
    }
    
    func createDirectFriendship(userId: String, friendId: String, token: String) async throws {
        // Note: This endpoint now sends a friend request instead of creating immediate friendship
        // due to the new unified friends API structure
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "user_id": userId,
            "friend_id": friendId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Failed to create direct friendship")
        }
        
        // Note: Response will now be a FriendRequest object instead of Friend object
        // since this endpoint now sends a friend request rather than creating immediate friendship
        if let newFriendRequest = try? JSONDecoder().decode(FriendRequest.self, from: data) {
            // Don't add to friends list since it's just a request
            print("✅ [FriendsManager] Friend request sent successfully: \(newFriendRequest.id)")
        } else {
            // Reload entire friends list to ensure consistency
            await reloadFriends()
            // Also invalidate Stripe friends cache
            lastStripeLoadTime = nil
            // Invalidate friends cache
            await MainActor.run {
                DataCacheManager.shared.invalidateFriendsCache()
            }
        }
    }
    
    func removeFriend(userId: String, friendId: String, token: String) async throws {
        let urlString = "\(AppConfig.baseURL)/friends/\(friendId)"
        
        guard let url = URL(string: urlString) else {
            print("❌ [FriendsManager] Invalid URL: \(urlString)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [FriendsManager] Invalid response type")
            throw APIError.invalidResponse
        }
        
        
        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ [FriendsManager] Failed to remove friend. Status: \(httpResponse.statusCode), Body: \(responseBody)")
            throw APIError.serverError("Failed to remove friend")
        }
        
        // Update UI immediately
        await MainActor.run {
            self.preloadedFriends.removeAll { $0.friendId == friendId }
            // Invalidate friends cache since we removed a friend
            DataCacheManager.shared.invalidateFriendsCache()
        }
    }
    
    func getFriends(userId: String, token: String) async throws -> [Friend] {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/user/\(userId)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Failed to get friends")
        }
        
        // Decode friends list
        let allFriends = try JSONDecoder().decode([Friend].self, from: data)

        // Filter out the current user so you never appear in your own friends list
        let filteredFriends = allFriends.filter { $0.friendId != userId }

        return filteredFriends
    }
    
    func preloadAll(userId: String, token: String) async throws {
        do {
            let friends = try await getFriends(userId: userId, token: token)
            await MainActor.run {
                self.preloadedFriends = friends
            }
        } catch {
            print("Error preloading friends: \(error)")
            await MainActor.run {
                self.preloadedFriends = []
            }
        }
    }
    
    func getFriendsWithStripeConnect(userId: UUID, token: String) async throws -> [Friend] {
        let url = URL(string: "\(AppConfig.baseURL)/users/friends-with-stripe-connect/\(userId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorDict["detail"] as? String {
                throw NSError(domain: "FriendsError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw NSError(domain: "FriendsError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch friends with Stripe Connect"])
        }
        
        // Debug: Log the raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📋 [FriendsManager] Raw friends with Stripe Connect response: \(jsonString)")
        }
        
        let friendsResponse = try JSONDecoder().decode(FriendsWithStripeResponse.self, from: data)
        return friendsResponse.friends
    }
    
    func preloadFriendsWithStripeConnect(forceRefresh: Bool = false) async {
        // If we're already loading, wait for the existing task
        if isLoadingFriendsWithStripe, let existingTask = friendsWithStripeTask {
            print("🔄 [FriendsManager] Already loading friends with Stripe, waiting for existing task...")
            do {
                try await existingTask.value
            } catch {
                print("❌ [FriendsManager] Existing task failed: \(error)")
            }
            return
        }
        
        // Check if data is already loaded from PreloadManager
        if !forceRefresh && !preloadedFriendsWithStripeConnect.isEmpty {
            print("📊 [FriendsManager] Friends with Stripe already loaded from PreloadManager (count: \(preloadedFriendsWithStripeConnect.count))")
            return
        }
        
        // Check DataCacheManager for cached data first (skip if force refresh)
        if !forceRefresh {
            await MainActor.run {
                if let cachedFriendsWithStripe = DataCacheManager.shared.getCachedFriendsWithStripe() {
                    // Convert cached data to Friend objects
                    let convertedFriends = cachedFriendsWithStripe.compactMap { friendData -> Friend? in
                        let hasStripe = (friendData.stripeConnectStatus == true) && (friendData.stripeConnectAccountId != nil)
                        return Friend(
                            id: UUID().uuidString,
                            friendId: friendData.id,
                            name: friendData.name,
                            phoneNumber: friendData.phoneNumber,
                            hasStripe: hasStripe
                        )
                    }
                    
                    if !convertedFriends.isEmpty {
                        self.preloadedFriendsWithStripeConnect = convertedFriends
                        self.lastStripeLoadTime = Date()
                        print("📦 [FriendsManager] Loaded \(convertedFriends.count) friends with Stripe from DataCacheManager")
                        return
                    }
                }
            }
        }
        
        // Track multiple simultaneous requests
        loadCoordinator.sync {
            pendingLoadCount += 1
        }
        
        // If this is not the first request, just wait for the existing load
        if pendingLoadCount > 1 {
            print("🔄 [FriendsManager] Multiple load requests detected (\(pendingLoadCount)), deferring to existing load")
            return
        }
        
        // Check if data is already cached and still valid (skip if force refresh)
        if !forceRefresh,
           let lastLoadTime = lastStripeLoadTime,
           Date().timeIntervalSince(lastLoadTime) < cacheValidityDuration,
           !preloadedFriendsWithStripeConnect.isEmpty {
            // Data is still fresh, no need to reload
            print("📊 [FriendsManager] Using cached friends with Stripe Connect (count: \(preloadedFriendsWithStripeConnect.count))")
            return
        }
        
        guard let currentUser = await AuthenticationManager.shared.currentUser,
              let token       = await AuthenticationManager.shared.storedAuthToken else {
            print("❌ [FriendsManager] No current user or token available")
            return
        }
        
        // Mark as loading and create task
        isLoadingFriendsWithStripe = true
        
        friendsWithStripeTask = Task {
            defer {
                isLoadingFriendsWithStripe = false
                friendsWithStripeTask = nil
                loadCoordinator.sync {
                    pendingLoadCount = 0
                }
            }
            
            print("🔄 [FriendsManager] Fetching friends with Stripe Connect from API...")
            
            do {
                guard let userId = UUID(uuidString: currentUser.id) else {
                    throw NSError(domain: "FriendsError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID format"])
                }
                
                let friendsWithStripe = try await getFriendsWithStripeConnect(userId: userId, token: token)
                
                print("✅ [FriendsManager] Fetched \(friendsWithStripe.count) friends with Stripe Connect")
                
                await MainActor.run {
                    self.preloadedFriendsWithStripeConnect = friendsWithStripe
                    self.lastStripeLoadTime = Date()
                    print("✅ [FriendsManager] Updated preloadedFriendsWithStripeConnect with \(friendsWithStripe.count) friends")
                }
            } catch {
                print("❌ [FriendsManager] Error fetching friends with Stripe Connect: \(error)")
                await MainActor.run {
                    self.preloadedFriendsWithStripeConnect = []
                }
                throw error
            }
        }
        
        // Wait for the task to complete
        do {
            try await friendsWithStripeTask?.value
        } catch {
            // Error already logged above
        }
    }
    
    // Force refresh friends with Stripe (useful for when user adds new friend)
    func refreshFriendsWithStripeConnect() async {
        // Invalidate time-based cache to force API call
        lastStripeLoadTime = nil
        
        // Clear DataCacheManager's cache to ensure fresh data
        await MainActor.run {
            DataCacheManager.shared.cacheFriendsWithStripe(nil)
        }
        
        // Keep existing data on screen while loading new data
        // preloadFriendsWithStripeConnect will update the array only after successful fetch
        await preloadFriendsWithStripeConnect(forceRefresh: true)
    }
    
    deinit {
        reloadTimer?.invalidate()
    }
}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case serverError(String)
}

struct Friend: Codable, Identifiable {
    let id: String
    let friendId: String
    let name: String
    let phoneNumber: String
    // Avatar fields for cached avatars
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let friendshipId: String?  // The relationship ID needed for removal
    let lastActive: String?  // ISO 8601 timestamp of last activity
    let hasStripe: Bool  // New field to indicate if friend has active Stripe Connect
    
    enum CodingKeys: String, CodingKey {
        case id
        case friendId = "friend_id"
        case name
        case phoneNumber = "phone_number"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
        case friendshipId = "friendship_id"
        case lastActive = "last_active"
        case hasStripe = "has_stripe"
    }
    
    // Memberwise initializer for manual creation
    init(id: String, friendId: String, name: String, phoneNumber: String, avatarVersion: Int? = nil, avatarUrl80: String? = nil, avatarUrl200: String? = nil, avatarUrlOriginal: String? = nil, friendshipId: String? = nil, lastActive: String? = nil, hasStripe: Bool = false) {
        self.id = id
        self.friendId = friendId
        self.name = name
        self.phoneNumber = phoneNumber
        self.avatarVersion = avatarVersion
        self.avatarUrl80 = avatarUrl80
        self.avatarUrl200 = avatarUrl200
        self.avatarUrlOriginal = avatarUrlOriginal
        self.friendshipId = friendshipId
        self.lastActive = lastActive
        self.hasStripe = hasStripe
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // Handle both friend_id and id as fallback for compatibility
        if let friendIdValue = try container.decodeIfPresent(String.self, forKey: .friendId) {
            friendId = friendIdValue
        } else {
            // If friend_id is missing, use id as fallback
            friendId = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        avatarVersion = try container.decodeIfPresent(Int.self, forKey: .avatarVersion)
        avatarUrl80 = try container.decodeIfPresent(String.self, forKey: .avatarUrl80)
        avatarUrl200 = try container.decodeIfPresent(String.self, forKey: .avatarUrl200)
        avatarUrlOriginal = try container.decodeIfPresent(String.self, forKey: .avatarUrlOriginal)
        friendshipId = try container.decodeIfPresent(String.self, forKey: .friendshipId)
        lastActive = try container.decodeIfPresent(String.self, forKey: .lastActive)
        hasStripe = try container.decodeIfPresent(Bool.self, forKey: .hasStripe) ?? false
    }
}

struct UserDetails: Codable {
    let name: String
    let phoneNumber: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case phoneNumber = "phone_number"
    }
}

struct FriendsWithStripeResponse: Codable {
    let friends: [Friend]
} 
