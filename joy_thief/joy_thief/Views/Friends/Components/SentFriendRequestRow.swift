////
//  SentFriendRequestRow.swift
//  joy_thief
//
//  Created to display sent friend requests with cancel functionality.
//

import SwiftUI

/// A row component for displaying sent friend requests with cancel option
struct SentFriendRequestRow: View {
    let request: UnifiedSentFriendRequest
    let isProcessing: Bool
    let onCancel: () async -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar – show cached avatar if present, otherwise fall back to initials
            if request.receiverAvatarUrl200 != nil || request.receiverAvatarUrl80 != nil {
                CachedAvatarView(
                    url80: request.receiverAvatarUrl80,
                    url200: request.receiverAvatarUrl200,
                    urlOriginal: request.receiverAvatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(initials(for: request.receiverName))
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.receiverName)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }

            Spacer()

            // Cancel button or processing indicator
            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                Button(action: {
                    Task { await onCancel() }
                }) {
                    Text("CANCEL")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func initials(for name: String) -> String {
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0).uppercased() }
        return initials.prefix(2).joined()
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    SentFriendRequestRow(
        request: UnifiedSentFriendRequest(
            id: "test-id",
            receiverId: "receiver-id",
            receiverName: "John Doe",
            receiverPhone: "+1234567890",
            receiverAvatarVersion: nil,
            receiverAvatarUrl80: nil,
            receiverAvatarUrl200: nil,
            receiverAvatarUrlOriginal: nil,
            message: "Friend request",
            status: "pending",
            createdAt: "2025-01-20T12:00:00Z"
        ),
        isProcessing: false,
        onCancel: {}
    )
    .background(Color.black)
} 