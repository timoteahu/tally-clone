import Foundation

// MARK: - Friend Request Models

enum FriendRequestStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        }
    }
}

struct FriendRequest: Codable, Identifiable {
    let id: String
    let senderId: String
    let receiverId: String
    let status: FriendRequestStatus
    let message: String?
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case status
        case message
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FriendRequestWithDetails: Codable, Identifiable {
    let id: String
    let senderId: String
    let receiverId: String
    let status: FriendRequestStatus
    let message: String?
    let createdAt: String
    let updatedAt: String
    let senderName: String
    let senderPhone: String
    let receiverName: String
    let receiverPhone: String
    // Avatar fields for sender
    let senderAvatarVersion: Int?
    let senderAvatarUrl80: String?
    let senderAvatarUrl200: String?
    let senderAvatarUrlOriginal: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case status
        case message
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case senderName = "sender_name"
        case senderPhone = "sender_phone"
        case receiverName = "receiver_name"
        case receiverPhone = "receiver_phone"
        case senderAvatarVersion = "sender_avatar_version"
        case senderAvatarUrl80 = "sender_avatar_url_80"
        case senderAvatarUrl200 = "sender_avatar_url_200"
        case senderAvatarUrlOriginal = "sender_avatar_url_original"
    }
}

struct FriendRequestCreate: Codable {
    let receiverId: String
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case receiverId = "receiver_id"
        case message
    }
}

// MARK: - Response Models

struct FriendRequestAcceptResponse: Codable {
    let message: String
    let friendshipId: String
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case friendshipId = "friendship_id"
        case requestId = "request_id"
    }
}

struct FriendRequestDeclineResponse: Codable {
    let message: String
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case requestId = "request_id"
    }
}

struct FriendRequestCancelResponse: Codable {
    let message: String
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case requestId = "request_id"
    }
}

// MARK: - API Error

enum FriendRequestError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case requestNotFound
    case requestAlreadyProcessed
    case alreadyFriends
    case requestAlreadySent
    case reverseRequestExists
    case cooldownPeriod
    case cannotRequestSelf
    case userNotFound
    case serverError(String)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "You are not authorized to perform this action"
        case .requestNotFound:
            return "Friend request not found"
        case .requestAlreadyProcessed:
            return "This request has already been processed"
        case .alreadyFriends:
            return "You are already friends with this person"
        case .requestAlreadySent:
            return "Friend request already sent to this user"
        case .reverseRequestExists:
            return "This user has already sent you a friend request"
        case .cooldownPeriod:
            return "Please wait before sending another request to this user"
        case .cannotRequestSelf:
            return "You cannot send a friend request to yourself"
        case .userNotFound:
            return "User not found"
        case .serverError(let message):
            return message
        case .networkError:
            return "Network connection error"
        }
    }
}

struct SentFriendRequest: Codable, Identifiable {
    let id: String
    let receiverId: String
    let receiverName: String
    let receiverPhone: String
    let message: String
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case receiverId = "receiver_id"
        case receiverName = "receiver_name"
        case receiverPhone = "receiver_phone"
        case message
        case status
    }
} 