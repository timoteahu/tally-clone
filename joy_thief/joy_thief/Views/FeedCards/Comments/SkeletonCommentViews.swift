//
//  Untitled.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct LoadingCommentsView: View {
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    let shimmerOpacity: Double

    var body: some View {
        ForEach(0..<3, id: \.self) { index in
            SkeletonCommentView(
                variation: index,
                cardHeight: cardHeight,
                cardWidth: cardWidth,
                shimmerOpacity: shimmerOpacity
            )
        }
    }
}

struct EmptyCommentsView: View {
    let cardHeight: CGFloat
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: cardHeight * 0.015) {
            Image(systemName: "message")
                .font(.system(size: cardWidth * 0.08))
                .foregroundColor(.white.opacity(0.3))
            
            Text("no comments yet")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.6))
            
            Text("be the first to comment!")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, cardHeight * 0.04)
    }
}

struct SkeletonCommentView: View {
    let variation: Int
    let cardHeight: CGFloat
    let cardWidth: CGFloat
    let shimmerOpacity: Double

    var body: some View {
        let commentWidths: [CGFloat] = [0.65, 0.45, 0.55]
        let nameWidths: [CGFloat] = [0.18, 0.25, 0.22]
        let timeWidths: [CGFloat] = [0.1, 0.14, 0.12]
        
        return VStack(spacing: cardHeight * 0.01) {
            HStack(alignment: .top, spacing: cardWidth * 0.03) {
                // ✅ ENHANCED skeleton avatar to match CachedAvatarView appearance
                Circle()
                    .fill(Color.white.opacity(shimmerOpacity * 0.3))
                    .frame(width: cardWidth * 0.08, height: cardWidth * 0.08)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(shimmerOpacity * 0.15))
                            .scaleEffect(0.7)
                    )
                    .overlay(
                        // Add a subtle inner glow effect like a loading avatar
                        Circle()
                            .stroke(Color.white.opacity(shimmerOpacity * 0.2), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: cardHeight * 0.008) {
                    // Skeleton user name and time
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(shimmerOpacity * 0.5))
                            .frame(width: cardWidth * nameWidths[variation], height: 12)
                        
                        Spacer()
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(shimmerOpacity * 0.3))
                            .frame(width: cardWidth * timeWidths[variation], height: 10)
                    }
                    
                    // Skeleton comment text (variable length based on variation)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(shimmerOpacity * 0.4))
                            .frame(width: cardWidth * commentWidths[variation], height: 14)
                        
                        // Some comments have second line, some don't
                        if variation != 1 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(shimmerOpacity * 0.35))
                                .frame(width: cardWidth * (commentWidths[variation] * 0.7), height: 14)
                        }
                    }
                    
                    // Skeleton reply button
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(shimmerOpacity * 0.25))
                        .frame(width: cardWidth * 0.08, height: 10)
                        .padding(.top, cardHeight * 0.005)
                }
                
                Spacer()
            }
            .padding(.horizontal, cardWidth * 0.025)
            .padding(.vertical, cardHeight * 0.015)
            .background(
                RoundedRectangle(cornerRadius: cardWidth * 0.025)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .opacity(0.8 + (Double(variation) * 0.1))
        .animation(
            Animation.easeInOut(duration: 1.0 + Double(variation) * 0.2)
                .repeatForever(autoreverses: true)
                .delay(Double(variation) * 0.2),
            value: shimmerOpacity
        )
    }
}
