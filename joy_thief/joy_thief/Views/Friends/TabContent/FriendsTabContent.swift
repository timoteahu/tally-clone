import SwiftUI

// MARK: - Friends Tab Content
struct FriendsTabContent: View {
    @ObservedObject var unifiedFriendManager: UnifiedFriendManager
    let tabsInInitialLoad: Set<Int>
    let visitedTabs: Set<Int>
    
    var body: some View {
        ScrollView {
            if tabsInInitialLoad.contains(0) || (!visitedTabs.contains(0)) {
                // Show skeleton during initial load OR for unvisited tab
                friendsTabSkeleton
            } else {
                // Show actual content with loading indicator if needed
                LazyVStack(alignment: .leading, spacing: 12) {
                    friendsSection
                    
                    // Empty state if no friends
                    if unifiedFriendManager.friends.isEmpty && !unifiedFriendManager.isLoading {
                        emptyState
                    }
                }
                .padding(.top, 8)
            }
        }
        .refreshable {
            await refreshFriendsData()
        }
    }
    
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !unifiedFriendManager.friends.isEmpty {
                HStack {
                    Text("YOUR FRIENDS")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                    
                ForEach(unifiedFriendManager.friends) { friend in
                    let activityInfo = FriendsView.getActivityDisplayText(from: friend.lastActive)
                    
                    FriendRow(friend: LocalFriend(
                        name: friend.name,
                        phoneNumber: friend.phoneNumber,
                        image: nil,
                        isActive: activityInfo.isActiveNow,
                        isRecommended: false,
                        mutuals: nil,
                        avatarVersion: friend.avatarVersion,
                        avatarUrl80: friend.avatarUrl80,
                        avatarUrl200: friend.avatarUrl200,
                        avatarUrlOriginal: friend.avatarUrlOriginal,
                        friendshipId: friend.friendshipId,
                        friendId: friend.friendId,
                        lastActive: friend.lastActive,
                        activityText: activityInfo.text
                    ), added: .constant(Set<UUID>()), removed: .constant(Set<UUID>()), onTap: {
                        showUserProfile(friend: friend)
                    })
                }
            }
        }
    }
    
    private func showUserProfile(friend: Friend) {
        // Post notification to trigger user account overlay
        NotificationCenter.default.post(
            name: Notification.Name("TriggerUserAccountOverlay"),
            object: nil,
            userInfo: [
                "userId": friend.friendId,
                "userName": friend.name,
                "userAvatarUrl": friend.avatarUrl200 ?? friend.avatarUrl80 ?? friend.avatarUrlOriginal ?? ""
            ]
        )
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("👥 no friends yet")
                .jtStyle(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            Text("invite your contacts to join tally or check your contacts permissions")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
    
    private var friendsTabSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // Friends list skeleton
                    ForEach(0..<6, id: \.self) { _ in
                        skeletonFriendRow
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(true)
    }
    
    private var skeletonFriendRow: some View {
        HStack(spacing: 14) {
            // Avatar skeleton
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 48, height: 48)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 6) {
                // Name skeleton
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 120, height: 16)
                    .cornerRadius(8)
                    .shimmer()
                
                // Phone skeleton
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 140, height: 12)
                    .cornerRadius(6)
                    .shimmer()
            }
            
            Spacer()
            
            // Button skeleton
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 60, height: 28)
                .cornerRadius(12)
                .shimmer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    @MainActor
    private func refreshFriendsData() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        await unifiedFriendManager.refreshFriendsOnly(token: token)
    }
}

// MARK: - Shimmer Effect
class ShimmerAnimator: ObservableObject {
    @Published var offset: CGFloat = -200
    
    init() {
        withAnimation(
            Animation.linear(duration: 1.5)
                .repeatForever(autoreverses: false)
        ) {
            offset = 200
        }
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @StateObject private var animator = ShimmerAnimator()
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color.black,
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(x: animator.offset)
                    )
            )
    }
} 