//
//  InCardErrorView.swift
//  joy_thief
//
//  Custom error display component for in-card error states
//

import SwiftUI

struct InCardErrorView: View {
    let message: String
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onDismiss: () -> Void
    
    @State private var iconScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Simple dark overlay
            Color.black.opacity(0.9)
            
            VStack(spacing: cardHeight * 0.03) {
                Spacer()
                
                // Simple error icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: cardWidth * 0.15, weight: .regular))
                    .foregroundColor(.red)
                    .scaleEffect(iconScale)
                    .padding(.bottom, cardHeight * 0.02)
                
                // Simple error message
                VStack(spacing: cardHeight * 0.02) {
                    Text("error")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.06))
                        .foregroundColor(.white.opacity(0.9))
                        .textCase(.lowercase)
                    
                    Text(message)
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, cardWidth * 0.08)
                }
                .opacity(contentOpacity)
                
                Spacer()
                
                // Simple action buttons
                VStack(spacing: cardHeight * 0.018) {
                    Button(action: {
                        HapticFeedbackManager.shared.lightImpact()
                        onDismiss()
                    }) {
                        Text("try again")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045))
                            .foregroundColor(.white)
                            .textCase(.lowercase)
                            .frame(width: cardWidth * 0.5)
                            .padding(.vertical, cardHeight * 0.02)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: cardWidth * 0.02)
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            )
                    }
                    
                    Button(action: {
                        HapticFeedbackManager.shared.lightImpact()
                        onDismiss()
                    }) {
                        Text("cancel")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.lowercase)
                            .padding(.vertical, cardHeight * 0.01)
                    }
                }
                .opacity(contentOpacity)
                .padding(.bottom, cardHeight * 0.05)
            }
        }
        .onAppear {
            // Simple fade-in animation
            withAnimation(.easeInOut(duration: 0.3)) {
                iconScale = 1.0
                contentOpacity = 1.0
            }
        }
    }
}

#Preview {
    InCardErrorView(
        message: "❌ Verification failed. Please ensure both you and the activity are clearly visible.",
        cardWidth: 350,
        cardHeight: 500,
        onDismiss: {}
    )
    .background(Color.black)
}