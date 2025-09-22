import SwiftUI
struct CommentSheet: View {
    // All the state and bindings you need
    @Binding var newCommentText: String
    @Binding var isSubmittingComment: Bool
    @Binding var replyingToComment: Comment?
    @FocusState var isCommentFieldFocused: Bool
    @Binding var scrollAtTop: Bool
    @Binding var showingComments: Bool
    @Binding var commentDetent: PresentationDetent
    
    /// We only need the post ID to look up the latest data from FeedManager each time the
    /// view is recomputed. Passing the whole `FeedPost` by value meant the sheet kept an
    /// outdated snapshot, so avatars that arrived after the first network refresh never
    /// appeared until the sheet was reopened.
    let postId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let maxCommentLength: Int
    let submitComment: () -> Void
    let dismissGesture: AnyGesture<Void>
    let timeAgo: (Date) -> String
    let shimmerOpacity: Double
    @Binding var isLoadingComments: Bool

    // Access to the live feed data
    @EnvironmentObject private var feedManager: FeedManager
    
    // 🆕 NEW: Smart comment loading state
    @State private var cachedComments: [Comment] = []
    @State private var hasLoadedComments = false
    @State private var isRefreshingComments = false
    
    // State for highlighting parent comments when @mention is tapped
    @State private var highlightedCommentId: UUID?

    // Convenience computed var that always returns the most up-to-date post instance.
    private var currentPost: FeedPost? {
        feedManager.feedPosts.first(where: { $0.postId == postId })
    }
    
    // 🆕 NEW: Use cached comments or fallback to post comments
    private var displayComments: [Comment] {
        // If we have loaded cached comments, use those
        // Otherwise, use the comments from the current post
        if hasLoadedComments {
            return cachedComments
        }
        return currentPost?.comments ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            DragHandle(scrollAtTop: $scrollAtTop, dismissGesture: dismissGesture)
            CommentsHeader()

            if let post = currentPost {
                CommentsScrollView(
                    isLoadingComments: isLoadingComments || isRefreshingComments,
                    currentPostComments: displayComments, // 🆕 Use smart cached comments
                    postAuthorId: post.userId,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    shimmerOpacity: shimmerOpacity,
                    timeAgo: timeAgo,
                    scrollAtTop: $scrollAtTop,
                    replyingToComment: $replyingToComment,
                    highlightedCommentId: $highlightedCommentId,
                    onReply: { replyingToComment = $0 },
                    onUserTap: { userId, userName, userAvatarUrl in
                        handleUserTap(userId: userId, userName: userName, userAvatarUrl: userAvatarUrl)
                    }
                )
            } else {
                // Safety fallback – should never happen unless post removed remotely.
                Text("This post is no longer available.")
                    .foregroundColor(.gray)
                    .padding()
            }

            CommentsInputBar(
                newCommentText: $newCommentText,
                isSubmittingComment: $isSubmittingComment,
                replyingToComment: $replyingToComment,
                isCommentFieldFocused: _isCommentFieldFocused,
                maxCommentLength: maxCommentLength,
                submitComment: submitComment
            )
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // 🆕 NEW: Load comments when sheet appears using smart caching
            Task {
                await loadCommentsWhenSheetOpens()
            }
        }
        .onChange(of: showingComments) { _, isShowing in
            // Reset state when sheet is dismissed
            if !isShowing {
                hasLoadedComments = false
                cachedComments = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commentsUpdated)) { notification in
            // 🆕 NEW: Update comments when backend data changes
            if let userInfo = notification.userInfo,
               let updatedPostId = userInfo["postId"] as? String,
               let freshComments = userInfo["comments"] as? [Comment],
               updatedPostId == postId.uuidString {
                print("🔔 [CommentSheet] Received comment update notification for post \(postId.uuidString.prefix(8))")
                
                // Update cached comments with fresh data
                cachedComments = freshComments
                hasLoadedComments = true
                
                print("📱 [CommentSheet] Updated displayed comments: \(freshComments.count) comments")
            }
        }
    }
    
    // 🆕 NEW: Smart comment loading when sheet opens
    @MainActor
    private func loadCommentsWhenSheetOpens() async {
        guard !hasLoadedComments else { return }
        
        print("💾 [CommentSheet] Loading comments for post \(postId.uuidString.prefix(8)) when sheet opens")
        
        // Set loading state
        isRefreshingComments = true
        
        // Use FeedManager's smart cache loading
        let comments = await feedManager.loadCommentsForSheet(postId: postId)
        
        // Update our local state
        cachedComments = comments
        hasLoadedComments = true
        
        print("✅ [CommentSheet] Loaded \(comments.count) comments from smart cache")
        
        isRefreshingComments = false
    }

    // MARK: – Handle user tap to open profile
    private func handleUserTap(userId: String, userName: String?, userAvatarUrl: String?) {
        // Dismiss comments sheet first
        showingComments = false

        // Present the UserAccount overlay after the sheet dismisses (delay ≈ animation duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: Notification.Name("TriggerUserAccountOverlay"),
                object: nil,
                userInfo: [
                    "userId": userId,
                    "userName": userName ?? "",
                    "userAvatarUrl": userAvatarUrl ?? ""
                ]
            )
        }
    }
}

struct DragHandle: View {
    @Binding var scrollAtTop: Bool
    let dismissGesture: AnyGesture<Void>

    var body: some View {
        VStack {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 48, height: 6)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }
}

struct CommentsHeader: View {
    var body: some View {
        HStack {
            Spacer()
            Text("comments")
                .jtStyle(.body)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct CommentsScrollView: View {
    let isLoadingComments: Bool
    let currentPostComments: [Comment]
    let postAuthorId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let shimmerOpacity: Double
    let timeAgo: (Date) -> String
    @Binding var scrollAtTop: Bool
    @Binding var replyingToComment: Comment?
    @Binding var highlightedCommentId: UUID?
    let onReply: (Comment) -> Void
    let onUserTap: ((String, String?, String?) -> Void)?

    var body: some View {
        ScrollView {
            // probe lets us know when list is at the very top
            GeometryReader { geo in
                Color.clear
                    .preference(key: TopOffsetKey.self,
                                value: geo.frame(in: .named("commentScroll")).minY)
            }
            .frame(height: 0)

            LazyVStack(spacing: 16) {
                if isLoadingComments {
                    LoadingCommentsView(cardHeight: cardHeight, cardWidth: cardWidth, shimmerOpacity: shimmerOpacity)
                        .onAppear {
                            print("💬 [CommentsScrollView] Showing LoadingCommentsView - isLoadingComments: \(isLoadingComments)")
                        }
                } else if currentPostComments.isEmpty {
                    EmptyCommentsView(cardHeight: cardHeight, cardWidth: cardWidth)
                        .onAppear {
                            print("💬 [CommentsScrollView] Showing EmptyCommentsView - comments count: \(currentPostComments.count)")
                        }
                } else {
                    CommentListView(
                        comments: currentPostComments,
                        postAuthorId: postAuthorId,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        timeAgo: timeAgo,
                        onReply: onReply,
                        onUserTap: onUserTap,
                        highlightedCommentId: $highlightedCommentId
                    )
                    .onAppear {
                        print("💬 [CommentsScrollView] Showing CommentListView - comments count: \(currentPostComments.count)")
                        for (index, comment) in currentPostComments.enumerated() {
                            print("   - Comment \(index): \(comment.userName) - '\(comment.content.prefix(30))...'")
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(minHeight: 0, maxHeight: .infinity)
        .coordinateSpace(name: "commentScroll")
        .onPreferenceChange(TopOffsetKey.self) { y in
            scrollAtTop = y >= 0
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct CommentsInputBar: View {
    @Binding var newCommentText: String
    @Binding var isSubmittingComment: Bool
    @Binding var replyingToComment: Comment?
    @FocusState var isCommentFieldFocused: Bool
    let maxCommentLength: Int
    let submitComment: () -> Void
    
    // Access the auth manager to get the current user's avatar
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some View {
        VStack(alignment: .leading) {
            // "Replying to …" pill
            if let reply = replyingToComment {
                HStack(spacing: 4) {
                    Text("replying to \(reply.userName)")
                        .font(.ebGaramondCaption)
                        .foregroundColor(.gray)
                    Button(action: {
                        replyingToComment = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                // Current user's avatar
                if let user = authManager.currentUser {
                    CachedAvatarView(url80: user.avatarUrl80, url200: user.avatarUrl200, urlOriginal: user.avatarUrlOriginal, size: .small)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 32, height: 32)
                }

                // Text field
                HStack {
                    TextField(replyingToComment == nil
                                ? "add a comment..."
                                : "add a reply...",
                              text: $newCommentText,
                              axis: .vertical)
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .focused($isCommentFieldFocused)
                        .foregroundColor(.white)
                        .onChange(of: newCommentText) { oldValue, txt in
                            if txt.count > maxCommentLength {
                                newCommentText = String(txt.prefix(maxCommentLength))
                            }
                        }
                    
                    Button(action: submitComment) {
                        Group {
                            if isSubmittingComment {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Text("Post")
                                    .jtStyle(.body)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(newCommentText
                                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSubmittingComment)
                    .foregroundColor(newCommentText.isEmpty ? .gray : .blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color.black.ignoresSafeArea())
    }
}

private struct TopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Overlay Wrapper for Swipe-in Presentation
struct CommentSheetOverlay: View {
    let postId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let maxCommentLength: Int
    let submitComment: () -> Void
    let timeAgo: (Date) -> String
    let shimmerOpacity: Double
    let onDismiss: (() -> Void)?
    
    // Gesture state
    @State private var isHorizontalDragging = false
    @State private var dragOffset: CGFloat = 0
    
    // Comment sheet state
    @State private var newCommentText = ""
    @State private var isSubmittingComment = false
    @State private var replyingToComment: Comment?
    @State private var scrollAtTop = false
    @State private var commentDetent: PresentationDetent = .medium
    @State private var isLoadingComments = false
    @State private var highlightedCommentId: UUID?
    
    var body: some View {
        ZStack {
            CommentSheet(
                newCommentText: $newCommentText,
                isSubmittingComment: $isSubmittingComment,
                replyingToComment: $replyingToComment,
                scrollAtTop: $scrollAtTop,
                showingComments: .constant(true), // Always true in overlay
                commentDetent: $commentDetent,
                postId: postId,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                maxCommentLength: maxCommentLength,
                submitComment: submitComment,
                dismissGesture: AnyGesture(DragGesture().onChanged { _ in }.map { _ in }),
                timeAgo: timeAgo,
                shimmerOpacity: shimmerOpacity,
                isLoadingComments: $isLoadingComments
            )
            .offset(x: dragOffset)
            .gesture(edgeSwipeGesture)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        }
        .preferredColorScheme(.dark)
    }
    
    private func dismissView() {
        if let callback = onDismiss {
            callback()
        }
    }
    
    // MARK: – Edge-swipe gesture (horizontal priority)
    private var edgeSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Start only from left edge & prioritise horizontal drags
                if value.startLocation.x < 80 && abs(value.translation.width) > abs(value.translation.height) {
                    if !isHorizontalDragging { isHorizontalDragging = true }
                    let progress = min(value.translation.width / 100, 1.0)
                    dragOffset = value.translation.width * 0.8 * progress
                }
            }
            .onEnded { value in
                if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                    dismissView()
                } else {
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) { dragOffset = 0 }
                }
                isHorizontalDragging = false
            }
    }
}
