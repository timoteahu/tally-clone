//
//  UserFeedView.swift
//  joy_thief
//
//  Created by Timothy Hu on 5/28/25.
//


import SwiftUI
import Charts


struct UserFeedView: View {
   let showFriendsView: () -> Void // Add closure for showing FriendsView
   let showProfileView: () -> Void // Add closure for showing Profile overlay 
   let onProfileViewDismissed: () -> Void // Callback when profile view is dismissed
   let triggerUserAccountOverlay: (String, String?, String?) -> Void // Show any user's profile overlay
  
   @State private var isProfileViewShowing = false
   @State private var isFriendsViewShowing = false
   @EnvironmentObject var authManager: AuthenticationManager
   @EnvironmentObject var habitManager: HabitManager
   @EnvironmentObject var friendsManager: FriendsManager
   @EnvironmentObject var feedManager: FeedManager
   @EnvironmentObject var notificationManager: NotificationManager
   @EnvironmentObject var paymentManager: PaymentManager
   @State private var currentPostIndex = 0
   @State private var sharedDragOffset: CGFloat = 0
   @State private var previousPostCount = 0
   @State private var scrollProxy: ScrollViewProxy? = nil
   @State private var pendingScrollPostId: String? = nil
   @State private var showAlert = false
   @State private var alertTitle = ""
   @State private var alertMessage = ""
   @State private var pressedProfileId: String? = nil
  
   // Notification dot logic
   private var hasIncomingFriendRequests: Bool {
       let hasRequests = !UnifiedFriendManager.shared.receivedRequests.isEmpty
       return hasRequests
   }
   private var needsPaymentSetup: Bool {
       paymentManager.paymentMethod == nil
   }
  
   var body: some View {
       NavigationView {
           // Navigation bar now floats over the feed; mainContent is padded so the first card
           // isn't hidden behind it.
           ZStack(alignment: .top) {
               AppBackground()
               mainContent
               navigationBar
           }
       }
       .navigationViewStyle(StackNavigationViewStyle()) // Use stack style for consistent behavior
       .refreshable {
           // Use the improved manual refresh method
           await feedManager.manualRefresh()
       }
       .ignoresSafeArea(.keyboard)
       .navigationBarBackButtonHidden(true)
       .preferredColorScheme(.dark)
       .onAppear {
           // OPTIMIZED: Posts are already cached and loaded instantly with comment counts
           // Periodic refresh handles new posts and comments
           // Individual posts will refresh comments when their comment view is opened
          
           // Preload images for the 10 most recent posts to balance speed & bandwidth.
           ImageCacheManager.shared.preloadFeedImages(for: Array(feedManager.feedPosts.prefix(10)))
          
           previousPostCount = feedManager.feedPosts.count
          
           // Setup callback for auto-navigation to new posts
           feedManager.onNewPostsDetected = { newCount in
               // Auto-navigate to the last (newest) post when new posts are loaded
               withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                   currentPostIndex = newCount - 1
               }
           }
          
           // Resume periodic refresh when view appears
           feedManager.resumePeriodicRefresh()
          
           print("📱 [UserFeedView] Appeared with \(feedManager.feedPosts.count) posts - cached comment counts preserved")
          
           // If the app was launched via a comment push, scroll as soon as possible
           if let pendingId = notificationManager.navigateToPostId {
               scrollToPost(pendingId)
           }
       }
       .onDisappear {
           // Pause periodic refresh when view disappears to save battery/bandwidth
           feedManager.pausePeriodicRefresh()
           print("📱 [UserFeedView] Disappeared - paused periodic refresh")
       }
       .onChange(of: feedManager.feedPosts.count) { oldValue, newCount in
           handleNewPostsLoaded(newCount: newCount)
           // Preload images for the top 10 posts (covers all new ones, keeps memory in check).
           ImageCacheManager.shared.preloadFeedImages(for: Array(feedManager.feedPosts.prefix(10)))
           // If a deep-link scroll is pending and the post is now loaded, attempt it
           if let target = pendingScrollPostId, feedManager.feedPosts.contains(where: { $0.postId.uuidString == target }) {
               scrollToPost(target)
           }
       }
       // Listen for push-notification deep links (NavigateToPost)
       .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPost"))) { notification in
           if let userInfo = notification.userInfo,
              let postId = userInfo["postId"] as? String {
               scrollToPost(postId)
           }
       }
       // Listen for Published var changes (cold start support)
       .onReceive(notificationManager.$navigateToPostId.compactMap { $0 }) { postId in
           scrollToPost(postId)
       }
       .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProfileViewDismissed"))) { _ in
           isProfileViewShowing = false
       }
       .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FriendsViewDismissed"))) { _ in
           isFriendsViewShowing = false
       }
       .alert(alertTitle, isPresented: $showAlert) {
           Button("OK") {
               showAlert = false
           }
       } message: {
           Text(alertMessage)
       }
   }
  
   private var navigationBar: some View {
       HStack {
           // Left side - tally logo aligned with house icon
           Text("tally.")
               .font(.custom("EBGaramond-Regular", size: 32))
               .foregroundColor(.white)
               .tracking(0.5)
               .padding(.leading, 24) // Match navbar (16px) + TabBarContent (12px) padding
         
           Spacer()
         
           // Right side - notifications and friends aligned with navbar edge
           HStack(spacing: 20) {
               // Friends button with filled/unfilled logic and notification dot
               Button(action: {
                   isFriendsViewShowing = true
                   showFriendsView()
               }) {
                   ZStack {
                   Image(systemName: isFriendsViewShowing ? "person.2.fill" : "person.2")
                       .foregroundColor(.white)
                       .font(.custom("EBGaramond-Regular", size: 22))
                       .animation(nil, value: isFriendsViewShowing)
                       if hasIncomingFriendRequests {
                           NotificationDot()
                               .offset(x: 12, y: -12)
                       }
                   }
               }
               // Settings button with filled/unfilled logic and notification dot
               Button(action: {
                   isProfileViewShowing = true
                   showProfileView()
               }) {
                   ZStack {
                   Image(systemName: isProfileViewShowing ? "gearshape.fill" : "gearshape")
                       .foregroundColor(.white)
                       .font(.custom("EBGaramond-Regular", size: 22))
                       .animation(nil, value: isProfileViewShowing)
                       if needsPaymentSetup {
                           NotificationDot()
                               .offset(x: 12, y: -12)
                       }
                   }
               }
           }
           .padding(.trailing, 16) // Match navbar horizontal padding
       }
       .frame(height: 44)
       .padding(.top, 4)
   }
  
   private var mainContent: some View {
       GeometryReader { geometry in
           VStack(spacing: 0) {
               if feedManager.feedPosts.isEmpty && feedManager.hasInitialized {
                   // Empty state still needs a little top space so it isn't glued to status bar
                   emptyStateView
                       .padding(.top, topFeedPadding)
                       .frame(height: geometry.size.height)  // fill remaining space
               } else if !feedManager.feedPosts.isEmpty {
                   // Feed list with a small top padding instead of a header spacer
                   ScrollViewReader { proxy in
                       ScrollView(.vertical, showsIndicators: false) {
                           LazyVStack(spacing: UIScreen.main.bounds.height * 0.04) {
                               ForEach(Array(feedManager.feedPosts.enumerated()), id: \.element.postId) { item in
                                   let index = item.offset
                                   let post  = item.element
                                   FeedListCardRow(post: post, index: index)
                                       .id(post.postId.uuidString)
                               }
                           }
                           .padding(.vertical, 8)
                           .padding(.top, topFeedPadding) // initial spacing beneath nav-icons
                       }
                       .onAppear {
                           // Capture the proxy and attempt any pending scroll once available
                           scrollProxy = proxy
                           if let target = pendingScrollPostId {
                               scrollToPost(target)
                           }
                       }
                   }
               }
           }
           // Pin a small spacer below the feed content (similar to top nav overlay)
           .safeAreaInset(edge: .bottom) {
               Color.clear.frame(height: bottomFeedPadding)
           }
       }
   }
  
   private var emptyStateView: some View {
       VStack(spacing: 30) {
           Image(systemName: "photo.on.rectangle.angled")
               .font(.custom("EBGaramond-Regular", size: 80))
               .foregroundColor(.white.opacity(0.3))
          
           VStack(spacing: 12) {
               Text("No posts yet")
                   .jtStyle(.title)
                   .foregroundColor(.white)
              
               Text("When your friends complete their habits,\ntheir posts will appear here automatically")
                   .jtStyle(.body)
                   .foregroundColor(.white.opacity(0.7))
                   .multilineTextAlignment(.center)
                   .lineSpacing(4)
           }
       }
       .frame(maxWidth: .infinity, maxHeight: .infinity)
   }
  
   // MARK: - List Row Wrapper
  
   private func FeedListCardRow(post: FeedPost, index: Int) -> some View {
       let cardWidth  = UIScreen.main.bounds.width  // Full edge-to-edge
       let cardHeight = cardWidth * 1.5


       return VStack(alignment: .leading, spacing: 12) {
           // User info section above the card - BeReal style
           UserInfoHeader(post: post, cardWidth: cardWidth)
               .zIndex(1)
           // Main card - now edge-to-edge with minimal rounding
           SwipeableFeedCard(
               feedPost: post,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cardIndex: index,
               currentIndex: index,
               isCurrentCard: true,
               onSwipeLeft: {},
               onSwipeRight: {},
               onTap: {},
               parentDragOffset: 0,
               onDragChanged: { _ in },
               enableGestures: false
           )
           .zIndex(0)
           .frame(width: cardWidth, height: cardHeight)


           // Caption at the bottom of the card
           if let caption = post.caption, !caption.isEmpty {
               Text(caption)
                   .font(.custom("EBGaramond-Regular", size: 15))
                   .foregroundColor(.white.opacity(0.9))
                   .lineLimit(2)
                   .padding(.horizontal, 8)
                   .padding(.leading, 4)
           }
       }
   }
  
   // MARK: - User Info Header Component
   // This component shows user info and is tappable to navigate to their profile
  
   private func UserInfoHeader(post: FeedPost, cardWidth: CGFloat) -> some View {
       let isPressed = pressedProfileId == post.userId.uuidString
       return HStack(spacing: 10) {
           // Profile picture and user info - make tappable
           Button(action: {
               triggerUserAccountOverlay(
                   post.userId.uuidString,
                   post.userName,
                   post.userAvatarUrl200 ?? post.userAvatarUrl80 ?? post.userAvatarUrlOriginal
               )
           }) {
               HStack(spacing: 10) {
                   // Profile picture
                   if post.userAvatarUrl200 != nil || post.userAvatarUrl80 != nil || post.userAvatarUrlOriginal != nil {
                       CachedAvatarView(
                           url80: post.userAvatarUrl80,
                           url200: post.userAvatarUrl200,
                           urlOriginal: post.userAvatarUrlOriginal,
                           size: .small
                       )
                       .frame(width: 35, height: 35)  // Reduced size to match BeReal proportions
                   } else {
                       // Fallback to initials circle if no avatar
                       Circle()
                           .fill(Color.white.opacity(0.2))
                           .frame(width: 35, height: 35)  // Reduced size to match BeReal proportions
                           .overlay(
                               Text(String(post.userName.prefix(1)).uppercased())
                                   .font(.custom("EBGaramond-Regular", size: 14))  // Adjusted font size
                                   .foregroundColor(.white.opacity(0.9))
                           )
                   }
                  
                   VStack(alignment: .leading, spacing: 1) {
                       Text(post.userName)
                           .font(.custom("EBGaramond-Medium", size: 16))
                           .foregroundColor(.white)
                      
                       Text(timeAgo(from: post.createdAt))
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.6))
                   }
               }
               .scaleEffect(isPressed ? 0.95 : 1.0)
               .animation(.easeInOut(duration: 0.1), value: isPressed)
           }
           .buttonStyle(PlainButtonStyle()) // Prevent default button styling
           .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
               withAnimation(.easeInOut(duration: 0.1)) {
                   pressedProfileId = pressing ? post.userId.uuidString : nil
               }
           }, perform: {})
          
           Spacer()
          
           // Three dots menu button (BeReal style)
           Menu {
               Button("this ain't it bro") {
                   showAlert(title: "", message: "this ain't it bro sent")
               }
               Button(role: .destructive, action: {
                   showAlert(title: "", message: "post reported")
               }) {
                   Label("report", systemImage: "exclamationmark.triangle.fill")
                       .font(.custom("EBGaramond-Regular", size: 17))
                       .foregroundColor(.red) // Apply red directly to the Label
               }
           } label: {
               Image(systemName: "ellipsis")
                   .font(.system(size: 16, weight: .medium))
                   .foregroundColor(.white)
                   .rotationEffect(.degrees(90))
                   .padding(16)
                   .contentShape(Rectangle())
                   .background(Color.clear)
                   .offset(x: 14, y: 8)
           }
           .highPriorityGesture(TapGesture())
           .buttonStyle(PlainButtonStyle()) // Prevent interference with other gestures
       }
       .padding(.horizontal, 16)
   }
  
   // Helper for time-ago string
   private func timeAgo(from date: Date) -> String {
       let interval = Date().timeIntervalSince(date)
       if interval < 60 {
           return "now"
       } else if interval < 3600 {
           let minutes = Int(interval / 60)
           return "\(minutes)m ago"
       } else if interval < 86400 {
           let hours = Int(interval / 3600)
           return "\(hours)h ago"
       } else {
           let days = Int(interval / 86400)
           return "\(days)d ago"
       }
   }
  
   // MARK: - Helper Properties
  
   private let topFeedPadding: CGFloat = 50 // user-adjusted value
   private let bottomFeedPadding: CGFloat = 50
  
   private func handleNewPostsLoaded(newCount: Int) {
       // Only auto-navigate if we have new posts and aren't on the last card already
       if newCount > previousPostCount && currentPostIndex < newCount - 1 {
           withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
               currentPostIndex = newCount - 1
           }
       }
       previousPostCount = newCount
   }
  
   // MARK: - Deep-link scroll helper
   private func scrollToPost(_ postId: String) {
       print("📱 [UserFeedView] scrollToPost called with postId: \(postId)")
       print("📱 [UserFeedView] Current feed posts count: \(feedManager.feedPosts.count)")
       print("📱 [UserFeedView] ScrollProxy available: \(scrollProxy != nil)")
       
       // Ensure the feed contains this post
       guard feedManager.feedPosts.contains(where: { $0.postId.uuidString == postId }) else {
           print("📱 [UserFeedView] Post \(postId) not found in feed, marking as pending")
           // Post not yet loaded – mark as pending and trigger a refresh
           pendingScrollPostId = postId
           Task {
               await feedManager.manualRefresh()
           }
           return
       }

       print("📱 [UserFeedView] Post found in feed")

       // If the proxy is available, perform the scroll. We add a slight delay to ensure
       // the LazyVStack rows have finished their initial layout on cold-start.
       guard let proxy = scrollProxy else {
           print("📱 [UserFeedView] ScrollProxy not available yet, marking as pending")
           pendingScrollPostId = postId // Wait until proxy becomes available
           return
       }

       print("📱 [UserFeedView] ScrollProxy available, preparing to scroll")

       let performScroll = {
           print("📱 [UserFeedView] Performing scroll to \(postId)")
           withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
               proxy.scrollTo(postId, anchor: .center)
           }
           pendingScrollPostId = nil // Clear after successful scroll
           notificationManager.navigateToPostId = nil // Clear global target
           print("📱 [UserFeedView] Scroll completed")
       }


       // If called very early in view lifecycle the rows might not be measured yet; delay slightly.
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
           performScroll()
       }
   }
  
   // MARK: - Alert Helper
   private func showAlert(title: String, message: String) {
       alertTitle = title
       alertMessage = message
       showAlert = true
   }
}


#Preview {
           UserFeedView(showFriendsView: {}, showProfileView: {}, onProfileViewDismissed: {}, triggerUserAccountOverlay: { _, _, _ in })
       .environmentObject(AuthenticationManager.shared)
       .environmentObject(HabitManager.shared)
       .environmentObject(FriendsManager.shared)
       .environmentObject(NotificationManager.shared)
}


