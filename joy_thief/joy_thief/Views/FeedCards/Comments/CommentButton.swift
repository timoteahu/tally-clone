//
//  CommentButton.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct CommentsButton: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isLoadingComments: Bool
    let cachedCommentCount: Int
    let currentCommentCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            onTap()
        }) {
            HStack(spacing: cardWidth * 0.01) {
                Image(systemName: "message")
                    .font(.system(size: cardWidth * 0.055))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("\(isLoadingComments ? cachedCommentCount : currentCommentCount)")
                    .font(.custom("EBGaramond-Regular", size: cardWidth * 0.038))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, cardWidth * 0.03)
            .padding(.vertical, cardHeight * 0.01)
            .background(
                RoundedRectangle(cornerRadius: cardWidth * 0.02)
                    .fill(Color.black.opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: cardWidth * 0.02)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.bottom, cardHeight * 0.015)
            .padding(.trailing, cardWidth * 0.033)
        }
        .contentShape(Rectangle())
        .padding(.all, 8)
    }
}


struct CommentSendButton: View {
    let cardWidth: CGFloat
    let isSubmittingComment: Bool
    let newCommentText: String
    let onSend: () -> Void

    var body: some View {
        Button(action: { onSend() }) {
            Group {
                if isSubmittingComment {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045))
                        .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.3) : .blue)
                }
            }
        }
        .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingComment)
        .frame(width: cardWidth * 0.12, height: cardWidth * 0.12)
        .background(
            Circle()
                .fill(Color.white.opacity(0.1))
        )
    }
}

