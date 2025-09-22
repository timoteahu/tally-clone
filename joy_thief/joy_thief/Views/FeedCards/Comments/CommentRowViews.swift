import SwiftUI

struct CommentListView: View {
    let comments: [Comment]
    let postAuthorId: UUID
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let timeAgo: (Date) -> String
    let onReply: (Comment) -> Void
    let onUserTap: ((String, String?, String?) -> Void)?
    @Binding var highlightedCommentId: UUID?

    var body: some View {
        // Comments are now organized with direct parent-child threading
        // Calculate proper indentation for each comment based on its depth
        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
            CommentRowView(
                comment: comment,
                postAuthorId: postAuthorId,
                timeAgo: timeAgo,
                onReply: onReply,
                onUserTap: onUserTap,
                highlightedCommentId: $highlightedCommentId
            )
            .padding(.leading, calculateIndentation(for: comment, at: index, in: comments))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(highlightedCommentId == comment.id ? 0.1 : 0))
                    .padding(.horizontal, -24) // Extend beyond LazyVStack padding
                    .padding(.vertical, -8) // Extend vertically to fully cover avatar area
            )
            .animation(.easeInOut(duration: 0.3), value: highlightedCommentId)
        }
    }
    
    /// Calculate the indentation level for a comment in the flat threading structure
    private func calculateIndentation(for comment: Comment, at index: Int, in comments: [Comment]) -> CGFloat {
        guard comment.parentComment != nil else { return 0 } // Top-level comments have no indentation
        
        // 🔧 FLAT THREADING: All replies (including replies to replies) use the same indentation
        // Only top-level comments have no indentation, everything else gets one level
        
        // Check if this is a direct reply to a top-level comment or a flattened reply-to-reply
        // In our flat structure, both should have the same indentation
        
        return 20.0 // Single level of indentation for all replies
    }
    
    /// Helper function to calculate depth based on position in organized structure (DEPRECATED)
    /// Kept for compatibility but not used in flat threading
    private func calculateDepthFromStructure(for index: Int, in comments: [Comment]) -> Int {
        let comment = comments[index]
        
        // In flat threading, we only have two levels: top-level (0) and replies (1)
        return comment.parentComment != nil ? 1 : 0
    }
}

struct CommentRowView: View {
    let comment: Comment
    let postAuthorId: UUID
    let timeAgo: (Date) -> String
    let onReply: (Comment) -> Void
    let onUserTap: ((String, String?, String?) -> Void)?
    @Binding var highlightedCommentId: UUID?

    // Computed property to format reply content with @mention
    private var displayContent: String {
        if let parentComment = comment.parentComment {
            return "@\(parentComment.userName) \(comment.content)"
        } else {
            return comment.content
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar - tappable
            Button(action: {
                onUserTap?(comment.userId.uuidString, comment.userName, comment.userAvatarUrl80)
            }) {
                if comment.userAvatarUrl80 != nil || comment.userAvatarUrl200 != nil || comment.userAvatarUrlOriginal != nil {
                    // Use any available avatar variant for display
                    CachedAvatarView(
                        url80: comment.userAvatarUrl80,
                        url200: comment.userAvatarUrl200,
                        urlOriginal: comment.userAvatarUrlOriginal,
                        size: .small
                    )
                    .frame(width: 32, height: 32)
                } else {
                    // Fallback to initials circle when no avatar URL available
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(comment.userName.prefix(1)))
                                .jtStyle(.body)
                                .foregroundColor(.white)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                // Username, Time, Author
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: {
                        onUserTap?(comment.userId.uuidString, comment.userName, comment.userAvatarUrl80)
                    }) {
                        Text(comment.userName)
                            .font(.custom("EBGaramond-Bold", size: 14))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(timeAgo(comment.createdAt).lowercased())
                        .jtStyle(.caption)
                        .foregroundColor(.gray)
                        
                    if comment.userId == postAuthorId {
                        Text("author")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                    }
                }
                .foregroundColor(.white)
                .padding(.top, -6)
                // Comment with @mention formatting - always show the direct person being replied to
                if let parentComment = comment.parentComment {
                    // Show @mention for the person this comment is directly replying to
                    // This preserves the correct conversation context regardless of threading structure
                    HStack(spacing: 0) {
                        Text("@\(parentComment.userName)")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                            .onTapGesture {
                                // Highlight the parent comment
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    highlightedCommentId = parentComment.id
                                }
                                
                                // Clear highlight after 1 second
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    if highlightedCommentId == parentComment.id {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            highlightedCommentId = nil
                                        }
                                    }
                                }
                            }
                        
                        Text(" \(comment.content)")
                            .foregroundColor(.white)
                    }
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
                } else {
                    // For top-level comments, display normally
                    Text(comment.content)
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }

                // Reply Button
                Button(action: {
                    print("🔘 [CommentRowView] Reply button tapped:")
                    print("   - Comment ID: \(comment.id.uuidString)")
                    print("   - Comment Author: \(comment.userName)")
                    print("   - Comment Content: '\(comment.content)'")
                    if let parent = comment.parentComment {
                        print("   - This comment is replying to: \(parent.userName) (ID: \(parent.id.uuidString))")
                    } else {
                        print("   - This is a top-level comment")
                    }
                    print("   - Setting this comment as replyingToComment")
                    onReply(comment)
                }) {
                    Text("reply")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
    }
}

// The CommentRowView and ReplyRowView that were previously in this file have been removed 
// as they are now replaced by InstagramCommentRow.

