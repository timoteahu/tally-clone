import SwiftUI

/// Educational overlay that appears during onboarding payment demo to explain payment concepts
struct OnboardingPaymentEducationOverlay: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    let onComplete: () -> Void // Called when user finishes the overlay to trigger payment setup
    let onStripeConnect: () -> Void // Called when user wants to set up Stripe Connect
    
    // Remove typing animation for immediate interactivity
    @State private var showControls = true // Always show controls
    @State private var currentPage = 0
    @State private var showOverlay = true
    @State private var showSetupOptions = false
    
    private var educationPages: [[String]] {
        return [
            ["Your payment hub", "View your balance and payment history below!"],
            ["When you miss a habit, we charge your card", "and send it to your accountability partner"],
            ["Set up Stripe Connect to receive money", "when your friends fail their habits!"]
        ]
    }
    
    private var currentContent: String {
        let pages = educationPages
        guard currentPage < pages.count else { return "" }
        return pages[currentPage].joined(separator: "\n")
    }
    
    private var isLastPage: Bool {
        currentPage >= educationPages.count - 1
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay - reduced opacity to see UI behind
            Color.black.opacity(showOverlay ? 0.3 : 0.0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: showOverlay)
                .allowsHitTesting(false) // Allow touches to pass through to UI behind
            
            if showOverlay {
                VStack {
                    if !showSetupOptions {
                        // Education content box at the top
                        VStack(spacing: 16) {
                        HStack {
                            Text("payment & stripe connect")
                                .font(.custom("EBGaramond-Regular", size: 20))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                            
                            // Page indicator
                            if educationPages.count > 1 {
                                HStack(spacing: 6) {
                                    ForEach(0..<educationPages.count, id: \.self) { index in
                                        Circle()
                                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.3))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                            }
                        }
                        
                        Text(currentContent)
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(minHeight: 80, alignment: .center)
                            .animation(.easeInOut(duration: 0.3), value: currentContent)
                        
                        if showControls {
                            HStack(spacing: 20) {
                                Button(action: onSkip) {
                                    HStack(spacing: 8) {
                                        Text("add payment later")
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                        Image(systemName: "arrow.right.circle")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: handleNext) {
                                    HStack(spacing: 8) {
                                        if isLastPage {
                                            Text("got it")
                                        } else {
                                            Text("next")
                                        }
                                        Image(systemName: isLastPage ? "checkmark" : "arrow.right")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white)
                                    )
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.85))
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                    .padding(.top, 60) // Position at top
                    } else {
                        // Setup options
                        VStack(spacing: 20) {
                            Text("Set up your account")
                                .font(.custom("EBGaramond-Regular", size: 24))
                                .foregroundColor(.white)
                            
                            Text("Choose what you'd like to set up:")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                            
                            VStack(spacing: 16) {
                                // Payment method button
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showOverlay = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        onComplete()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "creditcard.fill")
                                            .font(.system(size: 20))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Add Payment Method")
                                                .font(.custom("EBGaramond-Regular", size: 18))
                                                .fontWeight(.medium)
                                            Text("Required to participate in habits")
                                                .font(.custom("EBGaramond-Regular", size: 14))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 16))
                                    }
                                    .foregroundColor(.white)
                                    .padding(20)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                
                                // Stripe Connect button
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showOverlay = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        onStripeConnect()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                                            .font(.system(size: 20))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Set up Stripe Connect")
                                                .font(.custom("EBGaramond-Regular", size: 18))
                                                .fontWeight(.medium)
                                            Text("Receive payments from friends")
                                                .font(.custom("EBGaramond-Regular", size: 14))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 16))
                                    }
                                    .foregroundColor(.white)
                                    .padding(20)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                }
                            }
                            
                            Button(action: onSkip) {
                                Text("Set up later")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.top, 8)
                            }
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.85))
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                        .padding(.top, 60)
                    }
                    
                    Spacer() // Push content to top
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            // Show overlay immediately
            if !showOverlay {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOverlay = true
                }
            }
        }
    }
    
    private func handleNext() {
        if isLastPage {
            // Last page - show setup options
            withAnimation(.easeInOut(duration: 0.3)) {
                showSetupOptions = true
            }
        } else {
            // Show next page within current overlay
            withAnimation(.easeInOut(duration: 0.2)) {
                currentPage += 1
            }
        }
    }
} 