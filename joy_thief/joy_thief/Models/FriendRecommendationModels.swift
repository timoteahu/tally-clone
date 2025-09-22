import Foundation

// MARK: - Mutual Friend Model
struct MutualFriend: Codable, Identifiable {
    let id: UUID
    let name: String
}

// MARK: - Friend Recommendation Model
struct FriendRecommendation: Codable, Identifiable {
    let id = UUID() // For SwiftUI ForEach
    let recommendedUserId: UUID
    let userName: String
    let mutualFriendsCount: Int
    let mutualFriendsPreview: [MutualFriend]
    let recommendationReason: String
    let totalScore: Double
    // Avatar fields for recommended user
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    
    enum CodingKeys: String, CodingKey {
        case recommendedUserId = "recommended_user_id"
        case userName = "user_name"
        case mutualFriendsCount = "mutual_friends_count"
        case mutualFriendsPreview = "mutual_friends_preview"
        case recommendationReason = "recommendation_reason"
        case totalScore = "total_score"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
    }
}

// MARK: - API Response Model
struct FriendRecommendationResponse: Codable {
    let recommendations: [FriendRecommendation]
}

// MARK: - Send Request Response Model
struct SendRecommendationRequestResponse: Codable {
    let message: String
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case requestId = "request_id"
    }
}

// MARK: - Error Types
enum FriendRecommendationError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case networkError
    case serverError(String)
    case noRecommendations
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication failed"
        case .networkError:
            return "Network connection error"
        case .serverError(let message):
            return "Server error: \(message)"
        case .noRecommendations:
            return "No friend recommendations available"
        }
    }
} 