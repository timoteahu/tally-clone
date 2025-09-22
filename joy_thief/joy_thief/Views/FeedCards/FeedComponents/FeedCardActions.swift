import SwiftUI
import Foundation

// MARK: - FeedCard Actions
struct FeedCardActions {
    
    // MARK: - Comment Actions
    
    static func submitComment(
        newCommentText: String,
        maxCommentLength: Int,
        currentPost: FeedPost,
        replyingToComment: Comment?,
        authManager: AuthenticationManager,
        feedManager: FeedManager,
        isSubmittingComment: Binding<Bool>,
        showCommentLengthError: Binding<Bool>,
        newCommentTextBinding: Binding<String>,
        replyingToCommentBinding: Binding<Comment?>,
        isCommentFieldFocused: Binding<Bool>
    ) {
        let commentText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard commentText.count <= maxCommentLength else {
            showCommentLengthError.wrappedValue = true
            return
        }
        
        print("🔄 [SUBMIT_COMMENT] Starting comment submission for post: \(currentPost.postId)")
        print("🔄 [SUBMIT_COMMENT] Comment text: '\(commentText)'")
        if let replyingTo = replyingToComment {
            print("🔄 [SUBMIT_COMMENT] Replying to comment:")
            print("   - Reply Target ID: \(replyingTo.id.uuidString)")
            print("   - Reply Target Author: \(replyingTo.userName)")
            print("   - Reply Target Content: '\(replyingTo.content)'")
            if let parent = replyingTo.parentComment {
                print("   - Reply Target's Parent: \(parent.userName) (ID: \(parent.id.uuidString))")
            } else {
                print("   - Reply Target is a top-level comment")
            }
        } else {
            print("🔄 [SUBMIT_COMMENT] This is a top-level comment (no replyingToComment)")
        }
        isSubmittingComment.wrappedValue = true
        
        Task {
            do {
                // Get auth token
                guard let token = await authManager.storedAuthToken else {
                    print("❌ [Comment] Authentication failed - no token")
                    throw CommentError.authenticationFailed
                }
                
                print("🔄 [Comment] Token obtained, preparing API request")
                
                // Prepare comment data
                let commentData: [String: Any] = [
                    "post_id": currentPost.postId.uuidString,
                    "content": commentText,
                    "parent_comment_id": replyingToComment?.id.uuidString as Any
                ].compactMapValues { $0 } // Remove nil values
                
                print("🔄 [SUBMIT_COMMENT] API request data:")
                print("   - post_id: \(currentPost.postId.uuidString)")
                print("   - content: '\(commentText)'")
                print("   - parent_comment_id: \(replyingToComment?.id.uuidString ?? "nil")")
                print("🔄 [SUBMIT_COMMENT] Final commentData: \(commentData)")
                
                // Make API request
                let url = URL(string: "\(AppConfig.baseURL)/feed/comments")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: commentData)
                
                print("🔄 [Comment] Making API request to: \(url)")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [Comment] Invalid response type")
                    throw CommentError.networkError
                }
                
                print("🔄 [Comment] API response status: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                    print("❌ [Comment] API failed with status: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ [Comment] Error response: \(responseString)")
                    }
                    throw CommentError.networkError
                }
                
                print("✅ [Comment] API call successful, parsing response")
                
                // Parse the response to get the new comment
                let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let commentDict = jsonResponse,
                      let commentId = commentDict["id"] as? String,
                      let userId = commentDict["user_id"] as? String,
                      let userName = commentDict["user_name"] as? String,
                      let createdAtString = commentDict["created_at"] as? String else {
                    print("❌ [Comment] Invalid response format")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ [Comment] Response data: \(responseString)")
                    }
                    throw CommentError.invalidResponse
                }
                
                print("✅ [Comment] Response parsed successfully")
                print("🔄 [Comment] New comment ID: \(commentId), User: \(userName)")
                
                // Parse the date
                let createdAt = DateFormatterManager.shared.parseISO8601Date(createdAtString) ?? Date()
                
                // Parse parent comment if present
                var parentComment: ParentComment? = nil
                if let parentCommentDict = commentDict["parent_comment"] as? [String: Any],
                   let parentId = parentCommentDict["id"] as? String,
                   let parentContent = parentCommentDict["content"] as? String,
                   let parentCreatedAtString = parentCommentDict["created_at"] as? String,
                   let parentUserId = parentCommentDict["user_id"] as? String,
                   let parentUserName = parentCommentDict["user_name"] as? String,
                   let parentIsEdited = parentCommentDict["is_edited"] as? Bool {
                    
                    let parentCreatedAt = DateFormatterManager.shared.parseISO8601Date(parentCreatedAtString) ?? Date()
                    parentComment = ParentComment(
                        id: UUID(uuidString: parentId) ?? UUID(),
                        content: parentContent,
                        createdAt: parentCreatedAt,
                        userId: UUID(uuidString: parentUserId) ?? UUID(),
                        userName: parentUserName,
                        userAvatarUrl80: parentCommentDict["user_avatar_url_80"] as? String,
                        userAvatarUrl200: parentCommentDict["user_avatar_url_200"] as? String,
                        userAvatarUrlOriginal: parentCommentDict["user_avatar_url_original"] as? String,
                        userAvatarVersion: parentCommentDict["user_avatar_version"] as? Int,
                        isEdited: parentIsEdited
                    )
                    
                    print("✅ [Comment] Parent comment parsed: \(parentComment?.id.uuidString.prefix(8) ?? "nil") by \(parentComment?.userName ?? "unknown")")
                } else if replyingToComment != nil {
                    print("⚠️ [Comment] Expected parent comment in response but none found")
                }
                
                // Create new comment object
                let newComment = await Comment(
                    id: UUID(uuidString: commentId) ?? UUID(),
                    content: commentText,
                    createdAt: createdAt,
                    userId: UUID(uuidString: userId) ?? UUID(),
                    userName: userName,
                    userAvatarUrl80: authManager.currentUser?.avatarUrl80,
                    userAvatarUrl200: authManager.currentUser?.avatarUrl200,
                    userAvatarUrlOriginal: authManager.currentUser?.avatarUrlOriginal,
                    userAvatarVersion: authManager.currentUser?.avatarVersion,
                    isEdited: false,
                    parentComment: parentComment
                )
                
                print("💬 [SwipeableFeedCard] Created new comment:")
                print("   - Comment ID: \(commentId)")
                print("   - Content: \(commentText)")
                print("   - Parent comment: \(parentComment?.userName ?? "None (top-level)")")
                print("   - Parent comment ID: \(parentComment?.id.uuidString ?? "None")")
                
                // Add to feed manager immediately for instant UI update
                await feedManager.addComment(newComment, to: currentPost.postId)
                
                print("💬 [SwipeableFeedCard] Comment added to FeedManager")
                
                // Reset UI state on main thread
                await MainActor.run {
                    newCommentTextBinding.wrappedValue = ""
                    replyingToCommentBinding.wrappedValue = nil
                    isSubmittingComment.wrappedValue = false
                    isCommentFieldFocused.wrappedValue = false
                }
                
                print("✅ [SwipeableFeedCard] Comment submission completed successfully")
                
            } catch {
                await MainActor.run {
                    isSubmittingComment.wrappedValue = false
                    print("❌ [Comment] Failed to submit comment: \(error)")
                    // You might want to show an error alert here
                }
            }
        }
    }
    
    // MARK: - Caption Actions
    
    static func startEditingCaption(
        currentCaption: String,
        editingCaption: Binding<String>,
        isEditingCaption: Binding<Bool>,
        isCommentFieldFocused: Binding<Bool>
    ) {
        editingCaption.wrappedValue = currentCaption
        isEditingCaption.wrappedValue = true
        // Focus the text field to show keyboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isCommentFieldFocused.wrappedValue = true
        }
    }
    
    static func updateCaption(
        editingCaption: String,
        currentPost: FeedPost,
        authManager: AuthenticationManager,
        feedManager: FeedManager,
        isUpdatingCaption: Binding<Bool>,
        isEditingCaption: Binding<Bool>,
        isCommentFieldFocused: Binding<Bool>
    ) async {
        guard !editingCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                cancelCaptionEditing(
                    currentPost: currentPost,
                    editingCaption: Binding.constant(editingCaption),
                    isEditingCaption: isEditingCaption,
                    isCommentFieldFocused: isCommentFieldFocused
                )
            }
            return
        }
        
        await MainActor.run {
            isUpdatingCaption.wrappedValue = true
        }
        
        do {
            guard let token = await authManager.storedAuthToken else {
                throw CaptionUpdateError.authenticationFailed
            }
            
            let url = URL(string: "\(AppConfig.baseURL)/feed/update-caption")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "post_id": currentPost.postId.uuidString,
                "caption": editingCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw CaptionUpdateError.networkError
            }
            
            await MainActor.run {
                // Update the FeedManager with new caption
                feedManager.updatePostCaption(postId: currentPost.postId, newCaption: editingCaption)
                isEditingCaption.wrappedValue = false
                isUpdatingCaption.wrappedValue = false
                isCommentFieldFocused.wrappedValue = false
                print("✅ [SwipeableFeedCard] Caption updated successfully")
            }
            
        } catch {
            await MainActor.run {
                isUpdatingCaption.wrappedValue = false
                print("❌ [SwipeableFeedCard] Failed to update caption: \(error)")
            }
        }
    }
    
    static func cancelCaptionEditing(
        currentPost: FeedPost,
        editingCaption: Binding<String>,
        isEditingCaption: Binding<Bool>,
        isCommentFieldFocused: Binding<Bool>
    ) {
        withAnimation(.easeOut(duration: 0.2)) {
            isEditingCaption.wrappedValue = false
        }
        // Restore original caption
        if let originalCaption = currentPost.caption {
            editingCaption.wrappedValue = originalCaption
        } else {
            editingCaption.wrappedValue = ""
        }
        // Dismiss keyboard
        isCommentFieldFocused.wrappedValue = false
    }
}

// MARK: - Error Types

private enum CommentError: Error {
    case authenticationFailed
    case networkError
    case invalidResponse
}

private enum CaptionUpdateError: Error {
    case authenticationFailed
    case networkError
} 
