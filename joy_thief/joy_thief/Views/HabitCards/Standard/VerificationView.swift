//
//  VerificationView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct VerificationView: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let verificationContentView: AnyView
    let setupVerificationView: () async -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
         GeometryReader { geometry in
            VStack(spacing: cardHeight * 0.03) {  // Increased spacing for better distribution
                Spacer(minLength: cardHeight * 0.05)  // Add top spacing to move content down
                
                // Habit info section - centered with more emphasis
                VStack(alignment: .center, spacing: cardHeight * 0.02) {  // Increased spacing
                    Text(habit.name)
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.06)).fontWeight(.bold)  // Larger font
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, cardWidth * 0.05)
                    
                    if let recipientName = habit.getRecipientName() {
                        HStack(spacing: cardWidth * 0.02) {  // Increased spacing
                            Image(systemName: "person.fill")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))  // Larger icon
                                .foregroundColor(.white.opacity(0.8))
                            Text(recipientName)
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))  // Larger font
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, cardWidth * 0.05)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, cardHeight * 0.03)  // Add top padding
                
                // Verification content with more space
                verificationContentView
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, cardWidth * 0.05)
                    .padding(.vertical, cardHeight * 0.02)

                // Group Back button and instructional text closer together
                VStack(spacing: cardHeight * 0.008) {
                    Button(action: {
                        HapticFeedbackManager.shared.lightImpact()
                        onBack?()
                    }) {
                        HStack(spacing: cardWidth * 0.01) {
                            Image(systemName: "arrow.left")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025))
                            Text("back")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                        }
                        .padding(.vertical, cardHeight * 0.012)
                        .padding(.horizontal, cardWidth * 0.08)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(cardWidth * 0.025)
                    }
                    Text("Make sure both you and the activity are clearly visible in the photos.")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.020))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, cardWidth * 0.05)
                }
                
                Spacer(minLength: cardHeight * 0.08)  // Minimum spacing at bottom
            }
            .frame(minHeight: geometry.size.height)
        }
        .task {
            await setupVerificationView()
        }
    }
}

