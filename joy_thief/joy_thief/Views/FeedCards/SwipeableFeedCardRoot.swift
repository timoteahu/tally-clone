import SwiftUI
import Kingfisher

struct SwipeableFeedCard: View {
    let feedPost: FeedPost
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardIndex: Int
    let currentIndex: Int
    let isCurrentCard: Bool
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    let onTap: () -> Void
    let parentDragOffset: CGFloat
    let enableGestures: Bool
    
    @State private var verticalDragOffset = CGSize.zero
    @State private var horizontalDragOffset = CGSize.zero
    @State private var isFlipped = false
    @State private var cachedImage: UIImage?
    @State private var cachedSelfieImage: UIImage? // Cache for selfie image
    @State private var cachedContentImage: UIImage? // Cache for content image
    @State private var showingSelfieAsMain = false // Track which image is displayed as main
    @State private var isGestureReady: Bool
    @State private var showingComments = false // Track if comments are visible
    @State private var commentsOffset: CGFloat = 0 // Offset for comments animation
    @State private var newCommentText = "" // Text for new comment
    @State private var isSubmittingComment = false // Track if comment is being submitted
    @State private var replyingToComment: Comment? = nil // Track which comment we're replying to
    @State private var isLoadingComments = false // Track if comments are being refreshed
    @State private var shimmerOpacity: Double = 0.3 // For skeleton animation
    @State private var cachedCommentCount: Int = 0 // Preserve comment count during loading
    @State private var showCommentLengthError = false // Show alert when comment exceeds limit
    @State private var downloadProgress: Double = 0.0
    @StateObject private var imageCacheManager = ImageCacheManager.shared
    
    // Caption editing state
    @State private var isEditingCaption = false
    @State private var editingCaption = ""
    @State private var isUpdatingCaption = false
    
    // Environment objects to access habit data
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var feedManager: FeedManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    // Callback to update parent drag state for smooth animation
    let onDragChanged: ((CGFloat) -> Void)?
    
    @State private var isCommentFieldFocused: Bool = false
    
    private let maxCommentLength: Int = 150 // Maximum allowed characters for a comment
    
    @State private var scrollAtTop = true // Track if comments are scrolled to top
    @State private var commentDetent: PresentationDetent = .medium
    
    @State private var cachedStreakValue: Int = 0
    @State private var cachedHabitTypeDisplayName: String = ""
    @State private var cachedHabitType: String = ""
    @State private var cachedHabitProgress: (current: Int, total: Int)? = nil
    
    init(feedPost: FeedPost, cardWidth: CGFloat, cardHeight: CGFloat, cardIndex: Int, currentIndex: Int, isCurrentCard: Bool, onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void, onTap: @escaping () -> Void, parentDragOffset: CGFloat = 0, onDragChanged: ((CGFloat) -> Void)? = nil, enableGestures: Bool = true) {
        self.feedPost = feedPost
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.cardIndex = cardIndex
        self.currentIndex = currentIndex
        self.isCurrentCard = isCurrentCard
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.onTap = onTap
        self.parentDragOffset = parentDragOffset
        self.onDragChanged = onDragChanged
        self.enableGestures = enableGestures
        self._isGestureReady = State(initialValue: isCurrentCard)

        let baseKey = feedPost.postId.uuidString

        // Initialize cached images using FeedCardImageHelpers
        let (image, selfieImage, contentImage) = FeedCardImageHelpers.initializeCachedImages(baseKey: baseKey)
        self._cachedImage = State(initialValue: image)
        self._cachedSelfieImage = State(initialValue: selfieImage)
        self._cachedContentImage = State(initialValue: contentImage)
    }
    
    var body: some View {
        FeedCardContent(
            feedPost: feedPost,
            currentPost: currentPost,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            isFlipped: $isFlipped,
            showingSelfieAsMain: $showingSelfieAsMain,
            cachedImage: $cachedImage,
            cachedSelfieImage: $cachedSelfieImage,
            cachedContentImage: $cachedContentImage,
            downloadProgress: $downloadProgress,
            showingComments: $showingComments,
            commentsOffset: $commentsOffset,
            newCommentText: $newCommentText,
            isSubmittingComment: $isSubmittingComment,
            replyingToComment: $replyingToComment,
            isCommentFieldFocused: $isCommentFieldFocused,
            scrollAtTop: $scrollAtTop,
            commentDetent: $commentDetent,
            isLoadingComments: $isLoadingComments,
            cachedCommentCount: $cachedCommentCount,
            shimmerOpacity: shimmerOpacity,
            maxCommentLength: maxCommentLength,
            isEditingCaption: $isEditingCaption,
            editingCaption: $editingCaption,
            isUpdatingCaption: $isUpdatingCaption,
            cachedStreakValue: cachedStreakValue,
            cachedHabitTypeDisplayName: cachedHabitTypeDisplayName,
            cachedHabitType: cachedHabitType,
            cachedHabitProgress: cachedHabitProgress,
            cardScale: cardScale,
            cardOpacity: cardOpacity,
            cardOffset: cardOffset,
            verticalDragOffset: verticalDragOffset,
            enableGestures: enableGestures,
            isCurrentCard: isCurrentCard,
            isGestureReady: isGestureReady,
            cardGesture: cardGesture,
            onFlipCard: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFlipped.toggle()
                }
            },
            onShowComments: {
                withAnimation(.easeOut(duration: 0.3)) {
                    showingComments = true
                    commentsOffset = 0
                }
            },
            onSubmitComment: submitComment,
            onStartEditingCaption: startEditingCaption,
            onUpdateCaption: updateCaption,
            onCancelCaptionEditing: cancelCaptionEditing
        )
        .environmentObject(habitManager)
        .environmentObject(feedManager)
        .environmentObject(authManager)
        .onAppear {
            isGestureReady = true
            FeedCardImageHelpers.loadPostImageWithCaching(
                feedPost: currentPost,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                cachedImage: $cachedImage,
                cachedSelfieImage: $cachedSelfieImage,
                cachedContentImage: $cachedContentImage,
                downloadProgress: $downloadProgress,
                imageCacheManager: imageCacheManager
            )
            cachedCommentCount = currentPost.comments.count
            cachedStreakValue = FeedCardHelpers.computeStreakValue(post: currentPost, habitManager: habitManager)
            cachedHabitTypeDisplayName = FeedCardHelpers.computeHabitTypeDisplayName(post: currentPost, habitManager: habitManager)
            cachedHabitType = FeedCardHelpers.computeHabitType(post: currentPost, habitManager: habitManager)
            cachedHabitProgress = FeedCardHelpers.computeHabitProgress(post: currentPost, habitManager: habitManager)
        }
        .onChange(of: showingComments) { oldValue, newValue in
            FeedCardHelpers.handleCommentsChange(
                newValue: newValue,
                currentPost: currentPost,
                feedManager: feedManager,
                cachedCommentCount: $cachedCommentCount,
                isLoadingComments: $isLoadingComments,
                shimmerOpacity: $shimmerOpacity
            )
        }
        .onChange(of: isCurrentCard) { oldValue, newValue in
            if newValue {
                verticalDragOffset = .zero
                horizontalDragOffset = .zero
                isGestureReady = true
                FeedCardImageHelpers.loadPostImageWithCaching(
                    feedPost: currentPost,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    cachedImage: $cachedImage,
                    cachedSelfieImage: $cachedSelfieImage,
                    cachedContentImage: $cachedContentImage,
                    downloadProgress: $downloadProgress,
                    imageCacheManager: imageCacheManager
                )
            } else {
                if isEditingCaption {
                    cancelCaptionEditing()
                }
                if showingComments {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showingComments = false
                        commentsOffset = 0
                    }
                }
            }
        }
        .onChange(of: currentPost.comments.count) { oldValue, newCount in
            if !isLoadingComments {
                cachedCommentCount = newCount
            }
        }
        .onChange(of: isCommentFieldFocused) { oldValue, focus in
            if focus && commentDetent != .large {
                commentDetent = .large
            }
        }
        .onChange(of: habitManager.habits) { oldValue, _ in
            cachedStreakValue = FeedCardHelpers.computeStreakValue(post: currentPost, habitManager: habitManager)
            cachedHabitTypeDisplayName = FeedCardHelpers.computeHabitTypeDisplayName(post: currentPost, habitManager: habitManager)
            cachedHabitType = FeedCardHelpers.computeHabitType(post: currentPost, habitManager: habitManager)
            cachedHabitProgress = FeedCardHelpers.computeHabitProgress(post: currentPost, habitManager: habitManager)
        }
        .alert("Comment too long", isPresented: $showCommentLengthError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Comments must be 150 characters or fewer.")
        }
    }
    
    // MARK: - Computed Properties
    
    // Computed property to get the current post from FeedManager (for real-time updates)
    private var currentPost: FeedPost {
        // Find the post in FeedManager's array to get real-time updates
        if let updatedPost = feedManager.feedPosts.first(where: { $0.postId == feedPost.postId }) {
            // Only log if the comment count is different (to avoid spam)
            if updatedPost.comments.count != feedPost.comments.count {
                print("🔄 [SwipeableFeedCard] currentPost found updated post with \(updatedPost.comments.count) comments (was \(feedPost.comments.count))")
            }
            return updatedPost
        }
        // Fallback to the original post if not found
        print("⚠️ [SwipeableFeedCard] currentPost falling back to original feedPost with \(feedPost.comments.count) comments")
        return feedPost
    }
    
    private var cardScale: CGFloat {
        FeedCardHelpers.calculateCardScale(
            isCurrentCard: isCurrentCard,
            cardIndex: cardIndex,
            currentIndex: currentIndex,
            verticalDragOffset: verticalDragOffset
        )
    }
    
    private var cardOpacity: Double {
        FeedCardHelpers.calculateCardOpacity(
            isCurrentCard: isCurrentCard,
            verticalDragOffset: verticalDragOffset
        )
    }
    
    private var cardOffset: CGFloat {
        isCurrentCard ? verticalDragOffset.height : 0
    }
    
    private var cardGesture: AnyGesture<Void> {
        FeedCardGestureHandler.createCardGesture(
            isCurrentCard: isCurrentCard,
            isGestureReady: isGestureReady,
            showingComments: showingComments,
            cardHeight: cardHeight,
            commentsOffset: $commentsOffset,
            verticalDragOffset: $verticalDragOffset,
            showingCommentsBinding: $showingComments,
            isCommentFieldFocused: $isCommentFieldFocused,
            onDragChanged: onDragChanged,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
        )
    }
    
    // MARK: - Action Methods
    
    private func submitComment() {
        FeedCardActions.submitComment(
            newCommentText: newCommentText,
            maxCommentLength: maxCommentLength,
            currentPost: currentPost,
            replyingToComment: replyingToComment,
            authManager: authManager,
            feedManager: feedManager,
            isSubmittingComment: $isSubmittingComment,
            showCommentLengthError: $showCommentLengthError,
            newCommentTextBinding: $newCommentText,
            replyingToCommentBinding: $replyingToComment,
            isCommentFieldFocused: $isCommentFieldFocused
        )
    }
    
    private func startEditingCaption(_ currentCaption: String) {
        FeedCardActions.startEditingCaption(
            currentCaption: currentCaption,
            editingCaption: $editingCaption,
            isEditingCaption: $isEditingCaption,
            isCommentFieldFocused: $isCommentFieldFocused
        )
    }
    
    private func updateCaption() async {
        await FeedCardActions.updateCaption(
            editingCaption: editingCaption,
            currentPost: currentPost,
            authManager: authManager,
            feedManager: feedManager,
            isUpdatingCaption: $isUpdatingCaption,
            isEditingCaption: $isEditingCaption,
            isCommentFieldFocused: $isCommentFieldFocused
        )
    }
    
    private func cancelCaptionEditing() {
        FeedCardActions.cancelCaptionEditing(
            currentPost: currentPost,
            editingCaption: $editingCaption,
            isEditingCaption: $isEditingCaption,
            isCommentFieldFocused: $isCommentFieldFocused
        )
    }
}

#Preview {
    let samplePost = FeedPost(
        postId: UUID(),
        habitId: nil,
        caption: "Great workout session today!",
        createdAt: Date(),
        isPrivate: false,
        imageUrl: nil,
        selfieImageUrl: nil,
        contentImageUrl: nil,
        userId: UUID(),
        userName: "John Doe",
        userAvatarUrl80: nil,
        userAvatarUrl200: nil,
        userAvatarUrlOriginal: nil,
        userAvatarVersion: nil,
        streak: 7,
        habitType: nil,
        habitName: "Gym Session",
        penaltyAmount: 5.0,
        comments: []
    )
    
    SwipeableFeedCard(
        feedPost: samplePost,
        cardWidth: 300,
        cardHeight: 480,
        cardIndex: 0,
        currentIndex: 0,
        isCurrentCard: true,
        onSwipeLeft: {},
        onSwipeRight: {},
        onTap: {},
        parentDragOffset: 0,
        onDragChanged: { _ in },
        enableGestures: true
    )
    .background(Color.black)
} 