import SwiftUI

struct HabitVerificationAnimationView: View {
    let habitType: String
    let habitName: String
    @Binding var isVerifying: Bool
    
    @State private var showSuccessCheck = false
    @State private var successScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var isRotating = false
    
    var body: some View {
        ZStack {
            // Dark overlay matching app aesthetic
            Color(hex: "0A0F17").opacity(0.95)
            
            VStack(spacing: 20) {
                // Loading or success indicator
                if isVerifying {
                    // Simple rotating circle
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                isRotating = true
                            }
                        }
                } else if showSuccessCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.green.opacity(0.9))
                        .scaleEffect(successScale)
                }
                
                // Status text
                Text(isVerifying ? "verifying..." : "verified")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white.opacity(0.9))
                    .textCase(.lowercase)
                
                // Habit name
                Text(habitName.lowercased())
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .opacity(contentOpacity)
            .padding(.vertical, 28)
            .padding(.horizontal, 32)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "131824").opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 60)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                contentOpacity = 1.0
            }
            if !isVerifying {
                showSuccessAnimation()
            }
        }
        .onChange(of: isVerifying) { oldValue, newValue in
            if !newValue {
                showSuccessAnimation()
                isRotating = false
            }
        }
    }
    
    private func showSuccessAnimation() {
        HapticFeedbackManager.shared.playVerificationSuccess()
        
        withAnimation(.easeOut(duration: 0.25)) {
            showSuccessCheck = true
            successScale = 1.0
        }
    }
}

#Preview {
    HabitVerificationAnimationView(
        habitType: "gym",
        habitName: "Morning Workout",
        isVerifying: .constant(true)
    )
} 
