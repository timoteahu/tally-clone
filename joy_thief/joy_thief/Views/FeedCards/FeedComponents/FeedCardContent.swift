import SwiftUI

struct FeedCardContent: View {
    let feedPost: FeedPost
    let currentPost: FeedPost
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    
    @Binding var isFlipped: Bool
    @Binding var showingSelfieAsMain: Bool
    @Binding var cachedImage: UIImage?
    @Binding var cachedSelfieImage: UIImage?
    @Binding var cachedContentImage: UIImage?
    @Binding var downloadProgress: Double
    @Binding var showingComments: Bool
    @Binding var commentsOffset: CGFloat
    @Binding var newCommentText: String
    @Binding var isSubmittingComment: Bool
    @Binding var replyingToComment: Comment?
    @Binding var isCommentFieldFocused: Bool
    @Binding var scrollAtTop: Bool
    @Binding var commentDetent: PresentationDetent
    @Binding var isLoadingComments: Bool
    @Binding var cachedCommentCount: Int
    let shimmerOpacity: Double
    let maxCommentLength: Int
    
    @Binding var isEditingCaption: Bool
    @Binding var editingCaption: String
    @Binding var isUpdatingCaption: Bool
    
    let cachedStreakValue: Int
    let cachedHabitTypeDisplayName: String
    let cachedHabitType: String
    let cachedHabitProgress: (current: Int, total: Int)?
    
    let cardScale: CGFloat
    let cardOpacity: Double
    let cardOffset: CGFloat
    let verticalDragOffset: CGSize
    let enableGestures: Bool
    let isCurrentCard: Bool
    let isGestureReady: Bool
    let cardGesture: AnyGesture<Void>
    
    let onFlipCard: () -> Void
    let onShowComments: () -> Void
    let onSubmitComment: () -> Void
    let onStartEditingCaption: (String) -> Void
    let onUpdateCaption: () async -> Void
    let onCancelCaptionEditing: () -> Void
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    
    var body: some View {
        ZStack {
            cardFlipStack
            
            // Comments button positioned in bottom-right corner - BeReal style
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CommentsButton(
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        isLoadingComments: isLoadingComments,
                        cachedCommentCount: cachedCommentCount,
                        currentCommentCount: currentPost.comments.count,
                        onTap: onShowComments
                    )
                }
                .padding(.bottom, cardHeight * 0.021)
                .padding(.trailing, cardWidth * 0.035)
            }
        }
        .ignoresSafeArea(.keyboard)
        .frame(width: cardWidth, height: cardHeight)
        .background(cardBackground)
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .contentShape(Rectangle()) 
        .offset(y: cardOffset)
        .modifier(ConditionalGestureModifier(enable: enableGestures, gesture: cardGesture))
        .onTapGesture(coordinateSpace: .local) { location in
            // Only respond to taps within the card's actual bounds
            if location.x >= 0 && location.x <= cardWidth && 
               location.y >= 0 && location.y <= cardHeight &&
               isCurrentCard && !showingComments {
                if isEditingCaption && isFlipped {
                    onCancelCaptionEditing()
                } else if !isEditingCaption {
                    onFlipCard()
                }
            }
        }
        .sheet(isPresented: $showingComments) {
            commentSheetPresentation
        }
    }
    
    // MARK: - Card Components
    
    private var cardFlipStack: some View {
        ZStack {
            if isFlipped {
                VerifiedCardBack(
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    userName: currentPost.userName,
                    habitName: habitNameDisplay,
                    habitTypeDisplayName: cachedHabitTypeDisplayName,
                    habitType: cachedHabitType,
                    createdAt: currentPost.createdAt,
                    streakValue: cachedStreakValue,
                    progressCurrent: cachedHabitProgress?.current,
                    progressTotal: cachedHabitProgress?.total,
                    penaltyAmount: Double(penaltyAmount),
                    captionSectionBack: AnyView(captionSectionBack),
                    formatDate: formatDate
                )
                .transition(.opacity)
            } else {
                VerifiedCardFront(
                    showingSelfieAsMain: showingSelfieAsMain,
                    cachedSelfieImage: cachedSelfieImage,
                    cachedContentImage: cachedContentImage,
                    cachedImage: cachedImage,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    onOverlayTap: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSelfieAsMain.toggle()
                        }
                    },
                    downloadProgress: downloadProgress,
                    expectsBothImages: currentPost.selfieImageUrl != nil && currentPost.contentImageUrl != nil
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isFlipped)
    }
    
    private var commentSheetPresentation: some View {
        CommentSheet(
            newCommentText: $newCommentText,
            isSubmittingComment: $isSubmittingComment,
            replyingToComment: $replyingToComment,
            scrollAtTop: $scrollAtTop,
            showingComments: $showingComments,
            commentDetent: $commentDetent,
            postId: currentPost.postId,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            maxCommentLength: maxCommentLength,
            submitComment: onSubmitComment,
            dismissGesture: AnyGesture(dismissGesture),
            timeAgo: timeAgo,
            shimmerOpacity: shimmerOpacity,
            isLoadingComments: $isLoadingComments,

        )
        .presentationDetents([.medium, .large], selection: $commentDetent)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cardWidth * 0.035)  // Subtle rounding to match BeReal exactly
            .fill(Color(red: 0.08, green: 0.09, blue: 0.12, opacity: 0.97))
            .overlay(
                RoundedRectangle(cornerRadius: cardWidth * 0.035)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.3),
                radius: isCurrentCard ? 20 : 10,
                x: 0,
                y: 4
            )
    }
    
    // MARK: - Caption Components
    
    private var captionSectionBack: some View {
        VStack(alignment: .leading, spacing: cardHeight * 0.01) {
            captionHeaderText
            captionContentView
        }
        .padding(.horizontal, cardWidth * 0.04)
        .padding(.vertical, cardHeight * 0.015)
        .background(captionSectionBackground)
    }
    
    private var captionHeaderText: some View {
        Text("Caption")
            .jtStyle(.caption)
            .foregroundColor(.white.opacity(0.6))
    }
    
    private var captionContentView: some View {
        Group {
            if isEditingCaption && isCurrentUserPost {
                captionEditingView
            } else {
                captionDisplayView
            }
        }
    }
    
    private var captionEditingView: some View {
        CaptionEditingView(
            editingCaption: $editingCaption,
            isUpdatingCaption: isUpdatingCaption,
            isCommentFieldFocused: $isCommentFieldFocused,
            cardWidth: cardWidth,
            onUpdate: {
                Task {
                    await onUpdateCaption()
                }
            },
            onCancel: onCancelCaptionEditing
        )
    }
    
    private var captionDisplayView: some View {
        CaptionDisplayView(
            caption: currentPost.caption,
            isCurrentUserPost: isCurrentUserPost,
            onStartEditing: onStartEditingCaption
        )
    }
    
    private var captionSectionBackground: some View {
        RoundedRectangle(cornerRadius: cardWidth * 0.025)
            .fill(Color.black.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: cardWidth * 0.025)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    // MARK: - Helper Properties
    
    private var penaltyAmount: Float {
        FeedCardHelpers.calculatePenaltyAmount(post: currentPost, habitManager: habitManager)
    }
    
    private var habitNameDisplay: String? {
        FeedCardHelpers.getHabitNameDisplay(post: currentPost, habitManager: habitManager)
    }
    
    // Helper computed property to check if current user owns this post
    private var isCurrentUserPost: Bool {
        guard let currentUserId = authManager.currentUser?.id,
              let postUserId = UUID(uuidString: currentUserId) else {
            return false
        }
        return postUserId == currentPost.userId
    }
    
    private func formatDate(_ date: Date) -> String {
        return date.formattedForComment
    }
    
    private func timeAgo(from date: Date) -> String {
        FeedCardHelpers.timeAgo(from: date)
    }
    
    // Add dismiss gesture
    private var dismissGesture: AnyGesture<Void> {
        AnyGesture(
        DragGesture().onEnded { value in
            guard showingComments, scrollAtTop else { return }

            let fling = value.predictedEndTranslation.height
            let threshold: CGFloat = 60

            guard fling > threshold else { return }

            // If at .large OR keyboard is up, always collapse to .medium and dismiss keyboard
            if commentDetent == .large || isCommentFieldFocused {
                withAnimation(.spring()) {
                    commentDetent = .medium
                    isCommentFieldFocused = false
                }
            } else {
                withAnimation(.spring()) {
                    showingComments = false
                }
            }
        }
        .map{ _ in }
        )
    }
}

// Helper modifier to conditionally attach a gesture without triggering type mismatch in ternary
private struct ConditionalGestureModifier<G: Gesture>: ViewModifier {
    let enable: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enable {
            content.simultaneousGesture(gesture)
        } else {
            content
        }
    }
} 