import SwiftUI

/// Educational overlay that appears during onboarding habit demo to explain concepts
struct OnboardingHabitEducationOverlay: View {
    let currentAddHabitStep: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    let onComplete: () -> Void // New callback for completing the demo
    
    // Remove typing animation for immediate interactivity
    @State private var showControls = true // Always show controls
    @State private var currentPage = 0
    @State private var showOverlay = false
    @State private var isCompletionInProgress = false // Prevent race conditions
    
    private var educationPages: [[String]] {
        switch currentAddHabitStep {
        case 0: return [
            ["Pick a habit below", "Try selecting different options!"]
        ]
        case 1: return [
            ["Name your habit and add accountability partners", "Try typing and selecting friends!"],
            ["You need 3 different accountability partners", "before you can repeat the person!"]
        ]
        case 2: return [
            ["Set your schedule and penalty amount", "Interact with the controls below!"]
        ]
        default: return [[""]]
        }
    }
    
    private var currentContent: String {
        let pages = educationPages
        guard currentPage < pages.count else { return "" }
        return pages[currentPage].joined(separator: "\n")
    }
    
    private var stepTitle: String {
        switch currentAddHabitStep {
        case 0: return "step 1: pick your habit"
        case 1: return "step 2: accountability partners"
        case 2: return "step 3: set your stakes"
        default: return ""
        }
    }
    
    private var isLastPage: Bool {
        currentPage >= educationPages.count - 1
    }
    
    private var isLastStep: Bool {
        currentAddHabitStep >= 2
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
                    // Education content box at the top
                    VStack(spacing: 16) {
                        HStack {
                            Text(stepTitle)
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
                                        Text("skip demo")
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                        Image(systemName: "arrow.right")
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
                    
                    Spacer() // Push content to top
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            // Show overlay immediately for all steps
            if !showOverlay {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOverlay = true
                }
            }
        }
        .onChange(of: currentAddHabitStep) { oldValue, newValue in
            // Only show overlay if step actually changed (not just initialized)
            if oldValue != newValue && newValue > oldValue {
                // Reset when step changes
                resetState()
                // Show overlay immediately when advancing to any step
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOverlay = true
                }
            }
        }
    }
    
    private func resetState() {
        showControls = true // Always show controls for interactivity
        currentPage = 0
        showOverlay = false
        isCompletionInProgress = false // Reset completion flag
    }
    
    private func handleNext() {
        if isLastPage {
            if isLastStep {
                // Last page of last step - just dismiss overlay, let user complete naturally
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOverlay = false
                }
            } else {
                // Last page of current step - just dismiss overlay, let user advance naturally
                withAnimation(.easeInOut(duration: 0.3)) {
                    showOverlay = false
                }
            }
        } else {
            // Show next page within current step
            withAnimation(.easeInOut(duration: 0.2)) {
                currentPage += 1
            }
        }
    }
}

// MARK: – Shared haptic throttler (kept for other parts of the app)
fileprivate enum HapticThrottler {
    private static let generator = UIImpactFeedbackGenerator(style: .light)
    private static var lastTimestamp: CFTimeInterval = 0

    static func trigger(intensity: CGFloat = 0.4) {
        let now = CACurrentMediaTime()
        if now - lastTimestamp >= (1.0 / 16.0) {
            generator.impactOccurred(intensity: intensity)
            generator.prepare()
            lastTimestamp = now
        }
    }
} 