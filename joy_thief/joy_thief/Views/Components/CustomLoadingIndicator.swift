//
//  CustomLoadingIndicator.swift
//  joy_thief
//
//  Minimal loading indicator matching app aesthetic
//

import SwiftUI

struct CustomLoadingIndicator: View {
    @State private var isAnimating = false
    let size: CGFloat
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// Alternative minimal dot indicator
struct DotLoadingIndicator: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]
    let size: CGFloat
    
    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .opacity(dotOpacity[index])
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15)
                        ) {
                            dotOpacity[index] = 0.8
                        }
                    }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        CustomLoadingIndicator(size: 40)
        DotLoadingIndicator(size: 40)
    }
    .padding()
    .background(Color.black)
}