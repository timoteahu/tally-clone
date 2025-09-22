import SwiftUI
import UIKit
import StripePaymentSheet

// MARK: - Helper Structs


/// Stand-alone onboarding introduction (marketing copy / typewriter).
struct OnboardingIntroView: View {
    let onFinished: () -> Void
    let initialOnboardingState: Int? // New parameter for immediate phase initialization

    // Dynamic font size: smaller on narrow devices
    private let fontSize: CGFloat = UIScreen.main.bounds.width < 360 ? 22 : 26

    // MARK: – Flow phase: ToS → Intro → Habit Prompt → Habit Demo → Payment → Payment Setup → Final welcome
    private enum Phase { case terms, intro, habitPrompt, habitDemo, payment, paymentSetup, finish }
    
    // Initialize phase immediately using the passed parameter
    @State private var phase: Phase
    
    init(onFinished: @escaping () -> Void, initialOnboardingState: Int? = nil) {
        self.onFinished = onFinished
        self.initialOnboardingState = initialOnboardingState
        // Set initial phase based on onboarding state
        let state = initialOnboardingState ?? 0
        print("🎭 [OnboardingIntroView] INIT - received initialOnboardingState: \(initialOnboardingState?.description ?? "nil")")
        print("🎭 [OnboardingIntroView] INIT - using state: \(state)")
        
        switch state {
        case 0: 
            print("🎭 [OnboardingIntroView] INIT - setting phase to .terms")
            self._phase = State(initialValue: .terms)
        case 1: 
            // Skip intro and go to habit prompt
            print("🎭 [OnboardingIntroView] INIT - skipping intro, setting phase to .habitPrompt")
            self._phase = State(initialValue: .habitPrompt)
        case 2: 
            print("🎭 [OnboardingIntroView] INIT - setting phase to .habitPrompt")
            self._phase = State(initialValue: .habitPrompt)
        case 3: 
            print("🎭 [OnboardingIntroView] INIT - setting phase to .payment")
            self._phase = State(initialValue: .payment)
        case 4:
            print("🎭 [OnboardingIntroView] INIT - setting phase to .paymentSetup")
            self._phase = State(initialValue: .paymentSetup)
        default: 
            print("🎭 [OnboardingIntroView] INIT - fallback to .terms for state: \(state)")
            self._phase = State(initialValue: .terms) // fallback
        }
    }

    // MARK: – Segment definition
    private enum Segment {
        case plain(String)
        case rolling(prefix: String, words: [String])
    }

    private let segments: [Segment] = [
        .plain("when was the last time you\nactually followed through?"),
        .plain("what happened to showing up?"),
        .plain("what happened to you?"),
        .rolling(prefix: "you said you'd stop ", words: ["gooning", "doomscrolling", "_____"]),
        .rolling(prefix: "that'd you'd ",      words: ["wake up early", "go to the gym", "finally start"]),
        .plain("sure you meant it"),
        .plain("but meaning it isn't enough"),
        .plain("you don't need another pastel\nhabit tracker"),
        .plain("you need stakes"),
        .plain("welcome to tally"),
        .plain("the app that charges you 50 cents\nwhen you fold,"),
        .plain("and gives it to your friends\n(or enemies)."),
        .plain("because you should bet\non yourself."),
        .plain("see you at the arena"),
        .plain("- cayden, chief meme officer\n@tally"),
        .plain("it's game time, baby.") // final line
    ]

    private let typingSpeed: Double = 0.02 // Increased speed from 0.025 for better performance
    private let pauseDuration: Double = 1.0
    private let rollingWordDisplayTime: Double = 0.8

    // MARK: – State
    @State private var segmentIndex = 0
    @State private var charIndex = 0
    @State private var displayedPrefix = ""
    @State private var currentRollingWordIndex = 0
    @State private var wordCharIndex: Int = 0
    @State private var isRolling = false
    @State private var isFadingLine = false
    @State private var lineOpacity: Double = 1.0
    @State private var typingTimer: Timer? = nil
    @State private var activeRollingPrefix: String = ""
    @State private var displayedWord: String = ""
    
    // Skip functionality
    @State private var showSkipButton = false
    @State private var hasUserTapped = false
    
    // Habit demo state
    @State private var addHabitStep = 0
    @State private var isTransitioningFromHabitDemo = false // Prevent race conditions
    
    @EnvironmentObject var paymentManager: PaymentManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var customHabitManager: CustomHabitManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var habitManager: HabitManager

    // Haptic handled by shared throttler

    var body: some View {
        ZStack {
            AppBackground()

            switch phase {
            case .terms:
                TermsOfServiceGateView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        // Skip intro and go directly to habit creation
                        phase = .habitPrompt
                    }
                    Task { await authManager.updateOnboardingState(to: 2) }
                }
                .transition(.opacity)
                .onAppear {
                    print("🎭 [OnboardingIntroView] RENDERING .terms phase")
                }

            case .intro:
                // Intro phase is skipped - immediately go to habit prompt
                EmptyView()
                    .onAppear {
                        print("🎭 [OnboardingIntroView] Skipping intro phase, going to habitPrompt")
                        withAnimation(.easeInOut(duration: 0.6)) {
                            phase = .habitPrompt
                        }
                        Task { await authManager.updateOnboardingState(to: 2) }
                    }

            case .habitPrompt:
                HabitCreationPromptView(onContinue: {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        phase = .habitDemo
                    }
                    Task { await authManager.updateOnboardingState(to: 2) }
                }, onSkip: {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        phase = .payment
                    }
                    Task { await authManager.updateOnboardingState(to: 3) }
                })
                .transition(.opacity)
                .onAppear {
                    print("🎭 [OnboardingIntroView] RENDERING .habitPrompt phase")
                }

            case .habitDemo:
                ZStack {
                    AddHabitRoot(
                        isOnboarding: true,
                        onOnboardingComplete: {
                            // IMPORTANT: Only allow AddHabitRoot to complete if overlay is not managing completion
                            // This prevents race condition where both overlay and AddHabitRoot try to complete simultaneously
                            guard !isTransitioningFromHabitDemo else {
                                print("🎭 [OnboardingIntroView] AddHabitRoot completion blocked - already transitioning or overlay managing completion")
                                return
                            }
                            
                            // Additional check: Only complete from AddHabitRoot if user manually navigated through all steps
                            // If they're on the final step with overlay active, let overlay handle completion
                            guard addHabitStep >= 2 else {
                                print("🎭 [OnboardingIntroView] AddHabitRoot completion blocked - not on final step or overlay should handle completion")
                                return
                            }
                            
                            print("🎭 [OnboardingIntroView] AddHabitRoot onOnboardingComplete called")
                            isTransitioningFromHabitDemo = true
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .payment
                            }
                            Task { await authManager.updateOnboardingState(to: 3) }
                        },
                        onStepChanged: { step in
                            print("🎭 [OnboardingIntroView] AddHabit step changed to: \(step)")
                            addHabitStep = step
                        }
                    )
                    .environmentObject(customHabitManager)
                    .environmentObject(friendsManager)
                    
                    OnboardingHabitEducationOverlay(
                        currentAddHabitStep: addHabitStep,
                        onNext: {
                            // Advance the actual AddHabitRoot step
                            print("🎭 [OnboardingIntroView] Overlay onNext called - advancing AddHabit step")
                            NotificationCenter.default.post(name: NSNotification.Name("AddHabitStepForward"), object: nil)
                        },
                        onSkip: {
                            // User skipped the demo entirely - go to payment
                            guard !isTransitioningFromHabitDemo else {
                                print("🎭 [OnboardingIntroView] Overlay skip blocked - already transitioning")
                                return
                            }
                            print("🎭 [OnboardingIntroView] Overlay onSkip called - skipping to payment")
                            isTransitioningFromHabitDemo = true
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .payment
                            }
                            Task { await authManager.updateOnboardingState(to: 3) }
                        },
                        onComplete: {
                            // User completed the demo - go to payment
                            // This is the PRIMARY completion path when overlay manages the flow
                            guard !isTransitioningFromHabitDemo else {
                                print("🎭 [OnboardingIntroView] Overlay complete blocked - already transitioning")
                                return
                            }
                            print("🎭 [OnboardingIntroView] Overlay onComplete called - completed demo, going to payment")
                            isTransitioningFromHabitDemo = true
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .payment
                            }
                            Task { await authManager.updateOnboardingState(to: 3) }
                        }
                    )
                }
                .transition(.opacity)
                .onAppear {
                    print("🎭 [OnboardingIntroView] RENDERING .habitDemo phase")
                    addHabitStep = 0 // Reset step when entering habit demo
                    isTransitioningFromHabitDemo = false // Reset race condition flag
                }

            case .payment:
                ZStack {
                    PaymentRoot(onDismiss: {
                        // User completed payment setup
                        print("🎭 [OnboardingIntroView] PaymentRoot onDismiss called - this should NOT happen automatically!")
                        Task { await authManager.updateOnboardingState(to: 4) }
                        proceedToFinal()
                    })
                    .environmentObject(authManager)
                    .environmentObject(habitManager)
                    .environmentObject(paymentManager)
                    
                    OnboardingPaymentEducationOverlay(
                        onNext: {
                            // User finished the educational overlay - just let them interact
                            print("🎭 [OnboardingIntroView] Payment overlay onNext called - overlay dismissed")
                            // Don't advance phase, let user interact with PaymentRoot naturally
                        },
                        onSkip: {
                            // User wants to skip payment - go to payment setup
                            print("🎭 [OnboardingIntroView] Payment overlay onSkip called - going to payment setup")
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .paymentSetup
                            }
                            Task { await authManager.updateOnboardingState(to: 4) }
                        },
                        onComplete: {
                            // User chose payment method - go to payment setup
                            print("🎭 [OnboardingIntroView] Payment overlay completed - going to payment setup")
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .paymentSetup
                            }
                            Task { await authManager.updateOnboardingState(to: 4) }
                        },
                        onStripeConnect: {
                            // User chose Stripe Connect - go to payment setup view which will handle it
                            print("🎭 [OnboardingIntroView] Stripe Connect selected - going to payment setup")
                            withAnimation(.easeInOut(duration: 0.6)) {
                                phase = .paymentSetup
                            }
                            Task { await authManager.updateOnboardingState(to: 4) }
                        }
                    )
                }
                .transition(.opacity)
                .onAppear {
                    print("🎭 [OnboardingIntroView] RENDERING .payment phase")
                }

            case .paymentSetup:
                PaymentSetupView(onDismiss: {
                    // User completed payment setup - this should complete onboarding
                    print("🎭 [OnboardingIntroView] PaymentSetupView onDismiss called - completing onboarding")
                    Task { await authManager.updateOnboardingState(to: 5) }
                    proceedToFinal()
                })
                .environmentObject(authManager)
                .environmentObject(paymentManager)
                .transition(.opacity)
                .onAppear {
                    print("🎭 [OnboardingIntroView] RENDERING .paymentSetup phase")
                }

            case .finish:
                Text(finalDisplayedText)
                    .font(.custom("EBGaramond-Regular", size: fontSize))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .onAppear {
                        print("🎭 [OnboardingIntroView] RENDERING .finish phase")
                        startFinalTyping()
                    }
                    .onDisappear { finalTypingTimer?.invalidate() }
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            print("🎭 [OnboardingIntroView] Main onAppear called with phase: \(phase)")
            initializePhaseFromStoredState()
        }
    }

    // MARK: – View builders

    @ViewBuilder private var lineView: some View {
        if segmentIndex >= segments.count {
            EmptyView()
        } else {
            switch segments[segmentIndex] {
            case .plain(_):
                Text(displayedPrefix)
                    .font(.custom("EBGaramond-Regular", size: fontSize))
                    .foregroundColor(.white)
                    .opacity(lineOpacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
            case let .rolling(_, words):
                HStack(spacing: 0) {
                    Text(displayedPrefix)
                        .font(.custom("EBGaramond-Regular", size: fontSize))
                        .foregroundColor(.white)
                    ZStack(alignment: .leading) {
                        // invisible placeholder to reserve width
                        Text(words.max(by: { $0.count < $1.count }) ?? "")
                            .opacity(0)
                        Text(displayedWord)
                            .font(.custom("EBGaramond-Regular", size: fontSize))
                            .foregroundColor(.white)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: – Segment handling

    private func startSegment() {
        guard segmentIndex < segments.count else {
            // Move to habit demo phase after intro text completes
            if phase == .intro {
                withAnimation(.easeInOut(duration: 0.6)) {
                    phase = .habitPrompt
                }
                Task { await authManager.updateOnboardingState(to: 2) }
            } else {
                // FIXED: Don't call onFinished() here - this was causing random skips to completion
                // startSegment() should only be used during the intro phase
                print("🎭 [OnboardingIntroView] startSegment called outside intro phase (\(phase)) - ignoring")
            }
            return
        }

        charIndex = 0
        displayedPrefix = ""
        displayedWord = ""
        wordCharIndex = 0
        lineOpacity = 1
        isFadingLine = false
        currentRollingWordIndex = 0
        isRolling = false
        activeRollingPrefix = ""

        typingTimer?.invalidate()

        typingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            typeStep()
        }

        triggerLetterHaptic() // haptic when new segment starts
    }

    private func typeStep() {
        switch segments[segmentIndex] {
        case let .plain(text):
            handlePlainTyping(text: text)
        case let .rolling(prefix, words):
            handleRollingTyping(prefix: prefix, words: words)
        }
    }

    private func handlePlainTyping(text: String) {
        if isFadingLine { return }

        if charIndex < text.count {
            let idx = text.index(text.startIndex, offsetBy: charIndex)
            displayedPrefix.append(text[idx])
            charIndex += 1
            triggerLetterHaptic()
        } else {
            // Finished typing plain line
            typingTimer?.invalidate()
            // Fade out after pause
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                fadeOutLineAndAdvance()
            }
        }
    }

    private func handleRollingTyping(prefix: String, words: [String]) {
        // Phase 1: type prefix
        if !isRolling {
            if charIndex < prefix.count {
                let idx = prefix.index(prefix.startIndex, offsetBy: charIndex)
                displayedPrefix.append(prefix[idx])
                charIndex += 1
                triggerLetterHaptic()
                return
            } else {
                // Prefix done
                isRolling = true
                activeRollingPrefix = prefix
                charIndex = 0
                wordCharIndex = 0
                displayedWord = ""
            }
        }

        // Phase 2: type current word
        let word = words[currentRollingWordIndex]
        if wordCharIndex < word.count {
            let idx = word.index(word.startIndex, offsetBy: wordCharIndex)
            displayedWord.append(word[idx])
            wordCharIndex += 1
            triggerLetterHaptic()
        } else {
            // Finished current word
            typingTimer?.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + rollingWordDisplayTime) {
                if currentRollingWordIndex == words.count - 1 {
                    // last word → fade out line then advance
                    fadeOutLineAndAdvance()
                } else {
                    // next word
                    currentRollingWordIndex += 1
                    displayedWord = ""
                    wordCharIndex = 0
                    // restart typing timer
                    typingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
                        typeStep()
                    }
                }
            }
        }
    }

    private func fadeOutLineAndAdvance() {
        isFadingLine = true
        withAnimation(.easeOut(duration: 0.5)) { lineOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            segmentIndex += 1
            startSegment()
        }
    }

    private func triggerLetterHaptic() {
        HapticThrottler.trigger()
    }

    // MARK: – Initial Phase Helper
    private func initializePhaseFromStoredState() {
        guard !initialized else { return }
        initialized = true
        
        let currentState = initialOnboardingState ?? authManager.currentUser?.onboardingState ?? 0
        print("🎭 [OnboardingIntroView] Initializing with state: \(currentState) (from parameter: \(initialOnboardingState?.description ?? "nil"), from user: \(authManager.currentUser?.onboardingState.description ?? "nil"))")
        
        // CRITICAL FIX: Only update phase if we have a cached state parameter AND backend disagrees
        // If we were passed an initialOnboardingState (cached), trust it over backend during startup
        if let initialParam = initialOnboardingState {
            print("🎭 [OnboardingIntroView] Trusting cached state (\(initialParam)) - not overriding with backend state")
            
            // Only override if backend shows completion (state 5+) which means user completed onboarding elsewhere
            let backendState = authManager.currentUser?.onboardingState ?? 0
            print("🎭 [OnboardingIntroView] Comparing cached state \(initialParam) with backend state \(backendState)")
            if backendState >= 5 {
                print("🎭 [OnboardingIntroView] Backend shows completed onboarding (\(backendState)) - finishing")
                print("🎭 [OnboardingIntroView] initializePhaseFromStoredState calling onFinished due to backend completion")
                onFinished()
            } else {
                print("🎭 [OnboardingIntroView] Keeping initially set phase: \(phase) for cached state: \(initialParam)")
            }
        } else {
            // No cached state, use backend state
            let backendState = authManager.currentUser?.onboardingState ?? 0
            print("🎭 [OnboardingIntroView] No cached state - using backend state: \(backendState)")
            
            switch backendState {
            case 0: 
                if phase != .terms { 
                    print("🎭 [OnboardingIntroView] Setting phase to .terms based on backend state 0")
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .terms }
                }
            case 1: 
                // Skip intro and go to habit prompt for state 1
                if phase != .habitPrompt { 
                    print("🎭 [OnboardingIntroView] Skipping intro, setting phase to .habitPrompt based on backend state 1")
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .habitPrompt }
                }
            case 2: 
                if phase != .habitPrompt { 
                    print("🎭 [OnboardingIntroView] Setting phase to .habitPrompt based on backend state 2")
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .habitPrompt }
                }
            case 3: 
                if phase != .payment { 
                    print("🎭 [OnboardingIntroView] Setting phase to .payment based on backend state 3")
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .payment }
                }
            case 4: 
                if phase != .paymentSetup { 
                    print("🎭 [OnboardingIntroView] Setting phase to .paymentSetup based on backend state 4")
                    withAnimation(.easeInOut(duration: 0.3)) { phase = .paymentSetup }
                }
            default:
                // Already completed onboarding – skip view
                print("🎭 [OnboardingIntroView] Backend shows completed onboarding (state \(backendState)) - finishing")
                print("🎭 [OnboardingIntroView] Default case calling onFinished - backend state was: \(backendState)")
                onFinished()
            }
        }
    }

    @State private var initialized: Bool = false
    // Track whether we've already scheduled the first typing start
    @State private var hasScheduledIntroTyping: Bool = false

    // MARK: – Navigation helper
    private func proceedToFinal() {
        guard phase != .finish else { return }
        print("🎭 [OnboardingIntroView] proceedToFinal called - transitioning to finish phase")
        finalDisplayedText = ""
        finalCharIndex = 0
        finalTypingTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.6)) { phase = .finish }
    }

    // MARK: – Final typewriter
    @State private var finalDisplayedText: String = ""
    @State private var finalCharIndex: Int = 0
    @State private var finalTypingTimer: Timer? = nil
    private let finalMessage = "welcome to tally."

    private func startFinalTyping() {
        finalTypingTimer?.invalidate()
        finalDisplayedText = ""
        finalCharIndex = 0
        finalTypingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            if finalCharIndex < finalMessage.count {
                let idx = finalMessage.index(finalMessage.startIndex, offsetBy: finalCharIndex)
                finalDisplayedText.append(finalMessage[idx])
                finalCharIndex += 1
                triggerLetterHaptic()
            } else {
                finalTypingTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🎭 [OnboardingIntroView] Final typing animation completed - completing onboarding")
                    // Ensure we complete onboarding when finishing the welcome message
                    Task { await authManager.updateOnboardingState(to: 5) }
                    onFinished()
                }
            }
        }
    }

    // MARK: – Intro appear helper with initial 0.5 s delay
    private func handleIntroAppear() {
        guard !hasScheduledIntroTyping else {
            startSegment(); return
        }
        hasScheduledIntroTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startSegment()
        }
    }
}

// MARK: – Habit Creation Prompt View

private struct HabitCreationPromptView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let fontSize: CGFloat = UIScreen.main.bounds.width < 360 ? 18 : 22
    private let message = "let's create your first habit.\n\nthis is where the magic happens."
    private let typingSpeed: Double = 0.02

    @State private var displayedText = ""
    @State private var charIndex = 0
    @State private var typingTimer: Timer? = nil
    @State private var showControls = false
    // Flag to ensure 0.5 s delay only on the first presentation
    @State private var hasScheduledInitialTyping = false

    var body: some View {
        ZStack {
            // Centered content
            VStack(spacing: 16) {
                ZStack(alignment: .trailing) {
                    Text(displayedText)
                        .font(.custom("EBGaramond-Regular", size: fontSize))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 32)
                        .padding(.trailing, 60) // leave room for arrow

                    if showControls {
                        Button(action: onContinue) {
                            Image(systemName: "arrow.right")
                                .font(.custom("EBGaramond-Regular", size: 24)).fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.trailing, 32)
                        .transition(.opacity)
                    }
                }

                if showControls {
                    Button(action: onSkip) {
                        Text("skip for now")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 32)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear { handleAppear() }
            .onDisappear { typingTimer?.invalidate() }
        }
    }

    // MARK: – Typewriter logic
    private func handleAppear() {
        guard !hasScheduledInitialTyping else {
            startTyping(); return
        }
        hasScheduledInitialTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startTyping()
        }
    }

    private func startTyping() {
        typingTimer?.invalidate()
        displayedText = ""
        charIndex = 0
        showControls = false

        typingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            guard charIndex < message.count else {
                typingTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeIn(duration: 0.3)) { showControls = true }
                }
                return
            }
            let idx = message.index(message.startIndex, offsetBy: charIndex)
            displayedText.append(message[idx])
            charIndex += 1
            triggerLetterHaptic()
        }
    }

    private func triggerLetterHaptic() {
        HapticThrottler.trigger()
    }
}

// MARK: – Shared haptic throttler (16 Hz ceiling for smoother performance)
fileprivate enum HapticThrottler {
    private static let generator = UIImpactFeedbackGenerator(style: .light)
    private static var lastTimestamp: CFTimeInterval = 0

    static func trigger(intensity: CGFloat = 0.4) { // Reduced intensity for subtlety
        let now = CACurrentMediaTime()
        if now - lastTimestamp >= (1.0 / 16.0) { // Reduced from 32 Hz to 16 Hz
            generator.impactOccurred(intensity: intensity)
            generator.prepare()
            lastTimestamp = now
        }
    }
} 

// MARK: – Payment Setup View

private struct PaymentSetupView: View {
    let onDismiss: () -> Void
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var paymentManager: PaymentManager
    
    private let fontSize: CGFloat = UIScreen.main.bounds.width < 360 ? 18 : 22
    private let message = "ready to set up your account?\n\nchoose what you'd like to configure."
    private let skipMessage = "no problem, you can add this\nlater in your settings."
    private let typingSpeed: Double = 0.02

    @State private var displayedText = ""
    @State private var charIndex = 0
    @State private var typingTimer: Timer? = nil
    @State private var showControls = false
    @State private var showingSkipAck = false
    @State private var hasScheduledInitialTyping = false
    
    // PaymentSheet state
    @State private var paymentSheet: PaymentSheet? = nil
    @State private var isLoadingPaymentSheet = false
    @State private var isLoadingStripeConnect = false

    var body: some View {
        ZStack {
            // Centered content
            VStack(spacing: 24) {
                Text(displayedText)
                    .font(.custom("EBGaramond-Regular", size: fontSize))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if showControls && !showingSkipAck {
                    VStack(spacing: 16) {
                        // Payment method button
                        Button(action: { Task { await setupPaymentMethod() } }) {
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
                                if isLoadingPaymentSheet {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16))
                                }
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
                        .disabled(isLoadingPaymentSheet)
                        .padding(.horizontal, 32)
                        
                        // Stripe Connect button
                        Button(action: { openStripeConnect() }) {
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
                                if isLoadingStripeConnect {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 16))
                                }
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
                        .disabled(isLoadingStripeConnect)
                        .padding(.horizontal, 32)
                    }
                    .transition(.opacity)
                    
                    Button(action: { onDismiss() }) {
                        Text("continue ->")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 16)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear { handleAppear() }
            .onDisappear { typingTimer?.invalidate() }
        }
    }

    private func handleAppear() {
        guard !hasScheduledInitialTyping else {
            startTyping(); return
        }
        hasScheduledInitialTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startTyping()
        }
    }

    private func startTyping(text: String? = nil, afterComplete: (() -> Void)? = nil) {
        typingTimer?.invalidate()
        displayedText = ""
        charIndex = 0
        showControls = false

        let stringToType = text ?? message

        typingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            guard charIndex < stringToType.count else {
                typingTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !showingSkipAck {
                        withAnimation(.easeIn(duration: 0.3)) { showControls = true }
                    }
                    afterComplete?()
                }
                return
            }
            let idx = stringToType.index(stringToType.startIndex, offsetBy: charIndex)
            displayedText.append(stringToType[idx])
            charIndex += 1
            triggerLetterHaptic()
        }
    }

    private func triggerLetterHaptic() {
        HapticThrottler.trigger()
    }

    private func handleSkip() {
        withAnimation { showControls = false }
        displayedText = ""
        charIndex = 0
        showingSkipAck = true
        startTyping(text: skipMessage, afterComplete: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        })
    }
    
    private func setupPaymentMethod() async {
        guard paymentSheet == nil else { return }
        isLoadingPaymentSheet = true

        do {
            // Request a SetupIntent from backend
            guard let url = URL(string: "\(AppConfig.baseURL)/payments/create-setup-intent") else { 
                throw URLError(.badURL) 
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let token = UserDefaults.standard.string(forKey: "authToken") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 {
                throw NSError(domain: "", code: httpResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create setup intent"])
            }

            let decoded = try JSONDecoder().decode(SetupIntentResponse.self, from: data)

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Joy Thief"
            config.allowsDelayedPaymentMethods = true

            let sheet = PaymentSheet(setupIntentClientSecret: decoded.clientSecret, configuration: config)

            await MainActor.run {
                guard let topVC = topMostViewController() else {
                    print("❌ Unable to find top view controller")
                    handleSkip()
                    return
                }

                paymentSheet = sheet
                isLoadingPaymentSheet = false

                sheet.present(from: topVC) { _ in
                    paymentSheet = nil
                    Task {
                        let token = UserDefaults.standard.string(forKey: "authToken") ?? ""
                        _ = await paymentManager.fetchPaymentMethod(token: token)
                        // Don't auto-dismiss - let user click skip or complete setup
                    }
                }
            }
        } catch {
            print("❌ Error setting up payment: \(error)")
            await MainActor.run {
                isLoadingPaymentSheet = false
                handleSkip()
            }
        }
    }
    
    private func topMostViewController() -> UIViewController? {
        var topController: UIViewController?
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            topController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }
    
    private func openStripeConnect() {
        isLoadingStripeConnect = true
        
        Task {
            do {
                // Step 1: Create Stripe Connect account if needed
                guard let createAccountURL = URL(string: "\(AppConfig.baseURL)/payments/connect/create-account") else {
                    throw URLError(.badURL)
                }
                
                var createRequest = URLRequest(url: createAccountURL)
                createRequest.httpMethod = "POST"
                createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                if let token = UserDefaults.standard.string(forKey: "authToken") {
                    createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                
                let (accountData, accountResponse) = try await URLSession.shared.data(for: createRequest)
                
                guard let httpResponse = accountResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Connect account"])
                }
                
                struct AccountResponse: Codable {
                    let account_id: String
                }
                
                let accountResult = try JSONDecoder().decode(AccountResponse.self, from: accountData)
                
                // Step 2: Create account link for onboarding
                guard let linkURL = URL(string: "\(AppConfig.baseURL)/payments/connect/create-account-link") else {
                    throw URLError(.badURL)
                }
                
                var linkRequest = URLRequest(url: linkURL)
                linkRequest.httpMethod = "POST"
                linkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                if let token = UserDefaults.standard.string(forKey: "authToken") {
                    linkRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                
                let linkBody = [
                    "account_id": accountResult.account_id,
                    "refresh_url": "https://jointally.app/payment/refresh",
                    "return_url": "https://jointally.app/payment/return"
                ]
                
                linkRequest.httpBody = try JSONSerialization.data(withJSONObject: linkBody)
                
                let (linkData, linkResponse) = try await URLSession.shared.data(for: linkRequest)
                
                guard let linkHttpResponse = linkResponse as? HTTPURLResponse, linkHttpResponse.statusCode == 200 else {
                    // Log the response for debugging
                    if let responseString = String(data: linkData, encoding: .utf8) {
                        print("❌ Stripe Connect link error response: \(responseString)")
                    }
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create onboarding link"])
                }
                
                struct LinkResponse: Codable {
                    let url: String
                }
                
                let linkResult = try JSONDecoder().decode(LinkResponse.self, from: linkData)
                
                // Step 3: Open the onboarding link
                await MainActor.run {
                    if let onboardingURL = URL(string: linkResult.url) {
                        UIApplication.shared.open(onboardingURL)
                    }
                    isLoadingStripeConnect = false
                }
                
            } catch {
                print("❌ Error setting up Stripe Connect: \(error)")
                await MainActor.run {
                    isLoadingStripeConnect = false
                    // Could show an alert here
                }
            }
        }
    }
} 
