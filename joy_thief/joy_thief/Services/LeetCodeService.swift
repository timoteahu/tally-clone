import Foundation

enum LeetCodeService {
    static func fetchTotalProblemsSolved(token: String) async throws -> Int {
        guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/problems-count") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 404 {
            throw LeetCodeError.notConnected
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let responseData = try JSONDecoder().decode(LeetCodeCountResponse.self, from: data)
        return responseData.count
    }
    
    static func fetchTodayProblemsSolved(token: String) async throws -> Int {
        guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/today-count") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 404 {
            throw LeetCodeError.notConnected
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let responseData = try JSONDecoder().decode(LeetCodeCountResponse.self, from: data)
        return responseData.count
    }
    
    static func fetchCurrentWeekProblemsSolved(token: String, weekStartDay: Int) async throws -> LeetCodeWeeklyResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/current-week-count?week_start_day=\(weekStartDay)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 404 {
            throw LeetCodeError.notConnected
        }
        
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(LeetCodeWeeklyResponse.self, from: data)
    }
}

// Response models
struct LeetCodeCountResponse: Codable {
    let count: Int
    let username: String?
}

struct LeetCodeWeeklyResponse: Codable {
    let currentProblems: Int
    let weeklyGoal: Int
    let weekStartDate: String
    let weekEndDate: String
    let progressPercentage: Double
    
    enum CodingKeys: String, CodingKey {
        case currentProblems = "current_problems"
        case weeklyGoal = "weekly_goal"
        case weekStartDate = "week_start_date"
        case weekEndDate = "week_end_date"
        case progressPercentage = "progress_percentage"
    }
}

enum LeetCodeError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notConnected
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .notConnected:
            return "LeetCode account not connected"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}