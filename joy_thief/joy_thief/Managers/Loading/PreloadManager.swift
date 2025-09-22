import Foundation
import SwiftUI

@MainActor
class PreloadManager: ObservableObject {
    static let shared = PreloadManager()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastLoadTime: TimeInterval = 0 // Track performance
    
    private let urlSession = URLSession.shared
    
    private init() {}
    
    struct PreloadedData: Codable {
        let habits: [HabitData]
        let friends: [FriendData]
        let friendsWithStripe: [FriendWithStripeData]
        let paymentMethod: PaymentMethodData?
        let feedPosts: [FeedPostData]
        let customHabitTypes: [CustomHabitTypeData]
        let availableHabitTypes: AvailableHabitTypesData?
        let onboardingState: Int?
        let userProfile: UserProfileData?
        let weeklyProgress: [WeeklyProgressData]
        let verifiedHabitsToday: [String: Bool]?
        let habitVerifications: [String: [VerificationData]]?
        let weeklyVerifiedHabits: [String: [String: Bool]]?
        let friendRequests: FriendRequestsData?
        let stagedDeletions: [String: StagedDeletionInfo]?
        let contactsOnTally: [ContactOnTallyData]?
        
        init(habits: [HabitData] = [],
             friends: [FriendData] = [],
             friendsWithStripe: [FriendWithStripeData] = [],
             paymentMethod: PaymentMethodData? = nil,
             feedPosts: [FeedPostData] = [],
             customHabitTypes: [CustomHabitTypeData] = [],
             availableHabitTypes: AvailableHabitTypesData? = nil,
             onboardingState: Int? = nil,
             userProfile: UserProfileData? = nil,
             weeklyProgress: [WeeklyProgressData] = [],
             verifiedHabitsToday: [String: Bool]? = nil,
             habitVerifications: [String: [VerificationData]]? = nil,
             weeklyVerifiedHabits: [String: [String: Bool]]? = nil,
             friendRequests: FriendRequestsData? = nil,
             stagedDeletions: [String: StagedDeletionInfo]? = nil,
             contactsOnTally: [ContactOnTallyData]? = nil) {
            self.habits = habits
            self.friends = friends
            self.friendsWithStripe = friendsWithStripe
            self.paymentMethod = paymentMethod
            self.feedPosts = feedPosts
            self.customHabitTypes = customHabitTypes
            self.availableHabitTypes = availableHabitTypes
            self.onboardingState = onboardingState
            self.userProfile = userProfile
            self.weeklyProgress = weeklyProgress
            self.verifiedHabitsToday = verifiedHabitsToday
            self.habitVerifications = habitVerifications
            self.weeklyVerifiedHabits = weeklyVerifiedHabits
            self.friendRequests = friendRequests
            self.stagedDeletions = stagedDeletions
            self.contactsOnTally = contactsOnTally
        }
        
        enum CodingKeys: String, CodingKey {
            case habits, friends, customHabitTypes = "custom_habit_types"
            case friendsWithStripe = "friends_with_stripe"
            case paymentMethod = "payment_method"
            case feedPosts = "feed_posts"
            case availableHabitTypes = "available_habit_types"
            case onboardingState = "onboarding_state"
            case userProfile = "user_profile"
            case weeklyProgress = "weekly_progress"
            case verifiedHabitsToday = "verified_habits_today"
            case habitVerifications = "habit_verifications"
            case weeklyVerifiedHabits = "weekly_verified_habits"
            case friendRequests = "friend_requests"
            case stagedDeletions = "staged_deletions"
            case contactsOnTally = "contacts_on_tally"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            habits = try container.decodeIfPresent([HabitData].self, forKey: .habits) ?? []
            friends = try container.decodeIfPresent([FriendData].self, forKey: .friends) ?? []
            friendsWithStripe = try container.decodeIfPresent([FriendWithStripeData].self, forKey: .friendsWithStripe) ?? []
            paymentMethod = try container.decodeIfPresent(PaymentMethodData.self, forKey: .paymentMethod)
            feedPosts = try container.decodeIfPresent([FeedPostData].self, forKey: .feedPosts) ?? []
            customHabitTypes = try container.decodeIfPresent([CustomHabitTypeData].self, forKey: .customHabitTypes) ?? []
            availableHabitTypes = try container.decodeIfPresent(AvailableHabitTypesData.self, forKey: .availableHabitTypes)
            onboardingState = try container.decodeIfPresent(Int.self, forKey: .onboardingState)
            userProfile = try container.decodeIfPresent(UserProfileData.self, forKey: .userProfile)
            weeklyProgress = try container.decodeIfPresent([WeeklyProgressData].self, forKey: .weeklyProgress) ?? []
            verifiedHabitsToday = try container.decodeIfPresent([String: Bool].self, forKey: .verifiedHabitsToday)
            habitVerifications = try container.decodeIfPresent([String: [VerificationData]].self, forKey: .habitVerifications)
            weeklyVerifiedHabits = try container.decodeIfPresent([String: [String: Bool]].self, forKey: .weeklyVerifiedHabits)
            friendRequests = try container.decodeIfPresent(FriendRequestsData.self, forKey: .friendRequests)
            stagedDeletions = try container.decodeIfPresent([String: StagedDeletionInfo].self, forKey: .stagedDeletions)
            contactsOnTally = try container.decodeIfPresent([ContactOnTallyData].self, forKey: .contactsOnTally)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(habits, forKey: .habits)
            try container.encode(friends, forKey: .friends)
            try container.encode(friendsWithStripe, forKey: .friendsWithStripe)
            try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
            try container.encode(feedPosts, forKey: .feedPosts)
            try container.encode(customHabitTypes, forKey: .customHabitTypes)
            try container.encodeIfPresent(availableHabitTypes, forKey: .availableHabitTypes)
            try container.encodeIfPresent(onboardingState, forKey: .onboardingState)
            try container.encodeIfPresent(userProfile, forKey: .userProfile)
            try container.encode(weeklyProgress, forKey: .weeklyProgress)
            try container.encodeIfPresent(verifiedHabitsToday, forKey: .verifiedHabitsToday)
            try container.encodeIfPresent(habitVerifications, forKey: .habitVerifications)
            try container.encodeIfPresent(weeklyVerifiedHabits, forKey: .weeklyVerifiedHabits)
            try container.encodeIfPresent(friendRequests, forKey: .friendRequests)
            try container.encodeIfPresent(stagedDeletions, forKey: .stagedDeletions)
            try container.encodeIfPresent(contactsOnTally, forKey: .contactsOnTally)
        }
    }
    
    struct HabitData: Codable {
        let id: String
        let name: String
        let recipientId: String?
        let habitType: String
        let weekdays: [Int]?  // Make optional to handle null for weekly habits
        let penaltyAmount: Float
        let userId: String
        let createdAt: String
        let updatedAt: String
        let studyDurationMinutes: Int?
        let screenTimeLimitMinutes: Int?
        let restrictedApps: [String]?
        let alarmTime: String?
        let isPrivate: Bool?
        let customHabitTypeId: String?
        let habitScheduleType: String?
        let weeklyTarget: Int?
        let weekStartDay: Int?
        let commitTarget: Int?
        let todayCommitCount: Int?
        let currentWeekCommitCount: Int?
        let todayGamingHours: Double?
        let dailyLimitHours: Double?
        let hourlyPenaltyRate: Double?
        
        // Apple Health habit fields
        let healthTargetValue: Double?
        let healthTargetUnit: String?
        let healthDataType: String?
        let isZeroPenalty: Bool?  // Zero-penalty picture habit tracking
        
        enum CodingKeys: String, CodingKey {
            case id, name
            case recipientId = "recipient_id"
            case habitType = "habit_type"
            case weekdays
            case penaltyAmount = "penalty_amount"
            case userId = "user_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case studyDurationMinutes = "study_duration_minutes"
            case screenTimeLimitMinutes = "screen_time_limit_minutes"
            case restrictedApps = "restricted_apps"
            case alarmTime = "alarm_time"
            case isPrivate = "private"
            case customHabitTypeId = "custom_habit_type_id"
            case habitScheduleType = "habit_schedule_type"
            case weeklyTarget = "weekly_target"
            case weekStartDay = "week_start_day"
            case commitTarget = "commit_target"
            case todayCommitCount = "today_commit_count"
            case currentWeekCommitCount = "current_week_commit_count"
            case todayGamingHours = "today_gaming_hours"
            case dailyLimitHours = "daily_limit_hours"
            case hourlyPenaltyRate = "hourly_penalty_rate"
            case healthTargetValue = "health_target_value"
            case healthTargetUnit = "health_target_unit"
            case healthDataType = "health_data_type"
            case isZeroPenalty = "is_zero_penalty"
        }
    }
    
    struct FriendData: Codable {
        let id: String
        let friendId: String
        let name: String
        let phoneNumber: String
        let avatarVersion: Int?
        let avatarUrl80: String?
        let avatarUrl200: String?
        let avatarUrlOriginal: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case friendId = "friend_id"
            case name
            case phoneNumber = "phone_number"
            case avatarVersion = "avatar_version"
            case avatarUrl80 = "avatar_url_80"
            case avatarUrl200 = "avatar_url_200"
            case avatarUrlOriginal = "avatar_url_original"
        }
    }
    
    struct FriendWithStripeData: Codable {
        let id: String
        let name: String
        let phoneNumber: String
        let stripeConnectStatus: Bool?
        let stripeConnectAccountId: String?
        let hasStripe: Bool?
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case phoneNumber = "phone_number"
            case stripeConnectStatus = "stripe_connect_status"
            case stripeConnectAccountId = "stripe_connect_account_id"
            case hasStripe = "has_stripe"
        }
    }
    
    struct PaymentMethodData: Codable {
        let paymentMethod: PaymentMethodDetails
        
        enum CodingKeys: String, CodingKey {
            case paymentMethod = "payment_method"
        }
    }
    
    struct PaymentMethodDetails: Codable {
        let id: String
        let card: PaymentMethodCard?
    }
    
    struct PaymentMethodCard: Codable {
        let brand: String
        let last4: String
        let expMonth: Int
        let expYear: Int
        
        enum CodingKeys: String, CodingKey {
            case brand, last4
            case expMonth = "exp_month"
            case expYear = "exp_year"
        }
    }
    
    struct FeedPostData: Codable {
        let postId: String
        let caption: String?
        let createdAt: String
        let isPrivate: Bool
        let imageUrl: String?
        let selfieImageUrl: String?
        let contentImageUrl: String?
        let userId: String
        let userName: String
        let userAvatarUrl80: String?
        let userAvatarUrl200: String?
        let userAvatarUrlOriginal: String?
        let userAvatarVersion: Int?
        let streak: Int?
        let habitType: String?
        let habitName: String?
        let penaltyAmount: Float?
        let comments: [CommentData]
        let habitId: String?
        
        enum CodingKeys: String, CodingKey {
            case postId = "post_id"
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
            case habitId = "habit_id"
        }
    }
    
    struct CommentData: Codable {
        let id: String
        let content: String
        let createdAt: String
        let userId: String
        let userName: String
        let userAvatarUrl80: String?
        let userAvatarUrl200: String?
        let userAvatarUrlOriginal: String?
        let userAvatarVersion: Int?
        let isEdited: Bool
        let parentComment: String?
        
        enum CodingKeys: String, CodingKey {
            case id, content
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
    
    struct CustomHabitTypeData: Codable {
        let id: String
        let typeIdentifier: String
        let description: String
        let createdAt: String
        let updatedAt: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case typeIdentifier = "type_identifier"
            case description
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }
    
    struct AvailableHabitTypesData: Codable {
        let builtInTypes: [BuiltInHabitTypeData]
        let customTypes: [CustomHabitTypeAvailableData]
        let totalAvailable: Int
        
        enum CodingKeys: String, CodingKey {
            case builtInTypes = "built_in_types"
            case customTypes = "custom_types"
            case totalAvailable = "total_available"
        }
    }
    
    struct BuiltInHabitTypeData: Codable {
        let type: String
        let displayName: String
        let description: String
        let isCustom: Bool
        
        enum CodingKeys: String, CodingKey {
            case type
            case displayName = "display_name"
            case description
            case isCustom = "is_custom"
        }
    }
    
    struct CustomHabitTypeAvailableData: Codable {
        let type: String
        let displayName: String
        let description: String
        let isCustom: Bool
        
        enum CodingKeys: String, CodingKey {
            case type
            case displayName = "display_name"
            case description
            case isCustom = "is_custom"
        }
    }
    
    struct UserProfileData: Codable {
        let id: String
        let name: String
        let phoneNumber: String
        let onboardingState: Int?
        let profilePhotoUrl: String?
        let avatarVersion: Int?
        let avatarUrl80: String?
        let avatarUrl200: String?
        let avatarUrlOriginal: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name
            case phoneNumber = "phone_number"
            case onboardingState = "onboarding_state"
            case profilePhotoUrl = "profile_photo_url"
            case avatarVersion = "avatar_version"
            case avatarUrl80 = "avatar_url_80"
            case avatarUrl200 = "avatar_url_200"
            case avatarUrlOriginal = "avatar_url_original"
        }
    }
    
    struct WeeklyProgressData: Codable {
        let habitId: String
        let currentCompletions: Int
        let targetCompletions: Int
        let isWeekComplete: Bool
        let weekStartDate: String
        let weekEndDate: String
        // NEW: Optional timestamp to track data freshness
        let dataTimestamp: String?
        
        enum CodingKeys: String, CodingKey {
            case habitId = "habit_id"
            case currentCompletions = "current_completions"
            case targetCompletions = "target_completions"
            case isWeekComplete = "is_week_complete"
            case weekStartDate = "week_start_date"
            case weekEndDate = "week_end_date"
            case dataTimestamp = "data_timestamp"
        }
    }
    
    // NEW: Add verification data structure
    struct VerificationData: Codable {
        let id: String
        let habitId: String
        let userId: String
        let verificationType: String
        let verifiedAt: String
        let status: String
        let verificationResult: Bool?
        let imageUrl: String?
        let selfieImageUrl: String?
        let imageVerificationId: String?
        let imageFilename: String?
        let selfieImageFilename: String?
        
        enum CodingKeys: String, CodingKey {
            case id, habitId = "habit_id", userId = "user_id"
            case verificationType = "verification_type", verifiedAt = "verified_at"
            case status, verificationResult = "verification_result"
            case imageUrl = "image_url", selfieImageUrl = "selfie_image_url"
            case imageVerificationId = "image_verification_id"
            case imageFilename = "image_filename", selfieImageFilename = "selfie_image_filename"
        }
    }
    
    struct FriendRequestsData: Codable {
        let receivedRequests: [ReceivedFriendRequestData]
        let sentRequests: [SentFriendRequestData]
        
        enum CodingKeys: String, CodingKey {
            case receivedRequests = "received_requests"
            case sentRequests = "sent_requests"
        }
    }
    
    struct ReceivedFriendRequestData: Codable {
        let id: String
        let senderId: String
        let senderName: String
        let senderPhone: String
        let message: String
        let status: String
        let createdAt: String
        let senderAvatarVersion: Int?
        let senderAvatarUrl80: String?
        let senderAvatarUrl200: String?
        let senderAvatarUrlOriginal: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case senderId = "sender_id"
            case senderName = "sender_name"
            case senderPhone = "sender_phone"
            case message
            case status
            case createdAt = "created_at"
            case senderAvatarVersion = "sender_avatar_version"
            case senderAvatarUrl80 = "sender_avatar_url_80"
            case senderAvatarUrl200 = "sender_avatar_url_200"
            case senderAvatarUrlOriginal = "sender_avatar_url_original"
        }
    }
    
    struct SentFriendRequestData: Codable {
        let id: String
        let receiverId: String
        let receiverName: String
        let receiverPhone: String
        let message: String
        let status: String
        let createdAt: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case receiverId = "receiver_id"
            case receiverName = "receiver_name"
            case receiverPhone = "receiver_phone"
            case message
            case status
            case createdAt = "created_at"
        }
    }
    
    struct ContactOnTallyData: Codable {
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
    
    func preloadAllAppData(token: String) async throws -> PreloadedData {
        let startTime = Date()
        
        // Use the delta endpoint which now provides ALL data we need
        let deltaData = try await fetchAllDataFromDelta(token: token)
        
        let loadTime = Date().timeIntervalSince(startTime)
        lastLoadTime = loadTime
        
        return deltaData
    }
    
    /// Fetch all app data from the single /api/sync/delta endpoint
    private func fetchAllDataFromDelta(token: String) async throws -> PreloadedData {
        guard let url = URL(string: "\(AppConfig.baseURL)/sync/delta") else {
            throw PreloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PreloadError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw PreloadError.serverError("Failed to fetch app data from delta endpoint")
        }
        
        // Parse the response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Extract friends with Stripe data
            var friendsWithStripe: [FriendWithStripeData] = []
            if let friendsWithStripeArray = json["friends_with_stripe"] as? [[String: Any]] {
                friendsWithStripe = convertToFriendsWithStripe(friendsWithStripeArray) ?? []
            }
            
            // Extract custom habit types
            var customHabitTypes: [CustomHabitTypeData] = []
            if let customHabitTypesArray = json["custom_habit_types"] as? [[String: Any]] {
                customHabitTypes = convertToCustomHabitTypes(customHabitTypesArray) ?? []
            }
            
            // Extract available habit types
            var availableHabitTypes: AvailableHabitTypesData? = nil
            if let availableHabitTypesJson = json["available_habit_types"] as? [String: Any] {
                availableHabitTypes = convertToAvailableHabitTypes(availableHabitTypesJson)
            }
            
            // Extract verification data
            
            var habitVerifications: [String: [VerificationData]] = [:]
            if let habitVerificationsDict = json["habit_verifications"] as? [String: [[String: Any]]] {
                habitVerifications = convertToHabitVerifications(habitVerificationsDict) ?? [:]
            }
            
            var weeklyVerifiedHabits: [String: [String: Bool]] = [:]
            if let weeklyVerifiedHabitsDict = json["weekly_verified_habits"] as? [String: [String: Bool]] {
                weeklyVerifiedHabits = weeklyVerifiedHabitsDict
            }
            
            // Friend recommendations are no longer cached - they always fetch fresh data
            
            // Cache all the fetched data immediately
            DataCacheManager.shared.cacheHabits(convertToHabits(json["habits"] as? [[String: Any]]))
            DataCacheManager.shared.cacheFriends(convertToFriends(json["friends"] as? [[String: Any]]))
            DataCacheManager.shared.cacheFriendsWithStripe(friendsWithStripe)
            DataCacheManager.shared.cacheFeedPosts(convertToFeedPosts(json["feed_posts"] as? [[String: Any]]))
            DataCacheManager.shared.cacheCustomHabitTypes(customHabitTypes)
            DataCacheManager.shared.cacheWeeklyProgress(convertToWeeklyProgress(json["weekly_progress"] as? [[String: Any]]))
            DataCacheManager.shared.cacheVerifiedHabitsToday(filterVerifiedHabitsForToday(json["verified_habits_today"] as? [String: Bool]))
            DataCacheManager.shared.cacheHabitVerifications(habitVerifications)
            DataCacheManager.shared.cacheWeeklyVerifiedHabits(weeklyVerifiedHabits)
            // Friend recommendations are not cached anymore
            
            // Cache friend requests if available
            if let friendRequestsData = convertToFriendRequests(json["friend_requests"] as? [String: Any]) {
                DataCacheManager.shared.cacheFriendRequests(friendRequestsData)
            }
            
            // Cache staged deletions if available
            if let stagedDeletionsData = json["staged_deletions"] as? [String: Any] {
                let convertedStagedDeletions = convertToStagedDeletions(stagedDeletionsData)
                DataCacheManager.shared.cacheStagedDeletions(convertedStagedDeletions)
            }
            
            print("✅ [PreloadManager] Delta sync completed successfully")
            print("   📊 Data summary:")
            print("   - Habits: \(convertToHabits(json["habits"] as? [[String: Any]])?.count ?? 0)")
            print("   - Friends: \(convertToFriends(json["friends"] as? [[String: Any]])?.count ?? 0)")  
            print("   - Friends with Stripe: \(friendsWithStripe.count)")
            print("   - Feed posts: \(convertToFeedPosts(json["feed_posts"] as? [[String: Any]])?.count ?? 0)")
            print("   - Custom habit types: \(customHabitTypes.count)")
            print("   - Weekly progress: \(convertToWeeklyProgress(json["weekly_progress"] as? [[String: Any]])?.count ?? 0)")
            print("   - Verified habits today: \(filterVerifiedHabitsForToday(json["verified_habits_today"] as? [String: Bool])?.count ?? 0)")
            print("   - Habit verifications: \(habitVerifications.count)")
            print("   - Friend recommendations: Not cached")
            print("   - Friend requests: \(json["friend_requests"] != nil ? "Yes" : "No")")
            print("   - Staged deletions: \(json["staged_deletions"] != nil ? "Yes" : "No")")
            
            return PreloadedData(
                habits: convertToHabits(json["habits"] as? [[String: Any]]) ?? [],
                friends: convertToFriends(json["friends"] as? [[String: Any]]) ?? [],
                friendsWithStripe: friendsWithStripe,
                paymentMethod: convertToPaymentMethod(json["payment_method"] as? [String: Any]),
                feedPosts: convertToFeedPosts(json["feed_posts"] as? [[String: Any]]) ?? [],
                customHabitTypes: customHabitTypes,
                availableHabitTypes: availableHabitTypes,
                onboardingState: json["onboarding_state"] as? Int,
                userProfile: convertToUserProfile(json["user_profile"] as? [String: Any]),
                weeklyProgress: convertToWeeklyProgress(json["weekly_progress"] as? [[String: Any]]) ?? [],
                verifiedHabitsToday: filterVerifiedHabitsForToday(json["verified_habits_today"] as? [String: Bool]),
                habitVerifications: habitVerifications,
                weeklyVerifiedHabits: weeklyVerifiedHabits,
                friendRequests: convertToFriendRequests(json["friend_requests"] as? [String: Any]),
                stagedDeletions: convertToStagedDeletions(json["staged_deletions"] as? [String: Any]),

                contactsOnTally: convertToContactsOnTally(json["contacts_on_tally"] as? [[String: Any]])
            )
        } else {
            throw PreloadError.serverError("Invalid JSON response from delta endpoint")
        }
    }
    
    // MARK: - JSON Conversion Helpers
    
    private func convertToHabits(_ habitsJson: [[String: Any]]?) -> [HabitData]? {
        guard let habitsJson = habitsJson else { return nil }
        return habitsJson.compactMap { habitDict in
            do {
                let habitData = try JSONSerialization.data(withJSONObject: habitDict)
                return try JSONDecoder().decode(HabitData.self, from: habitData)
            } catch {
                print("Error converting habit: \(error)")
                return nil
            }
        }
    }
    
    private func convertToFriends(_ friendsJson: [[String: Any]]?) -> [FriendData]? {
        guard let friendsJson = friendsJson else { return nil }
        return friendsJson.compactMap { friendDict in
            do {
                let friendData = try JSONSerialization.data(withJSONObject: friendDict)
                return try JSONDecoder().decode(FriendData.self, from: friendData)
            } catch {
                print("Error converting friend: \(error)")
                return nil
            }
        }
    }
    
    private func convertToFriendsWithStripe(_ friendsJson: [[String: Any]]?) -> [FriendWithStripeData]? {
        guard let friendsJson = friendsJson else { return nil }
        return friendsJson.compactMap { friendDict in
            do {
                let friendData = try JSONSerialization.data(withJSONObject: friendDict)
                return try JSONDecoder().decode(FriendWithStripeData.self, from: friendData)
            } catch {
                print("Error converting friend with stripe: \(error)")
                return nil
            }
        }
    }
    
    private func convertToPaymentMethod(_ paymentMethodJson: [String: Any]?) -> PaymentMethodData? {
        guard let paymentMethodJson = paymentMethodJson else { return nil }
        do {
            let paymentMethodData = try JSONSerialization.data(withJSONObject: paymentMethodJson)
            return try JSONDecoder().decode(PaymentMethodData.self, from: paymentMethodData)
        } catch {
            print("Error converting payment method: \(error)")
            return nil
        }
    }
    
    private func convertToFeedPosts(_ feedPostsJson: [[String: Any]]?) -> [FeedPostData]? {
        guard let feedPostsJson = feedPostsJson else { return nil }
        return feedPostsJson.compactMap { postDict in
            do {
                let postData = try JSONSerialization.data(withJSONObject: postDict)
                return try JSONDecoder().decode(FeedPostData.self, from: postData)
            } catch {
                print("Error converting feed post: \(error)")
                return nil
            }
        }
    }
    
    private func convertToCustomHabitTypes(_ customHabitTypesJson: [[String: Any]]?) -> [CustomHabitTypeData]? {
        guard let customHabitTypesJson = customHabitTypesJson else { 
            return nil 
        }
        
        let result = customHabitTypesJson.compactMap { typeDict in
            do {
                let typeData = try JSONSerialization.data(withJSONObject: typeDict)
                let decoded = try JSONDecoder().decode(CustomHabitTypeData.self, from: typeData)
                return decoded
            } catch {
                print("⚠️ [DEBUG] Failed to decode custom habit type: \(error)")
                return nil
            }
        }
        
        return result.isEmpty ? nil : result
    }
    
    private func convertToAvailableHabitTypes(_ availableHabitTypesJson: [String: Any]?) -> AvailableHabitTypesData? {
        guard let availableHabitTypesJson = availableHabitTypesJson else { 
            print("⚠️ [DEBUG] availableHabitTypesJson is nil")
            return nil 
        }
        print("🔍 [DEBUG] Converting available habit types from JSON: \(availableHabitTypesJson.keys.sorted())")
        do {
            let availableHabitTypesData = try JSONSerialization.data(withJSONObject: availableHabitTypesJson)
            let decoded = try JSONDecoder().decode(AvailableHabitTypesData.self, from: availableHabitTypesData)
            print("✅ [DEBUG] Successfully decoded available habit types: \(decoded.customTypes.count) custom, \(decoded.builtInTypes.count) built-in")
            return decoded
        } catch {
            print("❌ [DEBUG] Error converting available habit types: \(error)")
            print("❌ [DEBUG] Failed JSON: \(availableHabitTypesJson)")
            return nil
        }
    }
    
    private func convertToUserProfile(_ userProfileJson: [String: Any]?) -> UserProfileData? {
        guard let userProfileJson = userProfileJson else { return nil }
        do {
            let userProfileData = try JSONSerialization.data(withJSONObject: userProfileJson)
            return try JSONDecoder().decode(UserProfileData.self, from: userProfileData)
        } catch {
            print("Error converting user profile: \(error)")
            return nil
        }
    }
    
    private func convertToWeeklyProgress(_ weeklyProgressJson: [[String: Any]]?) -> [WeeklyProgressData]? {
        guard let weeklyProgressJson = weeklyProgressJson else { return nil }
        
        return weeklyProgressJson.compactMap { progressDict in
            do {
                // NEW: Validate required fields before conversion
                guard let habitId = progressDict["habit_id"] as? String,
                      let _ = progressDict["current_completions"] as? Int,
                      let _ = progressDict["target_completions"] as? Int,
                      let _ = progressDict["is_week_complete"] as? Bool,
                      let _ = progressDict["week_start_date"] as? String else {
                    print("⚠️ [PreloadManager] Skipping invalid weekly progress record: missing required fields")
                    return nil
                }
                
                // NEW: Log data timestamp if available for debugging
                if let dataTimestamp = progressDict["data_timestamp"] as? String {
                    print("📊 [PreloadManager] Converting weekly progress for habit '\(habitId)' with timestamp: \(dataTimestamp)")
                }
                
                let progressData = try JSONSerialization.data(withJSONObject: progressDict)
                let convertedProgress = try JSONDecoder().decode(WeeklyProgressData.self, from: progressData)
                
                // NEW: Additional validation after decoding
                if convertedProgress.currentCompletions < 0 || convertedProgress.targetCompletions <= 0 {
                    print("⚠️ [PreloadManager] Skipping invalid weekly progress for habit '\(habitId)': invalid completion values")
                    return nil
                }
                
                return convertedProgress
            } catch {
                print("⚠️ [PreloadManager] Error converting weekly progress: \(error)")
                return nil
            }
        }
    }
    
    private func convertToHabitVerifications(_ habitVerificationsJson: [String: [[String: Any]]]?) -> [String: [VerificationData]]? {
        guard let habitVerificationsJson = habitVerificationsJson else { return nil }
        var result: [String: [VerificationData]] = [:]
        
        for (habitId, verificationsList) in habitVerificationsJson {
            result[habitId] = verificationsList.compactMap { verificationDict in
                do {
                    let verificationData = try JSONSerialization.data(withJSONObject: verificationDict)
                    return try JSONDecoder().decode(VerificationData.self, from: verificationData)
                } catch {
                    print("Error converting habit verification: \(error)")
                    return nil
                }
            }
        }
        
        return result
    }
    
    private func filterVerifiedHabitsForToday(_ verifiedHabitsToday: [String: Bool]?) -> [String: Bool]? {
        guard let verifiedHabitsToday = verifiedHabitsToday else { return nil }
        
        // Backend handles timezone filtering using user's stored timezone
        // The /sync/delta endpoint should already filter verified_habits_today 
        // to only include habits verified "today" in the user's timezone
        print("🕒 [PreloadManager] Received \(verifiedHabitsToday.count) verified habits from backend (pre-filtered by user timezone)")
        print("🕒 [PreloadManager] Backend-filtered verified habits today: \(verifiedHabitsToday)")
        
        return verifiedHabitsToday
    }
    
    private func convertToFriendRequests(_ friendRequestsJson: [String: Any]?) -> FriendRequestsData? {
        guard let friendRequestsJson = friendRequestsJson else { return nil }
        return FriendRequestsData(
            receivedRequests: convertToReceivedFriendRequests(friendRequestsJson["received_requests"] as? [[String: Any]]),
            sentRequests: convertToSentFriendRequests(friendRequestsJson["sent_requests"] as? [[String: Any]])
        )
    }
    
    private func convertVerificationDataToHabitVerification(_ verificationData: VerificationData) throws -> HabitVerification {
        return HabitVerification(
            id: verificationData.id,
            habitId: verificationData.habitId,
            userId: verificationData.userId,
            verificationType: verificationData.verificationType,
            verifiedAt: verificationData.verifiedAt,
            status: verificationData.status,
            verificationResult: verificationData.verificationResult,
            imageUrl: verificationData.imageUrl,
            selfieImageUrl: verificationData.selfieImageUrl,
            imageVerificationId: verificationData.imageVerificationId,
            imageFilename: verificationData.imageFilename,
            selfieImageFilename: verificationData.selfieImageFilename
        )
    }
    
    private func convertToReceivedFriendRequests(_ receivedRequestsJson: [[String: Any]]?) -> [ReceivedFriendRequestData] {
        guard let receivedRequestsJson = receivedRequestsJson else { return [] }
        return receivedRequestsJson.compactMap { requestDict in
            do {
                let receivedRequestData = try JSONSerialization.data(withJSONObject: requestDict)
                return try JSONDecoder().decode(ReceivedFriendRequestData.self, from: receivedRequestData)
            } catch {
                print("Error converting received friend request: \(error)")
                return nil
            }
        }
    }
    
    private func convertToSentFriendRequests(_ sentRequestsJson: [[String: Any]]?) -> [SentFriendRequestData] {
        guard let sentRequestsJson = sentRequestsJson else { return [] }
        return sentRequestsJson.compactMap { requestDict in
            do {
                let sentRequestData = try JSONSerialization.data(withJSONObject: requestDict)
                return try JSONDecoder().decode(SentFriendRequestData.self, from: sentRequestData)
            } catch {
                print("Error converting sent friend request: \(error)")
                return nil
            }
        }
    }
    
    private func convertToContactsOnTally(_ contactsJson: [[String: Any]]?) -> [ContactOnTallyData] {
        guard let contactsJson = contactsJson else { return [] }
        return contactsJson.compactMap { contactDict in
            do {
                let contactData = try JSONSerialization.data(withJSONObject: contactDict)
                return try JSONDecoder().decode(ContactOnTallyData.self, from: contactData)
            } catch {
                print("Error converting contact on tally: \(error)")
                return nil
            }
        }
    }
    
    private func convertToStagedDeletions(_ stagedDeletionsJson: [String: Any]?) -> [String: StagedDeletionInfo] {
        guard let stagedDeletionsJson = stagedDeletionsJson else { return [:] }
        
        var result: [String: StagedDeletionInfo] = [:]
        
        for (habitId, deletionData) in stagedDeletionsJson {
            guard let deletionDict = deletionData as? [String: Any] else { continue }
            
            let stagedDeletionInfo = StagedDeletionInfo(
                scheduledForDeletion: deletionDict["scheduled_for_deletion"] as? Bool ?? true,
                effectiveDate: deletionDict["effective_date"] as? String ?? "",
                userTimezone: deletionDict["user_timezone"] as? String ?? "",
                stagingId: deletionDict["staging_id"] as? String,
                createdAt: deletionDict["created_at"] as? String
            )
            
            result[habitId] = stagedDeletionInfo
        }
        
        return result
    }
    
    /// Ultra-fast preloader using the optimized single database call endpoint
    /// This achieves 8-20x better performance compared to the original implementation
    func preloadAllAppDataUltraFast(token: String) async throws -> PreloadedData {
        // Use the delta endpoint for all data loading now
        return try await fetchAllDataFromDelta(token: token)
    }
    
    /// Fallback to parallel processing version if ultra-fast fails
    func preloadAllAppDataParallel(token: String) async throws -> PreloadedData {
        // Use the delta endpoint for all data loading now
        return try await fetchAllDataFromDelta(token: token)
    }
    
    /// Resilient preloader that tries ultra-fast first, then falls back to parallel
    func preloadAllAppDataResilient(token: String) async throws -> PreloadedData {
        // All methods now use the same delta endpoint
        return try await fetchAllDataFromDelta(token: token)
    }
    
    func applyPreloadedDataToManagers(_ data: PreloadedData, 
                                     habitManager: HabitManager,
                                     friendsManager: FriendsManager,
                                     paymentManager: PaymentManager,
                                     feedManager: FeedManager,
                                     customHabitManager: CustomHabitManager) async {
        
        let startTime = Date()
        
        // Apply user profile data first to ensure currentUser is up to date
        if let userProfileData = data.userProfile {
            // Update the AuthenticationManager's currentUser with the latest server data
            let authManager = AuthenticationManager.shared
            if let currentUser = authManager.currentUser {
                let updatedUser = User(
                    id: currentUser.id,
                    phoneNumber: userProfileData.phoneNumber,
                    name: userProfileData.name,
                    createdAt: currentUser.createdAt,
                    updatedAt: currentUser.updatedAt,
                    timezone: currentUser.timezone,
                    profilePhotoUrl: userProfileData.profilePhotoUrl ?? currentUser.profilePhotoUrl,
                    // Include avatar data from the user profile
                    avatarVersion: userProfileData.avatarVersion ?? currentUser.avatarVersion,
                    avatarUrl80: userProfileData.avatarUrl80 ?? currentUser.avatarUrl80,
                    avatarUrl200: userProfileData.avatarUrl200 ?? currentUser.avatarUrl200,
                    avatarUrlOriginal: userProfileData.avatarUrlOriginal ?? currentUser.avatarUrlOriginal,
                    onboardingState: data.onboardingState ?? currentUser.onboardingState,
                    isPremium: currentUser.isPremium
                )
                
                await MainActor.run {
                    authManager.currentUser = updatedUser
                }
                print("✅ [PreloadManager] Updated currentUser with avatar URLs from user profile data")
                print("   🖼️ Avatar version: \(updatedUser.avatarVersion ?? -1)")
                print("   🖼️ Avatar URL 80: \(updatedUser.avatarUrl80 ?? "nil")")
                print("   🖼️ Avatar URL 200: \(updatedUser.avatarUrl200 ?? "nil")")
                print("   🖼️ Avatar URL original: \(updatedUser.avatarUrlOriginal ?? "nil")")
            }
        }
        
        // Apply habits data
        if !data.habits.isEmpty {
            let habits = data.habits.compactMap { habitData -> Habit? in
                return Habit(
                    id: habitData.id,
                    name: habitData.name,
                    recipientId: habitData.recipientId,
                    weekdays: habitData.weekdays ?? [], // Handle null weekdays
                    penaltyAmount: habitData.penaltyAmount,
                    isZeroPenalty: habitData.isZeroPenalty,
                    userId: habitData.userId,
                    createdAt: habitData.createdAt,
                    updatedAt: habitData.updatedAt,
                    habitType: habitData.habitType,
                    screenTimeLimitMinutes: habitData.screenTimeLimitMinutes,
                    restrictedApps: habitData.restrictedApps ?? [],
                    studyDurationMinutes: habitData.studyDurationMinutes,
                    isPrivate: habitData.isPrivate,
                    alarmTime: habitData.alarmTime,
                    customHabitTypeId: habitData.customHabitTypeId,
                    habitScheduleType: habitData.habitScheduleType ?? "daily",
                    weeklyTarget: habitData.weeklyTarget,
                    weekStartDay: habitData.weekStartDay ?? 0,
                    commitTarget: habitData.commitTarget,
                    todayCommitCount: habitData.todayCommitCount,
                    currentWeekCommitCount: habitData.currentWeekCommitCount,
                    dailyLimitHours: habitData.dailyLimitHours,
                    hourlyPenaltyRate: habitData.hourlyPenaltyRate,
                    healthTargetValue: habitData.healthTargetValue,
                    healthTargetUnit: habitData.healthTargetUnit,
                    healthDataType: habitData.healthDataType
                )
            }
            
            await MainActor.run {
                // Store recently added habits (added in last 5 seconds) to preserve them
                let recentCutoff = Date().addingTimeInterval(-5)
                var recentlyAddedHabits: [Habit] = []
                
                // Check for habits that exist locally but not in server response
                for localHabit in habitManager.habits {
                    if !habits.contains(where: { $0.id == localHabit.id }) {
                        // This habit exists locally but not on server - might be recently added
                        // Try multiple date formats
                        var createdDate: Date? = nil
                        
                        // Try ISO8601 with full format
                        let iso8601Formatter = ISO8601DateFormatter()
                        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        createdDate = iso8601Formatter.date(from: localHabit.createdAt)
                        
                        // Try without fractional seconds
                        if createdDate == nil {
                            iso8601Formatter.formatOptions = [.withInternetDateTime]
                            createdDate = iso8601Formatter.date(from: localHabit.createdAt)
                        }
                        
                        // Try custom format used elsewhere in the app
                        if createdDate == nil {
                            let customFormatter = DateFormatter()
                            customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                            customFormatter.timeZone = TimeZone(abbreviation: "UTC")
                            createdDate = customFormatter.date(from: localHabit.createdAt)
                        }
                        
                        // Fallback to simpler format
                        if createdDate == nil {
                            let fallbackFormatter = DateFormatter()
                            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                            fallbackFormatter.timeZone = TimeZone(abbreviation: "UTC")
                            createdDate = fallbackFormatter.date(from: localHabit.createdAt)
                        }
                        
                        if let date = createdDate, date > recentCutoff {
                            print("🔄 [PreloadManager] Preserving recently added habit: \(localHabit.name)")
                            recentlyAddedHabits.append(localHabit)
                        } else {
                            print("⚠️ [PreloadManager] Could not parse date for habit: \(localHabit.name), createdAt: \(localHabit.createdAt)")
                        }
                    }
                }
                
                // Replace habits array with server data
                habitManager.habits = habits
                
                // Re-add recently added habits that weren't in server response
                for recentHabit in recentlyAddedHabits {
                    if !habitManager.habits.contains(where: { $0.id == recentHabit.id }) {
                        habitManager.habits.append(recentHabit)
                    }
                }
                
                habitManager.habitsbydate = [:]
                habitManager.weeklyHabits = []
                
                // Organize habits by schedule type
                for habit in habitManager.habits {
                    if habit.isDailyHabit {
                        for weekday in habit.weekdays {
                            if habitManager.habitsbydate[weekday] == nil {
                                habitManager.habitsbydate[weekday] = []
                            }
                            habitManager.habitsbydate[weekday]?.append(habit)
                        }
                    } else if habit.isWeeklyHabit {
                        habitManager.weeklyHabits.append(habit)
                    }
                }
                
                for habit in habits {
                    if habit.habitType == "github_commits", let c = habit.todayCommitCount {
                        habitManager.todayCommitCounts[habit.id] = c
                    }
                    if habit.habitType == "github_commits", let c = habit.currentWeekCommitCount {
                        habitManager.weeklyCommitCounts[habit.id] = c
                    }
                }
                
                // Also populate gaming hours from preload data
                for habitData in data.habits {
                    if (habitData.habitType == "league_of_legends" || habitData.habitType == "valorant"), 
                       let hours = habitData.todayGamingHours {
                        habitManager.todayGamingHours[habitData.id] = hours
                    }
                }
                
                // Start refresh timers for GitHub commits and gaming hours
                if let token = AuthenticationManager.shared.storedAuthToken {
                    Task { await habitManager.refreshTodayCommitCounts(token: token) }
                    Task { await habitManager.refreshWeeklyCommitCounts(token: token) }
                    Task { await habitManager.refreshTodayGamingHours(token: token) }
                    Task { await habitManager.refreshTodayLeetCodeCounts(token : token)}
                    Task { await habitManager.refreshWeeklyLeetCodeCounts(token: token)}
                }
            }
        }
        
        // Apply weekly progress data to habit manager
        if !data.weeklyProgress.isEmpty {
            let convertedProgressData = data.weeklyProgress.reduce(into: [String: PreloadManager.WeeklyProgressData]()) { result, progress in
                result[progress.habitId] = PreloadManager.WeeklyProgressData(
                    habitId: progress.habitId,
                    currentCompletions: progress.currentCompletions,
                    targetCompletions: progress.targetCompletions,
                    isWeekComplete: progress.isWeekComplete,
                    weekStartDate: progress.weekStartDate,
                    weekEndDate: progress.weekEndDate,
                    dataTimestamp: progress.dataTimestamp
                )
            }
            
            habitManager.weeklyProgressData = convertedProgressData
        }
        
        // Apply verification data to habit manager
        if let verifiedHabitsToday = data.verifiedHabitsToday {
            habitManager.verifiedHabitsToday = verifiedHabitsToday
        }
        
        if let habitVerifications = data.habitVerifications {
            let convertedVerifications = habitVerifications.mapValues { verifications in
                verifications.compactMap { verificationData in
                    try? convertVerificationDataToHabitVerification(verificationData)
                }
            }
            
            habitManager.habitVerifications = convertedVerifications
        }
        
        if let weeklyVerifiedHabits = data.weeklyVerifiedHabits {
            habitManager.weeklyVerifiedHabits = weeklyVerifiedHabits
        }
        
        // Apply friends data
        if !data.friends.isEmpty {
            let friends = data.friends.compactMap { friendData -> Friend? in
                let friendJson: [String: Any] = [
                    "id": friendData.id,
                    "friend_id": friendData.friendId,
                    "name": friendData.name,
                    "phone_number": friendData.phoneNumber,
                    "avatar_version": friendData.avatarVersion as Any,
                    "avatar_url_80": friendData.avatarUrl80 as Any,
                    "avatar_url_200": friendData.avatarUrl200 as Any,
                    "avatar_url_original": friendData.avatarUrlOriginal as Any
                ]
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: friendJson)
                    return try JSONDecoder().decode(Friend.self, from: jsonData)
                } catch {
                    print("Error decoding friend: \(error)")
                    return nil
                }
            }
            
            await MainActor.run {
                friendsManager.preloadedFriends = friends
                // Update unified friend manager with new preloaded data
                // Use force refresh to ensure proper coordination
                UnifiedFriendManager.shared.forceRefreshFromPreloadedData()
            }
        }
        
        // Apply friends with Stripe data
        if !data.friendsWithStripe.isEmpty {
            print("🔍 [DEBUG] Applying \(data.friendsWithStripe.count) friends with Stripe data")
            let friendsWithStripe = data.friendsWithStripe.compactMap { friendData -> Friend? in
                // Use hasStripe field if available, otherwise calculate it
                let hasStripe = friendData.hasStripe ?? ((friendData.stripeConnectStatus == true) && (friendData.stripeConnectAccountId != nil))
                
                let friendJson: [String: Any] = [
                    "id": UUID().uuidString,
                    "friend_id": friendData.id,
                    "name": friendData.name,
                    "phone_number": friendData.phoneNumber,
                    "stripe_connect_status": friendData.stripeConnectStatus as Any,
                    "stripe_connect_account_id": friendData.stripeConnectAccountId as Any,
                    "has_stripe": hasStripe
                ]
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: friendJson)
                    return try JSONDecoder().decode(Friend.self, from: jsonData)
                } catch {
                    print("Error decoding stripe friend: \(error)")
                    return nil
                }
            }
            
            await MainActor.run {
                friendsManager.preloadedFriendsWithStripeConnect = friendsWithStripe
                print("✅ [DEBUG] Applied \(friendsWithStripe.count) friends with Stripe to friendsManager")
            }
        } else {
            print("⚠️ [DEBUG] No friends with Stripe data received")
        }
        
        // Apply payment method data
        if let paymentMethodData = data.paymentMethod {
            let expiryMonth = paymentMethodData.paymentMethod.card?.expMonth ?? 0
            let expiryYear = paymentMethodData.paymentMethod.card?.expYear ?? 0
            let monthMap = [1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun", 
                           7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec"]
            let expiryString = "\(monthMap[expiryMonth] ?? "") \(expiryYear % 100)"
            
            let paymentMethod = PaymentMethod(
                brand: paymentMethodData.paymentMethod.card?.brand ?? "",
                last4: paymentMethodData.paymentMethod.card?.last4 ?? "",
                expiry: expiryString
            )
            
            await MainActor.run {
                paymentManager.paymentMethod = paymentMethod
            }
        }
        
        // Apply feed data
        if !data.feedPosts.isEmpty {
            print("🔍 [PreloadManager] Converting \(data.feedPosts.count) feed posts from cache")
            
            let feedPosts = data.feedPosts.compactMap { postData -> FeedPost? in
                // More robust UUID parsing - try direct UUID parsing first, then fallback
                let postId: UUID
                if let directUUID = UUID(uuidString: postData.postId) {
                    postId = directUUID
                } else {
                    // Fallback: create deterministic UUID from string if not proper UUID format
                    postId = UUID()
                    print("⚠️ [PreloadManager] Invalid postId UUID '\(postData.postId)', using fallback UUID")
                }
                
                let userId: UUID
                if let directUserUUID = UUID(uuidString: postData.userId) {
                    userId = directUserUUID
                } else {
                    // Fallback: create deterministic UUID from string if not proper UUID format
                    userId = UUID()
                    print("⚠️ [PreloadManager] Invalid userId UUID '\(postData.userId)', using fallback UUID")
                }
                
                // Robust date parsing with multiple format support (matching FeedManager)
                let createdAt: Date
                let formatters = [
                    // ISO format with microseconds and timezone
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"),
                    // ISO format without microseconds
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
                    // Alternative formats
                    createDateFormatter("yyyy-MM-dd HH:mm:ss.SSSSSS"),
                    createDateFormatter("yyyy-MM-dd HH:mm:ss"),
                    // Handle formats with different microsecond lengths
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SS'Z'"),
                    createDateFormatter("yyyy-MM-dd'T'HH:mm:ss.S'Z'")
                ]
                
                var parsedDate: Date?
                for formatter in formatters {
                    if let date = formatter.date(from: postData.createdAt) {
                        parsedDate = date
                        break
                    }
                }
                
                if let parsedDate = parsedDate {
                    createdAt = parsedDate
                } else {
                    print("⚠️ [PreloadManager] Failed to parse date '\(postData.createdAt)' for post \(postData.postId), using current date")
                    createdAt = Date() // Fallback to current date instead of dropping the post
                }
                
                // Convert comments with similar robust parsing
                let comments = postData.comments.compactMap { commentData -> Comment? in
                    let commentId: UUID
                    if let directCommentUUID = UUID(uuidString: commentData.id) {
                        commentId = directCommentUUID
                    } else {
                        commentId = UUID()
                        print("⚠️ [PreloadManager] Invalid comment UUID '\(commentData.id)', using fallback UUID")
                    }
                    
                    let commentUserId: UUID
                    if let directCommentUserUUID = UUID(uuidString: commentData.userId) {
                        commentUserId = directCommentUserUUID
                    } else {
                        commentUserId = UUID()
                        print("⚠️ [PreloadManager] Invalid comment user UUID '\(commentData.userId)', using fallback UUID")
                    }
                    
                    // Parse comment date with same robust approach
                    var commentCreatedAt: Date?
                    for formatter in formatters {
                        if let date = formatter.date(from: commentData.createdAt) {
                            commentCreatedAt = date
                            break
                        }
                    }
                    
                    let finalCommentDate = commentCreatedAt ?? Date()
                    if commentCreatedAt == nil {
                        print("⚠️ [PreloadManager] Failed to parse comment date '\(commentData.createdAt)', using current date")
                    }
                    
                    // Reconstruct parent comment object if parentComment ID exists
                    var parentComment: ParentComment? = nil
                    if let parentCommentId = commentData.parentComment {
                        // Find the parent comment in the same post's comments
                        if let parentData = postData.comments.first(where: { $0.id == parentCommentId }) {
                            let parentId = UUID(uuidString: parentData.id) ?? UUID()
                            let parentUserId = UUID(uuidString: parentData.userId) ?? UUID()
                            
                            // Parse parent comment date
                            var parentCreatedAt: Date?
                            for formatter in formatters {
                                if let date = formatter.date(from: parentData.createdAt) {
                                    parentCreatedAt = date
                                    break
                                }
                            }
                            
                            parentComment = ParentComment(
                                id: parentId,
                                content: parentData.content,
                                createdAt: parentCreatedAt ?? Date(),
                                userId: parentUserId,
                                userName: parentData.userName,
                                userAvatarUrl80: parentData.userAvatarUrl80,
                                userAvatarUrl200: parentData.userAvatarUrl200,
                                userAvatarUrlOriginal: parentData.userAvatarUrlOriginal,
                                userAvatarVersion: parentData.userAvatarVersion,
                                isEdited: parentData.isEdited
                            )
                        }
                    }
                    
                    return Comment(
                        id: commentId,
                        content: commentData.content,
                        createdAt: finalCommentDate,
                        userId: commentUserId,
                        userName: commentData.userName,
                        userAvatarUrl80: commentData.userAvatarUrl80,
                        userAvatarUrl200: commentData.userAvatarUrl200,
                        userAvatarUrlOriginal: commentData.userAvatarUrlOriginal,
                        userAvatarVersion: commentData.userAvatarVersion,
                        isEdited: commentData.isEdited,
                        parentComment: parentComment
                    )
                }
                
                // 🔧 CRITICAL FIX: Organize comments with flat threading after loading from cache
                // This ensures the flat structure is maintained when reloading from cache
                let organizedComments = organizeCommentsFlat(comments)
                
                let feedPost = FeedPost(
                    postId: postId,
                    habitId: postData.habitId,
                    caption: postData.caption,
                    createdAt: createdAt,
                    isPrivate: postData.isPrivate,
                    imageUrl: postData.imageUrl,
                    selfieImageUrl: postData.selfieImageUrl,
                    contentImageUrl: postData.contentImageUrl,
                    userId: userId,
                    userName: postData.userName,
                    userAvatarUrl80: postData.userAvatarUrl80,
                    userAvatarUrl200: postData.userAvatarUrl200,
                    userAvatarUrlOriginal: postData.userAvatarUrlOriginal,
                    userAvatarVersion: postData.userAvatarVersion,
                    streak: postData.streak,
                    habitType: postData.habitType,
                    habitName: postData.habitName,
                    penaltyAmount: postData.penaltyAmount,
                    comments: organizedComments
                )
                
                return feedPost
            }
            
            print("✅ [PreloadManager] Successfully converted \(feedPosts.count) feed posts from cache")
            if feedPosts.count != data.feedPosts.count {
                print("⚠️ [PreloadManager] Some posts were filtered out during conversion: \(data.feedPosts.count) -> \(feedPosts.count)")
            }
            
            await MainActor.run {
                // Ensure newest posts are displayed first, regardless of cache order
                feedManager.feedPosts = feedPosts.sorted { $0.createdAt > $1.createdAt }
                feedManager.hasInitialized = true
            }
        } else {
            print("⚠️ [PreloadManager] No feed posts data in cache")
            await MainActor.run {
                feedManager.hasInitialized = true // Mark as initialized even if empty
            }
        }
        
        // Apply custom habit types data
        if !data.customHabitTypes.isEmpty {
            let customHabitTypes = data.customHabitTypes.map { typeData in
                return CustomHabitType(
                    id: typeData.id,
                    typeIdentifier: typeData.typeIdentifier,
                    description: typeData.description,
                    createdAt: typeData.createdAt,
                    updatedAt: typeData.updatedAt
                )
            }
            
            await MainActor.run {
                customHabitManager.customHabitTypes = customHabitTypes
            }
        }
        
        // Apply available habit types data
        if let availableHabitTypesData = data.availableHabitTypes {
            // Convert AvailableHabitTypesData to AvailableHabitTypes
            let builtInTypes = availableHabitTypesData.builtInTypes.map { typeData in
                BuiltInHabitType(
                    type: typeData.type,
                    displayName: typeData.displayName,
                    description: typeData.description,
                    isCustom: typeData.isCustom
                )
            }
            
            let customTypes = availableHabitTypesData.customTypes.map { typeData in
                AvailableCustomHabitType(
                    type: typeData.type,
                    displayName: typeData.displayName,
                    description: typeData.description,
                    isCustom: typeData.isCustom
                )
            }
            
            let availableHabitTypes = AvailableHabitTypes(
                builtInTypes: builtInTypes,
                customTypes: customTypes,
                totalAvailable: availableHabitTypesData.totalAvailable
            )
            
            await MainActor.run {
                customHabitManager.availableHabitTypes = availableHabitTypes
            }
        }
        
        // Apply friend requests data
        if let friendRequestsData = data.friendRequests {
            await MainActor.run {
                // Convert to FriendRequestWithDetails format for FriendRequestManager
                let receivedRequests = friendRequestsData.receivedRequests.map { requestData in
                    FriendRequestWithDetails(
                        id: requestData.id,
                        senderId: requestData.senderId,
                        receiverId: "", // Current user ID - could be filled if needed
                        status: .pending, // Default status for received requests
                        message: requestData.message,
                        createdAt: requestData.createdAt,
                        updatedAt: requestData.createdAt,
                        senderName: requestData.senderName,
                        senderPhone: requestData.senderPhone,
                        receiverName: "", // Current user - could be filled if needed
                        receiverPhone: "",
                        // Include avatar data if available
                        senderAvatarVersion: requestData.senderAvatarVersion,
                        senderAvatarUrl80: requestData.senderAvatarUrl80,
                        senderAvatarUrl200: requestData.senderAvatarUrl200,
                        senderAvatarUrlOriginal: requestData.senderAvatarUrlOriginal
                    )
                }
                
                let sentRequests = friendRequestsData.sentRequests.map { requestData in
                    SentFriendRequest(
                        id: requestData.id,
                        receiverId: requestData.receiverId,
                        receiverName: requestData.receiverName,
                        receiverPhone: requestData.receiverPhone,
                        message: requestData.message,
                        status: requestData.status
                    )
                }
                
                // Apply to FriendRequestManager
                let friendRequestManager = FriendRequestManager.shared
                friendRequestManager.receivedRequests = receivedRequests
                friendRequestManager.sentRequests = sentRequests
                
                // Force refresh unified friend manager with new friend request data
                // This ensures proper coordination and prevents race conditions
                UnifiedFriendManager.shared.forceRefreshFromPreloadedData()
                
                // Trigger immediate UI update for notification dots
                NotificationCenter.default.post(name: NSNotification.Name("FriendRequestsUpdated"), object: nil)
                
                print("✅ [PreloadManager] Applied friend requests data: \(receivedRequests.count) received, \(sentRequests.count) sent")
            }
        } else {
            print("⚠️ [DEBUG] No friend requests data received")
            // Even if no data, force refresh to ensure state is consistent
            UnifiedFriendManager.shared.forceRefreshFromPreloadedData()
            
            // Trigger UI update to clear any stale notification dots
            NotificationCenter.default.post(name: NSNotification.Name("FriendRequestsUpdated"), object: nil)
        }
        
        // Friend recommendations are no longer preloaded - they fetch fresh every time
        
        // Apply contacts on tally data
        if let contactsOnTallyData = data.contactsOnTally {
            await MainActor.run {
                // Convert ContactOnTallyData to ContactOnTally for UnifiedFriendManager
                let contactsOnTally = contactsOnTallyData.map { contactData in
                    ContactOnTally(
                        userId: contactData.userId,
                        name: contactData.name,
                        phoneNumber: contactData.phoneNumber,
                        avatarVersion: contactData.avatarVersion,
                        avatarUrl80: contactData.avatarUrl80,
                        avatarUrl200: contactData.avatarUrl200,
                        avatarUrlOriginal: contactData.avatarUrlOriginal
                    )
                }
                
                // Apply directly to unified friend manager
                UnifiedFriendManager.shared.contactsOnTally = contactsOnTally
                print("✅ [PreloadManager] Applied \(contactsOnTally.count) contacts on tally to unified manager")
            }
        } else {
            print("⚠️ [DEBUG] No contacts on tally data received")
        }
        
        let endTime = Date()
        let processTime = endTime.timeIntervalSince(startTime)
        
        // Mark UnifiedFriendManager as having completed initial data loading
        // This ensures notification dots work properly after PreloadManager completes
        UnifiedFriendManager.shared.hasInitialDataLoaded = true
        
        print("✅ [PreloadManager] Data application completed in \(String(format: "%.2f", processTime))s")
        print("✅ [PreloadManager] UnifiedFriendManager marked as having initial data loaded")
    }

    // MARK: - Legacy Methods (kept for backward compatibility)

    private func fetchWeeklyProgress(userId: String, token: String) async throws -> [WeeklyProgressData] {
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/weekly-progress/\(userId)") else {
            throw PreloadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PreloadError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                // No weekly progress data yet
                return []
            }
            throw PreloadError.serverError("Failed to fetch weekly progress")
        }
        
        return try JSONDecoder().decode([WeeklyProgressData].self, from: data)
    }

    // MARK: - Date Parsing Helper
    
    private func createDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }
    
    // MARK: - Image Download Helper
    
    /// Download verification images for all verified habits today
    private func downloadVerificationImages(for habitManager: HabitManager) async {
        print("🖼️ [PreloadManager] Starting verification image downloads...")
        
        // Get today's verified habits
        let verifiedHabitIds = habitManager.verifiedHabitsToday.compactMap { (habitId, isVerified) in
            isVerified ? habitId : nil
        }
        
        print("🖼️ [PreloadManager] Downloading images for \(verifiedHabitIds.count) verified habits")
        
        // Download images for each verified habit
        await withTaskGroup(of: Void.self) { group in
            for habitId in verifiedHabitIds {
                group.addTask {
                    await habitManager.preloadVerificationImage(for: habitId)
                }
            }
        }
        
        print("🖼️ [PreloadManager] Completed verification image downloads")
    }

    private func getFeed(token: String, since: Date? = nil, limit: Int = 20) async throws -> [FeedPost] {
        var urlComponents = URLComponents(string: "\(AppConfig.baseURL)/feed")!
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let since = since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await urlSession.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let posts = try decoder.decode([FeedPost].self, from: data)
        
        // DEBUG: Inspect habitType immediately after decoding
        for post in posts {
            print("DEBUG DECODE: Post ID: \(post.postId), Habit Type: \(post.habitType ?? "nil"), Habit Name: \(post.habitName ?? "nil")")
        }
        
        return posts
    }

    /// Organize comments using proper tree structure (no path compression)
    private func organizeCommentsFlat(_ comments: [Comment]) -> [Comment] {
        guard !comments.isEmpty else { return [] }
        
        // Build parent-to-children mapping
        var childrenByParent: [UUID: [Comment]] = [:]
        var topLevelComments: [Comment] = []
        
        // Categorize comments by their direct parent relationship
        for comment in comments {
            if let parentComment = comment.parentComment {
                // This is a reply - add to parent's children list
                let parentId = parentComment.id
                if childrenByParent[parentId] == nil {
                    childrenByParent[parentId] = []
                }
                childrenByParent[parentId]!.append(comment)
            } else {
                // This is a top-level comment
                topLevelComments.append(comment)
            }
        }
        
        // Sort top-level comments chronologically
        let sortedTopLevel = topLevelComments.sorted { $0.createdAt < $1.createdAt }
        
        // Iteratively build the flat list maintaining tree order using a stack
        var organizedComments: [Comment] = []
        
        // Stack to track comments to process
        var stack: [Comment] = sortedTopLevel.reversed()
        
        // Process comments iteratively
        while !stack.isEmpty {
            let comment = stack.removeLast()
            organizedComments.append(comment)
            
            // Add direct children to stack (in reverse order for correct processing)
            if let children = childrenByParent[comment.id] {
                let sortedChildren = children.sorted { $0.createdAt < $1.createdAt }
                // Add in reverse order so they're popped in correct order
                for child in sortedChildren.reversed() {
                    stack.append(child)
                }
            }
        }
        
        return organizedComments
    }

}

// MARK: - Error Types

enum PreloadError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case missingUserId
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return message
        case .missingUserId:
            return "Missing user ID"
        }
    }
} 
