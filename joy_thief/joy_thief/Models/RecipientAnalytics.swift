import Foundation

// MARK: - Recipient Analytics Models

struct WeeklyProgress: Codable {
    let currentCompletions: Int
    let targetCompletions: Int
    let weekStartDate: Date
    
    private enum CodingKeys: String, CodingKey {
        case currentCompletions = "current_completions"
        case targetCompletions = "target_completions"
        case weekStartDate = "week_start_date"
    }
}

extension WeeklyProgress {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        currentCompletions = try container.decode(Int.self, forKey: .currentCompletions)
        targetCompletions = try container.decode(Int.self, forKey: .targetCompletions)
        
        // Handle date parsing
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let weekStartDateString = try container.decode(String.self, forKey: .weekStartDate)
        weekStartDate = dateFormatter.date(from: weekStartDateString) ?? Date()
    }
}

struct RecipientAnalytics: Codable, Identifiable {
    let id: UUID
    let recipientId: UUID
    let habitId: UUID
    let habitOwnerId: UUID
    
    // Financial metrics
    let totalEarned: Double
    let pendingEarnings: Double
    
    // Performance metrics
    let totalCompletions: Int
    let totalFailures: Int
    let totalRequiredDays: Int
    let successRate: Double
    
    // Tracking dates
    let firstRecipientDate: Date
    let lastVerificationDate: Date?
    let lastPenaltyDate: Date?
    
    // Metadata
    let createdAt: Date
    let updatedAt: Date
    
    private enum CodingKeys: String, CodingKey {
        case id, recipientId = "recipient_id", habitId = "habit_id", habitOwnerId = "habit_owner_id"
        case totalEarned = "total_earned", pendingEarnings = "pending_earnings"
        case totalCompletions = "total_completions", totalFailures = "total_failures"
        case totalRequiredDays = "total_required_days", successRate = "success_rate"
        case firstRecipientDate = "first_recipient_date"
        case lastVerificationDate = "last_verification_date"
        case lastPenaltyDate = "last_penalty_date"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

struct HabitWithAnalytics: Codable, Identifiable {
    // Habit fields
    let id: UUID
    let name: String
    let recipientId: UUID?
    let habitType: String
    let weekdays: [Int]?
    let penaltyAmount: Double
    let hourlyPenaltyRate: Double?
    let userId: UUID
    let createdAt: Date?
    let updatedAt: Date?
    let studyDurationMinutes: Int?
    let screenTimeLimitMinutes: Int?
    let restrictedApps: [String]?
    let alarmTime: String?
    let isPrivate: Bool?
    let customHabitTypeId: UUID?
    let habitScheduleType: String?
    let weeklyTarget: Int?
    let weekStartDay: Int?
    let streak: Int?
    let commitTarget: Int?
    let isActive: Bool?
    let completedAt: Date?
    
    // Analytics data
    let analytics: RecipientAnalytics?
    
    // Owner information
    let ownerName: String?
    let ownerPhone: String?
    let ownerLastActive: Date?
    let ownerTimezone: String?
    
    // Weekly progress (for weekly habits)
    let weeklyProgress: WeeklyProgress?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, habitType = "habit_type", weekdays, userId = "user_id"
        case recipientId = "recipient_id", penaltyAmount = "penalty_amount"
        case hourlyPenaltyRate = "hourly_penalty_rate"
        case createdAt = "created_at", updatedAt = "updated_at"
        case studyDurationMinutes = "study_duration_minutes"
        case screenTimeLimitMinutes = "screen_time_limit_minutes"
        case restrictedApps = "restricted_apps", alarmTime = "alarm_time"
        case isPrivate = "private", customHabitTypeId = "custom_habit_type_id"
        case habitScheduleType = "habit_schedule_type", weeklyTarget = "weekly_target"
        case weekStartDay = "week_start_day", streak, commitTarget = "commit_target"
        case isActive = "is_active", completedAt = "completed_at"
        case analytics, ownerName = "owner_name", ownerPhone = "owner_phone"
        case ownerLastActive = "owner_last_active", ownerTimezone = "owner_timezone"
        case weeklyProgress = "weekly_progress"
    }
}

struct RecipientSummaryStats: Codable {
    let totalHabitsMonitored: Int
    let totalEarnedAllTime: Double
    let totalPendingAllHabits: Double
    let overallSuccessRate: Double
    let totalCompletionsAllHabits: Int
    let totalFailuresAllHabits: Int
    
    private enum CodingKeys: String, CodingKey {
        case totalHabitsMonitored = "total_habits_monitored"
        case totalEarnedAllTime = "total_earned_all_time"
        case totalPendingAllHabits = "total_pending_all_habits"
        case overallSuccessRate = "overall_success_rate"
        case totalCompletionsAllHabits = "total_completions_all_habits"
        case totalFailuresAllHabits = "total_failures_all_habits"
    }
}

struct RecipientSummaryResponse: Codable {
    let recipientId: String
    let summary: RecipientSummaryStats
    
    private enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
        case summary
    }
}

// MARK: - Custom Date Decoder
// Shared date parsing helper
private func parseDate(_ dateString: String, timezone: String? = nil) -> Date? {
    // Check if it's a date-only format (YYYY-MM-DD)
    if dateString.count == 10 && dateString.contains("-") {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        // Use provided timezone, fall back to current timezone
        if let tz = timezone, let timeZone = TimeZone(identifier: tz) {
            dateFormatter.timeZone = timeZone
        } else {
            dateFormatter.timeZone = TimeZone.current
        }
        if let date = dateFormatter.date(from: dateString) {
            // Add 12 hours to get noon instead of midnight
            // This prevents timezone rollover issues
            return date.addingTimeInterval(12 * 60 * 60)
        }
    }
    
    // Try with fractional seconds first
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Try date-only format
    formatter.formatOptions = [.withFullDate]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Last resort: try replacing Z with +00:00
    let modifiedString = dateString.replacingOccurrences(of: "Z", with: "+00:00")
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: modifiedString)
}

extension RecipientAnalytics {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        recipientId = try container.decode(UUID.self, forKey: .recipientId)
        habitId = try container.decode(UUID.self, forKey: .habitId)
        habitOwnerId = try container.decode(UUID.self, forKey: .habitOwnerId)
        
        totalEarned = try container.decode(Double.self, forKey: .totalEarned)
        pendingEarnings = try container.decode(Double.self, forKey: .pendingEarnings)
        
        totalCompletions = try container.decode(Int.self, forKey: .totalCompletions)
        totalFailures = try container.decode(Int.self, forKey: .totalFailures)
        totalRequiredDays = try container.decode(Int.self, forKey: .totalRequiredDays)
        successRate = try container.decode(Double.self, forKey: .successRate)
        
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        let firstRecipientDateString = try container.decode(String.self, forKey: .firstRecipientDate)
        
        // Parse dates with improved parsing
        createdAt = parseDate(createdAtString) ?? Date()
        updatedAt = parseDate(updatedAtString) ?? Date()
        firstRecipientDate = parseDate(firstRecipientDateString) ?? Date()
        
        // Optional dates
        if let lastVerificationString = try container.decodeIfPresent(String.self, forKey: .lastVerificationDate) {
            lastVerificationDate = parseDate(lastVerificationString)
        } else {
            lastVerificationDate = nil
        }
        
        if let lastPenaltyString = try container.decodeIfPresent(String.self, forKey: .lastPenaltyDate) {
            lastPenaltyDate = parseDate(lastPenaltyString)
        } else {
            lastPenaltyDate = nil
        }
    }
}

extension HabitWithAnalytics {
    // Shared date formatter for parsing dates with fractional seconds
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // Fallback date formatter for dates without fractional seconds
    private static let iso8601BasicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // Helper function to parse dates with multiple format attempts
    private static func parseDate(_ dateString: String) -> Date? {
        // Try with fractional seconds first
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        if let date = iso8601BasicFormatter.date(from: dateString) {
            return date
        }
        // Last resort: try replacing Z with +00:00 for timezone issues
        let modifiedString = dateString.replacingOccurrences(of: "Z", with: "+00:00")
        return iso8601Formatter.date(from: modifiedString) ?? iso8601BasicFormatter.date(from: modifiedString)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recipientId = try container.decodeIfPresent(UUID.self, forKey: .recipientId)
        habitType = try container.decode(String.self, forKey: .habitType)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays)
        penaltyAmount = try container.decode(Double.self, forKey: .penaltyAmount)
        hourlyPenaltyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyPenaltyRate)
        userId = try container.decode(UUID.self, forKey: .userId)
        
        // Handle optional date fields with improved parsing
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Self.parseDate(createdAtString)
        } else {
            createdAt = nil
        }
        
        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.parseDate(updatedAtString)
        } else {
            updatedAt = nil
        }
        
        studyDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .studyDurationMinutes)
        screenTimeLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .screenTimeLimitMinutes)
        restrictedApps = try container.decodeIfPresent([String].self, forKey: .restrictedApps)
        alarmTime = try container.decodeIfPresent(String.self, forKey: .alarmTime)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        customHabitTypeId = try container.decodeIfPresent(UUID.self, forKey: .customHabitTypeId)
        habitScheduleType = try container.decodeIfPresent(String.self, forKey: .habitScheduleType)
        weeklyTarget = try container.decodeIfPresent(Int.self, forKey: .weeklyTarget)
        weekStartDay = try container.decodeIfPresent(Int.self, forKey: .weekStartDay)
        streak = try container.decodeIfPresent(Int.self, forKey: .streak)
        commitTarget = try container.decodeIfPresent(Int.self, forKey: .commitTarget)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        
        // Handle completed_at date with improved parsing
        if let completedAtString = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = Self.parseDate(completedAtString)
        } else {
            completedAt = nil
        }
        
        analytics = try container.decodeIfPresent(RecipientAnalytics.self, forKey: .analytics)
        ownerName = try container.decodeIfPresent(String.self, forKey: .ownerName)
        ownerPhone = try container.decodeIfPresent(String.self, forKey: .ownerPhone)
        ownerTimezone = try container.decodeIfPresent(String.self, forKey: .ownerTimezone)
        
        // Handle owner last active date with improved parsing
        if let ownerLastActiveString = try container.decodeIfPresent(String.self, forKey: .ownerLastActive) {
            ownerLastActive = Self.parseDate(ownerLastActiveString)
            // Debug log to verify parsing
            if ownerLastActive == nil {
                print("⚠️ [RecipientAnalytics] Failed to parse ownerLastActive: \(ownerLastActiveString)")
            }
        } else {
            ownerLastActive = nil
        }
        
        weeklyProgress = try container.decodeIfPresent(WeeklyProgress.self, forKey: .weeklyProgress)
    }
}

// MARK: - Convenience Extensions
extension RecipientAnalytics {
    var formattedTotalEarned: String {
        return String(format: "%.2f", totalEarned)
    }
    
    var formattedPendingEarnings: String {
        return String(format: "%.2f", pendingEarnings)
    }
    
    var formattedSuccessRate: String {
        if totalRequiredDays == 0 {
            return "—"
        }
        return String(format: "%.1f%%", successRate)
    }
    
    var completionRatio: String {
        if totalRequiredDays == 0 {
            return "—"
        }
        return "\(totalCompletions)/\(totalRequiredDays)"
    }
}

extension RecipientSummaryStats {
    var formattedTotalEarned: String {
        return String(format: "%.2f", totalEarnedAllTime)
    }
    
    var formattedPendingEarnings: String {
        return String(format: "%.2f", totalPendingAllHabits)
    }
    
    var formattedSuccessRate: String {
        // Check if there's any data to calculate success rate
        if totalCompletionsAllHabits == 0 && totalFailuresAllHabits == 0 {
            return "—"
        }
        return String(format: "%.1f%%", overallSuccessRate)
    }
} 