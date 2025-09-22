import Foundation

struct FeedPost: Identifiable, Codable {
    let postId: UUID
    let habitId: String? // Keep as String since backend converts UUID to string
    let caption: String?
    let createdAt: Date
    let isPrivate: Bool
    let imageUrl: String?
    let selfieImageUrl: String?
    let contentImageUrl: String?
    let userId: UUID
    let userName: String
    let userAvatarUrl80: String?
    let userAvatarUrl200: String?
    let userAvatarUrlOriginal: String?
    let userAvatarVersion: Int?
    let streak: Int?
    var habitType: String?
    var habitName: String?
    let penaltyAmount: Float?
    let comments: [Comment]
    
    var id: UUID { postId }
    
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case habitId = "habit_id"
        case caption
        case createdAt = "created_at"
        case isPrivate = "is_private"
        case imageUrl = "image_url"
        case selfieImageUrl = "selfie_image_url"
        case contentImageUrl = "content_image_url"
        case userId = "user_id"
        case userName = "user_name"
        case userAvatarUrl80 = "user_avatar_url_80"
        case userAvatarUrl200 = "user_avatar_url_200"
        case userAvatarUrlOriginal = "user_avatar_url_original"
        case userAvatarVersion = "user_avatar_version"
        case streak
        case habitType = "habit_type"
        case habitName = "habit_name"
        case penaltyAmount = "penalty_amount"
        case comments
    }
}

struct Comment: Identifiable, Codable {
    let id: UUID
    let content: String
    let createdAt: Date
    let userId: UUID
    let userName: String
    let userAvatarUrl80: String?
    let userAvatarUrl200: String?
    let userAvatarUrlOriginal: String?
    let userAvatarVersion: Int?
    let isEdited: Bool
    let parentComment: ParentComment?
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case userId = "user_id"
        case userName = "user_name"
        case userAvatarUrl80 = "user_avatar_url_80"
        case userAvatarUrl200 = "user_avatar_url_200"
        case userAvatarUrlOriginal = "user_avatar_url_original"
        case userAvatarVersion = "user_avatar_version"
        case isEdited = "is_edited"
        case parentComment = "parent_comment"
    }
}

struct ParentComment: Codable {
    let id: UUID
    let content: String
    let createdAt: Date
    let userId: UUID
    let userName: String
    let userAvatarUrl80: String?
    let userAvatarUrl200: String?
    let userAvatarUrlOriginal: String?
    let userAvatarVersion: Int?
    let isEdited: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt = "created_at"
        case userId = "user_id"
        case userName = "user_name"
        case userAvatarUrl80 = "user_avatar_url_80"
        case userAvatarUrl200 = "user_avatar_url_200"
        case userAvatarUrlOriginal = "user_avatar_url_original"
        case userAvatarVersion = "user_avatar_version"
        case isEdited = "is_edited"
    }
} 