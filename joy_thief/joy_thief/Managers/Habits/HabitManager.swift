import Foundation
import UIKit

@MainActor
class HabitManager: ObservableObject {
    static let shared = HabitManager()
    
    @Published var habits: [Habit] = []
    @Published var habitsbydate: [Int: [Habit]] = [:]
    @Published var weeklyHabits: [Habit] = []  // Track weekly habits separately
    @Published var weeklyProgressData: [String: PreloadManager.WeeklyProgressData] = [:]  // Track weekly progress from server
    @Published var weeklyProgressSummary: [String: (current: Int, target: Int, percentage: Double)] = [:]  // Enhanced caching for quick access
    @Published var verifiedHabitsToday: [String: Bool] = [:]
    @Published var weeklyVerifiedHabits: [String: [String: Bool]] = [:] // [date: [habitId: isVerified]]
    @Published var habitVerifications: [String: [HabitVerification]] = [:] // [habitId: [verifications]]
    // Removed in-memory image storage to reduce memory usage - images are loaded from disk on demand
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var todayCommitCounts: [String:Int] = [:]
    @Published var weeklyCommitCounts: [String:Int] = [:]
    @Published var todayLeetCodeCounts: [String:Int] = [:]
    @Published var weeklyLeetCodeCounts: [String:Int] = [:]
    @Published var todayGamingHours: [String:Double] = [:]
    // Refresh GitHub commit counts periodically (every 10 min)
    private var commitCountTimer: Timer?
    // Refresh LeetCode counts periodically (every 10 min)
    private var leetCodeCountTimer: Timer?
    // Refresh gaming hours periodically (every 30 min)
    private var gamingHoursTimer: Timer?
    
    // MARK: - Configuration
    private let requestTimeout: TimeInterval = 30.0
    private var imageLoadingTasks: [String: Task<Void, Never>] = [:]
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    // MARK: - NEW: Weekly Progress Consistency Tracking
    private var lastWeeklyProgressCheck: Date?
    private var currentWeekStartDate: Date?
    private let weeklyProgressCheckInterval: TimeInterval = 60 * 60 // Check hourly for new weeks
    
    // MARK: - NEW: Persistent tracking key for week start
    private static let persistedWeekStartKey = "habit_manager_current_week_start"
    
    // Helper ISO formatter for storing dates in UserDefaults
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }()
    
    // MARK: - Shared utilities
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    // Separate URLSession for image downloads with more aggressive settings
    private lazy var imageUrlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0  // Shorter timeout for images
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // Always fetch fresh
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false  // Don't wait for connectivity
        config.allowsCellularAccess = true
        config.httpShouldUsePipelining = false  // Disable pipelining for better compatibility
        return URLSession(configuration: config)
    }()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    private init() {
        // 🆕 Load the last saved week-start so we don't mistakenly treat the
        // first launch of every session as a brand-new week.
        if let saved = UserDefaults.standard.string(forKey: Self.persistedWeekStartKey),
           let savedDate = isoDateFormatter.date(from: saved) {
            // Store as start-of-day to match calendar comparisons
            self.currentWeekStartDate = Calendar.current.startOfDay(for: savedDate)
        }
        loadPersistedImages()
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Response Models
    
    /// Enhanced response model for habit creation that includes updated friends data
    struct HabitCreateResponse: Codable {
        let habit: Habit
        let updatedFriendsWithStripe: [PreloadManager.FriendWithStripeData]?
        let friendsDataChanged: Bool
        
        enum CodingKeys: String, CodingKey {
            case habit
            case updatedFriendsWithStripe = "updated_friends_with_stripe"
            case friendsDataChanged = "friends_data_changed"
        }
    }
    
    // MARK: - Network Request Helpers
    
    private func createRequest(url: URL, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    private func handleNetworkResponse<T: Codable>(_ data: Data, _ response: URLResponse, expecting: T.Type) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HabitError.networkError
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            // Debug log the error response
            if let errorString = String(data: data, encoding: .utf8) {
                print("Error response (\(httpResponse.statusCode)): \(errorString)")
            }
            
            // Try to parse detailed error message from server
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                
                // Check for specific error types to provide better user guidance
                if detail.contains("Invalid habit type") {
                    throw HabitError.invalidHabitType(detail)
                } else if detail.contains("Invalid alarm_time format") {
                    throw HabitError.invalidAlarmTime(detail)
                } else if detail.contains("Invalid custom habit type") {
                    throw HabitError.invalidCustomHabitType(detail)
                } else {
                    throw HabitError.serverError(detail)
                }
            } else {
                // Try to decode as ErrorResponse for backwards compatibility
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    throw HabitError.serverError(errorResponse.detail)
                } else {
                    throw HabitError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
        }
    }
    
    private func updateLoadingState(_ loading: Bool, error: String? = nil) {
        Task { @MainActor in
            self.isLoading = loading
            self.errorMessage = error
        }
    }
    
    // MARK: - Habit Management
    
    func fetchHabits(userId: String, token: String, preserveRecentlyAdded: Bool = false) async throws {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/user/\(userId)") else {
            updateLoadingState(false, error: "Invalid URL")
            throw HabitError.networkError
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            let habits = try handleNetworkResponse(data, response, expecting: [Habit].self)
            
            await MainActor.run {
                // Store recently added habits (added in last 5 seconds) to preserve them
                let recentCutoff = Date().addingTimeInterval(-5)
                var recentlyAddedHabits: [Habit] = []
                
                if preserveRecentlyAdded {
                    // Check for habits that exist locally but not in server response
                    for localHabit in self.habits {
                        if !habits.contains(where: { $0.id == localHabit.id }) {
                            // This habit exists locally but not on server - might be recently added
                            if let createdDate = ISO8601DateFormatter().date(from: localHabit.createdAt),
                               createdDate > recentCutoff {
                                print("🔄 [HabitManager] Preserving recently added habit: \(localHabit.name)")
                                recentlyAddedHabits.append(localHabit)
                            }
                        }
                    }
                }
                
                // Replace habits array with server data
                self.habits = habits
                
                // Re-add recently added habits that weren't in server response
                for recentHabit in recentlyAddedHabits {
                    if !self.habits.contains(where: { $0.id == recentHabit.id }) {
                        self.habits.append(recentHabit)
                    }
                }
                
                // Rebuild the organized collections
                self.habitsbydate = [:]
                self.weeklyHabits = []
                
                for habit in self.habits {
                    if habit.isDailyHabit {
                        for weekday in habit.weekdays {
                            if self.habitsbydate[weekday] == nil {
                                self.habitsbydate[weekday] = []
                            }
                            self.habitsbydate[weekday]?.append(habit)
                        }
                    } else if habit.isWeeklyHabit {
                        self.weeklyHabits.append(habit)
                    }
                    if habit.habitType == "github_commits", let c = habit.todayCommitCount {
                        self.todayCommitCounts[habit.id] = c
                    }
                }
            }
            // Fetch GitHub counts
            if let token = AuthenticationManager.shared.storedAuthToken {
                Task { await self.refreshTodayCommitCounts(token: token) }
                Task { await self.refreshWeeklyCommitCounts(token: token) }
            }
            // Fetch LeetCode counts
            if let token = AuthenticationManager.shared.storedAuthToken {
                Task { await self.refreshTodayLeetCodeCounts(token: token) }
                Task { await self.refreshWeeklyLeetCodeCounts(token: token) }
            }
            // Fetch gaming hours
            if let token = AuthenticationManager.shared.storedAuthToken {
                Task { await self.refreshTodayGamingHours(token: token) }
            }
            // REMOVED: fetchVerifiedHabitsToday call - verification data now comes from cache via PreloadManager
            // try await fetchVerifiedHabitsToday(userId: userId, token: token)
            
            // REMOVED: preloadAllVerificationImages call - this is now handled in background after cache loading
            // await preloadAllVerificationImages()
            
            updateLoadingState(false)
        } catch {
            updateLoadingState(false, error: "Failed to fetch habits: \(error.localizedDescription)")
            throw error
        }
    }
    
    func createHabit(
        name: String,
        recipientId: String?,
        habitType: String,
        weekdays: [Int],
        penaltyAmount: Float,
        userId: String,
        token: String,
        isPrivate: Bool,
        alarmTime: String?,
        customHabitTypeId: String?,
        scheduleType: String,
        weeklyTarget: Int?,
        weekStartDay: Int,
        commitTarget: Int?,
        dailyLimitHours: Double?,
        hourlyPenaltyRate: Double?,
        healthTargetValue: Double?,
        healthTargetUnit: String?,
        healthDataType: String?,
        isZeroPenalty: Bool = false
    ) async throws {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/") else {
            throw HabitError.networkError
        }
        
        var request = createRequest(url: url, method: "POST", token: token)
        
        var habitData: [String: Any] = [
            "name": name.isEmpty ? "Habit" : name,
            "habit_type": habitType,
            "penalty_amount": penaltyAmount,
            "user_id": userId,
            "private": isPrivate,
            "recipient_id": recipientId ?? NSNull(),
            "habit_schedule_type": scheduleType,
            "week_start_day": weekStartDay,
            "is_zero_penalty": isZeroPenalty
        ]
        
        // Add schedule-specific fields
        if scheduleType == "daily" {
            habitData["weekdays"] = weekdays
        } else if scheduleType == "weekly" {
            habitData["weekly_target"] = weeklyTarget ?? 1
            // For weekly habits, don't include weekdays field at all
            // (backend validation expects this field to be absent, not null)
        }
        
        if let alarmTime = alarmTime {
            habitData["alarm_time"] = alarmTime
        }
        
        if let customHabitTypeId = customHabitTypeId {
            habitData["custom_habit_type_id"] = customHabitTypeId
        }
        
        // Add GitHub and LeetCode habit fields
        if habitType == "github_commits" || habitType == "leetcode" {
            // Set commit_target based on schedule type
            if scheduleType == "daily" {
                habitData["commit_target"] = commitTarget ?? 1
            } else if scheduleType == "weekly" {
                // For weekly habits, backend expects commit_target to contain the weekly goal
                habitData["commit_target"] = weeklyTarget ?? 1
            }
        }
        
        // Add gaming habit fields
        if habitType == "league_of_legends" || habitType == "valorant" {
            habitData["daily_limit_hours"] = dailyLimitHours ?? 2.0
            habitData["hourly_penalty_rate"] = hourlyPenaltyRate ?? 5.0
            habitData["games_tracked"] = [habitType == "league_of_legends" ? "lol" : "valorant"]
        }
        
        // Add health habit fields
        if habitType.hasPrefix("health_") {
            if let healthTargetValue = healthTargetValue {
                habitData["health_target_value"] = healthTargetValue
            }
            if let healthTargetUnit = healthTargetUnit {
                habitData["health_target_unit"] = healthTargetUnit
            }
            if let healthDataType = healthDataType {
                habitData["health_data_type"] = healthDataType
            }
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: habitData)
        request.httpBody = jsonData
        
        // Debug logging
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("Creating habit with data: \(jsonString)")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            let createResponse = try handleNetworkResponse(data, response, expecting: HabitCreateResponse.self)
            
            let newHabit = createResponse.habit
            
            await MainActor.run {
                self.habits.append(newHabit)
                
                // Organize habits by schedule type
                if newHabit.isDailyHabit {
                    for weekday in newHabit.weekdays {
                        if self.habitsbydate[weekday] == nil {
                            self.habitsbydate[weekday] = []
                        }
                        self.habitsbydate[weekday]?.append(newHabit)
                    }
                } else if newHabit.isWeeklyHabit {
                    self.weeklyHabits.append(newHabit)
                }
                
                // Add new habit to cache immediately
                DataCacheManager.shared.updateHabitsCache(with: newHabit)
                
                // Update zero-penalty count cache if this is a picture habit
                if let isZeroPenalty = newHabit.isZeroPenalty {
                    let pictureHabitTypes = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
                    let isPictureHabit = pictureHabitTypes.contains(newHabit.habitType) || newHabit.habitType.hasPrefix("custom_")
                    if isPictureHabit && (isZeroPenalty || newHabit.penaltyAmount == 0.0) {
                        DataCacheManager.shared.updateZeroPenaltyCountAfterHabitChange()
                    }
                }
            }
            
            // Update friends with Stripe if needed (outside MainActor.run)
            if createResponse.friendsDataChanged, let updatedFriendsWithStripe = createResponse.updatedFriendsWithStripe {
                print("✅ [HabitManager] Friends with Stripe data changed, updating cache and triggering sync")
                
                // Update friends cache immediately
                await DataCacheManager.shared.updateFriendsWithStripeCache(updatedFriendsWithStripe)
                
                // Update FriendsManager with the new data
                let friendsManager = FriendsManager.shared
                await MainActor.run {
                    // Convert to Friend objects for the FriendsManager
                    let updatedFriends = updatedFriendsWithStripe.map { friendData in
                        Friend(
                            id: friendData.id,
                            friendId: friendData.id,
                            name: friendData.name,
                            phoneNumber: friendData.phoneNumber
                        )
                    }
                    
                    friendsManager.preloadedFriendsWithStripeConnect = updatedFriends
                    print("✅ [HabitManager] Updated FriendsManager with \(updatedFriends.count) friends with Stripe Connect")
                }
                
                // Perform background sync to ensure data consistency
                if let token = AuthenticationManager.shared.storedAuthToken {
                    await DataCacheManager.shared.performBackgroundSync(token: token)
                    print("✅ [HabitManager] Background sync triggered after habit creation")
                }
            }
            
            // For GitHub and LeetCode habits, trigger an immediate data refresh
            // This ensures the weekly progress data is fetched right after creation
            if newHabit.habitType == "github_commits" || newHabit.habitType == "leetcode" {
                print("🔄 [HabitManager] Triggering data refresh for \(newHabit.habitType) habit")
                
                // Store the newly created habit ID to preserve it during refresh
                let newHabitId = newHabit.id
                
                Task.detached(priority: .userInitiated) {
                    // Small delay to ensure server has processed the new habit
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Force refresh to get the latest weekly progress data
                    _ = await DataCacheManager.shared.forceRefresh(token: token)
                    
                    // Ensure the new habit is still in our local array after refresh
                    await MainActor.run {
                        // Check if the habit was removed during refresh (race condition)
                        if !self.habits.contains(where: { $0.id == newHabitId }) {
                            print("⚠️ [HabitManager] New habit was lost during refresh, re-adding it")
                            self.habits.append(newHabit)
                            
                            // Re-organize habits by schedule type
                            if newHabit.isDailyHabit {
                                for weekday in newHabit.weekdays {
                                    if self.habitsbydate[weekday] == nil {
                                        self.habitsbydate[weekday] = []
                                    }
                                    if !self.habitsbydate[weekday]!.contains(where: { $0.id == newHabitId }) {
                                        self.habitsbydate[weekday]?.append(newHabit)
                                    }
                                }
                            } else if newHabit.isWeeklyHabit {
                                if !self.weeklyHabits.contains(where: { $0.id == newHabitId }) {
                                    self.weeklyHabits.append(newHabit)
                                }
                            }
                        }
                    }
                    
                    print("✅ [HabitManager] Data refresh completed for \(newHabit.habitType) habit")
                }
            }
            
            updateLoadingState(false)
        } catch {
            updateLoadingState(false, error: "Failed to create habit")
            throw error
        }
    }
    
    func updateHabit(habit: Habit, userId: String, token: String) async throws -> HabitUpdateResponse {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/\(habit.id)") else {
            updateLoadingState(false)
            throw HabitError.networkError
        }
        
        var request = createRequest(url: url, method: "PUT", token: token)
        
        var habitData: [String: Any] = [
            "name": habit.name,
            "habit_type": habit.habitType,
            "penalty_amount": habit.penaltyAmount,
            "user_id": userId,
            "private": habit.isPrivateHabit,
            "recipient_id": habit.recipientId ?? NSNull(),
            "habit_schedule_type": habit.habitScheduleType ?? "daily",
            "week_start_day": habit.weekStartDay ?? 0
        ]
        
        // Add schedule-specific fields
        if habit.isDailyHabit {
            habitData["weekdays"] = habit.weekdays
        } else if habit.isWeeklyHabit {
            habitData["weekly_target"] = habit.weeklyTarget ?? 1
            // For weekly habits, don't include weekdays field at all
            // (backend validation expects this field to be absent, not null)
        }
        
        if let alarmTime = habit.alarmTime {
            habitData["alarm_time"] = alarmTime
        }
        
        if let customHabitTypeId = habit.customHabitTypeId {
            habitData["custom_habit_type_id"] = customHabitTypeId
        }
        
        // Add GitHub habit fields
        if habit.habitType == "github_commits" {
            // Only set commit_target for daily habits
            if habit.habitScheduleType == "daily" {
                habitData["commit_target"] = habit.commitTarget ?? 1
            }
            // For weekly habits, the target is in weekly_target field, not commit_target
        }
        
        // Add gaming habit fields
        if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
            habitData["daily_limit_hours"] = habit.dailyLimitHours ?? 2.0
            habitData["hourly_penalty_rate"] = habit.hourlyPenaltyRate ?? 5.0
            if let gamesTracked = habit.gamesTracked {
                habitData["games_tracked"] = gamesTracked
            }
        }
        
        // Add health habit fields
        if habit.habitType.hasPrefix("health_") {
            if let healthTargetValue = habit.healthTargetValue {
                habitData["health_target_value"] = healthTargetValue
            }
            if let healthTargetUnit = habit.healthTargetUnit {
                habitData["health_target_unit"] = healthTargetUnit
            }
            if let healthDataType = habit.healthDataType {
                habitData["health_data_type"] = healthDataType
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: habitData)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            let updateResponse = try handleNetworkResponse(data, response, expecting: HabitUpdateResponse.self)
            
            // Note: We don't update the local habits array immediately since changes take effect tomorrow
            // The habit will be updated in the next sync after the staging period
            
            updateLoadingState(false)
            return updateResponse
        } catch {
            updateLoadingState(false, error: "Failed to update habit")
            throw error
        }
    }
    
    func deleteHabit(habitId: String, userId: String, token: String) async throws -> HabitDeleteResponse {
        updateLoadingState(true)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/\(habitId)") else {
            updateLoadingState(false)
            throw HabitError.networkError
        }
        
        let request = createRequest(url: url, method: "DELETE", token: token)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw HabitError.serverError("Failed to delete habit")
            }
            
            let deleteResponse = try handleNetworkResponse(data, response, expecting: HabitDeleteResponse.self)
            
            // Check if this is an immediate deletion
            if deleteResponse.deletionTiming == "immediate" {
                // Remove habit from local arrays immediately
                await MainActor.run {
                    self.habits.removeAll { $0.id == habitId }
                    
                    // Remove from weekday arrays
                    for (weekday, habits) in self.habitsbydate {
                        self.habitsbydate[weekday] = habits.filter { $0.id != habitId }
                    }
                    
                    // Remove from weekly habits
                    self.weeklyHabits.removeAll { $0.id == habitId }
                    
                    // Remove from verification data
                    self.verifiedHabitsToday.removeValue(forKey: habitId)
                    self.habitVerifications.removeValue(forKey: habitId)
                    self.weeklyProgressData.removeValue(forKey: habitId)
                    
                    // Remove from gaming hours tracking
                    self.todayGamingHours.removeValue(forKey: habitId)
                    
                    // Remove from commit counts tracking
                    self.todayCommitCounts.removeValue(forKey: habitId)
                    self.weeklyCommitCounts.removeValue(forKey: habitId)
                    
                    // Remove from LeetCode counts tracking
                    self.todayLeetCodeCounts.removeValue(forKey: habitId)
                    self.weeklyLeetCodeCounts.removeValue(forKey: habitId)
                }
                
                // Update cache to reflect immediate deletion
                DataCacheManager.shared.updateStagedDeletionStatus(for: habitId, deleted: true)
                
                // Remove habit from persistent cache to prevent it from reappearing on app restart
                DataCacheManager.shared.removeHabitFromCache(habitId: habitId)
            } else {
                // Update cache with staged deletion info
                let stagedDeletionInfo = StagedDeletionInfo(
                    scheduledForDeletion: true,
                    effectiveDate: deleteResponse.effectiveDate,
                    userTimezone: deleteResponse.timezone,
                    stagingId: "pending", // We don't have the actual staging ID from this response
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                
                // Update cache to show this habit is scheduled for deletion
                var currentStagedDeletions = DataCacheManager.shared.getCachedStagedDeletions()
                currentStagedDeletions[habitId] = stagedDeletionInfo
                DataCacheManager.shared.cacheStagedDeletions(currentStagedDeletions)
            }
            
            updateLoadingState(false)
            return deleteResponse
        } catch {
            updateLoadingState(false)
            throw error
        }
    }
    
    // MARK: - Verification Data Management
    
    func fetchVerifiedHabitsToday(userId: String, token: String) async throws {
        try await fetchVerifiedHabitsForDate(Date(), userId: userId, token: token)
        
        // Preload images for all verified habits today
        preloadTodaysVerificationImages()
    }
    
    // Preload all verification images for today's verified habits
    private func preloadTodaysVerificationImages() {
        Task.detached(priority: .background) {
            for habitId in await self.verifiedHabitsToday.keys where await self.verifiedHabitsToday[habitId] == true {
                await self.preloadVerificationImage(for: habitId)
            }
        }
    }
    
    func fetchVerifiedHabitsForDate(_ date: Date, userId: String, token: String) async throws {
        let dateString = dateFormatter.string(from: date)
        
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/get/\(dateString)?user_id=\(userId)") else {
            throw HabitError.networkError
        }
        
        let request = createRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return // No data for this date
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            await processVerificationData(json, for: dateString)
        }
    }
    
    func fetchWeeklyVerificationData(userId: String, token: String) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/get-week?user_id=\(userId)") else {
            throw HabitError.networkError
        }
        
        let request = createRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        let weeklyResponse = try handleNetworkResponse(data, response, expecting: WeeklyVerificationResponse.self)
        
        var allVerificationsWithImages: [HabitVerification] = []
        
        await MainActor.run {
            var merged = self.weeklyVerifiedHabits // keep existing data
            
            for (dateString, verifications) in weeklyResponse.verificationsByDate {
                var verifiedDict: [String: Bool] = [:]
                var verificationsToStore: [String: [HabitVerification]] = [:]
                
                for verification in verifications {
                    let habitId = verification.habitId
                    verifiedDict[habitId] = true
                    
                    if verificationsToStore[habitId] == nil {
                        verificationsToStore[habitId] = []
                    }
                    verificationsToStore[habitId]?.append(verification)
                    
                    // Track verifications with images for downloading
                    if verification.imageUrl != nil || verification.selfieImageUrl != nil {
                        allVerificationsWithImages.append(verification)
                    }
                }
                
                merged[dateString] = (merged[dateString] ?? [:]).merging(verifiedDict) { _, new in new }
                
                for (habitId, verifications) in verificationsToStore {
                    if self.habitVerifications[habitId] == nil {
                        self.habitVerifications[habitId] = []
                    }
                    self.habitVerifications[habitId]?.append(contentsOf: verifications)
                }
            }
            
            // Commit merged result
            self.weeklyVerifiedHabits = merged
            
            let todayString = self.dateFormatter.string(from: Date())
            if let todaysData = self.weeklyVerifiedHabits[todayString] {
                self.verifiedHabitsToday = todaysData
            }
        }
        
        // Download images for all verifications with images (in background)
        await withTaskGroup(of: Void.self) { group in
            for verification in allVerificationsWithImages {
                // Download content image
                if let imageUrl = verification.imageUrl {
                    group.addTask {
                        await self.downloadImageFromUrl(verificationId: verification.id, imageUrl: imageUrl)
                    }
                }
                
                // Download selfie image
                if let selfieImageUrl = verification.selfieImageUrl {
                    group.addTask {
                        let selfieVerificationId = "\(verification.id)_selfie"
                        await self.downloadImageFromUrl(verificationId: selfieVerificationId, imageUrl: selfieImageUrl)
                    }
                }
            }
        }
    }
    
    private func processVerificationData(_ json: [[String: Any]], for dateString: String) async {
        var verifiedDict: [String: Bool] = [:]
        var verificationsToStore: [String: [HabitVerification]] = [:]
        var verificationsWithImages: [HabitVerification] = []
        
        for item in json {
            if let habitId = item["habit_id"] as? String {
                verifiedDict[habitId] = true
                
                // Debug logging for LeetCode habits
                if let habit = self.habits.first(where: { $0.id == habitId }), habit.habitType == "leetcode" {
                    print("⚠️ [HabitManager] Found verification data for LeetCode habit '\(habit.name)' (id: \(habitId)) on date \(dateString)")
                    print("   - Verification data: \(item)")
                }
                
                if let verificationData = try? JSONSerialization.data(withJSONObject: item),
                   let verification = try? JSONDecoder().decode(HabitVerification.self, from: verificationData) {
                    if verificationsToStore[habitId] == nil {
                        verificationsToStore[habitId] = []
                    }
                    verificationsToStore[habitId]?.append(verification)
                    
                    // Track verifications with images for downloading
                    if verification.imageUrl != nil || verification.selfieImageUrl != nil {
                        verificationsWithImages.append(verification)
                    }
                }
            }
        }
        
        await MainActor.run {
            // 🔄 Merge new verification dict with any existing entries for the date instead of overwriting,
            // so we never lose previously-known verifications when the backend returns a partial list.
            let existingForDate = self.weeklyVerifiedHabits[dateString] ?? [:]
            self.weeklyVerifiedHabits[dateString] = existingForDate.merging(verifiedDict) { _, new in new }

            // Update today's map similarly (used by shouldShowVerificationImages & UI badges)
            let today = self.dateFormatter.string(from: Date())
            if dateString == today {
                self.verifiedHabitsToday = self.verifiedHabitsToday.merging(verifiedDict) { _, new in new }
            }

            // Append or create verification arrays without discarding earlier cached entries.
            for (habitId, verifications) in verificationsToStore {
                if self.habitVerifications[habitId] == nil {
                    self.habitVerifications[habitId] = []
                }
                self.habitVerifications[habitId]?.append(contentsOf: verifications)
            }
        }
        
        // Download images for all verifications with images (in background)
        await withTaskGroup(of: Void.self) { group in
            for verification in verificationsWithImages {
                // Download content image
                if let imageUrl = verification.imageUrl {
                    group.addTask {
                        await self.downloadImageFromUrl(verificationId: verification.id, imageUrl: imageUrl)
                    }
                }
                
                // Download selfie image
                if let selfieImageUrl = verification.selfieImageUrl {
                    group.addTask {
                        let selfieVerificationId = "\(verification.id)_selfie"
                        await self.downloadImageFromUrl(verificationId: selfieVerificationId, imageUrl: selfieImageUrl)
                    }
                }
            }
        }
    }
    
    func markHabitAsVerified(habitId: String, verificationData: HabitVerification? = nil) {
        Task { @MainActor in
            self.verifiedHabitsToday[habitId] = true
            
            if let verification = verificationData {
                if self.habitVerifications[habitId] == nil {
                    self.habitVerifications[habitId] = []
                }
                self.habitVerifications[habitId]?.append(verification)
                
                // ENHANCED: Download and cache both images immediately with high priority
                if let imageUrl = verification.imageUrl, !imageUrl.isEmpty {
                    // Load the content image with high priority and cache it immediately
                    Task.detached(priority: .userInitiated) {
                        await self.downloadImageFromUrl(verificationId: verification.id, imageUrl: imageUrl)
                        
                        // Images are now loaded from disk on demand - no longer storing in memory
                    }
                }
                
                // Download selfie image if available using the direct selfie URL
                if let selfieImageUrl = verification.selfieImageUrl, !selfieImageUrl.isEmpty {
                    // Create a selfie-specific verification ID for caching
                    let selfieVerificationId = "\(verification.id)_selfie"
                    
                    Task.detached(priority: .userInitiated) {
                        await self.downloadImageFromUrl(verificationId: selfieVerificationId, imageUrl: selfieImageUrl)
                        
                        // Selfie images are now loaded from disk on demand - no longer storing in memory
                    }
                }
                
                // NEW: Create and cache feed post if this verification creates a post
                self.createAndCacheFeedPostIfNeeded(for: verification)
            }
            
            let todayString = self.dateFormatter.string(from: Date())
            if self.weeklyVerifiedHabits[todayString] == nil {
                self.weeklyVerifiedHabits[todayString] = [:]
            }
            self.weeklyVerifiedHabits[todayString]?[habitId] = true
            
            // NEW: Check if this is a weekly habit and update progress immediately
            if let habit = self.habits.first(where: { $0.id == habitId }), habit.isWeeklyHabit {
                // NEW: Track user interaction with weekly habit verification
                DataCacheManager.shared.trackUserInteraction()
                
                // Update weekly progress data in memory for immediate frontend update
                if let currentProgress = self.weeklyProgressData[habit.id] {
                    let newCompletions = currentProgress.currentCompletions + 1
                    let isComplete = newCompletions >= currentProgress.targetCompletions
                    
                    let updatedProgress = PreloadManager.WeeklyProgressData(
                        habitId: currentProgress.habitId,
                        currentCompletions: newCompletions,
                        targetCompletions: currentProgress.targetCompletions,
                        isWeekComplete: isComplete,
                        weekStartDate: currentProgress.weekStartDate,
                        weekEndDate: currentProgress.weekEndDate,
                        dataTimestamp: nil // Local update, no server timestamp
                    )
                    
                    self.weeklyProgressData[habit.id] = updatedProgress
                    
                    print("🎯 [HabitManager] Updated weekly progress in memory for habit '\(habit.id)': \(newCompletions)/\(currentProgress.targetCompletions), complete: \(isComplete)")
                }
                
                // Update cache with comprehensive weekly habit verification data
                DataCacheManager.shared.updateCacheForWeeklyHabitVerification(habitId: habit.id, verificationData: verificationData)
                
                print("📸 [HabitManager] Weekly habit '\(habit.id)' verified and cached with images")
            } else {
                // For daily habits, use comprehensive daily habit cache update
                DataCacheManager.shared.updateCacheForDailyHabitVerification(habitId: habitId, verificationData: verificationData)
                
                print("📸 [HabitManager] Daily habit '\(habitId)' verified and cached with images")
            }
        }
    }
    
    // MARK: - Image Management
    
    func fetchVerificationImage(verificationId: String, imageUrl: String? = nil) async {
        // Check if already on disk
        if loadImageFromDisk(verificationId: verificationId) != nil {
            return
        }
        
        let taskKey = "verification_\(verificationId)"
        if imageLoadingTasks[taskKey] != nil {
            return
        }
        
        // Check disk cache first (on background queue to avoid blocking)
        if loadImageFromDisk(verificationId: verificationId) != nil {
            // Image is already on disk, no need to store in memory
            return
        }
        
        // Create loading task to get signed URL from backend and download image
        let task = Task.detached(priority: .utility) {
            defer { 
                Task { @MainActor in
                    self.imageLoadingTasks.removeValue(forKey: taskKey)
                }
            }
            
            // First, get the signed URL from our backend
            guard let signedUrlResponse = await self.getSignedUrlForVerification(verificationId: verificationId) else {
                return
            }
            
            guard let url = URL(string: signedUrlResponse) else { 
                return 
            }
            
            // Now download the image using the signed URL
            for attempt in 1...2 {  // Reduced attempts since we have fresh signed URL
                do {
                    // Use dedicated image session
                    let (data, response) = try await self.imageUrlSession.data(from: url)
                    
                    // Validate response
                    if let httpResponse = response as? HTTPURLResponse {
                        guard httpResponse.statusCode == 200 else {
                            throw URLError(.badServerResponse)
                        }
                    }
                    
                    // Validate data
                    guard data.count > 0 else {
                        throw URLError(.zeroByteResource)
                    }
                    
                    // Save to disk on background queue
                    await Task.detached(priority: .utility) {
                        await self.saveImageToDisk(verificationId: verificationId, imageData: data)
                    }.value
                    
                    await MainActor.run {
                        // Image saved to disk, no need to store in memory
                    }
                    
                    return // Success, exit retry loop
                    
                } catch {
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
        
        await MainActor.run {
            self.imageLoadingTasks[taskKey] = task
        }
        
        await task.value
    }
    
    // Simple method to download image directly from URL (for when URL is already provided)
    func downloadImageFromUrl(verificationId: String, imageUrl: String) async {
        // Check if already on disk
        if loadImageFromDisk(verificationId: verificationId) != nil {
            return
        }
        
        let taskKey = "verification_\(verificationId)"
        if imageLoadingTasks[taskKey] != nil {
            return
        }
        
        guard let url = URL(string: imageUrl) else {
            return
        }
        
        // Check disk cache first
        let persistedData = await Task.detached(priority: .utility) {
            return await self.loadImageFromDisk(verificationId: verificationId)
        }.value
        
        if persistedData != nil {
            // Image is already persisted to disk, no need to store in memory
            return
        }
        
        // Download the image
        let task = Task.detached(priority: .utility) {
            defer { 
                Task { @MainActor in
                    self.imageLoadingTasks.removeValue(forKey: taskKey)
                }
            }
            
            do {
                let (data, response) = try await self.imageUrlSession.data(from: url)
                
                // Validate response
                if let httpResponse = response as? HTTPURLResponse {
                    guard httpResponse.statusCode == 200 else {
                        return
                    }
                }
                
                // Validate data
                guard data.count > 0 else {
                    return
                }
                
                // Save to disk
                await Task.detached(priority: .utility) {
                    await self.saveImageToDisk(verificationId: verificationId, imageData: data)
                }.value
                
            } catch {
                // Handle error silently
            }
        }
        
        await MainActor.run {
            self.imageLoadingTasks[taskKey] = task
        }
        
        _ = await task.value
    }
    
    // New method to get signed URL from backend
    private func getSignedUrlForVerification(verificationId: String) async -> String? {
        guard let url = URL(string: "\(AppConfig.baseURL)/habit-verification/image/\(verificationId)") else {
            return nil
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let imageUrl = json["image_url"] as? String {
                return imageUrl
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    func getVerificationImage(for habitId: String) -> Data? {
        let today = dateFormatter.string(from: Date())
        
        guard let verifications = habitVerifications[habitId] else { return nil }
        
        let todaysVerification = verifications.first { verification in
            let verificationDate = String(verification.verifiedAt.prefix(10))
            // Check if this is today's verification and if it has an image URL
            return verificationDate == today && verification.imageUrl != nil
        }
        
        guard let verification = todaysVerification else { return nil }
        
        // Check if we already have the image on disk
        if let existingImage = loadImageFromDisk(verificationId: verification.id) {
            return existingImage
        }
        
        // If verification has imageUrl, download it
        if let imageUrl = verification.imageUrl, !imageUrl.isEmpty {
            Task {
                await downloadImageFromUrl(verificationId: verification.id, imageUrl: imageUrl)
            }
        }
        
        return nil
    }
    
    // Efficient method that only returns cached images without triggering network calls
    func getCachedVerificationImage(for habitId: String) -> Data? {
        // For weekly habits, show images if verified today OR if completed this week and has verification today
        let habit = habits.first(where: { $0.id == habitId })
        let isWeeklyHabit = habit?.isWeeklyHabit ?? false
        
        // Check verification status - for weekly habits, show image if verified today even if completed
        let isVerifiedToday = verifiedHabitsToday[habitId] == true
        let isWeeklyCompleted = isWeeklyHabit ? isWeeklyHabitCompleted(for: habit!) : false
        
        // Show images if:
        // 1. Daily habit that's verified today
        // 2. Weekly habit that's verified today (regardless of completion status)
        // 3. Weekly habit that's completed but was verified today
        let shouldShowImage = isVerifiedToday || (isWeeklyHabit && isWeeklyCompleted && isVerifiedToday)
        
        guard shouldShowImage else { 
            return nil 
        }
        
        // Check for image on disk (stored with habitId as key)
        if let directImage = loadImageFromDisk(verificationId: habitId) {
            print("📸 [HabitManager] Found cached image on disk for habit '\(habitId)'")
            return directImage
        }
        
        // Finally, check verification-based caching
        guard let verifications = habitVerifications[habitId] else { 
            print("⚠️ [HabitManager] No verifications found for habit '\(habitId)'")
            return nil 
        }
        
        // Find today's verification for the image
        let today = dateFormatter.string(from: Date())
        let todaysVerification = verifications.first { verification in
            let verificationDate = String(verification.verifiedAt.prefix(10))
            return verificationDate == today
        }
        
        let verification = todaysVerification ?? (isWeeklyHabit ? verifications.first : nil)
        
        guard let verification = verification else { 
            print("⚠️ [HabitManager] No suitable verification found for habit '\(habitId)'")
            return nil 
        }
        
        // Return image from disk if available
        let cachedImage = loadImageFromDisk(verificationId: verification.id)
        print("📸 [HabitManager] Found verification-based image on disk for habit '\(habitId)': \(cachedImage != nil)")
        return cachedImage
    }
    
    func getCachedVerificationImages(for habitId: String) -> (selfie: Data?, content: Data?) {
        // For weekly habits, show images if verified today OR if completed this week and has verification today
        let habit = habits.first(where: { $0.id == habitId })
        let isWeeklyHabit = habit?.isWeeklyHabit ?? false
        
        // Check verification status - for weekly habits, show image if verified today even if completed
        let isVerifiedToday = verifiedHabitsToday[habitId] == true
        let isWeeklyCompleted = isWeeklyHabit ? isWeeklyHabitCompleted(for: habit!) : false
        
        // Show images if:
        // 1. Daily habit that's verified today
        // 2. Weekly habit that's verified today (regardless of completion status)
        // 3. Weekly habit that's completed but was verified today
        let shouldShowImages = isVerifiedToday || (isWeeklyHabit && isWeeklyCompleted && isVerifiedToday)
        
        guard shouldShowImages else { 
            return (nil, nil) 
        }
        
        // Check for images on disk (stored with habitId as key)
        let directSelfie = loadImageFromDisk(verificationId: "\(habitId)_selfie")
        let directContent = loadImageFromDisk(verificationId: habitId)
        
        if directSelfie != nil || directContent != nil {
            print("📸 [HabitManager] Found cached images on disk for habit '\(habitId)': selfie=\(directSelfie != nil), content=\(directContent != nil)")
            return (directSelfie, directContent)
        }
        
        // Finally, check verification-based caching
        guard let verifications = habitVerifications[habitId] else { 
            print("⚠️ [HabitManager] No verifications found for habit '\(habitId)'")
            return (nil, nil) 
        }
        
        // Find today's verification for the images
        let today = dateFormatter.string(from: Date())
        let todaysVerification = verifications.first { verification in
            let verificationDate = String(verification.verifiedAt.prefix(10))
            return verificationDate == today
        }
        
        guard let verification = todaysVerification else { 
            // For weekly habits, also check the most recent verification if no today verification
            if isWeeklyHabit, let latestVerification = verifications.first {
                let selfieImage = loadImageFromDisk(verificationId: "\(latestVerification.id)_selfie")
                let contentImage = loadImageFromDisk(verificationId: latestVerification.id)
                print("📸 [HabitManager] Using latest verification images for weekly habit '\(habitId)'")
                return (selfieImage, contentImage)
            }
            
            print("⚠️ [HabitManager] No today's verification found for habit '\(habitId)'")
            return (nil, nil) 
        }
        
        // Return images from disk if available
        let selfieImage = loadImageFromDisk(verificationId: "\(verification.id)_selfie")
        let contentImage = loadImageFromDisk(verificationId: verification.id)
        
        print("📸 [HabitManager] Found verification-based images for habit '\(habitId)': selfie=\(selfieImage != nil), content=\(contentImage != nil)")
        return (selfieImage, contentImage)
    }
    
    // Preload verification image for a habit (call this when verification status changes)
    func preloadVerificationImage(for habitId: String) async {
        let today = dateFormatter.string(from: Date())
        
        guard let verifications = habitVerifications[habitId] else { 
            return 
        }
        
        let todaysVerification = verifications.first { verification in
            let verificationDate = String(verification.verifiedAt.prefix(10))
            // Check if this is today's verification and if it has any image URLs
            return verificationDate == today && (verification.imageUrl != nil || verification.selfieImageUrl != nil)
        }
        
        guard let verification = todaysVerification else {
            return
        }
        
        // Download content image if available and not already cached
        if let imageUrl = verification.imageUrl,
           loadImageFromDisk(verificationId: verification.id) == nil,
           imageLoadingTasks["verification_\(verification.id)"] == nil {
            await downloadImageFromUrl(verificationId: verification.id, imageUrl: imageUrl)
        }
    }
    
    // Preload ALL verification images for ALL habits to eliminate swipe lag
    func preloadAllVerificationImages() async {
        // Use background priority to avoid blocking UI
        await Task.detached(priority: .background) {
            // Get all habit IDs that have verification data
            let allHabitIds = await Set(self.habitVerifications.keys)
            
            // Also get today's habits that might get verified
            let today = Calendar.current.component(.weekday, from: Date()) - 1 // Convert to 0-6 format
            let todaysHabitIds = await Set((self.habitsbydate[today] ?? []).map { $0.id })
            
            // Combine both sets to preload images for all relevant habits
            let habitIdsToPreload = allHabitIds.union(todaysHabitIds)
            
            // Preload images for all habits with verification data or today's habits
            await withTaskGroup(of: Void.self) { group in
                for habitId in habitIdsToPreload {
                    group.addTask {
                        await self.preloadVerificationImage(for: habitId)
                    }
                }
            }
        }.value
    }
    
    // MARK: - Persistent Storage
    
    private func saveImageToDisk(verificationId: String, imageData: Data) {
        let imageURL = documentsPath.appendingPathComponent("\(verificationId).jpg")
        try? imageData.write(to: imageURL)
    }
    
    private func loadImageFromDisk(verificationId: String) -> Data? {
        let imageURL = documentsPath.appendingPathComponent("\(verificationId).jpg")
        return try? Data(contentsOf: imageURL)
    }
    
    private func loadPersistedImages() {
        // Images are now loaded from disk on demand, not preloaded into memory
        // This function is kept for compatibility but no longer loads images into memory
    }
    
    // Force refresh all habits data
    func refreshHabits(preserveRecentlyAdded: Bool = true) async {
        guard let userId = AuthenticationManager.shared.currentUser?.id,
              let token = AuthenticationManager.shared.storedAuthToken else {
            print("⚠️ [HabitManager] User credentials not available for habits refresh")
            return
        }
        
        do {
            print("🔄 [HabitManager] Refreshing habits data")
            try await fetchHabits(userId: userId, token: token, preserveRecentlyAdded: preserveRecentlyAdded)
        } catch {
            print("⚠️ [HabitManager] Failed to refresh habits: \(error)")
        }
    }

    // Force refresh verification data for a specific habit or all habits
    func refreshVerificationData(for habitId: String) async {
        // Only refresh if cache is stale or invalid
        // This prevents unnecessary network calls when we have fresh cached data
        guard !DataCacheManager.shared.isCacheValid() else {
            print("📅 [HabitManager] Cache is fresh, skipping verification data refresh for '\(habitId)'")
            return
        }
        
        guard let userId = UserDefaults.standard.string(forKey: "user_id"),
              let token = UserDefaults.standard.string(forKey: "auth_token") else {
            return
        }
        
        do {
            if habitId == "all" {
                // Refresh all verification data
                print("🔄 [HabitManager] Refreshing all verification data due to app foreground")
                try await fetchVerifiedHabitsToday(userId: userId, token: token)
                try await fetchWeeklyVerificationData(userId: userId, token: token)
            } else {
                // Refresh specific habit data
                print("🔄 [HabitManager] Refreshing verification data for habit '\(habitId)'")
                try await fetchVerifiedHabitsToday(userId: userId, token: token)
            }
        } catch {
            print("⚠️ [HabitManager] Failed to refresh verification data: \(error)")
        }
    }
    
    // MARK: - Weekly Habit Progress Tracking
    
    /// Get the number of times a weekly habit has been verified this week
    func getWeeklyHabitProgress(for habitId: String) -> Int {
        // NEW: Track that user is accessing weekly progress data
        DataCacheManager.shared.trackUserInteraction()
        
        // Use real weekly progress data from server
        if let progressData = weeklyProgressData[habitId] {
            return progressData.currentCompletions
        }
        
        // Fallback to old calculation method if no progress data available
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        
        // Get the start of the current week (Sunday)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return 0
        }
        
        var verificationCount = 0
        
        // Check each day of the current week
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                continue
            }
            
            let dateString = formatter.string(from: date)
            let todayString = formatter.string(from: today)
            
            // Get verification data for this specific date
            var verifiedHabitsForDate = weeklyVerifiedHabits[dateString] ?? [:]
            
            // Fallback: If this is today and we have no data from server, use verifiedHabitsToday
            if dateString == todayString && verifiedHabitsForDate.isEmpty {
                verifiedHabitsForDate = verifiedHabitsToday
            }
            
            // Check if this habit was verified on this date
            if verifiedHabitsForDate[habitId] == true {
                verificationCount += 1
            }
        }
        
        return verificationCount
    }
    
    /// Check if a weekly habit has reached its target for this week
    func isWeeklyHabitCompleted(for habit: Habit) -> Bool {
        guard habit.isWeeklyHabit else {
            return false
        }
        
        // NEW: Track that user is checking weekly habit completion
        DataCacheManager.shared.trackUserInteraction()
        
        // Use real weekly progress data from server first
        if let progressData = weeklyProgressData[habit.id] {
            let isComplete = progressData.isWeekComplete || progressData.currentCompletions >= progressData.targetCompletions
            return isComplete
        }
        
        // Fallback to old calculation method
        guard let weeklyTarget = habit.weeklyTarget else {
            return false
        }
        
        let currentProgress = getWeeklyHabitProgress(for: habit.id)
        let isComplete = currentProgress >= weeklyTarget
        return isComplete
    }
    
    /// Get incomplete weekly habits (those that haven't reached their target yet)
    var incompleteWeeklyHabits: [Habit] {
        return weeklyHabits.filter { !isWeeklyHabitCompleted(for: $0) }
    }
    
    /// Get completed weekly habits (those that have reached their target this week)
    var completedHabitsThisWeek: [Habit] {
        return weeklyHabits.filter { isWeeklyHabitCompleted(for: $0) }
    }
    
    /// Calculate total penalties avoided this week from completed weekly habits
    var penaltiesAvoidedThisWeek: Double {
        var totalPenaltiesAvoided: Double = 0.0
        
        for habit in weeklyHabits {
            let currentProgress = getWeeklyHabitProgress(for: habit.id)
            let target = habit.weeklyTarget ?? 1
            
            // Calculate how many completions we've achieved vs target
            // Only count penalties avoided for actual completions, not over-completions
            let completionsAchieved = min(currentProgress, target)
            totalPenaltiesAvoided += Double(completionsAchieved) * Double(habit.penaltyAmount)
        }
        
        return totalPenaltiesAvoided
    }
    
    /// Determine if a habit should show verification images based on verification status and completion
    func shouldShowVerificationImages(for habitId: String) -> Bool {
        let habit = habits.first(where: { $0.id == habitId })
        let isWeeklyHabit = habit?.isWeeklyHabit ?? false
        
        // Check verification status
        let isVerifiedToday = verifiedHabitsToday[habitId] == true
        let isWeeklyCompleted = isWeeklyHabit ? isWeeklyHabitCompleted(for: habit!) : false
        
        // Show images if:
        // 1. Daily habit that's verified today
        // 2. Weekly habit that's verified today (regardless of completion status)
        // 3. Weekly habit that's completed this week (should still show verification images)
        return isVerifiedToday || (isWeeklyHabit && isWeeklyCompleted)
    }
    
    /// Check if verification images are available for a habit
    func hasVerificationImages(for habitId: String) -> Bool {
        let (selfie, content) = getCachedVerificationImages(for: habitId)
        return selfie != nil || content != nil
    }
    
    // MARK: - Feed Post Management
    
    private func createAndCacheFeedPostIfNeeded(for verification: HabitVerification) {
        // Check if this verification type creates feed posts (matches backend trigger logic)
        let postCreatingTypes = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
        let isCustomType = verification.verificationType.hasPrefix("custom_")
        // Only health habits with images (verification type "health") create posts, not health_* types
        let isHealthWithImages = verification.verificationType == "health"
        
        guard postCreatingTypes.contains(verification.verificationType) || isCustomType || isHealthWithImages else {
            print("🔍 [HabitManager] Verification type '\(verification.verificationType)' doesn't create feed posts, skipping")
            return
        }
        
        // Get the habit to check privacy setting
        guard let habit = habits.first(where: { $0.id == verification.habitId }) else {
            print("⚠️ [HabitManager] Habit not found for verification, skipping feed post creation")
            return
        }
        
        // Get current user information
        guard let userId = UserDefaults.standard.string(forKey: "user_id"),
              let userProfile = UserDefaults.standard.string(forKey: "user_name") else {
            print("⚠️ [HabitManager] User information not available, skipping feed post creation")
            return
        }
        
        // Attempt to pull current user's avatar data (fallback to profile photo URL)
        let currentUser = AuthenticationManager.shared.currentUser

        // Determine avatar URLs with graceful fallbacks so the new feed post always
        // carries *some* picture reference if the user has uploaded any photo at all.
        let finalAvatarUrl80      = currentUser?.avatarUrl80
        let finalAvatarUrl200     = currentUser?.avatarUrl200
        let finalAvatarUrlOriginal: String? = {
            // Prefer explicit original-size avatar, else fall back to 200, else profilePhotoUrl
            if let orig = currentUser?.avatarUrlOriginal, !orig.isEmpty { return orig }
            if let large = currentUser?.avatarUrl200,  !large.isEmpty { return large }
            if let profile = currentUser?.profilePhotoUrl, !profile.isEmpty { return profile }
            return nil
        }()

        // Generate unique post ID
        let postId = UUID().uuidString
        
        // Create the feed post data matching the backend structure
        let feedPostData = PreloadManager.FeedPostData(
            postId: postId,
            caption: "Habit verification completed",
            createdAt: verification.verifiedAt,
            isPrivate: habit.isPrivateHabit,
            imageUrl: verification.imageUrl, // Legacy field
            selfieImageUrl: verification.selfieImageUrl,
            contentImageUrl: verification.imageUrl, // Same as imageUrl for compatibility
            userId: userId,
            userName: userProfile,
            userAvatarUrl80: finalAvatarUrl80,
            userAvatarUrl200: finalAvatarUrl200,
            userAvatarUrlOriginal: finalAvatarUrlOriginal,
            userAvatarVersion: currentUser?.avatarVersion,
            streak: habit.streak,
            habitType: habit.habitType,
            habitName: habit.name,
            penaltyAmount: habit.penaltyAmount,
            comments: [], // New posts start with no comments
            habitId: verification.habitId
        )
        
        // Add the feed post to cache immediately
        DataCacheManager.shared.addFeedPostToCache(feedPostData)
        
        // Also update the FeedManager if it's available
        Task { @MainActor in
            // Convert to FeedPost format for FeedManager
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
            dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
            
            var createdAt: Date
            if let parsedDate = dateFormatter.date(from: verification.verifiedAt) {
                createdAt = parsedDate
            } else {
                // Fallback with simpler format
                let fallbackFormatter = DateFormatter()
                fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                fallbackFormatter.timeZone = TimeZone(abbreviation: "UTC")
                createdAt = fallbackFormatter.date(from: verification.verifiedAt) ?? Date()
            }
            
            // 🔧 ENHANCED: Better UUID handling with debug logging to prevent random UUID creation
            guard let postUUID = UUID(uuidString: postId) else {
                print("❌ [HabitManager] Failed to create UUID from postId '\(postId)', skipping feed post creation")
                return
            }
            
            guard let userUUID = UUID(uuidString: userId) else {
                print("❌ [HabitManager] Failed to create UUID from userId '\(userId)', skipping feed post creation")
                print("   - This indicates a data inconsistency. UserDefaults user_id should be a valid UUID string")
                return
            }
            
            print("🔧 [HabitManager] Creating feed post with userId '\(userId)' -> UUID '\(userUUID.uuidString)'")
            
            let feedPost = FeedPost(
                postId: postUUID,
                habitId: verification.habitId,
                caption: "Habit verification completed",
                createdAt: createdAt,
                isPrivate: habit.isPrivateHabit,
                imageUrl: verification.imageUrl,
                selfieImageUrl: verification.selfieImageUrl,
                contentImageUrl: verification.imageUrl,
                userId: userUUID,
                userName: userProfile,
                userAvatarUrl80: finalAvatarUrl80,
                userAvatarUrl200: finalAvatarUrl200,
                userAvatarUrlOriginal: finalAvatarUrlOriginal,
                userAvatarVersion: currentUser?.avatarVersion,
                streak: habit.currentStreak,
                habitType: habit.habitType,
                habitName: habit.name,
                penaltyAmount: habit.penaltyAmount,
                comments: []
            )
            
            // 🔧 CRITICAL FIX: Use proper insertOrUpdatePost method to ensure avatar caching works
            await FeedManager.shared.insertOrUpdatePost(feedPost)
            
            print("✅ [HabitManager] Created and cached feed post for verification '\(verification.id)' of habit '\(verification.habitId)'")
        }
    }
    
    // MARK: - NEW: Weekly Progress Management & Consistency Checks
    
    /// Check if we've entered a new week and refresh weekly progress data if needed
    func checkForNewWeekAndRefreshProgress(userId: String, token: String) async {
        let calendar = Calendar.current
        let today = Date()
        
        // Get the start of the current week (Sunday)
        guard let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return
        }
        
        let newWeekStart = currentWeekInterval.start
        
        // Check if this is a new week since our last check
        let isNewWeek = currentWeekStartDate == nil || 
                       !calendar.isDate(newWeekStart, equalTo: currentWeekStartDate!, toGranularity: .weekOfYear)
        
        // Also check if enough time has passed since last check
        let shouldCheckProgress = lastWeeklyProgressCheck == nil ||
                                Date().timeIntervalSince(lastWeeklyProgressCheck!) > weeklyProgressCheckInterval
        
        if isNewWeek || shouldCheckProgress {
            print("🔄 [HabitManager] \(isNewWeek ? "New week detected" : "Periodic check") - refreshing weekly progress")
            
            // Update our tracking variables
            currentWeekStartDate = newWeekStart
            // 🆕 Persist so next cold-start knows we have already seen this week
            UserDefaults.standard.set(isoDateFormatter.string(from: newWeekStart), forKey: Self.persistedWeekStartKey)
            lastWeeklyProgressCheck = Date()
            
            // Refresh weekly progress data from server
            await refreshWeeklyProgressData(userId: userId, token: token)
            
            if isNewWeek {
                print("🆕 [HabitManager] New week started: \(dateFormatter.string(from: newWeekStart))")
                
                // NEW: Only invalidate cache if user isn't actively using weekly progress
                let shouldInvalidate = !DataCacheManager.shared.shouldSkipSyncDueToUserActivity
                if shouldInvalidate {
                    DataCacheManager.shared.invalidateWeeklyProgressCache()
                    print("🗑️ [HabitManager] Invalidated weekly progress cache for new week")
                } else {
                    print("👤 [HabitManager] User is active - deferring cache invalidation for new week")
                    
                    // Schedule cache invalidation for later when user is not active
                    Task.detached(priority: .background) {
                        // Wait for user to finish interacting
                        try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000)) // 1 minute delay
                        
                        await MainActor.run {
                            if !DataCacheManager.shared.shouldSkipSyncDueToUserActivity {
                                DataCacheManager.shared.invalidateWeeklyProgressCache()
                                print("🗑️ [HabitManager] Deferred invalidation of weekly progress cache")
                            }
                        }
                    }
                }
                
                // Notify about the new week
                await MainActor.run {
                    // Clear today's verification status for weekly habits since it's a new week
                    for habit in weeklyHabits {
                        verifiedHabitsToday[habit.id] = false
                    }
                }
            }
        }
    }
    
    /// Refresh weekly progress data from server for consistency
    private func refreshWeeklyProgressData(userId: String, token: String) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/sync/delta") else {
            return
        }
        
        do {
            let request = createRequest(url: url, token: token)
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("⚠️ [HabitManager] Failed to fetch weekly progress delta")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let weeklyProgressArray = json["weekly_progress"] as? [[String: Any]] {
                
                await processWeeklyProgressUpdate(weeklyProgressArray)
                print("✅ [HabitManager] Refreshed weekly progress data from server")
            }
        } catch {
            print("⚠️ [HabitManager] Error refreshing weekly progress: \(error)")
        }
    }
    
    /// Process weekly progress data from server
    /// FIXED: Smart merging logic that preserves recent user interactions and validates data freshness
    /// This prevents resync from overwriting local progress that is ahead of server data
    private func processWeeklyProgressUpdate(_ progressArray: [[String: Any]]) async {
        var updatedProgressData: [String: PreloadManager.WeeklyProgressData] = [:]
        
        // NEW: Track if this is a potentially stale update
        let serverTimestamp = progressArray.first?["data_timestamp"] as? String
        for progressItem in progressArray {
            guard let habitId = progressItem["habit_id"] as? String,
                  let currentCompletions = progressItem["current_completions"] as? Int,
                  let targetCompletions = progressItem["target_completions"] as? Int,
                  let isWeekComplete = progressItem["is_week_complete"] as? Bool,
                  let weekStartDate = progressItem["week_start_date"] as? String else {
                continue
            }
            
            // Calculate week end date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let weekEndDate: String
            if let startDate = dateFormatter.date(from: weekStartDate) {
                let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
                weekEndDate = dateFormatter.string(from: endDate)
            } else {
                weekEndDate = weekStartDate
            }
            
            let serverProgressData = PreloadManager.WeeklyProgressData(
                habitId: habitId,
                currentCompletions: currentCompletions,
                targetCompletions: targetCompletions,
                isWeekComplete: isWeekComplete,
                weekStartDate: weekStartDate,
                weekEndDate: weekEndDate,
                dataTimestamp: serverTimestamp // Include server timestamp
            )
            
            updatedProgressData[habitId] = serverProgressData
        }
        
        await MainActor.run {
            // NEW: Smart merging logic that preserves recent user interactions
            var finalProgressData: [String: PreloadManager.WeeklyProgressData] = [:]
            
            // Start with existing data
            finalProgressData = self.weeklyProgressData
            
            // Apply server updates with validation
            for (habitId, serverData) in updatedProgressData {
                let existingData = self.weeklyProgressData[habitId]
                
                // NEW: Check if user recently interacted with this habit
                let hasRecentUserActivity = DataCacheManager.shared.shouldSkipSyncDueToUserActivity
                
                // NEW: Advanced merging logic
                if let existing = existingData {
                    // Case 1: User has recent activity - be conservative with server updates
                    if hasRecentUserActivity && existing.currentCompletions > serverData.currentCompletions {
                        print("👤 [HabitManager] Preserving local progress for habit '\(habitId)' due to recent user activity: local=\(existing.currentCompletions), server=\(serverData.currentCompletions)")
                        // Keep existing data, but update other fields like targets
                        finalProgressData[habitId] = PreloadManager.WeeklyProgressData(
                            habitId: existing.habitId,
                            currentCompletions: existing.currentCompletions, // Keep local progress
                            targetCompletions: serverData.targetCompletions, // Update target from server
                            isWeekComplete: existing.currentCompletions >= serverData.targetCompletions, // Recalculate completion
                            weekStartDate: serverData.weekStartDate,
                            weekEndDate: serverData.weekEndDate,
                            dataTimestamp: existing.dataTimestamp // Preserve local timestamp
                        )
                    }
                    // Case 2: Server data is more recent or user not active - use server data
                    else if serverData.currentCompletions >= existing.currentCompletions || !hasRecentUserActivity {
                        print("📊 [HabitManager] Updating progress for habit '\(habitId)' with server data: \(existing.currentCompletions) -> \(serverData.currentCompletions)")
                        finalProgressData[habitId] = serverData
                    }
                    // Case 3: Local data is newer - keep local but log the discrepancy
                    else {
                        print("⚠️ [HabitManager] Local progress ahead of server for habit '\(habitId)': local=\(existing.currentCompletions), server=\(serverData.currentCompletions), keeping local")
                        finalProgressData[habitId] = existing
                    }
                } else {
                    // No existing data - use server data
                    print("📊 [HabitManager] Adding new progress for habit '\(habitId)': \(serverData.currentCompletions)/\(serverData.targetCompletions)")
                    finalProgressData[habitId] = serverData
                }
            }
            
            // Apply the merged result
            self.weeklyProgressData = finalProgressData

            // NEW: Use safe update method that respects user activity
            DataCacheManager.shared.safeUpdateWeeklyProgressFromServer(Array(finalProgressData.values))

            print("🎯 [HabitManager] Smart merged weekly progress for \(updatedProgressData.count) habits (total now: \(finalProgressData.count))")
            
            // NEW: Debug logging for merge results
            for (habitId, data) in finalProgressData {
                print("   📊 \(habitId): \(data.currentCompletions)/\(data.targetCompletions) (complete: \(data.isWeekComplete))")
            }
        }
    }
    
    /// Check for app launch consistency - verify data is current and valid
    func performAppLaunchConsistencyCheck(userId: String, token: String) async {
        print("🔍 [HabitManager] Performing app launch consistency check")
        
        // Check if we need to refresh weekly progress due to time passage
        await checkForNewWeekAndRefreshProgress(userId: userId, token: token)
        
        // Verify verification data consistency
        await verifyVerificationDataConsistency(userId: userId, token: token)
        
        print("✅ [HabitManager] App launch consistency check completed")
    }
    
    /// Verify that verification data is consistent with server
    private func verifyVerificationDataConsistency(userId: String, token: String) async {
        // Only check if cache is older than 5 minutes to avoid excessive calls
        if DataCacheManager.shared.isCacheValid() {
            print("📅 [HabitManager] Cache is fresh, skipping verification consistency check")
            return
        }
        
        let today = Date()
        
        // Fetch today's verification data to ensure consistency
        do {
            try await fetchVerifiedHabitsForDate(today, userId: userId, token: token)
            
            // IMPORTANT: Also fetch weekly verification data for complete weekly habit context
            // This ensures that weekly habits that were verified today are properly processed
            // and their verification status is correctly reflected in the UI
            try await fetchWeeklyVerificationData(userId: userId, token: token)
            
            print("✅ [HabitManager] Verification data consistency check completed (both daily and weekly)")
        } catch {
            print("⚠️ [HabitManager] Failed verification consistency check: \(error)")
        }
    }
    
    /// Schedule periodic weekly progress checks (called from app lifecycle events)
    func schedulePeriodicWeeklyProgressCheck(userId: String, token: String) {
        // Use background task to avoid blocking UI
        Task.detached(priority: .background) {
            // Wait a bit to ensure app is fully loaded
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await self.checkForNewWeekAndRefreshProgress(userId: userId, token: token)
            
            // Schedule next check in an hour
            DispatchQueue.main.asyncAfter(deadline: .now() + self.weeklyProgressCheckInterval) {
                Task.detached(priority: .background) {
                    await self.checkForNewWeekAndRefreshProgress(userId: userId, token: token)
                }
            }
        }
    }
    
    /// Check if a habit is scheduled for deletion
    func checkStagedDeletion(habitId: String, token: String) async throws -> StagedDeletionInfo? {
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/\(habitId)/staged-deletion") else {
            throw HabitError.networkError
        }
        
        let request = createRequest(url: url, method: "GET", token: token)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HabitError.networkError
        }
        
        if httpResponse.statusCode == 200 {
            // Try to decode as StagedDeletionInfo directly
            let stagedDeletionInfo = try JSONDecoder().decode(StagedDeletionInfo.self, from: data)
            return stagedDeletionInfo.scheduledForDeletion ? stagedDeletionInfo : nil
        } else if httpResponse.statusCode == 404 {
            // No staged deletion found
            return nil
        } else {
            let errorData = try JSONDecoder().decode(ErrorResponse.self, from: data)
            throw HabitError.serverError(errorData.detail)
        }
    }
    
    /// Restore a habit that is scheduled for deletion
    func restoreHabit(habitId: String, token: String) async throws -> RestoreHabitResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/\(habitId)/restore") else {
            throw HabitError.networkError
        }
        
        let request = createRequest(url: url, method: "POST", token: token)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HabitError.networkError
        }
        
        if httpResponse.statusCode == 200 {
            let restoreResponse = try JSONDecoder().decode(RestoreHabitResponse.self, from: data)
            
            // Update cache immediately to reflect restoration
            DataCacheManager.shared.updateStagedDeletionStatus(for: habitId, deleted: true)
            
            return restoreResponse
        } else {
            let errorData = try JSONDecoder().decode(ErrorResponse.self, from: data)
            throw HabitError.serverError(errorData.detail)
        }
    }
    
    // MARK: - Verification Data Utilities

    /// Clear today's verification status so UI won't momentarily show stale "Completed" state while a fresh sync is running.
    /// This should be invoked right before a cache refresh / resync starts.
    @MainActor
    func resetTodaysVerificationData() {
        // Remove in-memory map for today
        verifiedHabitsToday = [:]

        // Also clear the entry for the current date inside weeklyVerifiedHabits to keep graphs in sync
        let todayString = dateFormatter.string(from: Date())
        weeklyVerifiedHabits[todayString] = [:]
    }
    
    // MARK: - Reset on Logout

    /// Clears all in-memory state so the next user sees a blank slate.
    @MainActor
    func resetForLogout() {
        habits                 = []
        weeklyHabits           = []
        habitsbydate           = [:]
        weeklyProgressData     = [:]
        verifiedHabitsToday    = [:]
        habitVerifications     = [:]
        weeklyVerifiedHabits   = [:]
        // verificationImages removed - images loaded from disk on demand
        imageLoadingTasks.forEach { $0.value.cancel() }
        imageLoadingTasks      = [:]
        print("🗑️ [HabitManager] In-memory caches cleared on logout")
    }

    // MARK: - GitHub Commit Counts
    func refreshTodayCommitCounts(token: String) async {
        // Check if we have any GitHub habits
        guard habits.contains(where: { $0.habitType == "github_commits" }) else { return }
        
        // Ensure we keep refreshing periodically
        await MainActor.run {
            self.ensureCommitCountTimer(token: token)
        }
        
        do {
            let count = try await GitHubService.fetchTodayCommitCount(token: token)
            
            await MainActor.run {
                for habit in habits where habit.habitType == "github_commits" {
                    todayCommitCounts[habit.id] = count
                    
                    // Update cache with new commit count
                    DataCacheManager.shared.updateHabitCommitCount(habitId: habit.id, count: count)
                }
            }
        } catch {
            print("❌ GitHub count fetch failed: \(error)")
        }
    }
    
    func refreshWeeklyCommitCounts(token: String) async {
        // Check if we have any weekly GitHub habits
        guard habits.contains(where: { $0.habitType == "github_commits" && $0.isWeeklyHabit }) else { return }
        
        do {
            // Get weekly habits and their week start days
            let weeklyGitHubHabits = habits.filter { $0.habitType == "github_commits" && $0.isWeeklyHabit }
            
            for habit in weeklyGitHubHabits {
                let weekStartDay = habit.weekStartDay ?? 0
                let response = try await GitHubService.fetchCurrentWeekCommitCount(token: token, weekStartDay: weekStartDay)
                
                await MainActor.run {
                    weeklyCommitCounts[habit.id] = response.currentCommits
                }
            }
        } catch {
            print("❌ Weekly GitHub count fetch failed: \(error)")
        }
    }
    
    func refreshTodayLeetCodeCounts(token: String) async {
        // Check if we have any LeetCode habits
        guard habits.contains(where: { $0.habitType == "leetcode" }) else { return }
        
        // Ensure we keep refreshing periodically
        await MainActor.run {
            self.ensureLeetCodeCountTimer(token: token)
        }
        
        do {
            // Fetch today's LeetCode problems solved
            let todayCount = try await LeetCodeService.fetchTodayProblemsSolved(token: token)
            
            await MainActor.run {
                // Update today's count for all daily LeetCode habits
                for habit in habits where habit.habitType == "leetcode" && !habit.isWeeklyHabit {
                    todayLeetCodeCounts[habit.id] = todayCount
                }
            }
        } catch {
            print("❌ LeetCode daily count fetch failed: \(error)")
        }
    }
    
    func refreshWeeklyLeetCodeCounts(token: String) async {
        // Check if we have any weekly LeetCode habits
        guard habits.contains(where: { $0.habitType == "leetcode" && $0.isWeeklyHabit }) else { return }
        
        do {
            // Get weekly habits and their week start days
            let weeklyLeetCodeHabits = habits.filter { $0.habitType == "leetcode" && $0.isWeeklyHabit }
            
            for habit in weeklyLeetCodeHabits {
                let weekStartDay = habit.weekStartDay ?? 0
                let response = try await LeetCodeService.fetchCurrentWeekProblemsSolved(token: token, weekStartDay: weekStartDay)
                
                await MainActor.run {
                    weeklyLeetCodeCounts[habit.id] = response.currentProblems
                    print("📊 [HabitManager] Updated weekly LeetCode count for habit '\(habit.name)': \(response.currentProblems)/\(response.weeklyGoal)")
                }
            }
        } catch {
            print("❌ Weekly LeetCode count fetch failed: \(error)")
            // Log more details about the error
            if let urlError = error as? URLError {
                print("   - URL Error code: \(urlError.code)")
                print("   - URL Error description: \(urlError.localizedDescription)")
            } else if let leetCodeError = error as? LeetCodeError {
                print("   - LeetCode Error: \(leetCodeError.localizedDescription)")
            }
        }
    }

    // MARK: - Gaming Hours
    func refreshTodayGamingHours(token: String) async {
        guard habits.contains(where: { $0.habitType == "league_of_legends" || $0.habitType == "valorant" }) else { return }
        
        // Ensure we keep refreshing periodically
        await MainActor.run {
            self.ensureGamingHoursTimer(token: token)
        }
        
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayString = formatter.string(from: today)
            
            // Fetch gaming hours for each gaming habit
            for habit in habits where habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                guard let url = URL(string: "\(AppConfig.baseURL)/gaming/habits/\(habit.id)/sessions?start_date=\(todayString)T00:00:00Z&end_date=\(todayString)T23:59:59Z") else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                struct GamingSession: Codable {
                    let id: String?
                    let habitId: String?
                    let matchId: String?
                    let gameStartTime: String?
                    let gameEndTime: String?
                    let durationMinutes: Int
                    let gameMode: String?
                    let createdAt: String?
                    
                    enum CodingKeys: String, CodingKey {
                        case id
                        case habitId = "habit_id"
                        case matchId = "match_id"
                        case gameStartTime = "game_start_time"
                        case gameEndTime = "game_end_time"
                        case durationMinutes = "duration_minutes"
                        case gameMode = "game_mode"
                        case createdAt = "created_at"
                    }
                }
                
                do {
                    let sessions = try JSONDecoder().decode([GamingSession].self, from: data)
                    let totalMinutes = sessions.reduce(0) { $0 + $1.durationMinutes }
                    let totalHours = Double(totalMinutes) / 60.0
                    
                    await MainActor.run {
                        self.todayGamingHours[habit.id] = totalHours
                        // Update cache with new gaming hours
                        DataCacheManager.shared.updateHabitGamingHours(habitId: habit.id, hours: totalHours)
                    }
                } catch {
                    print("❌ Failed to decode gaming sessions for habit \(habit.id): \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Raw response: \(jsonString)")
                    }
                    await MainActor.run {
                        self.todayGamingHours[habit.id] = 0
                        // Update cache with zero hours
                        DataCacheManager.shared.updateHabitGamingHours(habitId: habit.id, hours: 0)
                    }
                }
            }
        } catch {
            print("❌ Gaming hours fetch failed: \(error)")
        }
    }
    
    // MARK: - Private helpers
    @MainActor
    private func ensureCommitCountTimer(token: String) {
        guard commitCountTimer == nil else { return }
        
        commitCountTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.refreshTodayCommitCounts(token: token) }
            Task { await self.refreshWeeklyCommitCounts(token: token) }
        }
        
        // Fire timer immediately to get fresh data
        commitCountTimer?.fire()
    }
    
    @MainActor
    private func ensureLeetCodeCountTimer(token: String) {
        guard leetCodeCountTimer == nil else { return }
        
        leetCodeCountTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.refreshTodayLeetCodeCounts(token: token) }
            Task { await self.refreshWeeklyLeetCodeCounts(token: token) }
        }
        
        // Fire timer immediately to get fresh data
        leetCodeCountTimer?.fire()
    }
    
    @MainActor
    private func ensureGamingHoursTimer(token: String) {
        guard gamingHoursTimer == nil else { return }
        gamingHoursTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.refreshTodayGamingHours(token: token) }
        }
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received - clearing HabitManager caches")
        
        // Cancel all image loading tasks
        imageLoadingTasks.values.forEach { $0.cancel() }
        imageLoadingTasks.removeAll()
        
        // Note: We don't clear habitVerifications as it contains essential metadata
        // about habit verifications, not just images. Images are loaded from disk on demand.
        
        // Keep only essential data (habits list and verification metadata)
        print("🧹 HabitManager memory cleanup completed")
    }
    
    // MARK: - Zero-Penalty Habits
    
    // NOTE: Zero-penalty habit count is now handled via DataCacheManager.getZeroPenaltyHabitCount()
    // This eliminates the need for separate API calls and uses the existing cache system
    
    // MARK: - Helper Functions
}
