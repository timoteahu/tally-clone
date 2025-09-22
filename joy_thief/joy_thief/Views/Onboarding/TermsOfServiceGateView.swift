import SwiftUI

/// First step of onboarding – typewriter line + arrow leading to Terms of Service sheet.
struct TermsOfServiceGateView: View {
    /// Called once the user has accepted the Terms of Service.
    let onAgreed: () -> Void

    private let fontSize: CGFloat = UIScreen.main.bounds.width < 360 ? 18 : 22
    private let message = "before we get started, please\nreview and accept our terms of \nservice"
    private let typingSpeed: Double = 0.035

    @State private var displayedText = ""
    @State private var charIndex = 0
    @State private var typingTimer: Timer? = nil

    @State private var presentingSheet = false
    @State private var hasAcceptedTerms = false
    @State private var showArrow = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(displayedText)
                .font(.custom("EBGaramond-Regular", size: fontSize))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32)
                .padding(.trailing, 90)
                .onAppear { startTyping() }
                .onDisappear { typingTimer?.invalidate() }

            if showArrow {
                Button(action: { presentingSheet = true }) {
                    Image(systemName: "arrow.right")
                        .font(.custom("EBGaramond-Regular", size: 24)).fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.trailing, 38)
                        .padding(.bottom, 36)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $presentingSheet) {
            TermsOfServiceView(hasAcceptedTerms: $hasAcceptedTerms)
        }
        .onChange(of: hasAcceptedTerms) { oldValue, newValue in
            if newValue {
                typingTimer?.invalidate()
                onAgreed()
            }
        }
    }

    // MARK: – Typewriter logic
    private func startTyping() {
        typingTimer?.invalidate()
        displayedText = ""
        charIndex = 0
        showArrow = false

        typingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            guard charIndex < message.count else {
                typingTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeIn(duration: 0.3)) { showArrow = true }
                }
                return
            }
            let idx = message.index(message.startIndex, offsetBy: charIndex)
            displayedText.append(message[idx])
            charIndex += 1
            triggerLetterHaptic()
        }
    }

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private func triggerLetterHaptic() {
        feedbackGenerator.impactOccurred(intensity: 0.6)
        feedbackGenerator.prepare()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TermsOfServiceGateView(onAgreed: {})
    }
    .preferredColorScheme(.dark)
} 