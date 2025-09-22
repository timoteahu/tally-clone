import Foundation
import SwiftUI

@MainActor
final class LeetCodeManager: ObservableObject {
    static let shared = LeetCodeManager()
    private init() {}
    
    @Published var isProcessing = false
    @Published var lastError: String? = nil
    @Published var connectionStatus: ConnectStatus = .notConnected
    @Published var connectedUsername: String? = nil
    
    /// Validate a LeetCode username
    func validateUsername(_ username: String) async -> (valid: Bool, message: String) {
        guard !username.isEmpty else {
            return (false, "Username cannot be empty")
        }
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return (false, "User not authenticated")
        }
        
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/validate/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)") else {
                throw URLError(.badURL)
            }
            
            print("🔍 LeetCode validate request to: \(url)")
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            
            guard let httpResp = resp as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            print("🔍 Validate response status: \(httpResp.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8) {
                print("🔍 Validate response body: \(responseStr)")
            }
            
            if httpResp.statusCode == 200 {
                struct ValidationResponse: Codable {
                    let valid: Bool
                    let exists: Bool
                    let is_public: Bool
                    let message: String
                }
                
                let decoded = try JSONDecoder().decode(ValidationResponse.self, from: data)
                return (decoded.valid, decoded.message)
            } else {
                // Try to parse error message from response
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = errorData["detail"] {
                    return (false, detail)
                }
                return (false, "Failed to validate username (Status: \(httpResp.statusCode))")
            }
            
        } catch {
            print("❌ Error validating LeetCode username: \(error)")
            return (false, "Failed to connect to server. Please try again.")
        }
    }
    
    /// Connect a LeetCode account
    func connectAccount(username: String) async {
        guard !username.isEmpty else {
            lastError = "Username cannot be empty"
            return
        }
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            lastError = "User not authenticated"
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/connect") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let body = ["username": username]
            req.httpBody = try JSONEncoder().encode(body)
            
            print("🔍 LeetCode connect request to: \(url)")
            print("🔍 Request body: \(body)")
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            
            if let httpResp = resp as? HTTPURLResponse {
                print("🔍 Response status: \(httpResp.statusCode)")
                if let responseStr = String(data: data, encoding: .utf8) {
                    print("🔍 Response body: \(responseStr)")
                }
                
                if httpResp.statusCode == 200 {
                    struct ConnectResponse: Codable {
                        let status: String
                        let message: String
                        let username: String?
                    }
                    
                    let decoded = try JSONDecoder().decode(ConnectResponse.self, from: data)
                    print("✅ LeetCode account connected: \(decoded.username ?? username)")
                    lastError = nil
                    connectionStatus = .connected
                    connectedUsername = decoded.username ?? username
                    
                    // Notify UI to refresh
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshLeetCodeStatus"), object: nil)
                } else {
                    // Parse error message
                    if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                       let detail = errorData["detail"] {
                        lastError = detail
                    } else {
                        lastError = "Failed to connect LeetCode account"
                    }
                    connectionStatus = .notConnected
                }
            }
            
        } catch {
            print("❌ LeetCode connection failed: \(error)")
            lastError = error.localizedDescription
            connectionStatus = .notConnected
        }
    }
    
    /// Check LeetCode connection status
    func checkStatus() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            connectionStatus = .notConnected
            return
        }
        
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/status") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
                connectionStatus = .notConnected
                return
            }
            
            struct StatusResponse: Codable {
                let status: String
                let username: String?
                let message: String?
            }
            
            let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
            
            switch decoded.status {
            case "connected":
                connectionStatus = .connected
                connectedUsername = decoded.username
            case "error":
                connectionStatus = .notConnected
                lastError = decoded.message
            default:
                connectionStatus = .notConnected
                connectedUsername = nil
            }
            
        } catch {
            print("❌ Error checking LeetCode status: \(error)")
            connectionStatus = .notConnected
        }
    }
    
    /// Disconnect LeetCode account
    func disconnectAccount() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/leetcode/disconnect") else {
                throw URLError(.badURL)
            }
            
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (_, resp) = try await URLSession.shared.data(for: req)
            
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                print("✅ LeetCode account disconnected")
                connectionStatus = .notConnected
                connectedUsername = nil
                lastError = nil
                
                // Notify UI to refresh
                NotificationCenter.default.post(name: NSNotification.Name("RefreshLeetCodeStatus"), object: nil)
            }
            
        } catch {
            print("❌ Error disconnecting LeetCode account: \(error)")
            lastError = error.localizedDescription
        }
    }
}