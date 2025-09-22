//
//  CameraTransitionView.swift
//  joy_thief
//
//  Minimal transition view for camera switching
//

import SwiftUI

struct CameraTransitionView: View {
    let message: String
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    
    @State private var contentOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Simple dark background
            Color(hex: "0A0F17").opacity(0.95)
            
            VStack(spacing: cardHeight * 0.03) {
                // Simple loading indicator
                CustomLoadingIndicator(size: cardWidth * 0.1)
                    .opacity(0.6)
                
                // Message text
                Text(message.lowercased())
                    .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            // Simple fade in
            withAnimation(.easeOut(duration: 0.2)) {
                contentOpacity = 1.0
            }
            
            // Subtle haptic feedback
            HapticFeedbackManager.shared.lightImpact()
        }
    }
}

#Preview {
    CameraTransitionView(
        message: "Switching to rear camera...",
        cardWidth: 350,
        cardHeight: 500
    )
    .frame(width: 350, height: 500)
    .background(Color.gray)
}