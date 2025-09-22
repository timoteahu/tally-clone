////
//  FriendRequestRow.swift
//  joy_thief
//
//  Extracted from FriendsView on 2025-06-18 so it can be reused independently.
//

import SwiftUI

/// A single incoming friend-request cell, complete with accept/decline actions and optimistic UI updates.
struct FriendRequestRow: View {
    let request: FriendRequestWithDetails
    let isProcessing: Bool
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar – show cached avatar if present, otherwise fall back to initials
            if request.senderAvatarUrl200 != nil || request.senderAvatarUrl80 != nil {
                CachedAvatarView(
                    url80: request.senderAvatarUrl80,
                    url200: request.senderAvatarUrl200,
                    urlOriginal: request.senderAvatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(initials(for: request.senderName))
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.senderName)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                if let message = request.message,
                   !message.isEmpty,
                   message != "Friend request via add" && message != "Friend request via direct add" {
                    Text(message)
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button(action: {
                        Task { await onAccept() }
                    }) {
                        Text("ACCEPT")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        Task { await onDecline() }
                    }) {
                        Text("DECLINE")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helper Functions
    
    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
} 