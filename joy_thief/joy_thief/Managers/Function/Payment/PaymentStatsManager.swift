import Foundation
import Combine
import UIKit

// MARK: - Payment Stats Models
struct PaymentStats: Codable {
    let weeklyPayments: Double
    let monthlyPayments: Double
    let totalPayments: Double
    let dailyPayments: [Double]
    let weekDays: [String]
    let unpaidPenalties: Double
    let processingPayments: Double
    let paymentHistory: [PaymentHistoryItem]
    
    enum CodingKeys: String, CodingKey {
        case weeklyPayments = "weekly_payments"
        case monthlyPayments = "monthly_payments"
        case totalPayments = "total_payments"
        case dailyPayments = "daily_payments"
        case weekDays = "week_days"
        case unpaidPenalties = "unpaid_penalties"
        case processingPayments = "processing_payments"
        case paymentHistory = "payment_history"
    }
}

struct PaymentHistoryItem: Codable, Identifiable {
    let id: String
    let amount: Double
    let date: String
    let isPaid: Bool
    let paymentStatus: String
    let reason: String
    
    enum CodingKeys: String, CodingKey {
        case id, amount, date, reason
        case isPaid = "is_paid"
        case paymentStatus = "payment_status"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(String.self, forKey: .date)
        isPaid = try container.decode(Bool.self, forKey: .isPaid)
        paymentStatus = try container.decode(String.self, forKey: .paymentStatus)
        
        // Handle nullable reason field
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Missed habit"
    }
}

// MARK: - Payment Stats Manager
@MainActor
class PaymentStatsManager: ObservableObject {
    static let shared = PaymentStatsManager()
    
    @Published var paymentStats: PaymentStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let urlSession = URLSession.shared
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private var isInitialLoadComplete = false
    private var lastFetchTime: Date?
    private let minimumRefreshInterval: TimeInterval = 60 // 1 minute minimum between fetches
    
    private init() {
        // Listen for authentication state changes
        NotificationCenter.default.publisher(for: .authenticationStateChanged)
            .sink { [weak self] _ in
                self?.handleAuthenticationChange()
            }
            .store(in: &cancellables)
        
        // Listen for app foreground events
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    func startPeriodicUpdates() {
        stopPeriodicUpdates()
        
        // Update every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPaymentStats()
            }
        }
    }
    
    func stopPeriodicUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func handleAuthenticationChange() {
        if AuthenticationManager.shared.isAuthenticated {
            // User logged in - start loading data
            refreshPaymentStats()
            startPeriodicUpdates()
        } else {
            // User logged out - stop updates and clear data
            stopPeriodicUpdates()
            paymentStats = nil
            errorMessage = nil
        }
    }
    
    private func handleAppWillEnterForeground() {
        // Refresh data when app comes to foreground
        if AuthenticationManager.shared.isAuthenticated {
            refreshPaymentStats()
        }
    }
    
    func fetchPaymentStats(token: String) async {
        // Prevent duplicate calls within minimum interval
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minimumRefreshInterval {
            print("🔄 [PaymentStats] Skipping fetch - too soon since last fetch")
            return
        }
        
        isLoading = true
        errorMessage = nil
        lastFetchTime = Date()
        
        print("🔍 [PaymentStats] Fetching payment stats...")
        
        guard let url = URL(string: "\(AppConfig.baseURL)/sync/payment-stats") else {
            print("❌ [PaymentStats] Invalid URL: \(AppConfig.baseURL)/sync/payment-stats")
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔍 [PaymentStats] Making request to: \(url)")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [PaymentStats] Invalid response type")
                errorMessage = "Invalid response"
                isLoading = false
                return
            }
            
            print("🔍 [PaymentStats] Response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ [PaymentStats] Failed with status \(httpResponse.statusCode): \(responseBody)")
                errorMessage = "Failed to fetch payment stats: \(httpResponse.statusCode)"
                isLoading = false
                return
            }
            
            // Log response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📊 [PaymentStats] Response data: \(responseString.prefix(500))...")
            }
            
            let stats = try JSONDecoder().decode(PaymentStats.self, from: data)
            
            print("✅ [PaymentStats] Successfully decoded stats:")
            print("   Total payments: $\(stats.totalPayments)")
            print("   Payment history items: \(stats.paymentHistory.count)")
            print("   Unpaid penalties: $\(stats.unpaidPenalties)")
            
            paymentStats = stats
            isLoading = false
            isInitialLoadComplete = true
            
        } catch {
            print("❌ [PaymentStats] Error: \(error)")
            if let decodingError = error as? DecodingError {
                print("❌ [PaymentStats] Decoding error details: \(decodingError)")
            }
            errorMessage = "Error fetching payment stats: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func refreshPaymentStats() {
        // Check if data already exists from PreloadManager
        if paymentStats != nil && !isInitialLoadComplete {
            print("📊 [PaymentStats] Already have payment stats from PreloadManager")
            isInitialLoadComplete = true
            return
        }
        
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        Task {
            await fetchPaymentStats(token: token)
        }
    }
    
    // MARK: - Auto-initialization
    func initializeIfAuthenticated() {
        guard AuthenticationManager.shared.isAuthenticated else { return }
        
        // Only refresh if we don't have data already
        if paymentStats == nil {
            refreshPaymentStats()
        }
        startPeriodicUpdates()
    }
    
    // Computed properties for easy access
    var weeklyPayments: Double {
        paymentStats?.weeklyPayments ?? 0.0
    }
    
    var monthlyPayments: Double {
        paymentStats?.monthlyPayments ?? 0.0
    }
    
    var totalPayments: Double {
        paymentStats?.totalPayments ?? 0.0
    }
    
    var dailyPayments: [Double] {
        paymentStats?.dailyPayments ?? Array(repeating: 0.0, count: 7)
    }
    
    var weekDays: [String] {
        paymentStats?.weekDays ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }
    
    var unpaidPenalties: Double {
        paymentStats?.unpaidPenalties ?? 0.0
    }
    
    var processingPayments: Double {
        paymentStats?.processingPayments ?? 0.0
    }
    
    var paymentHistory: [PaymentHistoryItem] {
        paymentStats?.paymentHistory ?? []
    }
    
    // Helper to get total amount saved (what user didn't have to pay)
    var totalSaved: Double {
        // This would be calculated based on completed habits vs potential penalties
        // For now, return 0 as we'd need habit completion data
        return 0.0
    }
    
    deinit {
        // Timer cleanup happens automatically when the object is deallocated
        refreshTimer?.invalidate()
    }
} 