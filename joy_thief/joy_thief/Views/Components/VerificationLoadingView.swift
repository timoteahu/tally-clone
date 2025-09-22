//
//  VerificationLoadingView.swift
//  joy_thief
//
//  Clean loading state for verification process
//

import SwiftUI

struct VerificationLoadingView: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let message: String
    
    @State private var isComplete: Bool = false
    
    var body: some View {
        ZStack {
            // Simple dark background
            Color.black.opacity(0.9)
            
            VStack(spacing: cardHeight * 0.04) {
                Spacer()
                
                // Loading indicator
                if !isComplete {
                    CustomLoadingIndicator(size: cardWidth * 0.15)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: cardWidth * 0.12, weight: .regular))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Status text
                Text(isComplete ? "Verified!" : message)
                    .font(.system(size: cardWidth * 0.05, weight: .medium))
                    .foregroundColor(.white)
                    .transition(.opacity)
                
                Spacer()
            }
        }
    }
}

#Preview {
    VerificationLoadingView(
        cardWidth: 350,
        cardHeight: 500,
        message: "Analyzing your photos..."
    )
    .frame(width: 350, height: 500)
    .cornerRadius(20)
}