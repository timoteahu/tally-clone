import SwiftUI
import Combine

// MARK: - Non-UI helper logic extracted from FriendsView
extension FriendsView {
    // MARK: Data loading
    @MainActor
    func loadData() async {
        // NEW ARCHITECTURE: Simple trigger that handles all caching logic internally
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isLoading = false
            return
        }
        
        // The unified manager will handle all cache logic internally
        await unifiedFriendManager.triggerRefreshIfNeeded(token: token)
        
        // Always set local loading to false - manager handles its own loading state
        isLoading = false
        
        print("✅ [FriendsView] Load data completed")
    }

    // MARK: Pull-to-refresh using unified manager
    @MainActor
    func refreshAllData() async {
        print("🔄 [FriendsView] Starting force refresh…")
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        // Force refresh all data (for pull-to-refresh which should reload everything)
        await unifiedFriendManager.forceRefresh(token: token)
        
        print("✅ [FriendsView] Force refresh completed")
    }
    
    // MARK: Legacy force refresh for compatibility - now delegates to current tab
    @MainActor
    func forceRefreshData() async {
        // For compatibility, refresh the currently selected tab with specific data only
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        switch selectedTab {
        case 0: // Friends tab
            await unifiedFriendManager.refreshFriendsOnly(token: token)
        case 1: // Discover tab
            // Load unified recommendations (contacts + friend recommendations)
            await unifiedFriendManager.refreshContactsOnly(token: token)
        case 2: // Requests tab
            await unifiedFriendManager.refreshRequestsOnly(token: token)
        default:
            await unifiedFriendManager.refreshFriendsOnly(token: token)
        }
    }

    // MARK: Friend-request actions using unified manager
    func acceptFriendRequest(_ request: ReceivedFriendRequest) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        processingRequests.insert(request.id)

        // Snapshot for rollback
        let originalReceivedRequests = unifiedFriendManager.receivedRequests
        let originalFriends = unifiedFriendManager.friends

        // Optimistic update
        unifiedFriendManager.receivedRequests.removeAll { $0.id == request.id }
        let newFriend = Friend(
            id: UUID().uuidString,
                                                    friendId: request.senderId,
                                                    name: request.senderName,
            phoneNumber: request.senderPhone,
            avatarVersion: request.senderAvatarVersion,
            avatarUrl80: request.senderAvatarUrl80,
            avatarUrl200: request.senderAvatarUrl200,
            avatarUrlOriginal: request.senderAvatarUrlOriginal
        )
        unifiedFriendManager.friends.append(newFriend)

        do {
            // Use legacy friend request manager for API call
            _ = try await FriendRequestManager.shared.acceptFriendRequest(requestId: request.id, token: token)
            print("✅ Accepted friend request from \(request.senderName)")
            
            // Refresh the friends list first to ensure the new friendship is registered
            print("🔄 Refreshing friends list after accepting friend request...")
            await FriendsManager.shared.reloadFriends()
            print("✅ Friends list refreshed")
            
            // Small delay to ensure server has fully processed the new friendship
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Refresh the feed to include new friend's posts
            print("🔄 Refreshing feed after accepting friend request...")
            await FeedManager.shared.refreshAfterNewFriend()
            print("✅ Feed refreshed to include posts from new friend")
        } catch {
            // Rollback on failure
            unifiedFriendManager.receivedRequests = originalReceivedRequests
            unifiedFriendManager.friends = originalFriends
            errorMessage = "Failed to accept friend request: \(error.localizedDescription)"
            showError = true
            print("❌ Failed to accept friend request: \(error)")
        }

        processingRequests.remove(request.id)
    }

    func declineFriendRequest(_ request: ReceivedFriendRequest) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        processingRequests.insert(request.id)

        let originalReceivedRequests = unifiedFriendManager.receivedRequests
        unifiedFriendManager.receivedRequests.removeAll { $0.id == request.id }

        do {
            // Use legacy friend request manager for API call
            _ = try await FriendRequestManager.shared.declineFriendRequest(requestId: request.id, token: token)
        } catch {
            unifiedFriendManager.receivedRequests = originalReceivedRequests
            errorMessage = error.localizedDescription
            showError = true
        }

        processingRequests.remove(request.id)
    }

    func sendFriendRequestToRecommendation(_ recommendation: FriendRecommendation) async throws {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            throw FriendRecommendationError.unauthorized
        }

        do {
            let response = try await friendRecommendationsManager.sendFriendRequest(to: recommendation.recommendedUserId, token: token)
            print("✅ [FriendsView] Friend request sent to \(recommendation.userName): \(response.message)")
            // Refresh requests data after sending friend request
            await unifiedFriendManager.refreshRequestsOnly(token: token)
        } catch {
            print("❌ [FriendsView] Failed to send friend request: \(error)")
            throw error
        }
    }

    func cancelFriendRequest(_ request: UnifiedSentFriendRequest) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        processingRequests.insert(request.id)

        // Snapshot for rollback
        let originalSentRequests = unifiedFriendManager.sentRequests

        // Optimistic update - remove the request from sent requests
        unifiedFriendManager.sentRequests.removeAll { $0.id == request.id }

        do {
            // Use legacy friend request manager for API call
            _ = try await FriendRequestManager.shared.cancelFriendRequest(requestId: request.id, token: token)
            print("✅ Cancelled friend request to \(request.receiverName)")
        } catch {
            // Rollback on failure
            unifiedFriendManager.sentRequests = originalSentRequests
            errorMessage = "Failed to cancel friend request: \(error.localizedDescription)"
            showError = true
            print("❌ Failed to cancel friend request: \(error)")
        }

        processingRequests.remove(request.id)
    }

    // MARK: Cache helpers (legacy - no longer needed with unified manager)
    func updateCachedLists() {
        // This function is now a no-op since we use the unified manager
        // Keeping for backward compatibility only
        return
    }
} 
