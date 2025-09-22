import SwiftUI

// MARK: - Requests Tab Content
struct RequestsTabContent: View {
    @ObservedObject var unifiedFriendManager: UnifiedFriendManager
    let tabsInInitialLoad: Set<Int>
    let visitedTabs: Set<Int>
    
    @State private var processingRequests: Set<String> = []
    
    var body: some View {
        ScrollView {
            if tabsInInitialLoad.contains(2) || (!visitedTabs.contains(2)) {
                requestsTabSkeleton
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !unifiedFriendManager.receivedRequests.isEmpty {
                        friendRequestsSection
                            .padding(.bottom, 16) 
                    }
                    
                    if !unifiedFriendManager.sentRequests.isEmpty {
                        sentFriendRequestsSection
                    }
                    
                    if unifiedFriendManager.receivedRequests.isEmpty && unifiedFriendManager.sentRequests.isEmpty && !unifiedFriendManager.isLoading {
                        emptyStateForRequests
                    }
                }
                .padding(.top, 8)
            }
        }
        .refreshable {
            await refreshRequestsData()
        }
    }
    
    private var friendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !unifiedFriendManager.receivedRequests.isEmpty {
                HStack {
                    Text("INCOMING REQUESTS")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ForEach(unifiedFriendManager.receivedRequests) { request in
                    FriendRequestRow(request: request.toFriendRequestWithDetails(),
                                     isProcessing: processingRequests.contains(request.id),
                                     onAccept: { await acceptFriendRequest(request) },
                                     onDecline: { await declineFriendRequest(request) })
                }
            }
        }
    }

    // NEW: Sent Friend Requests Section
    private var sentFriendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !unifiedFriendManager.sentRequests.isEmpty {
                HStack {
                    Text("REQUESTS SENT")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                ForEach(unifiedFriendManager.sentRequests) { request in
                    SentFriendRequestRow(
                        request: request,
                        isProcessing: processingRequests.contains(request.id),
                        onCancel: {
                            Task {
                                await cancelFriendRequest(request)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var emptyStateForRequests: some View {
        VStack(spacing: 16) {
            Text("📮 no requests yet")
                .jtStyle(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            Text("friend requests you send and get will show up here")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .padding(.top, 40)
    }
    
    private var requestsTabSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // Friend requests skeleton
                    ForEach(0..<4, id: \.self) { _ in
                        skeletonRequestRow
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(true)
    }
    
    private var skeletonRequestRow: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 4) {
                // Name placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 16)
                    .shimmer()
                
                // Request message placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 12)
                    .shimmer()
            }
            
            Spacer()
            
            // Accept/Decline buttons placeholder
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 32)
                    .cornerRadius(16)
                    .shimmer()
                
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 32)
                    .cornerRadius(16)
                    .shimmer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Friend Request Actions
    
    @MainActor
    private func acceptFriendRequest(_ request: ReceivedFriendRequest) async {
        processingRequests.insert(request.id)
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            processingRequests.remove(request.id)
            return
        }
        
        do {
            let response = try await FriendRequestManager.shared.acceptFriendRequest(
                requestId: request.id,
                token: token
            )
            
            // Let UnifiedFriendManager handle the state updates via its refresh
            await unifiedFriendManager.refreshRequestsOnly(token: token)
            
            // Small delay to ensure server has fully processed the new friendship
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Refresh the feed to include posts from the new friend
            await FeedManager.shared.refreshAfterNewFriend()
            
            print("✅ Accepted friend request from \(request.senderName): \(response.message)")
        } catch {
            print("❌ Failed to accept friend request from \(request.senderName): \(error)")
        }
        
        processingRequests.remove(request.id)
    }
    
    @MainActor
    private func declineFriendRequest(_ request: ReceivedFriendRequest) async {
        processingRequests.insert(request.id)
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            processingRequests.remove(request.id)
            return
        }
        
        do {
            let response = try await FriendRequestManager.shared.declineFriendRequest(
                requestId: request.id,
                token: token
            )
            
            // Let UnifiedFriendManager handle the state updates via its refresh
            await unifiedFriendManager.refreshRequestsOnly(token: token)
            
            print("✅ Declined friend request from \(request.senderName): \(response.message)")
        } catch {
            print("❌ Failed to decline friend request from \(request.senderName): \(error)")
        }
        
        processingRequests.remove(request.id)
    }
    
    @MainActor
    private func cancelFriendRequest(_ request: UnifiedSentFriendRequest) async {
        processingRequests.insert(request.id)
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            processingRequests.remove(request.id)
            return
        }
        
        do {
            let response = try await FriendRequestManager.shared.cancelFriendRequest(
                requestId: request.id,
                token: token
            )
            
            // Let UnifiedFriendManager handle the state updates via its refresh
            await unifiedFriendManager.refreshRequestsOnly(token: token)
            
            print("✅ Cancelled friend request to \(request.receiverName): \(response.message)")
        } catch {
            print("❌ Failed to cancel friend request to \(request.receiverName): \(error)")
        }
        
        processingRequests.remove(request.id)
    }
    
    @MainActor
    private func refreshRequestsData() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        await unifiedFriendManager.refreshRequestsOnly(token: token)
    }
} 
