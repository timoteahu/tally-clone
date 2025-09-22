import SwiftUI

// MARK: - FeedCard Gesture Handler
struct FeedCardGestureHandler {
    
    static func createCardGesture(
        isCurrentCard: Bool,
        isGestureReady: Bool,
        showingComments: Bool,
        cardHeight: CGFloat,
        commentsOffset: Binding<CGFloat>,
        verticalDragOffset: Binding<CGSize>,
        showingCommentsBinding: Binding<Bool>,
        isCommentFieldFocused: Binding<Bool>,
        onDragChanged: ((CGFloat) -> Void)?,
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void
    ) -> AnyGesture<Void> {
        
        let dragGesture = DragGesture(coordinateSpace: .local)
            .onChanged { value in
                guard isCurrentCard && isGestureReady else { return }
                
                // If comments are showing, handle drag for comments
                if showingComments {
                    // Allow dismissing comments by dragging down
                    if value.translation.height > 50 {
                        commentsOffset.wrappedValue = value.translation.height * 0.5 // Damped drag
                    } else {
                        commentsOffset.wrappedValue = 0
                    }
                    return
                }
                
                // Simplified drag detection - less computation
                let absHeight = abs(value.translation.height)
                let absWidth = abs(value.translation.width)
                
                if absWidth > absHeight * 1.5 {
                    // Handle horizontal swipe for navigation - immediate response
                    let dampedTranslation = value.translation.width * 0.8
                    onDragChanged?(dampedTranslation)
                } else if value.translation.height < -30 {
                    // Upward swipe for comments
                    commentsOffset.wrappedValue = max(value.translation.height, -cardHeight * 0.3)
                } else if value.translation.height > 0 {
                    // Downward drag for dismissal
                    verticalDragOffset.wrappedValue = value.translation
                    // Reset parent drag state
                    onDragChanged?(0)
                }
            }
            .onEnded { value in
                guard isCurrentCard && isGestureReady else { return }
                
                // If comments are showing, handle end gesture for comments
                if showingComments {
                    if value.translation.height > 100 {
                        // Swipe down to close comments
                        withAnimation(.easeOut(duration: 0.3)) {
                            showingCommentsBinding.wrappedValue = false
                            commentsOffset.wrappedValue = 0
                            isCommentFieldFocused.wrappedValue = false // Dismiss keyboard in sync
                        }
                    } else {
                        // Snap back to show comments
                        withAnimation(.easeOut(duration: 0.2)) {
                            commentsOffset.wrappedValue = 0
                        }
                    }
                    return
                }
                
                // Simplified drag detection for end gesture
                let absHeight = abs(value.translation.height)
                let absWidth = abs(value.translation.width)
                
                var didTriggerAction = false
                
                if absWidth > absHeight * 1.5 {
                    // Horizontal swipe for navigation
                    let swipeThreshold: CGFloat = 50
                    
                    if value.translation.width > swipeThreshold {
                        didTriggerAction = true
                        onSwipeRight()
                    } else if value.translation.width < -swipeThreshold {
                        didTriggerAction = true
                        onSwipeLeft()
                    }
                }
                
                // Reset parent drag state
                onDragChanged?(0)
                
                // Reset offsets
                if !didTriggerAction {
                    withAnimation(.easeOut(duration: 0.2)) {
                        verticalDragOffset.wrappedValue = .zero
                        commentsOffset.wrappedValue = 0
                    }
                } else {
                    verticalDragOffset.wrappedValue = .zero
                    commentsOffset.wrappedValue = 0
                }
            }
        
        return AnyGesture(dragGesture.map { _ in })
    }
} 