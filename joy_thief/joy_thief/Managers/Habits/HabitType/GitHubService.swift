import Foundation

enum GitHubService {
    static func fetchTodayCommitCount(token: String) async throws -> Int {
        guard let url = URL(string: "\(AppConfig.baseURL)/github/today-count") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let obj = try JSONDecoder().decode(Response.self, from: data)
        return obj.count
    }
    
    static func fetchCurrentWeekCommitCount(token: String, weekStartDay: Int = 0) async throws -> GitHubWeeklyResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/github/current-week-count?week_start_day=\(weekStartDay)") else { 
            throw URLError(.badURL) 
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let response = try JSONDecoder().decode(GitHubWeeklyResponse.self, from: data)
        return response
    }
    
    private struct Response: Codable { 
        let count: Int 
    }
    
    // Response model for weekly GitHub commit data
    struct GitHubWeeklyResponse: Codable {
        let currentCommits: Int
        let weeklyGoal: Int
        let weekStartDate: String
        let weekEndDate: String
        let habits: [GitHubHabitInfo]
        let progressPercentage: Double
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case currentCommits = "current_commits"
            case weeklyGoal = "weekly_goal"
            case weekStartDate = "week_start_date"
            case weekEndDate = "week_end_date"
            case habits
            case progressPercentage = "progress_percentage"
            case error
        }
    }

    struct GitHubHabitInfo: Codable {
        let id: String
        let name: String
        let weeklyGoal: Int
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case weeklyGoal = "weekly_goal"
        }
    }
} 