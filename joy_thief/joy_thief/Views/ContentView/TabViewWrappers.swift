import SwiftUI

// MARK: - Tab View Wrappers

struct HabitViewWrapper: View {
    let isFirstVisit: Bool
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isFirstVisit && isLoading {
                // Simple loading view instead of complex skeleton
                ZStack {
                    AppBackground()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            } else {
                HabitView()
            }
        }
    }
}

struct FeedViewWrapper: View {
    let showFriendsView: () -> Void
    let isFirstVisit: Bool
    let isLoading: Bool
    let triggerProfileView: () -> Void
    let triggerUserAccountOverlay: (String, String?, String?) -> Void
    @Binding var showUserAccountOverlay: Bool
    @Binding var userAccountOverlayOffset: CGFloat
    @Binding var userAccountOverlayParams: UserAccountOverlayParams?
    
    @EnvironmentObject var feedManager: FeedManager
    
    var body: some View {
        Group {
            if isFirstVisit && isLoading && !feedManager.hasInitialized {
                // Simple loading view instead of complex skeleton
                ZStack {
                    AppBackground()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            } else {
                UserFeedView(
                    showFriendsView: showFriendsView,
                    showProfileView: triggerProfileView,
                    onProfileViewDismissed: {},
                    triggerUserAccountOverlay: { userId, userName, userAvatarUrl in
                        userAccountOverlayParams = UserAccountOverlayParams(
                            userId: userId,
                            userName: userName,
                            userAvatarUrl: userAvatarUrl
                        )
                        userAccountOverlayOffset = UIScreen.main.bounds.width
                        showUserAccountOverlay = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                userAccountOverlayOffset = 0
                            }
                        }
                    }
                )
            }
        }
    }
}

struct ProfileViewWrapper: View {
    let showPaymentView: () -> Void
    let isFirstVisit: Bool
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isFirstVisit && isLoading {
                // Simple loading view instead of complex skeleton
                ZStack {
                    AppBackground()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            } else {
                PersonalUserAccount()
            }
        }
    }
}

struct PartnerHabitsViewWrapper: View {
    let isFirstVisit: Bool
    let isLoading: Bool
    
    var body: some View {
        if isFirstVisit && isLoading {
            // Simple loading view instead of complex skeleton
            ZStack {
                AppBackground()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        } else {
            PartnerHabitsView()
        }
    }
}

 