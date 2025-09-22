//
//  UserAccountSkeleton.swift
//  joy_thief
//
//  Created by Timothy Hu on 7/17/25.
//

import SwiftUI

struct UserAccountSkeleton: View {
    let onDismiss: (() -> Void)?
    @State private var pulse = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background gradient matching UserAccount
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: Color(hex: "161C29"), location: 0.0),
                    Gradient.Stop(color: Color(hex: "131824"), location: 0.15),
                    Gradient.Stop(color: Color(hex: "0F141F"), location: 0.3),
                    Gradient.Stop(color: Color(hex: "0C111A"), location: 0.45),
                    Gradient.Stop(color: Color(hex: "0A0F17"), location: 0.6),
                    Gradient.Stop(color: Color(hex: "080D15"), location: 0.7),
                    Gradient.Stop(color: Color(hex: "060B12"), location: 0.8),
                    Gradient.Stop(color: Color(hex: "03070E"), location: 0.9),
                    Gradient.Stop(color: Color(hex: "01050B"), location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Dismiss/back arrow (if onDismiss is provided)
            if let onDismiss = onDismiss {
                Button(action: { onDismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44) // Match UserAccount tap target size
                        .contentShape(Rectangle())
                }
                .padding(.top, 8)
                .padding(.leading, 16)
                .zIndex(10)
            }
            
            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header Skeleton
                    profileHeaderSkeleton
                    // Thin gray line separator
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .padding(.top, 48) // Match UserAccount padding
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            pulse = true
        }
    }
    
    // MARK: - Profile Header Skeleton
    private var profileHeaderSkeleton: some View {
        VStack(spacing: 24) {
            // Profile Avatar Skeleton
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .opacity(pulse ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            // Username Skeleton
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 150, height: 24)
                .opacity(pulse ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            // Stats Skeleton
            HStack(spacing: 40) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 28)
                            .opacity(pulse ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 16)
                            .opacity(pulse ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
}

// MARK: - Preview
struct UserAccountSkeleton_Previews: PreviewProvider {
    static var previews: some View {
        UserAccountSkeleton(onDismiss: nil)
    }
}
