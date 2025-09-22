import Foundation
import UIKit

@MainActor
final class InviteManager: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let urlSession = URLSession.shared
    
    enum InviteError: Error {
        case networkError
        case serverError(String)
        case inviteNotFound
        case inviteExpired
        case inviteAlreadyUsed
        case alreadyFriends
        case cannotInviteSelf
        
        var localizedDescription: String {
            switch self {
            case .networkError:
                return "Network connection error. Please check your internet connection and try again."
            case .serverError(let message):
                return message
            case .inviteNotFound:
                return "Invite not found or has expired."
            case .inviteExpired:
                return "This invite has expired."
            case .inviteAlreadyUsed:
                return "This invite has already been used."
            case .alreadyFriends:
                return "You are already friends with this person."
            case .cannotInviteSelf:
                return "You cannot invite yourself."
            }
        }
    }
    
    func acceptBranchInvite(inviterId: String, token: String) async throws -> BranchInviteAcceptResponse {
        print("🎯 [InviteManager] acceptBranchInvite() called for inviterId: \(inviterId)")
        
        isLoading = true
        defer { 
            isLoading = false
            print("📊 [InviteManager] Loading state set to false")
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/invites/branch-accept/\(inviterId)") else {
            print("❌ [InviteManager] Failed to create URL with baseURL: \(AppConfig.baseURL)")
            throw InviteError.networkError
        }
        
        print("🌐 [InviteManager] Making request to: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("📡 [InviteManager] Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        do {
            print("⏳ [InviteManager] Sending network request...")
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [InviteManager] Invalid response type")
                throw InviteError.networkError
            }
            
            print("📊 [InviteManager] HTTP Status Code: \(httpResponse.statusCode)")
            print("📊 [InviteManager] Response headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📋 [InviteManager] Response body: \(responseString)")
            }
            
            if httpResponse.statusCode == 200 {
                print("✅ [InviteManager] Success response received")
                let result = try JSONDecoder().decode(BranchInviteAcceptResponse.self, from: data)
                print("✅ [InviteManager] Successfully decoded response: \(result)")
                return result
            } else if httpResponse.statusCode == 400 {
                print("⚠️ [InviteManager] Bad request (400)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    print("📋 [InviteManager] Error detail: \(detail)")
                    if detail.contains("already exists") {
                        throw InviteError.alreadyFriends
                    } else if detail.contains("own invite") {
                        throw InviteError.cannotInviteSelf
                    } else {
                        throw InviteError.serverError(detail)
                    }
                }
                throw InviteError.serverError("Bad request")
            } else if httpResponse.statusCode == 404 {
                print("❌ [InviteManager] Inviter not found (404)")
                throw InviteError.inviteNotFound
            } else {
                print("❌ [InviteManager] Unexpected status code: \(httpResponse.statusCode)")
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    print("📋 [InviteManager] Server error detail: \(detail)")
                    throw InviteError.serverError(detail)
                } else {
                    throw InviteError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
        } catch let error as InviteError {
            print("❌ [InviteManager] InviteError caught: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ [InviteManager] Network error caught: \(error)")
            throw InviteError.networkError
        }
    }
    
    func acceptInvite(inviteId: String, token: String) async throws -> InviteAcceptanceResponse {
        isLoading = true
        defer { isLoading = false }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/invites/accept/\(inviteId)") else {
            throw InviteError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw InviteError.networkError
            }
            
            if httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(InviteAcceptanceResponse.self, from: data)
            } else {
                // Parse error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    
                    // Check for specific error types
                    if detail.contains("Invite not found") {
                        throw InviteError.inviteNotFound
                    } else if detail.contains("expired") {
                        throw InviteError.inviteExpired
                    } else if detail.contains("already been used") {
                        throw InviteError.inviteAlreadyUsed
                    } else if detail.contains("already exists") {
                        throw InviteError.alreadyFriends
                    } else if detail.contains("your own invite") {
                        throw InviteError.cannotInviteSelf
                    } else {
                        throw InviteError.serverError(detail)
                    }
                } else {
                    throw InviteError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
        } catch let error as InviteError {
            throw error
        } catch {
            throw InviteError.networkError
        }
    }
    
    func lookupInvite(inviterId: String, token: String) async throws -> Invite {
        guard let url = URL(string: "\(AppConfig.baseURL)/invites/lookup/\(inviterId)") else {
            throw InviteError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw InviteError.networkError
            }
            
            if httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(Invite.self, from: data)
            } else if httpResponse.statusCode == 404 {
                throw InviteError.inviteNotFound
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    throw InviteError.serverError(detail)
                } else {
                    throw InviteError.serverError("HTTP \(httpResponse.statusCode)")
                }
            }
        } catch let error as InviteError {
            throw error
        } catch {
            throw InviteError.networkError
        }
    }
}

struct InviteAcceptanceResponse: Codable {
    let message: String
    let friendshipId: String
    let inviteId: String
    let habitId: String?
    
    private enum CodingKeys: String, CodingKey {
        case message
        case friendshipId = "friendship_id"
        case inviteId = "invite_id"
        case habitId = "habit_id"
    }
} 