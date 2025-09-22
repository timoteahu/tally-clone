import Foundation
import SwiftUI

@MainActor
class FriendRecommendationsManager: ObservableObject {
    static let shared = FriendRecommendationsManager()
    
    @Published var recommendations: [FriendRecommendation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Remove caching - recommendations should always be fresh
    // @Published var lastUpdated: Date?
    // private let cacheValidityDuration: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - Configuration
    private let requestTimeout: TimeInterval = 15.0
    
    private init() {} // Singleton pattern
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    // MARK: - Public API
    
    /// Get friend recommendations - always fresh, no caching
    func getFriendRecommendations(token: String, limit: Int = 10, forceRefresh: Bool = false) async throws -> [FriendRecommendation] {
        // Always fetch fresh recommendations - no cache checking
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            let fetchedRecommendations = try await fetchRecommendationsFromAPI(token: token, limit: limit)
            
            await MainActor.run {
                self.recommendations = fetchedRecommendations
                // Remove lastUpdated since we're not caching
                // self.lastUpdated = Date()
            }
            
            return fetchedRecommendations
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                print("❌ [FriendRecommendations] Error fetching recommendations: \(error)")
            }
            throw error
        }
    }
    
    /// Send friend request to recommended user
    func sendFriendRequest(to userId: UUID, token: String) async throws -> SendRecommendationRequestResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/recommendations/\(userId.uuidString)/send-request") else {
            throw FriendRecommendationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FriendRecommendationError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            let sendResponse = try JSONDecoder().decode(SendRecommendationRequestResponse.self, from: data)
            
            // Remove the user from recommendations since request was sent
            await MainActor.run {
                self.recommendations.removeAll { $0.recommendedUserId == userId }
            }
            
            return sendResponse
            
        case 401:
            throw FriendRecommendationError.unauthorized
        case 400...499:
            // Try to parse error message from response
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                throw FriendRecommendationError.serverError(detail)
            }
            throw FriendRecommendationError.serverError("Client error")
        case 500...599:
            throw FriendRecommendationError.serverError("Server error")
        default:
            throw FriendRecommendationError.invalidResponse
        }
    }
    
    /// Refresh recommendations (always fresh since no caching)
    func refreshRecommendations(token: String, limit: Int = 10) async {
        do {
            _ = try await getFriendRecommendations(token: token, limit: limit)
        } catch {
            print("❌ [FriendRecommendations] Failed to refresh: \(error)")
        }
    }
    
    /// Clear recommendations data
    func clearCache() {
        recommendations = []
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    
    private func fetchRecommendationsFromAPI(token: String, limit: Int) async throws -> [FriendRecommendation] {
        
        guard let url = URL(string: "\(AppConfig.baseURL)/friends/recommendations?limit=\(limit)") else {
            throw FriendRecommendationError.invalidURL
        }
        
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [FriendRecommendations] Invalid HTTP response")
            throw FriendRecommendationError.networkError
        }
        
        
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ [FriendRecommendations] Error response body: \(responseString)")
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                
                let recommendationResponse = try JSONDecoder().decode(FriendRecommendationResponse.self, from: data)
                
                return recommendationResponse.recommendations
            } catch {
                print("❌ [FriendRecommendations] Failed to decode JSON: \(error)")
                if let dataString = String(data: data, encoding: .utf8) {
                    print("❌ [FriendRecommendations] Raw response: \(dataString)")
                }
                throw error
            }
            
        case 401:
            print("❌ [FriendRecommendations] Unauthorized")
            throw FriendRecommendationError.unauthorized
        case 404:
            return []
        case 400...499:
            // Try to parse error message from response
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorData["detail"] as? String {
                print("❌ [FriendRecommendations] Client error: \(detail)")
                throw FriendRecommendationError.serverError(detail)
            }
            print("❌ [FriendRecommendations] Client error (no detail)")
            throw FriendRecommendationError.serverError("Client error")
        case 500...599:
            print("❌ [FriendRecommendations] Server error")
            throw FriendRecommendationError.serverError("Server error")
        default:
            print("❌ [FriendRecommendations] Unknown status code: \(httpResponse.statusCode)")
            throw FriendRecommendationError.invalidResponse
        }
    }
} 
