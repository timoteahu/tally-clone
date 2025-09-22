import Foundation

enum VerificationError: Error, LocalizedError {
    case networkError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error. Please check your internet connection and try again."
        case .serverError(let message):
            return message
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case unauthorized
    case invalidResponse
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Please log in to continue"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

// POST /payments/create-setup-intent
struct SetupIntentResponse: Decodable {
    let clientSecret: String
    let customerId:   String
    let ephemeralKey: String
}

// POST /gym/verify
struct VerificationResponse: Codable {
    let message: String
    let status: String
    let isVerified: Bool
    let streak: Int?

    private enum CodingKeys: String, CodingKey {
        case message, status, streak
        case isVerified = "is_verified"
    }
}

// POST /study/start
struct StudySessionResponse: Codable {
    let message: String
    let sessionID: String
    let durationMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case message
        case sessionID       = "session_id"
        case durationMinutes = "duration_minutes"
    }
}

// POST /invites/create
struct InviteResponse: Codable {
    let id: String
    let inviter_user_id: String
    let invite_link: String
    let invite_status: String
    let expires_at: String
    let created_at: String
}

// For invite lookups and acceptance
struct Invite: Identifiable, Codable {
    let id: String
    let inviterUserId: String
    let inviteLink: String
    let inviteStatus: String
    let expiresAt: String?
    let createdAt: String
    let habitId: String?
    let inviterName: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case inviterUserId = "inviter_user_id"
        case inviteLink = "invite_link"
        case inviteStatus = "invite_status"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case habitId = "habit_id"
        case inviterName = "inviter_name"
    }
}

struct BranchInviteAcceptResponse: Codable {
    let message: String
    let friendshipCreated: Bool
    let inviterId: String
    let inviterName: String
    
    private enum CodingKeys: String, CodingKey {
        case message
        case friendshipCreated = "friendship_created"
        case inviterId = "inviter_id"
        case inviterName = "inviter_name"
    }
}
