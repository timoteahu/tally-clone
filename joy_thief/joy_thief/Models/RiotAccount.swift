import Foundation

struct RiotAccount: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let riotId: String
    let tagline: String
    let puuid: String?
    let region: String
    let gameName: String
    let lastSyncAt: Date?
    let createdAt: Date
    let updatedAt: Date
    
    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case riotId = "riot_id"
        case tagline
        case puuid
        case region
        case gameName = "game_name"
        case lastSyncAt = "last_sync_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RiotAccountCreate: Codable {
    let riotId: String
    let tagline: String
    let region: String
    let gameName: String
    
    private enum CodingKeys: String, CodingKey {
        case riotId = "riot_id"
        case tagline
        case region
        case gameName = "game_name"
    }
}