import SwiftUI

// MARK: - Main App View Component

struct MainAppView: View {
    @Binding var selectedTab: Int
    @Binding var previousTab: Int
    @Binding var showFriendsView: Bool
    @Binding var friendsViewOffset: CGFloat
    @Binding var showAddHabitSheet: Bool
    @Binding var addHabitViewOffset: CGFloat
    @Binding var showPaymentView: Bool
    @Binding var paymentViewOffset: CGFloat
    @Binding var showPaymentHistoryView: Bool
    @Binding var paymentHistoryViewOffset: CGFloat
    @Binding var showInviteAcceptanceView: Bool
    @Binding var pendingInviteData: BranchInviteData?
    @Binding var hasAnimatedFriendsIn: Bool
    @Binding var showProfileView: Bool
    @Binding var profileViewOffset: CGFloat
    @Binding var showHabitOverlay: Bool
    @Binding var habitOverlayOffset: CGFloat
    // UserAccount overlay state
    @Binding var showUserAccountOverlay: Bool
    @Binding var userAccountOverlayOffset: CGFloat
    @Binding var userAccountOverlayParams: UserAccountOverlayParams?
    // CommentSheet overlay state
    @Binding var showCommentSheetOverlay: Bool
    @Binding var commentSheetOverlayOffset: CGFloat
    @Binding var commentSheetOverlayParams: CommentSheetOverlayParams?
    
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var customHabitManager: CustomHabitManager
    
    private var showFriendsViewAction: () -> Void {
        {
            showFriendsView = true
        }
    }
    
    private var showProfileViewAction: () -> Void {
        {
            profileViewOffset = UIScreen.main.bounds.width
            showProfileView = true
        }
    }
    // Trigger UserAccount overlay for a given user
    private var triggerUserAccountOverlay: (String, String?, String?) -> Void {
        { userId, userName, userAvatarUrl in
            userAccountOverlayParams = UserAccountOverlayParams(userId: userId, userName: userName, userAvatarUrl: userAvatarUrl)
            userAccountOverlayOffset = UIScreen.main.bounds.width
            showUserAccountOverlay = true
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Add the global app background so it extends behind the custom tab bar
                AppBackground()
                MainContentArea(
                    selectedTab: selectedTab,
                    showFriendsView: $showFriendsView,
                    friendsViewOffset: $friendsViewOffset,
                    showPaymentView: $showPaymentView,
                    paymentViewOffset: $paymentViewOffset,
                    showPaymentHistoryView: $showPaymentHistoryView,
                    paymentHistoryViewOffset: $paymentHistoryViewOffset,
                    showProfileView: $showProfileView,
                    profileViewOffset: $profileViewOffset,
                    showHabitOverlay: $showHabitOverlay,
                    habitOverlayOffset: $habitOverlayOffset,
                    showUserAccountOverlay: $showUserAccountOverlay,
                    userAccountOverlayOffset: $userAccountOverlayOffset,
                    userAccountOverlayParams: $userAccountOverlayParams,
                    triggerProfileView: showProfileViewAction,
                    triggerUserAccountOverlay: triggerUserAccountOverlay
                )
                
                CustomTabBar(selectedTab: $selectedTab, 
                           showAddHabitSheet: $showAddHabitSheet,
                           showFriendsViewAction: showFriendsViewAction)
                
                OverlayViews(showFriendsView: $showFriendsView,
                           friendsViewOffset: $friendsViewOffset,
                           showAddHabitSheet: $showAddHabitSheet,
                           addHabitViewOffset: $addHabitViewOffset,
                           showPaymentView: $showPaymentView,
                           paymentViewOffset: $paymentViewOffset,
                           showPaymentHistoryView: $showPaymentHistoryView,
                           paymentHistoryViewOffset: $paymentHistoryViewOffset,
                           showInviteAcceptanceView: $showInviteAcceptanceView,
                           pendingInviteData: $pendingInviteData,
                           hasAnimatedFriendsIn: $hasAnimatedFriendsIn,
                           showProfileView: $showProfileView,
                           profileViewOffset: $profileViewOffset,
                           showHabitOverlay: $showHabitOverlay,
                           habitOverlayOffset: $habitOverlayOffset,
                           showUserAccountOverlay: $showUserAccountOverlay,
                           userAccountOverlayOffset: $userAccountOverlayOffset,
                           userAccountOverlayParams: $userAccountOverlayParams,
                           showCommentSheetOverlay: $showCommentSheetOverlay,
                           commentSheetOverlayOffset: $commentSheetOverlayOffset,
                           commentSheetOverlayParams: $commentSheetOverlayParams
                )
            }
        }
        .onAppear {
            selectedTab = 0
        }
    }
}

// MARK: - Main Content Area Component

struct MainContentArea: View {
    let selectedTab: Int
    @Binding var showFriendsView: Bool
    @Binding var friendsViewOffset: CGFloat
    @Binding var showPaymentView: Bool
    @Binding var paymentViewOffset: CGFloat
    @Binding var showPaymentHistoryView: Bool
    @Binding var paymentHistoryViewOffset: CGFloat
    @Binding var showProfileView: Bool
    @Binding var profileViewOffset: CGFloat
    @Binding var showHabitOverlay: Bool
    @Binding var habitOverlayOffset: CGFloat
    @Binding var showUserAccountOverlay: Bool
    @Binding var userAccountOverlayOffset: CGFloat
    @Binding var userAccountOverlayParams: UserAccountOverlayParams?
    let triggerProfileView: () -> Void
    let triggerUserAccountOverlay: (String, String?, String?) -> Void
    
    // Tab caching state
    @State private var visitedMainTabs: Set<Int> = [0] // Home is always visited first
    @State private var isLoadingTab: [Int: Bool] = [:]
    
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var feedManager: FeedManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0:
                    HomeView(showFriendsView: showFriendsViewAction, showProfileView: triggerProfileView, onProfileViewDismissed: {}, showHabitOverlay: $showHabitOverlay, habitOverlayOffset: $habitOverlayOffset)
                case 1:
                    HabitViewWrapper(
                        isFirstVisit: !visitedMainTabs.contains(1),
                        isLoading: isLoadingTab[1] ?? false
                    )
                case 3:
                    FeedViewWrapper(
                        showFriendsView: showFriendsViewAction,
                        isFirstVisit: !visitedMainTabs.contains(3),
                        isLoading: isLoadingTab[3] ?? false,
                        triggerProfileView: triggerProfileView,
                        triggerUserAccountOverlay: triggerUserAccountOverlay,
                        showUserAccountOverlay: $showUserAccountOverlay,
                        userAccountOverlayOffset: $userAccountOverlayOffset,
                        userAccountOverlayParams: $userAccountOverlayParams
                    )
                case 4:
                    ProfileViewWrapper(
                        showPaymentView: showPaymentViewAction,
                        isFirstVisit: !visitedMainTabs.contains(4),
                        isLoading: isLoadingTab[4] ?? false
                    )
                case 5:
                    PartnerHabitsViewWrapper(
                        isFirstVisit: !visitedMainTabs.contains(5),
                        isLoading: isLoadingTab[5] ?? false
                    )
                default:
                    HomeView(showFriendsView: showFriendsViewAction, showProfileView: triggerProfileView, onProfileViewDismissed: {}, showHabitOverlay: $showHabitOverlay, habitOverlayOffset: $habitOverlayOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) { oldValue, newTab in
            Task {
                await handleMainTabChange(to: newTab)
            }
        }
    }
    
    @MainActor
    private func handleMainTabChange(to newTab: Int) async {
        // Skip processing for home tab and add habit tab
        guard newTab != 0 && newTab != 2 else { return }
        
        // If tab was already visited, no loading needed
        if visitedMainTabs.contains(newTab) {
            return
        }
        
        // Mark tab as visited and set loading state
        visitedMainTabs.insert(newTab)
        isLoadingTab[newTab] = true
        
        // Load data for specific tabs
        await loadDataForMainTab(newTab)
        
        isLoadingTab[newTab] = false
    }
    
    @MainActor
    private func loadDataForMainTab(_ tab: Int) async {
        guard AuthenticationManager.shared.storedAuthToken != nil else { return }
        
        switch tab {
        case 1: // Habits tab
            // Habits are already preloaded, but we can refresh if needed
            await habitManager.refreshHabits()
        case 3: // Feed tab
            // Feed has its own intelligent loading, just ensure it's initialized
            if !feedManager.hasInitialized {
                await feedManager.manualRefresh()
            }
        case 4: // Profile tab
            // Profile loads data on demand, no preloading needed
            break
        default:
            break
        }
    }
    
    private var showFriendsViewAction: () -> Void {
        {
            showFriendsView = true
        }
    }
    
    private var showPaymentViewAction: () -> Void {
        {
            paymentViewOffset = UIScreen.main.bounds.width
            showPaymentView = true
        }
    }
} 