import SwiftUI
import Foundation

// MARK: - ContentView
// Main entry point for the app's authenticated view
// Logic has been split across multiple files for better organization

struct ContentView: View {
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var paymentManager: PaymentManager
    @EnvironmentObject var feedManager: FeedManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var contactManager: ContactManager
    @EnvironmentObject var loadingManager: LoadingStateManager
    @Environment(BranchService.self) var branchService
    @EnvironmentObject var dataCacheManager: DataCacheManager
    @EnvironmentObject var backgroundUpdateManager: BackgroundUpdateManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var customHabitManager: CustomHabitManager
    
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - State Variables
    @State var selectedTab = 0
    @State var previousTab = 0
    @State var showFriendsView = false
    @State var friendsViewOffset = UIScreen.main.bounds.width
    @State var showAddHabitSheet = false
    @State var addHabitViewOffset: CGFloat = UIScreen.main.bounds.height
    @State var lastBackgroundTime: Date?
    
    // Overlay state variables
    @State var showPaymentView = false
    @State var paymentViewOffset: CGFloat = UIScreen.main.bounds.width
    @State var showPaymentHistoryView = false
    @State var paymentHistoryViewOffset: CGFloat = UIScreen.main.bounds.width
    @State var showHabitOverlay = false
    @State var habitOverlayOffset: CGFloat = UIScreen.main.bounds.width
    // UserAccount overlay state
    @State var showUserAccountOverlay = false
    @State var userAccountOverlayOffset: CGFloat = UIScreen.main.bounds.width
    @State var userAccountOverlayParams: UserAccountOverlayParams? = nil
    // CommentSheet overlay state
    @State var showCommentSheetOverlay = false
    @State var commentSheetOverlayOffset: CGFloat = UIScreen.main.bounds.width
    @State var commentSheetOverlayParams: CommentSheetOverlayParams? = nil
    
    // Branch.io invite handling
    @State var showInviteAcceptanceView = false
    @State var pendingInviteData: BranchInviteData?
    
    // Onboarding intro overlay
    @State var showOnboardingIntro = false
    @State var hasAnimatedFriendsIn = false
    @State var showProfileView = false
    @State var profileViewOffset: CGFloat = UIScreen.main.bounds.width
    
    // Race condition protection
    @State var recentSignupCompletionTime: Date?
    
    // MARK: - Initializer
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = UIColor.clear
        
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.iconColor = .white
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
        UITabBar.appearance().backgroundColor = UIColor.clear
    }
    
    // MARK: - Body
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainAppView(
                    selectedTab: $selectedTab,
                    previousTab: $previousTab,
                    showFriendsView: $showFriendsView,
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
            } else {
                LoginView()
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) { oldValue, newValue in
            handleTabChange(newValue)
        }
        .onChange(of: scenePhase) { oldValue, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerAddHabit)) { _ in
            if !showAddHabitSheet { showAddHabitSheet = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFriends)) { _ in
            if selectedTab != 3 { selectedTab = 3 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFeed)) { _ in
            if selectedTab != 3 { selectedTab = 3 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDiscover"))) { _ in
            if selectedTab != 3 { 
                selectedTab = 3  // Navigate to Discover tab
                // Optionally, you might want to show the friends view specifically
                showFriendsView = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPost"))) { notification in
            handleNavigateToPost(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHabitPost"))) { notification in
            handleNavigateToHabitPost(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshFeed"))) { notification in
            handleRefreshFeed()
        }
        .onReceive(NotificationCenter.default.publisher(for: .branchEnhancedInviteReceived)) { notification in
            handleBranchInviteNotification(notification)
        }
        .onChange(of: branchService.pendingInviteData?.inviterId) { oldValue, _ in
            guard let inviteData = branchService.pendingInviteData else { return }
            handleBranchInviteData(inviteData)
        }
        .onChange(of: authManager.isAuthenticated) { oldValue, isAuth in
            handleAuthenticationChange(isAuth)
        }
        .onReceive(notificationManager.$navigateToPostId.compactMap { $0 }) { _ in
            if selectedTab != 3 { selectedTab = 3 }
        }
        .onAppear {
            handleViewAppear()
        }
        .onChange(of: authManager.currentUser) { oldValue, _ in
            if shouldShowOnboardingIntro() { showOnboardingIntro = true }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showOnboardingIntro) {
            let effectiveState = getEffectiveOnboardingState()
            return OnboardingIntroView(onFinished: {
                showOnboardingIntro = false
                // FIXED: Don't prematurely complete onboarding here
                // The OnboardingIntroView should only call onFinished when user has actually completed all steps
                // State updates are handled within OnboardingIntroView itself
                print("🎭 [ContentView] Onboarding intro finished - closing view")
            }, initialOnboardingState: effectiveState)
        }
        .sheet(item: $pendingInviteData, onDismiss: {
            showInviteAcceptanceView = false
        }) { inviteData in
            InviteAcceptanceView(
                inviterId: inviteData.inviterId,
                habitId: inviteData.habitId,
                branchInviteData: inviteData
            )
            .environmentObject(authManager)
            .environmentObject(friendsManager)
            .environmentObject(habitManager)
        }
        // Removed duplicate UserAccount overlay; handled globally in OverlayViews
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerTestInvite"))) { notification in
            if let userInfo = notification.userInfo,
               let testInviteData = userInfo["testInviteData"] as? BranchInviteData {
                handleBranchInviteData(testInviteData)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SignupJustCompleted"))) { _ in
            recentSignupCompletionTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                recentSignupCompletionTime = nil
            }
        }
        .task {
            await handlePeriodicInviteCheck()
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthenticationChange(_ isAuth: Bool) {
        if !isAuth {
            showOnboardingIntro = false
        } else {
            if shouldShowOnboardingIntro() { showOnboardingIntro = true }
            
            // Preload custom habit types
            if customHabitManager.customHabitTypes.isEmpty,
               let token = AuthenticationManager.shared.storedAuthToken {
                Task { await customHabitManager.preloadAll(token: token) }
            }
            
            // Handle pending Branch invites
            guard let pendingData = branchService.pendingInviteData else { return }
            DispatchQueue.main.async {
                guard let currentUser = authManager.currentUser else { return }
                
                let isSelfInvite = (pendingData.inviterId == currentUser.id || pendingData.inviterPhone == currentUser.phoneNumber)
                let isAlreadyFriend = friendsManager.preloadedFriends.contains { $0.friendId == pendingData.inviterId }
                
                guard !isSelfInvite && !isAlreadyFriend else {
                    print("🚫 [ContentView] Suppressing invite – self-invite or already friends")
                    branchService.clearPendingInvite()
                    return
                }
                
                self.pendingInviteData = pendingData
                self.showInviteAcceptanceView = true
                branchService.clearPendingInvite()
            }
        }
    }
    
    private func handleViewAppear() {
        guard authManager.isAuthenticated else {
            print("🔒 [ContentView] User not authenticated, skipping setup")
            return
        }
        
        // Preload custom habit types
        if customHabitManager.customHabitTypes.isEmpty,
           let token = AuthenticationManager.shared.storedAuthToken {
            Task { await customHabitManager.preloadAll(token: token) }
        }
        
        initializeBackgroundSync()
        handleTabChange(selectedTab)
        
        // Check onboarding state
        if shouldShowOnboardingIntro() { showOnboardingIntro = true }
        
        // Re-check onboarding after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if shouldShowOnboardingIntro() && !showOnboardingIntro {
                showOnboardingIntro = true
            }
        }
        
        // Check for pending invites
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let pendingData = self.branchService.pendingInviteData,
               let currentUser = self.authManager.currentUser {
                
                let isSelfInvite = (pendingData.inviterId == currentUser.id || pendingData.inviterPhone == currentUser.phoneNumber)
                let isAlreadyFriend = self.friendsManager.preloadedFriends.contains { $0.friendId == pendingData.inviterId }
                
                if !isSelfInvite && !isAlreadyFriend {
                    self.pendingInviteData = pendingData
                    self.showInviteAcceptanceView = true
                } else {
                    print("🚫 [ContentView] Suppressed pending invite after login")
                }
                
                self.branchService.clearPendingInvite()
            }
        }
        
        // Handle deep links
        if notificationManager.navigateToPostId != nil {
            selectedTab = 3
        }
    }
    
    private func handlePeriodicInviteCheck() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                guard authManager.isAuthenticated,
                      !showInviteAcceptanceView,
                      let pendingData = branchService.pendingInviteData,
                      let currentUser = authManager.currentUser else { return }
                
                let isSelfInvite = (pendingData.inviterId == currentUser.id || pendingData.inviterPhone == currentUser.phoneNumber)
                let isAlreadyFriend = friendsManager.preloadedFriends.contains { $0.friendId == pendingData.inviterId }
                
                if !isSelfInvite && !isAlreadyFriend {
                    pendingInviteData = pendingData
                    showInviteAcceptanceView = true
                    branchService.clearPendingInvite()
                } else {
                    branchService.clearPendingInvite()
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let triggerAddHabit = Notification.Name("triggerAddHabit")
    static let navigateToFriends = Notification.Name("navigateToFriends")
    static let navigateToFeed = Notification.Name("navigateToFeed")
} 

// Overlay params struct for UserAccount overlay
struct UserAccountOverlayParams: Equatable {
    let userId: String
    let userName: String?
    let userAvatarUrl: String?
}

// Overlay params struct for CommentSheet overlay
struct CommentSheetOverlayParams {
    let postId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let maxCommentLength: Int
    let submitComment: () -> Void
    let timeAgo: (Date) -> String
    let shimmerOpacity: Double
} 