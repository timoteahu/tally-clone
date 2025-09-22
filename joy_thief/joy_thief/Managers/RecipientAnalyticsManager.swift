import Foundation

@MainActor
class RecipientAnalyticsManager: ObservableObject {
    static let shared = RecipientAnalyticsManager()
    
    // Separated habit lists
    @Published var activeHabits: [HabitWithAnalytics] = []
    @Published var inactiveHabits: [HabitWithAnalytics] = []
    @Published var summaryStats: RecipientSummaryStats?
    @Published var errorMessage: String?
    
    // Legacy property for compatibility (will be removed later)
    var recipientHabits: [HabitWithAnalytics] {
        activeHabits + inactiveHabits
    }
    
    // Section-specific loading states
    @Published var isLoadingActiveHabits = false
    @Published var isLoadingInactiveHabits = false
    @Published var isLoadingSummary = false
    
    // Combined loading state
    @Published var isLoading = false
    
    // Manual refresh state
    @Published var isManuallyRefreshing = false
    
    // Track if sections have been loaded at least once
    @Published var hasLoadedActiveHabits = false
    @Published var hasLoadedInactiveHabits = false
    
    // Cache manager
    private let cacheManager = RecipientCacheManager.shared
    
    // Individual loading states (for compatibility)
    @Published var isLoadingHabits = false {
        didSet { updateCombinedLoadingState() }
    }
    @Published var isLoadingStats = false {
        didSet { updateCombinedLoadingState() }
    }
    
    private func updateCombinedLoadingState() {
        isLoading = isLoadingHabits || isLoadingStats || isLoadingActiveHabits || isLoadingInactiveHabits || isLoadingSummary
    }
    
    @MainActor
    private func checkAndClearManualRefresh() {
        if isManuallyRefreshing && manualRefreshHabitsComplete && manualRefreshStatsComplete {
            isManuallyRefreshing = false
            isLoadingSummary = false
            manualRefreshHabitsComplete = false
            manualRefreshStatsComplete = false
            print("✅ [RecipientAnalytics] Manual refresh complete, clearing skeleton")
        }
    }
    
    // MARK: - Configuration
    private let requestTimeout: TimeInterval = 30.0
    
    // MARK: - Task Management
    private var habitsFetchTask: Task<Void, Never>?
    private var summaryFetchTask: Task<Void, Never>?
    private var isRefreshing = false
    
    // Track manual refresh completion
    private var manualRefreshHabitsComplete = false
    private var manualRefreshStatsComplete = false
    
    private init() {}
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
    
    // MARK: - API Methods
    
    /// Fetch habits where the current user is the recipient with analytics data
    func fetchRecipientHabits() async {
        await fetchRecipientHabits(forceRefresh: false)
    }
    
    /// Fetch habits where the current user is the recipient with analytics data
    func fetchRecipientHabits(forceRefresh: Bool = false, includeInactive: Bool = true, isManualRefresh: Bool = false) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            await updateErrorState("Authentication required")
            return
        }
        
        // Always include inactive habits now (for two-section display)
        let shouldIncludeInactive = true
        
        // Load from cache first if not forcing refresh
        if !forceRefresh {
            if let cache = await cacheManager.getCachedData() {
                await MainActor.run {
                    self.activeHabits = cache.activeHabits
                    self.inactiveHabits = cache.inactiveHabits
                    self.summaryStats = cache.summaryStats
                    self.hasLoadedActiveHabits = true
                    self.hasLoadedInactiveHabits = true
                    self.errorMessage = nil
                }
                
                print("📱 [RecipientAnalytics] Loaded from cache: \(cache.activeHabits.count) active, \(cache.inactiveHabits.count) inactive")
                
                // Check if cache needs refresh
                if await cacheManager.needsRefresh() {
                    print("🔄 [RecipientAnalytics] Cache is stale, refreshing in background...")
                    // Continue to fetch fresh data below
                } else {
                    // Cache is fresh, no need to fetch
                    return
                }
            }
        }
        
        // Cancel any existing fetch task
        habitsFetchTask?.cancel()
        
        // Create new fetch task
        habitsFetchTask = Task {
            // Show loading if we don't have cached data OR if it's a manual refresh
            let showLoading = activeHabits.isEmpty && inactiveHabits.isEmpty || isManualRefresh
            
            await MainActor.run {
                if showLoading {
                    self.isLoadingActiveHabits = true
                    self.isLoadingInactiveHabits = true
                }
                self.isLoadingHabits = true
            }
            
            do {
                let allHabits = try await fetchRecipientHabitsFromAPI(token: token, includeInactive: shouldIncludeInactive)
                
                // Check if task was cancelled
                if Task.isCancelled { 
                    await MainActor.run {
                        self.isLoadingHabits = false
                        self.isLoadingActiveHabits = false
                        self.isLoadingInactiveHabits = false
                        
                        // Mark habits as complete even on early cancellation
                        if isManualRefresh {
                            self.manualRefreshHabitsComplete = true
                            self.checkAndClearManualRefresh()
                        }
                    }
                    return 
                }
                
                // Separate active and inactive habits
                let active = allHabits.filter { $0.isActive ?? true }
                // For previous habits, show inactive habits that had meaningful activity
                let inactive = allHabits.filter { habit in
                    let isInactive = !(habit.isActive ?? true)
                    let hasCompletions = (habit.analytics?.totalCompletions ?? 0) > 0
                    let hasFailures = (habit.analytics?.totalFailures ?? 0) > 0
                    let hasEarnings = (habit.analytics?.totalEarned ?? 0) > 0 || 
                                     (habit.analytics?.pendingEarnings ?? 0) > 0
                    let hasRequiredDays = (habit.analytics?.totalRequiredDays ?? 0) > 0
                    
                    // Show inactive habits that have any of: completions, failures, earnings, or required days
                    return isInactive && (hasCompletions || hasFailures || hasEarnings || hasRequiredDays)
                }
                
                await MainActor.run {
                    self.activeHabits = active
                    self.inactiveHabits = inactive
                    self.hasLoadedActiveHabits = true
                    self.hasLoadedInactiveHabits = true
                    self.errorMessage = nil
                    self.isLoadingHabits = false
                    self.isLoadingActiveHabits = false
                    self.isLoadingInactiveHabits = false
                    
                    // Mark habits as complete for manual refresh
                    if isManualRefresh {
                        self.manualRefreshHabitsComplete = true
                        self.checkAndClearManualRefresh()
                    }
                }
                
                // Update cache
                await cacheManager.cacheData(
                    activeHabits: active,
                    inactiveHabits: inactive,
                    summaryStats: self.summaryStats
                )
                
                print("✅ [RecipientAnalytics] Fetched \(active.count) active, \(inactive.count) inactive habits")
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled { return }
                
                // Ignore cancellation errors
                if (error as NSError).code == NSURLErrorCancelled {
                    print("ℹ️ [RecipientAnalytics] Habit fetch was cancelled")
                    await MainActor.run {
                        self.isLoadingHabits = false
                        self.isLoadingActiveHabits = false
                        self.isLoadingInactiveHabits = false
                        
                        // Mark habits as complete even on cancellation
                        if isManualRefresh {
                            self.manualRefreshHabitsComplete = true
                            self.checkAndClearManualRefresh()
                        }
                    }
                    return
                }
                
                print("❌ [RecipientAnalytics] Error fetching recipient habits: \(error)")
                await MainActor.run {
                    self.isLoadingHabits = false
                    self.isLoadingActiveHabits = false
                    self.isLoadingInactiveHabits = false
                    
                    // Mark habits as complete even on error
                    if isManualRefresh {
                        self.manualRefreshHabitsComplete = true
                        self.checkAndClearManualRefresh()
                    }
                }
                await updateErrorState(error.localizedDescription)
            }
        }
    }
    
    /// Fetch recipient summary statistics
    func fetchSummaryStats(forceRefresh: Bool = false) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            await updateErrorState("Authentication required")
            return
        }
        
        // Return cached data if available and not forcing refresh
        if !forceRefresh && summaryStats != nil {
            return
        }
        
        // Cancel any existing fetch task
        summaryFetchTask?.cancel()
        
        // Create new fetch task
        summaryFetchTask = Task {
            await MainActor.run {
                self.isLoadingStats = true
            }
            
            do {
                let response = try await fetchSummaryStatsFromAPI(token: token)
                
                // Check if task was cancelled
                if Task.isCancelled { 
                    await MainActor.run {
                        self.isLoadingStats = false
                        
                        // Mark stats as complete even on early cancellation
                        if self.isManuallyRefreshing {
                            self.manualRefreshStatsComplete = true
                            self.checkAndClearManualRefresh()
                        }
                    }
                    return 
                }
                
                await MainActor.run {
                    self.summaryStats = response.summary
                    self.errorMessage = nil
                    self.isLoadingStats = false
                    
                    // Mark stats as complete for manual refresh
                    if self.isManuallyRefreshing {
                        self.manualRefreshStatsComplete = true
                        self.checkAndClearManualRefresh()
                    }
                }
                
                print("✅ [RecipientAnalytics] Fetched summary stats")
                
            } catch {
                // Check if task was cancelled
                if Task.isCancelled { return }
                
                // Ignore cancellation errors
                if (error as NSError).code == NSURLErrorCancelled {
                    print("ℹ️ [RecipientAnalytics] Summary stats fetch was cancelled")
                    await MainActor.run {
                        self.isLoadingStats = false
                        
                        // Mark stats as complete even on cancellation
                        if self.isManuallyRefreshing {
                            self.manualRefreshStatsComplete = true
                            self.checkAndClearManualRefresh()
                        }
                    }
                    return
                }
                
                print("❌ [RecipientAnalytics] Error fetching summary stats: \(error)")
                await MainActor.run {
                    self.isLoadingStats = false
                    
                    // Mark stats as complete even on error
                    if self.isManuallyRefreshing {
                        self.manualRefreshStatsComplete = true
                        self.checkAndClearManualRefresh()
                    }
                }
                await updateErrorState(error.localizedDescription)
            }
        }
    }
    
    /// Refresh all data
    func refreshAllData(includeInactive: Bool = true) async {
        // Prevent duplicate refreshes
        guard !isRefreshing else {
            print("ℹ️ [RecipientAnalytics] Refresh already in progress, skipping")
            return
        }
        
        isRefreshing = true
        
        // Set manual refresh state to show skeletons
        await MainActor.run {
            self.isManuallyRefreshing = true
            self.isLoadingActiveHabits = true
            self.isLoadingInactiveHabits = true
            self.isLoadingSummary = true
            self.manualRefreshHabitsComplete = false
            self.manualRefreshStatsComplete = false
        }
        
        // Small delay to ensure UI updates with skeleton view
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Always include inactive habits for two-section display
        // Fetch both data types concurrently
        async let habitsTask: () = fetchRecipientHabits(forceRefresh: true, includeInactive: true, isManualRefresh: true)
        async let statsTask: () = fetchSummaryStats(forceRefresh: true)
        
        // Wait for both to complete
        _ = await (habitsTask, statsTask)
        
        isRefreshing = false
        
        // Update cache with fresh data
        await cacheManager.cacheData(
            activeHabits: self.activeHabits,
            inactiveHabits: self.inactiveHabits,
            summaryStats: self.summaryStats
        )
        
        // Clear manual refresh state only after data is loaded
        // This will be handled in the individual fetch functions
    }
    
    /// Clear cached data
    func clearCache() {
        activeHabits = []
        inactiveHabits = []
        summaryStats = nil
        errorMessage = nil
    }
    
    /// Cancel all ongoing tasks
    func cancelAllTasks() {
        habitsFetchTask?.cancel()
        summaryFetchTask?.cancel()
        habitsFetchTask = nil
        summaryFetchTask = nil
        isRefreshing = false
        isLoadingHabits = false
        isLoadingStats = false
        print("ℹ️ [RecipientAnalytics] Cancelled all ongoing tasks")
    }
    
    // MARK: - Private API Methods
    
    private func fetchRecipientHabitsFromAPI(token: String, includeInactive: Bool = false) async throws -> [HabitWithAnalytics] {
        var urlComponents = URLComponents(string: "\(AppConfig.baseURL)/habits/recipient")
        urlComponents?.queryItems = [URLQueryItem(name: "include_inactive", value: String(includeInactive))]
        
        guard let url = urlComponents?.url else {
            throw RecipientAnalyticsError.invalidURL
        }
        
        let request = createRequest(url: url, token: token)
        
        print("🔄 [RecipientAnalytics] Fetching recipient habits from: \(url)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        try validateResponse(response)
        
        // Debug: Log raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🔍 [RecipientAnalytics] Raw API response (first 500 chars):")
            print(String(jsonString.prefix(500)))
        }
        
        let habits = try JSONDecoder().decode([HabitWithAnalytics].self, from: data)
        
        return habits
    }
    
    private func fetchSummaryStatsFromAPI(token: String) async throws -> RecipientSummaryResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/habits/recipient/summary") else {
            throw RecipientAnalyticsError.invalidURL
        }
        
        let request = createRequest(url: url, token: token)
        
        print("🔄 [RecipientAnalytics] Fetching summary stats from: \(url)")
        
        let (data, response) = try await urlSession.data(for: request)
        
        try validateResponse(response)
        
        let summaryResponse = try JSONDecoder().decode(RecipientSummaryResponse.self, from: data)
        
        return summaryResponse
    }
    
    // MARK: - Helper Methods
    
    private func createRequest(url: URL, method: String = "GET", token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecipientAnalyticsError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            switch httpResponse.statusCode {
            case 401:
                throw RecipientAnalyticsError.authenticationFailed
            case 403:
                throw RecipientAnalyticsError.forbidden
            case 404:
                throw RecipientAnalyticsError.notFound
            case 500...599:
                throw RecipientAnalyticsError.serverError
            default:
                throw RecipientAnalyticsError.networkError
            }
        }
    }
    
    private func updateErrorState(_ error: String) async {
        await MainActor.run {
            self.errorMessage = error
        }
    }
    
    /// Fetch only inactive habits without affecting the main loading states
    func fetchInactiveHabitsOnly() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            await updateErrorState("Authentication required")
            return
        }
        
        // Don't show any loading state for the full page
        await MainActor.run {
            self.isLoadingInactiveHabits = true
        }
        
        do {
            let allHabits = try await fetchRecipientHabitsFromAPI(token: token, includeInactive: true)
            
            // Filter for inactive habits with meaningful activity
            let inactive = allHabits.filter { habit in
                let isInactive = !(habit.isActive ?? true)
                let hasCompletions = (habit.analytics?.totalCompletions ?? 0) > 0
                let hasFailures = (habit.analytics?.totalFailures ?? 0) > 0
                let hasEarnings = (habit.analytics?.totalEarned ?? 0) > 0 || 
                                 (habit.analytics?.pendingEarnings ?? 0) > 0
                let hasRequiredDays = (habit.analytics?.totalRequiredDays ?? 0) > 0
                
                // Show inactive habits that have any of: completions, failures, earnings, or required days
                return isInactive && (hasCompletions || hasFailures || hasEarnings || hasRequiredDays)
            }
            
            await MainActor.run {
                self.inactiveHabits = inactive
                self.hasLoadedInactiveHabits = true
                self.isLoadingInactiveHabits = false
            }
            
            // Update cache with new inactive habits
            await cacheManager.cacheData(
                activeHabits: self.activeHabits,
                inactiveHabits: inactive,
                summaryStats: self.summaryStats
            )
            
            print("✅ [RecipientAnalytics] Fetched \(inactive.count) inactive habits")
            
        } catch {
            print("❌ [RecipientAnalytics] Error fetching inactive habits: \(error)")
            await MainActor.run {
                self.isLoadingInactiveHabits = false
            }
        }
    }
}

// MARK: - Error Types

enum RecipientAnalyticsError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed
    case forbidden
    case notFound
    case serverError
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationFailed:
            return "Authentication failed"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .serverError:
            return "Server error occurred"
        case .networkError:
            return "Network error occurred"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - Convenience Extensions

extension RecipientAnalyticsManager {
    /// Check if we have any recipient habits (active or inactive)
    var hasRecipientHabits: Bool {
        !activeHabits.isEmpty || !inactiveHabits.isEmpty
    }
    
    /// Check if we have active habits
    var hasActiveHabits: Bool {
        !activeHabits.isEmpty
    }
    
    /// Check if we have inactive habits
    var hasInactiveHabits: Bool {
        !inactiveHabits.isEmpty
    }
    
    /// Get total earnings across all habits
    var totalEarningsAcrossAllHabits: Double {
        recipientHabits.compactMap { $0.analytics?.totalEarned }.reduce(0, +)
    }
    
    /// Get total pending earnings across all habits
    var totalPendingEarningsAcrossAllHabits: Double {
        recipientHabits.compactMap { $0.analytics?.pendingEarnings }.reduce(0, +)
    }
    
    /// Get this week's earnings across all habits
    /// Note: This is currently showing pending earnings as a proxy for "this week"
    /// since we don't have detailed transaction history from the API
    var totalEarningsThisWeek: Double {
        // For now, we'll use pending earnings as "this week" earnings
        // In a full implementation, this would filter transactions by date
        totalPendingEarningsAcrossAllHabits
    }
    
    /// Get formatted total earnings string
    var formattedTotalEarnings: String {
        String(format: "%.2f", totalEarningsAcrossAllHabits)
    }
    
    /// Get formatted total pending earnings string
    var formattedTotalPendingEarnings: String {
        String(format: "%.2f", totalPendingEarningsAcrossAllHabits)
    }
    
    /// Get formatted this week's earnings string
    var formattedEarningsThisWeek: String {
        String(format: "%.2f", totalEarningsThisWeek)
    }
} 