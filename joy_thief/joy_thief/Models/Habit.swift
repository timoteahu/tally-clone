import Foundation

struct Habit: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let recipientId: String?
    let weekdays: [Int]
    let penaltyAmount: Float
    let isZeroPenalty: Bool?
    let userId: String
    let createdAt: String
    let updatedAt: String
    let habitType: String
    let screenTimeLimitMinutes: Int?
    let restrictedApps: [String]?
    let studyDurationMinutes: Int?
    let isPrivate: Bool?
    let alarmTime: String?
    let customHabitTypeId: String?
    let streak: Int?
    
    // Weekly schedule fields
    let habitScheduleType: String?  // "daily" or "weekly"
    let weeklyTarget: Int?         // Number of times per week for weekly habits
    let weekStartDay: Int?         // Week start day (0=Sunday, 1=Monday)
    let commitTarget: Int?
    let todayCommitCount: Int?
    let currentWeekCommitCount: Int?
    
    // Gaming habit fields
    let dailyLimitHours: Double?
    let hourlyPenaltyRate: Double?
    let gamesTracked: [String]?
    
    // Apple Health habit fields
    let healthTargetValue: Double?
    let healthTargetUnit: String?
    let healthDataType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case recipientId = "recipient_id"
        case weekdays
        case penaltyAmount = "penalty_amount"
        case isZeroPenalty = "is_zero_penalty"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case habitType = "habit_type"
        case screenTimeLimitMinutes = "screen_time_limit_minutes"
        case restrictedApps = "restricted_apps"
        case studyDurationMinutes = "study_duration_minutes"
        case isPrivate = "private"
        case alarmTime = "alarm_time"
        case customHabitTypeId = "custom_habit_type_id"
        case habitScheduleType = "habit_schedule_type"
        case weeklyTarget = "weekly_target"
        case weekStartDay = "week_start_day"
        case streak
        case commitTarget = "commit_target"
        case todayCommitCount = "today_commit_count"
        case currentWeekCommitCount = "current_week_commit_count"
        case dailyLimitHours = "daily_limit_hours"
        case hourlyPenaltyRate = "hourly_penalty_rate"
        case gamesTracked = "games_tracked"
        case healthTargetValue = "health_target_value"
        case healthTargetUnit = "health_target_unit"
        case healthDataType = "health_data_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recipientId = try container.decodeIfPresent(String.self, forKey: .recipientId)
        
        // Handle weekdays - can be null for weekly habits
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        
        penaltyAmount = try container.decode(Float.self, forKey: .penaltyAmount)
        isZeroPenalty = try container.decodeIfPresent(Bool.self, forKey: .isZeroPenalty) ?? false
        userId = try container.decode(String.self, forKey: .userId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        habitType = try container.decode(String.self, forKey: .habitType)
        screenTimeLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .screenTimeLimitMinutes)
        restrictedApps = try container.decodeIfPresent([String].self, forKey: .restrictedApps)
        studyDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .studyDurationMinutes)
        alarmTime = try container.decodeIfPresent(String.self, forKey: .alarmTime)
        customHabitTypeId = try container.decodeIfPresent(String.self, forKey: .customHabitTypeId)
        
        // Handle the case where the private field might be missing in older responses
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        
        // Handle weekly schedule fields with defaults for backwards compatibility
        habitScheduleType = try container.decodeIfPresent(String.self, forKey: .habitScheduleType) ?? "daily"
        weeklyTarget = try container.decodeIfPresent(Int.self, forKey: .weeklyTarget)
        weekStartDay = try container.decodeIfPresent(Int.self, forKey: .weekStartDay) ?? 0
        streak = try container.decodeIfPresent(Int.self, forKey: .streak)
        commitTarget = try container.decodeIfPresent(Int.self, forKey: .commitTarget)
        todayCommitCount = try container.decodeIfPresent(Int.self, forKey: .todayCommitCount)
        currentWeekCommitCount = try container.decodeIfPresent(Int.self, forKey: .currentWeekCommitCount)
        
        // Gaming habit fields
        dailyLimitHours = try container.decodeIfPresent(Double.self, forKey: .dailyLimitHours)
        hourlyPenaltyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyPenaltyRate)
        gamesTracked = try container.decodeIfPresent([String].self, forKey: .gamesTracked)
        
        // Apple Health habit fields
        healthTargetValue = try container.decodeIfPresent(Double.self, forKey: .healthTargetValue)
        healthTargetUnit = try container.decodeIfPresent(String.self, forKey: .healthTargetUnit)
        healthDataType = try container.decodeIfPresent(String.self, forKey: .healthDataType)
    }
    
    // Memberwise initializer for Habit
    init(
        id: String,
        name: String,
        recipientId: String?,
        weekdays: [Int],
        penaltyAmount: Float,
        isZeroPenalty: Bool? = false,
        userId: String,
        createdAt: String,
        updatedAt: String,
        habitType: String,
        screenTimeLimitMinutes: Int? = nil,
        restrictedApps: [String]? = nil,
        studyDurationMinutes: Int? = nil,
        isPrivate: Bool? = nil,
        alarmTime: String? = nil,
        customHabitTypeId: String? = nil,
        habitScheduleType: String? = "daily",
        weeklyTarget: Int? = nil,
        weekStartDay: Int? = 0,
        streak: Int? = nil,
        commitTarget: Int? = nil,
        todayCommitCount: Int? = nil,
        currentWeekCommitCount: Int? = nil,
        dailyLimitHours: Double? = nil,
        hourlyPenaltyRate: Double? = nil,
        gamesTracked: [String]? = nil,
        healthTargetValue: Double? = nil,
        healthTargetUnit: String? = nil,
        healthDataType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.recipientId = recipientId
        self.weekdays = weekdays
        self.penaltyAmount = penaltyAmount
        self.isZeroPenalty = isZeroPenalty
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.habitType = habitType
        self.screenTimeLimitMinutes = screenTimeLimitMinutes
        self.restrictedApps = restrictedApps
        self.studyDurationMinutes = studyDurationMinutes
        self.isPrivate = isPrivate
        self.alarmTime = alarmTime
        self.customHabitTypeId = customHabitTypeId
        self.habitScheduleType = habitScheduleType
        self.weeklyTarget = weeklyTarget
        self.weekStartDay = weekStartDay
        self.streak = streak
        self.commitTarget = commitTarget
        self.todayCommitCount = todayCommitCount
        self.currentWeekCommitCount = currentWeekCommitCount
        self.dailyLimitHours = dailyLimitHours
        self.hourlyPenaltyRate = hourlyPenaltyRate
        self.gamesTracked = gamesTracked
        self.healthTargetValue = healthTargetValue
        self.healthTargetUnit = healthTargetUnit
        self.healthDataType = healthDataType
    }
    
    // var isScreenTimeHabit: Bool {
    //     habitType == HabitType.screenTime.rawValue
    // }
    
    var isAlarmHabit: Bool {
        habitType == HabitType.alarm.rawValue
    }
    
    // var isStudyHabit: Bool {
    //     habitType == HabitType.studying.rawValue && studyDurationMinutes != nil
    // }
    
    var isGymHabit: Bool {
        habitType == HabitType.gym.rawValue
    }
    
    var isYogaHabit: Bool {
        habitType == HabitType.yoga.rawValue
    }
    
    var isOutdoorsHabit: Bool {
        habitType == HabitType.outdoors.rawValue
    }
    
    var isCyclingHabit: Bool {
        habitType == HabitType.cycling.rawValue
    }
    
    var isCookingHabit: Bool {
        habitType == HabitType.cooking.rawValue
    }
    
    var isLeagueOfLegendsHabit: Bool {
        habitType == HabitType.league_of_legends.rawValue
    }
    
    var isValorantHabit: Bool {
        habitType == HabitType.valorant.rawValue
    }
    
    // Apple Health habit checks
    var isHealthHabit: Bool {
        habitType == "health_steps" ||
        habitType == "health_walking_running_distance" ||
        habitType == "health_flights_climbed" ||
        habitType == "health_exercise_minutes" ||
        habitType == "health_cycling_distance" ||
        habitType == "health_sleep_hours" ||
        habitType == "health_calories_burned" ||
        habitType == "health_mindful_minutes"
    }
    
    var requiresAppleWatch: Bool {
        habitType == "health_calories_burned" ||
        habitType == "health_exercise_minutes" ||
        habitType == "health_sleep_hours"
    }
    
    var supportsManualEntry: Bool {
        habitType == "health_mindful_minutes" ||
        habitType == "health_cycling_distance"
    }
    
    var isStepsHabit: Bool {
        habitType == "health_steps"
    }
    
    var isDistanceHabit: Bool {
        habitType == "health_walking_running_distance" || habitType == "health_cycling_distance"
    }
    
    var isExerciseHabit: Bool {
        habitType == "health_exercise_minutes"
    }
    
    var isSleepHabit: Bool {
        habitType == "health_sleep_hours"
    }
    
    var isCaloriesHabit: Bool {
        habitType == "health_calories_burned"
    }
    
    var isFlightsClimbedHabit: Bool {
        habitType == "health_flights_climbed"
    }
    
    var isMindfulMinutesHabit: Bool {
        habitType == "health_mindful_minutes"
    }
    
    var isGamingHabit: Bool {
        isLeagueOfLegendsHabit || isValorantHabit
    }
    
    var isCustomHabit: Bool {
        habitType.hasPrefix("custom_") || customHabitTypeId != nil
    }
    
    var isPrivateHabit: Bool {
        isPrivate ?? false
    }
    
    var isZeroPenaltyHabit: Bool {
        isZeroPenalty ?? false
    }
    
    var isWeeklyHabit: Bool {
        habitScheduleType == "weekly"
    }
    
    var isDailyHabit: Bool {
        habitScheduleType == "daily"
    }
    
    var currentStreak: Int {
        return streak ?? 0
    }
    
    // Get the custom habit type identifier from the habit type
    var customTypeIdentifier: String? {
        if habitType.hasPrefix("custom_") {
            return String(habitType.dropFirst(7)) // Remove "custom_" prefix
        }
        return nil
    }
    
    // Get the friend name for the recipient_id
    func getRecipientName() -> String? {
        guard let recipientId = self.recipientId else { return nil }
        
        // Find the friend in the FriendsManager
        let friend = FriendsManager.shared.preloadedFriends.first { friend in
            friend.friendId == recipientId
        }
        
        return friend?.name
    }
    
    // Get today's verification image data efficiently without triggering network calls
    @MainActor func getTodaysVerificationImageData(from habitManager: HabitManager) -> Data? {
        return habitManager.getCachedVerificationImage(for: self.id)
    }
    
    // Equatable conformance - compare by ID since each habit has a unique ID
    static func == (lhs: Habit, rhs: Habit) -> Bool {
        return lhs.id == rhs.id
    }
}

enum HabitType: String, CaseIterable, Identifiable {
    // case studying
    // case screenTime
    case gym
    case alarm
    case yoga
    case outdoors
    case cycling
    case cooking
    case league_of_legends
    case valorant
    
    // Apple Health habit types
    case health_steps
    case health_walking_running_distance
    case health_flights_climbed
    case health_exercise_minutes
    case health_cycling_distance
    case health_sleep_hours
    case health_calories_burned
    case health_mindful_minutes
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        // case .studying:
        //     return "Study"
        // case .screenTime:
        //     return "Phone"
        case .gym:
            return "Gym"
        case .alarm:
            return "Alarm"
        case .yoga:
            return "Pilates"
        case .outdoors:
            return "Outdoors"
        case .cycling:
            return "Biking"
        case .cooking:
            return "Cooking"
        case .league_of_legends:
            return "League of Legends"
        case .valorant:
            return "Valorant"
        // Apple Health habit types
        case .health_steps:
            return "Steps"
        case .health_walking_running_distance:
            return "Walking + Running"
        case .health_flights_climbed:
            return "Flights Climbed"
        case .health_exercise_minutes:
            return "Exercise Minutes"
        case .health_cycling_distance:
            return "Cycling Distance"
        case .health_sleep_hours:
            return "Sleep"
        case .health_calories_burned:
            return "Calories Burned"
        case .health_mindful_minutes:
            return "Mindful Minutes"
        }
    }
    
    var icon: String {
        switch self {
        // case .studying:
        //     return "book.fill"
        // case .screenTime:
        //     return "iphone"
        case .gym:
            return "dumbbell.fill"
        case .alarm:
            return "alarm.fill"
        case .yoga:
            return "figure.yoga"
        case .outdoors:
            return "figure.walk"
        case .cycling:
            return "bicycle"
        case .cooking:
            return "fork.knife"
        case .league_of_legends:
            return "gamecontroller"
        case .valorant:
            return "gamecontroller"
        // Apple Health habit types
        case .health_steps:
            return "figure.walk"
        case .health_walking_running_distance:
            return "figure.run"
        case .health_flights_climbed:
            return "figure.stairs"
        case .health_exercise_minutes:
            return "heart.fill"
        case .health_cycling_distance:
            return "bicycle"
        case .health_sleep_hours:
            return "bed.double.fill"
        case .health_calories_burned:
            return "flame.fill"
        case .health_mindful_minutes:
            return "brain.head.profile"
        }
    }
}

enum HabitError: Error {
    case networkError
    case serverError(String)
    case invalidHabitType(String)
    case invalidAlarmTime(String)
    case invalidCustomHabitType(String)
    
    var localizedDescription: String {
        switch self {
        case .networkError:
            return "Network connection error. Please check your internet connection and try again."
        case .serverError(let message):
            return message
        case .invalidHabitType(let message):
            return message
        case .invalidAlarmTime(let message):
            return message
        case .invalidCustomHabitType(let message):
            return message
        }
    }
}

struct ErrorResponse: Codable {
    let detail: String
}

// MARK: - Habit Verification Model
struct HabitVerification: Codable, Identifiable {
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
        case id
        case habitId = "habit_id"
        case userId = "user_id"
        case verificationType = "verification_type"
        case verifiedAt = "verified_at"
        case status
        case verificationResult = "verification_result"
        case imageUrl = "image_url"
        case selfieImageUrl = "selfie_image_url"
        case imageVerificationId = "image_verification_id"
        case imageFilename = "image_filename"
        case selfieImageFilename = "selfie_image_filename"
    }
}

// MARK: - Weekly Verification Response Model
struct WeeklyVerificationResponse: Codable {
    let weekStart: String
    let weekEnd: String
    let verificationsByDate: [String: [HabitVerification]]
    
    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case verificationsByDate = "verifications_by_date"
    }
}

// MARK: - Habit Change Response Models
struct HabitDeleteResponse: Codable {
    let message: String
    let effectiveDate: String
    let timezone: String
    let habitType: String
    let deletionTiming: String
    
    enum CodingKeys: String, CodingKey {
        case message
        case effectiveDate = "effective_date"
        case timezone
        case habitType = "habit_type"
        case deletionTiming = "deletion_timing"
    }
}

struct HabitUpdateResponse: Codable {
    let message: String
    let effectiveDate: String
    let timezone: String
    let oldHabit: Habit
    let stagedChanges: [String: AnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case message
        case effectiveDate = "effective_date"
        case timezone
        case oldHabit = "old_habit"
        case stagedChanges = "staged_changes"
    }
}

// MARK: - Staged Deletion Models
struct StagedDeletion: Codable {
    let id: String
    let habitId: String
    let userId: String
    let changeType: String
    let effectiveDate: String
    let userTimezone: String
    let applied: Bool
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case habitId = "habit_id"
        case userId = "user_id" 
        case changeType = "change_type"
        case effectiveDate = "effective_date"
        case userTimezone = "user_timezone"
        case applied
        case createdAt = "created_at"
    }
}

struct RestoreHabitResponse: Codable {
    let message: String
    let habitId: String
    let restored: Bool
    
    enum CodingKeys: String, CodingKey {
        case message
        case habitId = "habit_id"
        case restored
    }
}

// Helper for dynamic JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else {
            try container.encodeNil()
        }
    }
} 
