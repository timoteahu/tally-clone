import SwiftUI

// MARK: - Global Search Result Row
struct GlobalSearchResultRow: View {
    let result: UserSearchResult
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var unifiedFriendManager: UnifiedFriendManager
    @State private var isProcessing = false
    @State private var localRequestSent = false
    
    private var hasSentRequest: Bool {
        localRequestSent || unifiedFriendManager.sentRequests.contains { $0.receiverId == result.id }
    }
    
    private var buttonText: String {
        if result.isFriend {
            return "FRIENDS"
        } else if result.hasReceivedRequest {
            // Prioritize accepting their request over canceling ours
            return "ACCEPT"
        } else if hasSentRequest || result.hasPendingRequest {
            return "CANCEL" 
        } else {
            return "ADD"
        }
    }
    
    private var buttonColor: Color {
        if result.isFriend {
            return .gray.opacity(0.3)
        } else if result.hasReceivedRequest {
            return .blue
        } else if hasSentRequest || result.hasPendingRequest {
            return .red.opacity(0.7)
        } else {
            return .green
        }
    }
    
    private var isButtonEnabled: Bool {
        !result.isFriend
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar – cached image or generated initials
            if result.avatarUrl200 != nil || result.avatarUrl80 != nil {
                CachedAvatarView(
                    url80: result.avatarUrl80,
                    url200: result.avatarUrl200,
                    urlOriginal: result.avatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(result.name.initials())
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Action button
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                Button(action: handleAction) {
                    Text(buttonText)
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(buttonColor)
                        .cornerRadius(12)
                }
                .disabled(!isButtonEnabled)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func handleAction() {
        if result.hasReceivedRequest {
            // Accept the received request (this will make us friends, even if we also sent them one)
            Task {
                await acceptReceivedRequest()
            }
        } else if hasSentRequest || result.hasPendingRequest {
            // Cancel our sent request (only if they haven't sent us one)
            Task {
                await cancelSentRequest()
            }
        } else if !result.isFriend {
            // Send new friend request
            Task {
                await sendFriendRequest()
            }
        }
    }
    
    private func acceptReceivedRequest() async {
        // Find the request in received requests and accept it
        if let request = unifiedFriendManager.receivedRequests.first(where: { $0.senderId == result.id }) {
            isProcessing = true
            
            guard let token = AuthenticationManager.shared.storedAuthToken else {
                isProcessing = false
                return
            }
            
            do {
                _ = try await FriendRequestManager.shared.acceptFriendRequest(
                    requestId: request.id,
                    token: token
                )
                
                await MainActor.run {
                    isProcessing = false
                    // The UnifiedFriendManager will handle updating the UI
                }
                
                print("✅ Accepted friend request from \(result.name)")
            } catch {
                await MainActor.run {
                    isProcessing = false
                }
                print("❌ Failed to accept friend request from \(result.name): \(error)")
            }
        }
    }
    
    private func sendFriendRequest() async {
        isProcessing = true
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isProcessing = false
            return
        }
        
        do {
            let response = try await FriendRequestManager.shared.sendFriendRequest(
                to: result.id,
                token: token
            )
            
            await MainActor.run {
                isProcessing = false
                localRequestSent = true
                
                // Add to UnifiedFriendManager's sent requests for consistency
                let newSentRequest = UnifiedSentFriendRequest(
                    id: response.id,
                    receiverId: response.receiverId,
                    receiverName: result.name,
                    receiverPhone: result.phoneNumber,
                    receiverAvatarVersion: result.avatarVersion,
                    receiverAvatarUrl80: result.avatarUrl80,
                    receiverAvatarUrl200: result.avatarUrl200,
                    receiverAvatarUrlOriginal: result.avatarUrlOriginal,
                    message: response.message,
                    status: response.status.rawValue,
                    createdAt: response.createdAt
                )
                
                if !unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == result.id }) {
                    unifiedFriendManager.sentRequests.append(newSentRequest)
                }
            }
            
            print("✅ Friend request sent to \(result.name): \(response.message ?? "No message")")
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            print("❌ Failed to send friend request to \(result.name): \(error)")
        }
    }
    
    private func cancelSentRequest() async {
        isProcessing = true
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isProcessing = false
            return
        }
        
        do {
            // Try to find the request in our sent requests first
            if let sentRequest = unifiedFriendManager.sentRequests.first(where: { $0.receiverId == result.id }) {
                _ = try await FriendRequestManager.shared.cancelFriendRequest(
                    requestId: sentRequest.id,
                    token: token
                )
                
                await MainActor.run {
                    isProcessing = false
                    localRequestSent = false
                    
                    // Remove from UnifiedFriendManager's sent requests
                    unifiedFriendManager.sentRequests.removeAll { $0.receiverId == result.id }
                }
                
                print("✅ Cancelled friend request to \(result.name)")
            } else {
                // If we can't find the request locally, refresh the data to get the latest state
                await MainActor.run {
                    isProcessing = false
                    localRequestSent = false
                }
                
                // Refresh data to get current state
                await unifiedFriendManager.refreshRequestsOnly(token: token)
                print("⚠️ Could not find local request to cancel, refreshed data instead")
            }
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            print("❌ Failed to cancel friend request to \(result.name): \(error)")
        }
    }
}

// MARK: - Recommendation Source Type
enum RecommendationSourceType {
    case fromContacts
    case fromMutuals
    
    func displayText(mutualCount: Int? = nil) -> String {
        switch self {
        case .fromContacts:
            return "From contacts"
        case .fromMutuals:
            if let count = mutualCount, count > 0 {
                return count == 1 ? "1 mutual friend" : "\(count) mutual friends"
            } else {
                return "Mutual connections"
            }
        }
    }
    
    var textColor: Color {
        switch self {
        case .fromContacts:
            return .green.opacity(0.7)
        case .fromMutuals:
            return .blue.opacity(0.7)
        }
    }
}

// MARK: - Unified Recommendation Row
struct UnifiedRecommendationRow: View {
    let userId: String
    let name: String
    let phoneNumber: String
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let sourceType: RecommendationSourceType
    let mutualFriendsCount: Int?
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var unifiedFriendManager: UnifiedFriendManager
    @State private var isProcessing = false
    @State private var localRequestSent = false
    @State private var managerHasSentRequest = false // Track manager state separately for reactivity
    
    private var hasSentRequest: Bool {
        localRequestSent || managerHasSentRequest
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar – cached image or generated initials
            if avatarUrl200 != nil || avatarUrl80 != nil {
                CachedAvatarView(
                    url80: avatarUrl80,
                    url200: avatarUrl200,
                    urlOriginal: avatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(name.initials())
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(sourceType.displayText(mutualCount: mutualFriendsCount))
                    .jtStyle(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(sourceType.textColor)
            }
            
            Spacer()
            
            // Add friend button with CANCEL state support
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                Button(action: handleAction) {
                    Text(hasSentRequest ? "CANCEL" : "ADD")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(hasSentRequest ? Color.red.opacity(0.7) : Color.green)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .onAppear {
            // Initialize state when view appears
            updateSentRequestState()
        }
        .onChange(of: unifiedFriendManager.sentRequests) { oldValue, newValue in
            // React to changes in sent requests (e.g., when a request is sent via search)
            updateSentRequestState()
        }
    }
    
    private func updateSentRequestState() {
        let wasFound = managerHasSentRequest
        managerHasSentRequest = unifiedFriendManager.sentRequests.contains { $0.receiverId == userId }
        
        // Debug logging when state changes
        if wasFound != managerHasSentRequest {
            print("🔄 [UnifiedRecommendationRow] \(name): hasSentRequest changed \(wasFound) → \(managerHasSentRequest)")
        }
    }
    
    private func handleAction() {
        if hasSentRequest {
            // Cancel the sent request
            Task {
                await cancelSentRequest()
            }
        } else {
            // Send new friend request
            Task {
                await sendFriendRequest()
            }
        }
    }
    
    private func sendFriendRequest() async {
        isProcessing = true
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isProcessing = false
            return
        }
        
        do {
            // Use existing friend request system
            let response = try await FriendRequestManager.shared.sendFriendRequest(
                to: userId,
                token: token
            )
            
            await MainActor.run {
                isProcessing = false
                
                print("✅ Updated button state to CANCEL for user: \(name)")
                
                // Mark request as sent locally for instant UI feedback
                localRequestSent = true
                
                // Then add to UnifiedFriendManager's sent requests for consistency
                let newSentRequest = UnifiedSentFriendRequest(
                    id: response.id,
                    receiverId: response.receiverId,
                    receiverName: name,
                    receiverPhone: phoneNumber,
                    receiverAvatarVersion: avatarVersion,
                    receiverAvatarUrl80: avatarUrl80,
                    receiverAvatarUrl200: avatarUrl200,
                    receiverAvatarUrlOriginal: avatarUrlOriginal,
                    message: response.message,
                    status: response.status.rawValue,
                    createdAt: response.createdAt
                )
                
                // Add to the sent requests array if not already present
                if !unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == userId }) {
                    unifiedFriendManager.sentRequests.append(newSentRequest)
                    print("✅ Added request to unified manager for: \(name)")
                }
            }
            
            print("✅ Friend request sent to \(name): \(response.message ?? "No message")")
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            print("❌ Failed to send friend request to \(name): \(error)")
        }
    }
    
    private func cancelSentRequest() async {
        isProcessing = true
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isProcessing = false
            return
        }
        
        do {
            // Try to find the request in our sent requests first
            if let sentRequest = unifiedFriendManager.sentRequests.first(where: { $0.receiverId == userId }) {
                _ = try await FriendRequestManager.shared.cancelFriendRequest(
                    requestId: sentRequest.id,
                    token: token
                )
                
                await MainActor.run {
                    isProcessing = false
                    localRequestSent = false
                    
                    // Remove from UnifiedFriendManager's sent requests
                    unifiedFriendManager.sentRequests.removeAll { $0.receiverId == userId }
                }
                
                print("✅ Cancelled friend request to \(name)")
            } else {
                // If we can't find the request locally, refresh the data to get the latest state
                await MainActor.run {
                    isProcessing = false
                    localRequestSent = false
                }
                
                // Refresh data to get current state
                await unifiedFriendManager.refreshRequestsOnly(token: token)
                print("⚠️ Could not find local request to cancel, refreshed data instead")
            }
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            print("❌ Failed to cancel friend request to \(name): \(error)")
        }
    }
} 