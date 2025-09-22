import Foundation

@MainActor
class FriendRequestManager: ObservableObject {
    static let shared = FriendRequestManager()
    
    @Published var receivedRequests: [FriendRequestWithDetails] = []
    @Published var sentRequests: [SentFriendRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Optimized URLSession Configuration
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0  // Shorter timeout for friend requests
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    
    // MARK: - Request Deduplication
    private var pendingRequests: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Send Friend Request
    
    func sendFriendRequest(to userId: String, message: String? = nil, token: String) async throws -> FriendRequest {
        // Prevent duplicate requests
        let requestKey = "send_\(userId)"
        guard !pendingRequests.contains(requestKey) else {
            throw FriendRequestError.requestAlreadySent
        }
        
        pendingRequests.insert(requestKey)
        defer { pendingRequests.remove(requestKey) }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let body = FriendRequestCreate(receiverId: userId, message: message)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            let friendRequest = try JSONDecoder().decode(FriendRequest.self, from: data)
            
            // Optimistically update sent requests immediately
            let optimisticRequest = SentFriendRequest(
                id: friendRequest.id,
                receiverId: friendRequest.receiverId,
                receiverName: "", // Will be filled by background refresh
                receiverPhone: "",
                message: friendRequest.message ?? "",
                status: friendRequest.status.rawValue
            )
            
            sentRequests.append(optimisticRequest)
            
            return friendRequest
            
        case 400:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw mapErrorMessage(detail)
            }
            throw FriendRequestError.serverError("Failed to send friend request")
            
        case 401, 403:
            throw FriendRequestError.unauthorized
            
        case 404:
            throw FriendRequestError.userNotFound
            
        case 429:
            throw FriendRequestError.cooldownPeriod
            
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Unknown error occurred")
        }
    }
    
    // MARK: - Get Received Requests
    
    func getReceivedRequests(token: String) async throws -> [FriendRequestWithDetails] {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests/received") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Failed to get received requests")
        }
        
        let requests = try JSONDecoder().decode([FriendRequestWithDetails].self, from: data)
        self.receivedRequests = requests
        return requests
    }
    
    // MARK: - Get Sent Requests
    
    func getSentRequests(token: String) async throws -> [SentFriendRequest] {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests/sent") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Failed to get sent requests")
        }
        
        let requestsWithDetails = try JSONDecoder().decode([FriendRequestWithDetails].self, from: data)
        
        // Convert to SentFriendRequest format
        let sentRequests = requestsWithDetails.map { request in
            SentFriendRequest(
                id: request.id,
                receiverId: request.receiverId,
                receiverName: request.receiverName,
                receiverPhone: request.receiverPhone,
                message: request.message ?? "",
                status: request.status.rawValue
            )
        }
        
        self.sentRequests = sentRequests
        return sentRequests
    }
    
    // MARK: - Accept Friend Request
    
    func acceptFriendRequest(requestId: String, token: String) async throws -> FriendRequestAcceptResponse {
        // Prevent duplicate accepts
        let requestKey = "accept_\(requestId)"
        guard !pendingRequests.contains(requestKey) else {
            throw FriendRequestError.requestAlreadyProcessed
        }
        
        pendingRequests.insert(requestKey)
        defer { pendingRequests.remove(requestKey) }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests/\(requestId)/accept") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let acceptResponse = try JSONDecoder().decode(FriendRequestAcceptResponse.self, from: data)
            
            // Optimistically remove the request from received requests
            receivedRequests.removeAll { $0.id == requestId }
            
            return acceptResponse
            
        case 400:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw mapErrorMessage(detail)
            }
            throw FriendRequestError.requestAlreadyProcessed
            
        case 403:
            throw FriendRequestError.unauthorized
            
        case 404:
            throw FriendRequestError.requestNotFound
            
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Failed to accept friend request")
        }
    }
    
    // MARK: - Decline Friend Request
    
    func declineFriendRequest(requestId: String, token: String) async throws -> FriendRequestDeclineResponse {
        // Prevent duplicate declines
        let requestKey = "decline_\(requestId)"
        guard !pendingRequests.contains(requestKey) else {
            throw FriendRequestError.requestAlreadyProcessed
        }
        
        pendingRequests.insert(requestKey)
        defer { pendingRequests.remove(requestKey) }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests/\(requestId)/decline") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let declineResponse = try JSONDecoder().decode(FriendRequestDeclineResponse.self, from: data)
            
            // Optimistically remove the request from received requests
            receivedRequests.removeAll { $0.id == requestId }
            
            return declineResponse
            
        case 403:
            throw FriendRequestError.unauthorized
            
        case 404:
            throw FriendRequestError.requestNotFound
            
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Failed to decline friend request")
        }
    }
    
    // MARK: - Cancel Friend Request
    
    func cancelFriendRequest(requestId: String, token: String) async throws -> FriendRequestCancelResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/requests/\(requestId)") else {
            throw FriendRequestError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRequestError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let cancelResponse = try JSONDecoder().decode(FriendRequestCancelResponse.self, from: data)
            
            // Optimistically remove the request from sent requests
            sentRequests.removeAll { $0.id == requestId }
            
            return cancelResponse
            
        case 403:
            throw FriendRequestError.unauthorized
            
        case 404:
            throw FriendRequestError.requestNotFound
            
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRequestError.serverError(detail)
            }
            throw FriendRequestError.serverError("Failed to cancel friend request")
        }
    }
    
    // MARK: - Optimized Refresh Methods
    
    func refreshReceivedRequests(token: String) async {
        do {
            _ = try await getReceivedRequests(token: token)
        } catch {
            print("Error refreshing received requests: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshSentRequests(token: String) async {
        do {
            _ = try await getSentRequests(token: token)
        } catch {
            print("Error refreshing sent requests: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshAllRequests(token: String) async {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        refreshTask = Task {
            isLoading = true
            defer { isLoading = false }
            
            // Run both requests in parallel for better performance
            async let receivedTask: Void = refreshReceivedRequests(token: token)
            async let sentTask: Void = refreshSentRequests(token: token)
            
            _ = await receivedTask
            _ = await sentTask
        }
        
        await refreshTask?.value
    }
    
    // MARK: - Helper Methods
    
    private func mapErrorMessage(_ detail: String) -> FriendRequestError {
        switch detail.lowercased() {
        case let msg where msg.contains("already friends"):
            return .alreadyFriends
        case let msg where msg.contains("already sent"):
            return .requestAlreadySent
        case let msg where msg.contains("already sent you"):
            return .reverseRequestExists
        case let msg where msg.contains("wait before"):
            return .cooldownPeriod
        case let msg where msg.contains("yourself"):
            return .cannotRequestSelf
        case let msg where msg.contains("not found"):
            return .userNotFound
        case let msg where msg.contains("already been processed"):
            return .requestAlreadyProcessed
        default:
            return .serverError(detail)
        }
    }
    
    // MARK: - Convenience Methods
    
    func hasReceivedRequestFrom(userId: String) -> Bool {
        return receivedRequests.contains { $0.senderId == userId }
    }
    
    func hasSentRequestTo(userId: String) -> Bool {
        return sentRequests.contains { $0.receiverId == userId }
    }
    
    func getReceivedRequestFrom(userId: String) -> FriendRequestWithDetails? {
        return receivedRequests.first { $0.senderId == userId }
    }
    
    func getSentRequestTo(userId: String) -> SentFriendRequest? {
        return sentRequests.first { $0.receiverId == userId }
    }
    
    // MARK: - Cleanup Methods
    
    func cancelPendingRequests() {
        refreshTask?.cancel()
        pendingRequests.removeAll()
    }
    
    deinit {
        // Only cancel the task in deinit - this is thread-safe
        refreshTask?.cancel()
    }
} 