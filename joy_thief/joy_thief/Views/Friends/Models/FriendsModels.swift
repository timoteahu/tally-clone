import SwiftUI
import UIKit
import Contacts
import Foundation

// MARK: - Share sheet helper
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var activities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: activities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Helper extension to create global Friend struct
extension FriendsManager {
    static func createFriend(id: String, friendId: String, name: String, phoneNumber: String) -> Friend {
        return Friend(id: id, friendId: friendId, name: name, phoneNumber: phoneNumber)
    }
}

// MARK: - Local model strictly for UI
struct LocalFriend: Identifiable {
    let id: UUID
    let name: String
    let phoneNumber: String
    let image: Image?            // Use nil for initials
    let isActive: Bool
    let isRecommended: Bool
    let mutuals: Int?            // Only for recommended users
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let friendshipId: String?    // For removing friends
    let friendId: String?        // User ID of the friend
    let lastActive: String?      // ISO 8601 timestamp of last activity
    let activityText: String?    // Human-readable activity text like "Active 2h ago"

    init(id: UUID = UUID(),
         name: String,
         phoneNumber: String,
         image: Image? = nil,
         isActive: Bool,
         isRecommended: Bool,
         mutuals: Int? = nil,
         avatarVersion: Int? = nil,
         avatarUrl80: String? = nil,
         avatarUrl200: String? = nil,
         avatarUrlOriginal: String? = nil,
         friendshipId: String? = nil,
         friendId: String? = nil,
         lastActive: String? = nil,
         activityText: String? = nil) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.image = image
        self.isActive = isActive
        self.isRecommended = isRecommended
        self.mutuals = mutuals
        self.avatarVersion = avatarVersion
        self.avatarUrl80 = avatarUrl80
        self.avatarUrl200 = avatarUrl200
        self.avatarUrlOriginal = avatarUrlOriginal
        self.friendshipId = friendshipId
        self.friendId = friendId
        self.lastActive = lastActive
        self.activityText = activityText
    }
}

// MARK: - User Search Result Model
struct UserSearchResult: Identifiable, Codable {
    let id: String
    let name: String
    let phoneNumber: String
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let isFriend: Bool
    let hasPendingRequest: Bool
    let hasReceivedRequest: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phoneNumber = "phone_number"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
        case isFriend = "is_friend"
        case hasPendingRequest = "has_pending_request"
        case hasReceivedRequest = "has_received_request"
    }
} 