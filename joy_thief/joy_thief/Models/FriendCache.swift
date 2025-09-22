import Foundation

/// Codable data model for persistent friend cache storage
struct FriendCache: Codable {
    let friends: [Friend]
    let receivedRequests: [ReceivedFriendRequest]
    let sentRequests: [UnifiedSentFriendRequest]
    let contactsOnTally: [ContactOnTally]
    let lastFetchDate: Date
    let contactsHash: String
    let cacheVersion: Int
    
    /// Current cache version for migration support
    static let currentVersion = 1
    
    init(
        friends: [Friend] = [],
        receivedRequests: [ReceivedFriendRequest] = [],
        sentRequests: [UnifiedSentFriendRequest] = [],
        contactsOnTally: [ContactOnTally] = [],
        lastFetchDate: Date = Date(),
        contactsHash: String = "",
        cacheVersion: Int = FriendCache.currentVersion
    ) {
        self.friends = friends
        self.receivedRequests = receivedRequests
        self.sentRequests = sentRequests
        self.contactsOnTally = contactsOnTally
        self.lastFetchDate = lastFetchDate
        self.contactsHash = contactsHash
        self.cacheVersion = cacheVersion
    }
    
    /// Check if cache data is meaningful (not empty)
    var hasMeaningfulData: Bool {
        return !friends.isEmpty || !receivedRequests.isEmpty || !contactsOnTally.isEmpty
    }
    
    /// Get cache age in seconds
    var ageInSeconds: TimeInterval {
        return Date().timeIntervalSince(lastFetchDate)
    }
    
    /// Determine cache staleness level
    var stalenessLevel: CacheStalenessLevel {
        let age = ageInSeconds
        
        switch age {
        case 0..<(30 * 60): // 0-30 minutes
            return .fresh
        case (30 * 60)..<(4 * 60 * 60): // 30 minutes - 4 hours
            return .stale
        case (4 * 60 * 60)..<(24 * 60 * 60): // 4-24 hours
            return .expired
        default: // > 24 hours
            return .ancient
        }
    }
}

/// Multi-tier staleness model
enum CacheStalenessLevel {
    case fresh      // 0-30min: Use immediately, no refresh needed
    case stale      // 30min-4hrs: Use immediately, trigger background refresh
    case expired    // 4hrs-24hrs: Use with warning indicator, force refresh attempt
    case ancient    // >24hrs: Discard, show loading, mandatory refresh
    
    var shouldUseCache: Bool {
        switch self {
        case .fresh, .stale, .expired:
            return true
        case .ancient:
            return false
        }
    }
    
    var needsRefresh: Bool {
        switch self {
        case .fresh:
            return false
        case .stale, .expired, .ancient:
            return true
        }
    }
    
    var requiresForceRefresh: Bool {
        switch self {
        case .fresh, .stale:
            return false
        case .expired, .ancient:
            return true
        }
    }
} 