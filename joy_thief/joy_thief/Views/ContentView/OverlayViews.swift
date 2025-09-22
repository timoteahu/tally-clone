import SwiftUI

// MARK: - Overlay Views Component

struct OverlayViews: View {
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
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var habitManager: HabitManager
    
    init(showFriendsView: Binding<Bool>,
         friendsViewOffset: Binding<CGFloat>,
         showAddHabitSheet: Binding<Bool>,
         addHabitViewOffset: Binding<CGFloat>,
         showPaymentView: Binding<Bool>,
         paymentViewOffset: Binding<CGFloat>,
         showPaymentHistoryView: Binding<Bool>,
         paymentHistoryViewOffset: Binding<CGFloat>,
         showInviteAcceptanceView: Binding<Bool>,
         pendingInviteData: Binding<BranchInviteData?>,
         hasAnimatedFriendsIn: Binding<Bool>,
         showProfileView: Binding<Bool>,
         profileViewOffset: Binding<CGFloat>,
         showHabitOverlay: Binding<Bool>,
         habitOverlayOffset: Binding<CGFloat>,
         showUserAccountOverlay: Binding<Bool>,
         userAccountOverlayOffset: Binding<CGFloat>,
         userAccountOverlayParams: Binding<UserAccountOverlayParams?>,
         showCommentSheetOverlay: Binding<Bool>,
         commentSheetOverlayOffset: Binding<CGFloat>,
         commentSheetOverlayParams: Binding<CommentSheetOverlayParams?>) {
        _showFriendsView = showFriendsView
        _friendsViewOffset = friendsViewOffset
        _showAddHabitSheet = showAddHabitSheet
        _addHabitViewOffset = addHabitViewOffset
        _showPaymentView = showPaymentView
        _paymentViewOffset = paymentViewOffset
        _showPaymentHistoryView = showPaymentHistoryView
        _paymentHistoryViewOffset = paymentHistoryViewOffset
        _showInviteAcceptanceView = showInviteAcceptanceView
        _pendingInviteData = pendingInviteData
        _hasAnimatedFriendsIn = hasAnimatedFriendsIn
        _showProfileView = showProfileView
        _profileViewOffset = profileViewOffset
        _showHabitOverlay = showHabitOverlay
        _habitOverlayOffset = habitOverlayOffset
        _showUserAccountOverlay = showUserAccountOverlay
        _userAccountOverlayOffset = userAccountOverlayOffset
        _userAccountOverlayParams = userAccountOverlayParams
        _showCommentSheetOverlay = showCommentSheetOverlay
        _commentSheetOverlayOffset = commentSheetOverlayOffset
        _commentSheetOverlayParams = commentSheetOverlayParams

        NotificationCenter.default.addObserver(forName: Notification.Name("TriggerPaymentOverlay"), object: nil, queue: .main) { _ in
            paymentViewOffset.wrappedValue = UIScreen.main.bounds.width
            showPaymentView.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration:0.3)) {
                    paymentViewOffset.wrappedValue = 0
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name("TriggerPaymentHistoryOverlay"), object: nil, queue: .main) { _ in
            paymentHistoryViewOffset.wrappedValue = UIScreen.main.bounds.width
            showPaymentHistoryView.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration:0.3)) {
                    paymentHistoryViewOffset.wrappedValue = 0
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name("TriggerCommentSheetOverlay"), object: nil, queue: .main) { notification in
            if let userInfo = notification.userInfo,
               let params = userInfo["params"] as? CommentSheetOverlayParams {
                commentSheetOverlayParams.wrappedValue = params
                commentSheetOverlayOffset.wrappedValue = UIScreen.main.bounds.width
                showCommentSheetOverlay.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration:0.3)) {
                        commentSheetOverlayOffset.wrappedValue = 0
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name("TriggerUserAccountOverlay"), object: nil, queue: .main) { notification in
            if let userInfo = notification.userInfo,
               let userId = userInfo["userId"] as? String,
               let userName = userInfo["userName"] as? String,
               let userAvatarUrl = userInfo["userAvatarUrl"] as? String {
                userAccountOverlayParams.wrappedValue = UserAccountOverlayParams(
                    userId: userId,
                    userName: userName.isEmpty ? nil : userName,
                    userAvatarUrl: userAvatarUrl.isEmpty ? nil : userAvatarUrl
                )
                userAccountOverlayOffset.wrappedValue = UIScreen.main.bounds.width
                showUserAccountOverlay.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration:0.3)) {
                        userAccountOverlayOffset.wrappedValue = 0
                    }
                }
            }
        }
    }
    
    var body: some View {
        Group {
            // Overlay FriendsView when showFriendsView is true
            if showFriendsView {
                FriendsView(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        friendsViewOffset = UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showFriendsView = false
                        friendsViewOffset = UIScreen.main.bounds.width
                        hasAnimatedFriendsIn = false
                    }
                })
                .offset(x: friendsViewOffset)
                .onAppear {
                    hasAnimatedFriendsIn = true
                }
                .environmentObject(UnifiedFriendManager.shared)
                .zIndex(1)
            }
            
            // Overlay AddHabitView when showAddHabitSheet is true (slide from bottom)
            if showAddHabitSheet {
                AddHabitOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        addHabitViewOffset = UIScreen.main.bounds.height
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAddHabitSheet = false
                        addHabitViewOffset = UIScreen.main.bounds.height
                    }
                })
                .offset(y: addHabitViewOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        addHabitViewOffset = 0
                    }
                }
            }
            
            // Overlay PaymentView when showPaymentView is true
            if showPaymentView {
                PaymentView(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        paymentViewOffset = UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPaymentView = false
                        paymentViewOffset = UIScreen.main.bounds.width // Reset for next time
                    }
                })
                .offset(x: paymentViewOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        paymentViewOffset = 0
                    }
                }
                .zIndex(2)
            }
            
            // Overlay PaymentHistoryView when showPaymentHistoryView is true
            if showPaymentHistoryView {
                PaymentHistoryOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        paymentHistoryViewOffset = UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPaymentHistoryView = false
                        paymentHistoryViewOffset = UIScreen.main.bounds.width // Reset for next time
                    }
                })
                .offset(x: paymentHistoryViewOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        paymentHistoryViewOffset = 0
                    }
                }
                .zIndex(2)
            }
            
            // Overlay ProfileView
            if showProfileView {
                ProfileOverlay(onDismiss: {
                    // Notify views immediately that profile view is being dismissed
                    NotificationCenter.default.post(name: NSNotification.Name("ProfileViewDismissed"), object: nil)
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        profileViewOffset = UIScreen.main.bounds.width
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showProfileView = false
                        profileViewOffset = UIScreen.main.bounds.width
                    }
                })
                .offset(x: profileViewOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) { profileViewOffset = 0 }
                }
                .zIndex(1)
            }

            // Overlay UserAccountOverlay when showUserAccountOverlay is true
            if showUserAccountOverlay, let params = userAccountOverlayParams {
                UserAccountOverlay(
                    userId: params.userId,
                    userName: params.userName,
                    userAvatarUrl: params.userAvatarUrl,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            userAccountOverlayOffset = UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showUserAccountOverlay = false
                            userAccountOverlayOffset = UIScreen.main.bounds.width
                            userAccountOverlayParams = nil
                        }
                    }
                )
                .offset(x: userAccountOverlayOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        userAccountOverlayOffset = 0
                    }
                }
                .zIndex(2)  // Higher z-index to appear above friends
            }

            if showHabitOverlay {
                HabitOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        habitOverlayOffset = UIScreen.main.bounds.width   // slide back out
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showHabitOverlay  = false
                        habitOverlayOffset = UIScreen.main.bounds.width
                    }
                })
                .offset(x: habitOverlayOffset)      // horizontal offset, not vertical
                .zIndex(2)                          // above main views, below payment if you like
            }
            
            // Overlay CommentSheetOverlay when showCommentSheetOverlay is true
            if showCommentSheetOverlay, let params = commentSheetOverlayParams {
                CommentSheetOverlay(
                    postId: params.postId,
                    cardWidth: params.cardWidth,
                    cardHeight: params.cardHeight,
                    maxCommentLength: params.maxCommentLength,
                    submitComment: params.submitComment,
                    timeAgo: params.timeAgo,
                    shimmerOpacity: params.shimmerOpacity,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            commentSheetOverlayOffset = UIScreen.main.bounds.width
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCommentSheetOverlay = false
                            commentSheetOverlayOffset = UIScreen.main.bounds.width
                            commentSheetOverlayParams = nil
                        }
                    }
                )
                .offset(x: commentSheetOverlayOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) { commentSheetOverlayOffset = 0 }
                }
                .zIndex(3)  // Highest z-index to appear above everything
            }
        }
        .onChange(of: showFriendsView) { oldValue, isShowing in
            if isShowing {
                friendsViewOffset = UIScreen.main.bounds.width
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        friendsViewOffset = 0
                    }
                }
            } else {
                hasAnimatedFriendsIn = false
                friendsViewOffset = UIScreen.main.bounds.width
            }
        }
        .sheet(isPresented: $showInviteAcceptanceView) {
            print("🎭 [OverlayViews] InviteAcceptanceView sheet dismissed")
            // Clear pending data when sheet is dismissed
            pendingInviteData = nil
        } content: {
            if let inviteData = pendingInviteData {
                InviteAcceptanceView(
                    inviterId: inviteData.inviterId,
                    habitId: inviteData.habitId,
                    branchInviteData: inviteData
                )
                .environmentObject(authManager)
                .environmentObject(friendsManager)
                .environmentObject(habitManager)
                .onAppear {
                    print("🎭 [OverlayViews] InviteAcceptanceView sheet presenting with data: \(inviteData.inviterName)")
                }
            } else {
                Text("No invite data available")
                    .foregroundColor(.white)
                    .background(Color.black)
                    .onAppear {
                        print("❌ [OverlayViews] InviteAcceptanceView sheet presenting but no invite data available")
                    }
            }
        }
        .onChange(of: showInviteAcceptanceView) { oldValue, newValue in
            print("📊 [OverlayViews] showInviteAcceptanceView changed to: \(newValue)")
            if newValue {
                print("🎯 [OverlayViews] Invite acceptance view should now be visible")
                if pendingInviteData != nil {
                    print("✅ [OverlayViews] Pending invite data is available")
                } else {
                    print("❌ [OverlayViews] No pending invite data - sheet will show error")
                }
            }
        }
    }
}

// MARK: - Add Habit Overlay Wrapper

private struct AddHabitOverlay: View {
    var onDismiss: () -> Void

    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var customHabitManager: CustomHabitManager

    var body: some View {
        AddHabitView()
            .environmentObject(habitManager)
            .environmentObject(authManager)
            .environmentObject(friendsManager)
            .environmentObject(customHabitManager)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DismissAddHabitOverlay"))) { _ in
                onDismiss()
            }
    }
}

private struct HabitOverlay: View {
    var onDismiss: () -> Void

    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var customHabitManager: CustomHabitManager

    var body: some View {
        HabitView(onDismiss: onDismiss)
            .environmentObject(authManager)
            .environmentObject(habitManager)
            .environmentObject(friendsManager)
            .environmentObject(customHabitManager)

    }
} 