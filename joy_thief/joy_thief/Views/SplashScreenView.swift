import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    // Enhanced animation states for the tally text
    @State private var currentText = "t"
    @State private var textScale: Double = 1.0
    @State private var textOpacity: Double = 0.0
    @State private var letterRotations: [Double] = [0, 0, 0, 0, 0]
    @State private var letterOffsets: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var letterOpacities: [Double] = [1, 0, 0, 0, 0]
    @State private var showingPulse = false
    @State private var glowIntensity: Double = 0.0
    
    // Animation timing tracking
    @State private var animationStartTime: Date?
    @State private var isAnimationComplete = false
    @State private var isPendingUIActivation = false
    
    // Create shared manager instances only once at the top level
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var habitManager = HabitManager.shared
    @StateObject private var friendsManager = FriendsManager.shared
    @StateObject private var paymentManager = PaymentManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @Environment(BranchService.self) private var branchService
    @StateObject private var loadingManager = LoadingStateManager.shared
    @StateObject private var customHabitManager = CustomHabitManager.shared
    @StateObject private var feedManager = FeedManager.shared
    @StateObject private var preloadManager = PreloadManager.shared
    @StateObject private var dataCacheManager = DataCacheManager.shared
    @StateObject private var backgroundUpdateManager = BackgroundUpdateManager.shared
    @StateObject private var friendRecommendationsManager = FriendRecommendationsManager.shared
    @StateObject private var identitySnapshotManager = IdentitySnapshotManager.shared
    @StateObject private var paymentStatsManager = PaymentStatsManager.shared
    @StateObject private var recipientAnalyticsManager = RecipientAnalyticsManager.shared
    
    @State private var isPreloading = false
    @State private var showOnboardingIntro = false
    
    // Race condition protection: track recent signup completion
    @State private var recentSignupCompletionTime: Date?
    
    // Break up the complex ContentView expression to avoid type-checking timeout
    private var mainContentView: some View {
        ContentView()
            .environmentObject(authManager)
            .environmentObject(habitManager)
            .environmentObject(friendsManager)
            .environmentObject(paymentManager)
            .environmentObject(contactManager)
            .environment(branchService)
            .environmentObject(loadingManager)
            .environmentObject(customHabitManager)
            .environmentObject(feedManager)
            .environmentObject(dataCacheManager)
            .environmentObject(backgroundUpdateManager)
            .environmentObject(friendRecommendationsManager)
            .environmentObject(identitySnapshotManager)
            .environmentObject(paymentStatsManager)
            .environmentObject(recipientAnalyticsManager)
            .transition(.opacity)
    }

    var body: some View {
        ZStack {
            // Unified gradient background used across the app
            AppBackground()
            
            if isActive && !authManager.needsPreloading {
                mainContentView
            } else {
                // Enhanced splash screen content
                VStack {
                    Spacer()
                    
                    // Creative animated text transformation
                    ZStack {
                        // Glow effect background
                        Text("tally")
                            .font(.custom("EBGaramond-Regular", size: 44))
                            .foregroundColor(.white.opacity(0.3))
                            .blur(radius: glowIntensity)
                            .scaleEffect(1.1)
                        
                        // Main text with individual letter animations
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Text(String(Array("tally")[index]))
                                    .font(.custom("EBGaramond-Regular", size: 40))
                                    .foregroundColor(.white)
                                    .opacity(letterOpacities[index])
                                    .scaleEffect(index == 0 ? textScale : 1.0)
                                    .rotationEffect(.degrees(letterRotations[index]))
                                    .offset(y: letterOffsets[index])
                                    .animation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0), value: letterOpacities[index])
                                    .animation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0), value: letterOffsets[index])
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: letterRotations[index])
                            }
                        }
                        .scaleEffect(showingPulse ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: showingPulse)
                    }
                    .opacity(textOpacity)
                    
                    // NEW: Animated typing text below the main logo
                    TypingTextView(
                        phrases: ["cutting the bullsh*t", "unpacking the excuses", "redefining discipline"],
                        typingSpeed: 0.05,
                        pauseDuration: 1.0
                    )
                    .frame(height: 28)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    
                    Spacer()
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    print("🎬 [SplashScreenView] Splash screen onAppear - starting text animation")
                    startEnhancedTextAnimation()
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 0.9
                        self.opacity = 1.0
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            print("🎬 [SplashScreenView] Main body onAppear - starting preload task")
            Task {
                await preloadDataWithCache()
            }
        }
        .onChange(of: authManager.needsPreloading) { oldValue, needsPreloading in
            print("🔄 [SplashScreenView] needsPreloading changed: \(oldValue) -> \(needsPreloading)")
            if needsPreloading {
                print("🔄 [SplashScreenView] Resetting to splash screen state")
                // Reset to splash screen state when preloading is needed
                isActive = false
                
                // Reset text animation
                resetEnhancedTextAnimation()
                if !isPreloading {startEnhancedTextAnimation()}
                
                Task {
                    print("🔄 [SplashScreenView] Starting preload task due to needsPreloading")
                    await preloadDataWithCache()
                }
            }
        }
        .onChange(of: authManager.isAuthenticated) { oldValue, isAuth in
            print("🔐 [SplashScreenView] isAuthenticated changed: \(oldValue) -> \(isAuth)")
            if !isAuth {
                // Clear onboarding intro when user logs out
                showOnboardingIntro = false
                print("🔐 [SplashScreenView] Cleared onboarding intro due to logout")
            } else {
                // Immediately check onboarding state when user becomes authenticated
                if shouldShowOnboardingIntro() {
                    showOnboardingIntro = true
                    print("🔐 [SplashScreenView] Will show onboarding intro")
                } else {
                    print("🔐 [SplashScreenView] Will NOT show onboarding intro")
                }
            }
            // Preload custom habit types once the user logs in
            if isAuth,
               customHabitManager.customHabitTypes.isEmpty,
               let token = AuthenticationManager.shared.storedAuthToken {
                Task { await customHabitManager.preloadAll(token: token) }
                print("🔐 [SplashScreenView] Started preloading custom habit types")
            }

            // Initialize PaymentStatsManager when user logs in
            if isAuth {
                paymentStatsManager.initializeIfAuthenticated()
                print("🔐 [SplashScreenView] Initialized PaymentStatsManager")
            }

            guard isAuth, branchService.pendingInviteData != nil else { return }
        }
        .onChange(of: isActive) { oldValue, newValue in
            print("🎬 [SplashScreenView] isActive changed: \(oldValue) -> \(newValue)")
        }
        .onChange(of: isPreloading) { oldValue, newValue in
            print("🔄 [SplashScreenView] isPreloading changed: \(oldValue) -> \(newValue)")
        }
        .onChange(of: authManager.currentUser?.avatarUrl80) { oldValue, newValue in
            // When avatar URL changes (e.g., after upload during onboarding), trigger download
            if let newValue = newValue, !newValue.isEmpty, oldValue != newValue {
                print("🖼️ [SplashScreenView] Avatar URL changed, triggering download...")
                startIndependentAvatarLoading()
            }
        }
    }
    
    private func resetEnhancedTextAnimation() {
        currentText = "t"
        textScale = 1.0
        textOpacity = 0.0
        letterRotations = [0, 0, 0, 0, 0]
        letterOffsets = [0, 0, 0, 0, 0]
        letterOpacities = [1, 0, 0, 0, 0]
        showingPulse = false
        glowIntensity = 0.0
        
        // Reset animation tracking
        animationStartTime = nil
        isAnimationComplete = false
        isPendingUIActivation = false
    }
    
    private func startEnhancedTextAnimation() {
        // Reset to initial state
        resetEnhancedTextAnimation()
        
        // Track animation start time
        animationStartTime = Date()
        isAnimationComplete = false
        print("🎬 [SplashScreenView] Starting splash animation (total duration: ~1.3s)")
        
        // Phase 1: Fade in the "t" with a gentle bounce (0.3s)
        withAnimation(.easeOut(duration: 0.3)) {
            textOpacity = 1.0
            textScale = 1.3
            glowIntensity = 8.0
        }
        
        // Phase 2: Settle the "t" (0.15s delay + 0.2s animation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                self.textScale = 1.0
                self.glowIntensity = 3.0
            }
        }
        
        // Phase 3: Dramatic reveal of remaining letters (0.4s delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // First, make "t" jump up slightly
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                self.letterOffsets[0] = -10
                self.letterRotations[0] = 5
            }
            
            // Then bring in "a" from the right with rotation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    self.letterOpacities[1] = 1.0
                    self.letterOffsets[1] = -8
                    self.letterRotations[1] = -10
                }
            }
            
            // Then "l" drops in from above
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    self.letterOpacities[2] = 1.0
                    self.letterOffsets[2] = -5
                    self.letterRotations[2] = 8
                }
            }
            
            // Second "l" bounces in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    self.letterOpacities[3] = 1.0
                    self.letterOffsets[3] = -6
                    self.letterRotations[3] = -5
                }
            }
            
            // Finally "y" slides in from below
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.letterOpacities[4] = 1.0
                    self.letterOffsets[4] = -4
                    self.letterRotations[4] = 3
                }
            }
            
            // Phase 4: Settle all letters and add subtle pulse (0.4s total delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    // Reset all offsets and rotations
                    self.letterOffsets = [0, 0, 0, 0, 0]
                    self.letterRotations = [0, 0, 0, 0, 0]
                    self.glowIntensity = 5.0
                }
                
                // Start subtle pulsing effect and mark animation complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.showingPulse = true
                    
                    // Mark animation as complete after pulsing starts (total: ~1.3s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.isAnimationComplete = true
                        let totalTime = Date().timeIntervalSince(self.animationStartTime ?? Date())
                        print("🎬 [SplashScreenView] Animation completed after \(String(format: "%.1f", totalTime))s")
                        
                        // If UI activation is pending, activate it now
                        if self.isPendingUIActivation {
                            print("🎬 [SplashScreenView] Activating pending UI...")
                            self.activateUIImmediately()
                        }
                    }
                }
            }
        }
    }
    
    /// NEW: Ultra-fast cache-first startup approach
    private func preloadDataWithCache() async {
        print("🚀 [SplashScreenView] === STARTING PRELOAD PROCESS ===")
        
        isPreloading = true
        authManager.isPreloading = true
        authManager.needsPreloading = false
        
        // Start independent avatar loading immediately (non-blocking)
        startIndependentAvatarLoading()
        
        do {
            let storedToken = AuthenticationManager.shared.storedAuthToken
            print("🔐 [SplashScreenView] Checking stored token... exists: \(storedToken != nil)")
            
            if let token = storedToken {
                // Always validate token first
                print("🔐 [SplashScreenView] Starting token validation...")
                try await authManager.validateToken(token)
                print("✅ [SplashScreenView] Token validation completed")
                
                if authManager.isAuthenticated {
                    // Try to load from cache first
                    let cachedData = dataCacheManager.loadCacheOnlyForStartup()
                    
                    if let cachedData = cachedData {
                        print("✅ [SplashScreenView] Found cached data, applying...")
                        await applyCachedDataToManagers(cachedData)
                        
                        // Wait for animation to complete before activating UI
                        await activateUIRespectingAnimation()
                        
                        // Refresh data in background after UI is active
                        Task.detached(priority: .background) {
                            await self.refreshDataInBackground(token: token)
                        }
                        
                    } else {
                        print("❌ [SplashScreenView] No cached data, loading from network...")
                        await loadDataFromNetwork(token: token)
                        
                        // Wait for animation to complete before activating UI
                        await activateUIRespectingAnimation()
                    }
                } else {
                    print("❌ [SplashScreenView] User not authenticated")
                    await activateUI()
                }
            } else {
                print("❌ [SplashScreenView] No stored token")
                await activateUI()
            }
        } catch {
            print("❌ [SplashScreenView] Error in preload: \(error)")
            await activateUI()
        }
        
        // Always reset loading states
        await MainActor.run {
            self.isPreloading = false
            self.authManager.isPreloading = false
        }
        
        print("🚀 [SplashScreenView] === PRELOAD PROCESS COMPLETED ===")
    }
    
    /// Helper to activate UI immediately without waiting for animation
    private func activateUIImmediately() {
        withAnimation(.easeInOut(duration: 0.5)) {
            self.isActive = true
        }
        isPendingUIActivation = false
    }
    
    /// Helper to activate UI respecting animation timing
    private func activateUIRespectingAnimation() async {
        await MainActor.run {
            if isAnimationComplete {
                // Animation already done, activate immediately
                print("🎬 [SplashScreenView] Animation complete, activating UI immediately")
                activateUIImmediately()
            } else {
                // Animation still running, mark as pending
                print("🎬 [SplashScreenView] Animation in progress, marking UI activation as pending")
                isPendingUIActivation = true
            }
        }
    }
    
    /// Helper to activate UI (legacy - for error cases where we want immediate activation)
    private func activateUI() async {
        await MainActor.run {
            activateUIImmediately()
        }
    }
    
    /// Refresh data in background after UI is already active
    private func refreshDataInBackground(token: String) async {
        print("🔄 [SplashScreenView] Refreshing data in background...")
        
        do {
            let freshData = try await preloadManager.preloadAllAppData(token: token)
            
            // Apply fresh data to managers
            await preloadManager.applyPreloadedDataToManagers(
                freshData,
                habitManager: habitManager,
                friendsManager: friendsManager,
                paymentManager: paymentManager,
                feedManager: feedManager,
                customHabitManager: customHabitManager
            )
            
            // Update cache with fresh data
            let updatedCachedData = CachedAppData(
                habits: freshData.habits,
                friends: freshData.friends,
                friendsWithStripe: freshData.friendsWithStripe,
                feedPosts: freshData.feedPosts,
                customHabitTypes: freshData.customHabitTypes,
                paymentMethod: freshData.paymentMethod,
                userProfile: freshData.userProfile,
                weeklyProgress: freshData.weeklyProgress,
                onboardingState: freshData.onboardingState,
                availableHabitTypes: freshData.availableHabitTypes,
                verifiedHabitsToday: freshData.verifiedHabitsToday,
                habitVerifications: freshData.habitVerifications?.mapValues { verificationDataArray in
                    verificationDataArray.map { verificationData in
                        CachedHabitVerification(
                            id: verificationData.id,
                            habitId: verificationData.habitId,
                            userId: verificationData.userId,
                            verificationType: verificationData.verificationType,
                            verifiedAt: verificationData.verifiedAt,
                            status: verificationData.status,
                            verificationResult: verificationData.verificationResult,
                            imageUrl: verificationData.imageUrl,
                            selfieImageUrl: verificationData.selfieImageUrl,
                            imageVerificationId: verificationData.imageVerificationId,
                            imageFilename: verificationData.imageFilename,
                            selfieImageFilename: verificationData.selfieImageFilename,
                            verificationImageData: nil,
                            selfieImageData: nil
                        )
                    }
                },
                weeklyVerifiedHabits: freshData.weeklyVerifiedHabits,
                stagedDeletions: freshData.stagedDeletions,
                contactsOnTally: freshData.contactsOnTally
            )
            dataCacheManager.saveToCache(updatedCachedData)
            
            print("✅ [SplashScreenView] Background data refresh completed")
            
        } catch {
            print("⚠️ [SplashScreenView] Background data refresh failed: \(error)")
        }
    }
    
    /// 🖼️ Independent avatar loading that doesn't block the main UI flow
    private func startIndependentAvatarLoading() {
        print("🖼️ [SplashScreenView] Checking if avatar loading is needed...")
        
        Task.detached(priority: .userInitiated) {
            // Wait a moment to ensure authentication is complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            guard let user = await AuthenticationManager.shared.currentUser else {
                print("🖼️ [SplashScreenView] No current user available for avatar loading")
                return
            }
            
            // Check if user is in onboarding (state <= 4)
            let isInOnboarding = user.onboardingState <= 4
            
            // Check if avatar is already cached before attempting to load
            let urls = [user.avatarUrl80, user.avatarUrl200, user.avatarUrlOriginal, user.profilePhotoUrl]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            
            var alreadyCached = false
            // Only check cache if NOT in onboarding - during onboarding, always download
            if !isInOnboarding {
                for url in urls {
                    if await AvatarImageStore.shared.image(for: url) != nil {
                        print("✅ [SplashScreenView] Avatar already cached for: \(url)")
                        alreadyCached = true
                        break
                    }
                }
            } else {
                print("🔄 [SplashScreenView] User in onboarding (state: \(user.onboardingState)), forcing avatar download")
            }
            
            if alreadyCached && !isInOnboarding {
                print("✅ [SplashScreenView] Avatar already cached, skipping download")
                return
            }
            
            if urls.isEmpty {
                print("⚠️ [SplashScreenView] No avatar URLs available for current user")
                return
            }
            
            // Download avatar (forced during onboarding, or if not cached)
            print("🔄 [SplashScreenView] Avatar not cached or in onboarding, starting download...")
            let avatarStartTime = CFAbsoluteTimeGetCurrent()
            
            var avatarSuccess = await AuthenticationManager.shared.ensureAvatarReady()
            
            // If failed and in onboarding, retry a few times with delays
            if !avatarSuccess && isInOnboarding {
                print("⚠️ [SplashScreenView] Avatar loading failed during onboarding, retrying...")
                for attempt in 1...3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000) // 0.5s, 1s, 1.5s delays
                    print("🔄 [SplashScreenView] Avatar download retry attempt \(attempt)...")
                    avatarSuccess = await AuthenticationManager.shared.ensureAvatarReady()
                    if avatarSuccess {
                        print("✅ [SplashScreenView] Avatar download succeeded on retry \(attempt)")
                        break
                    }
                }
            }
            
            let avatarEndTime = CFAbsoluteTimeGetCurrent()
            let avatarTime = avatarEndTime - avatarStartTime
            print("🖼️ [SplashScreenView] Avatar download completed in \(String(format: "%.3f", avatarTime))s, success: \(avatarSuccess)")
            
            if !avatarSuccess {
                print("⚠️ [SplashScreenView] Avatar loading failed after all attempts, but this won't affect UI activation")
            }
        }
    }
    
    private func scheduleAppLaunchConsistencyCheck(token: String) {
        // Get user ID for consistency check
        guard let userId = authManager.currentUser?.id else { return }
        
        // Schedule consistency check AFTER main UI has loaded and settled
        Task.detached(priority: .background) {
            // Wait for main UI to load and become interactive - increased delay
            try? await Task.sleep(nanoseconds: 15_000_000_000) //15 sec delay
            
            // Perform weekly progress consistency check
            await HabitManager.shared.performAppLaunchConsistencyCheck(userId: userId, token: token)
            
            // Schedule periodic weekly progress checks for the session
            await HabitManager.shared.schedulePeriodicWeeklyProgressCheck(userId: userId, token: token)
            
            // DEFERRED: Schedule feed-specific updates even later to avoid impacting main UI
            try? await Task.sleep(nanoseconds: 5_000_000_000) // Additional 5 seconds (increased from 2)
            
            
            
        }
    }
    
    /// Apply ultra-fast cached data to all managers (reusing PreloadManager logic)
    private func applyCachedDataToManagers(_ cachedData: CachedAppData) async {
        // Create PreloadedData struct from cached data
        let preloadedData = PreloadManager.PreloadedData(
            habits: cachedData.habits ?? [],
            friends: cachedData.friends ?? [],
            friendsWithStripe: cachedData.friendsWithStripe ?? [],
            paymentMethod: cachedData.paymentMethod,
            feedPosts: cachedData.feedPosts ?? [],
            customHabitTypes: cachedData.customHabitTypes ?? [],
            availableHabitTypes: cachedData.availableHabitTypes,
            onboardingState: cachedData.onboardingState,
            userProfile: cachedData.userProfile,
            weeklyProgress: cachedData.weeklyProgress ?? [],
            verifiedHabitsToday: cachedData.verifiedHabitsToday,
            habitVerifications: cachedData.habitVerifications?.mapValues { cachedVerifications in
                cachedVerifications.map { cached in
                    PreloadManager.VerificationData(
                        id: cached.id,
                        habitId: cached.habitId,
                        userId: cached.userId,
                        verificationType: cached.verificationType,
                        verifiedAt: cached.verifiedAt,
                        status: cached.status,
                        verificationResult: cached.verificationResult,
                        imageUrl: cached.imageUrl,
                        selfieImageUrl: cached.selfieImageUrl,
                        imageVerificationId: cached.imageVerificationId,
                        imageFilename: cached.imageFilename,
                        selfieImageFilename: cached.selfieImageFilename
                    )
                }
            },
            weeklyVerifiedHabits: cachedData.weeklyVerifiedHabits,
            friendRequests: nil, // Friend requests not cached yet, will be nil for cached data
            stagedDeletions: cachedData.stagedDeletions,
            contactsOnTally: cachedData.contactsOnTally
        )
        
    
        
        // Apply the cached data to all managers (reuse existing logic)
        await preloadManager.applyPreloadedDataToManagers(
            preloadedData,
            habitManager: habitManager,
            friendsManager: friendsManager,
            paymentManager: paymentManager,
            feedManager: feedManager,
            customHabitManager: customHabitManager
        )
        
        // Avatar is now loaded earlier in the startup process, so no need to call ensureAvatarReady here
        print("✅ [SplashScreenView] Applied cached data to managers (avatar already loaded)")
        
    }
    
    /// Load images in background without blocking startup
    private func loadImagesInBackground() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Preload verification images for existing habits
        await habitManager.preloadAllVerificationImages()
        
        // Preload feed images for the latest 10 posts so the feed feels instant without a huge upfront hit.
        ImageCacheManager.shared.preloadFeedImages(for: Array(feedManager.feedPosts.prefix(10)))
        
        _ = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Load contacts in background without blocking startup
    private func loadContactsInBackground() async {
        await contactManager.loadContactsOnAppStartup()
    }
    
    /// Fallback to network loading if cache fails
    private func loadDataFromNetwork(token: String) async {
        loadingManager.addLoadingTask("Loading app data")
        
        do {
            let preloadedData = try await preloadManager.preloadAllAppData(token: token)
            loadingManager.completeLoadingTask("Loading app data")
            
            // Apply the preloaded data to all managers
            loadingManager.addLoadingTask("Processing app data")
            await preloadManager.applyPreloadedDataToManagers(
                preloadedData,
                habitManager: habitManager,
                friendsManager: friendsManager,
                paymentManager: paymentManager,
                feedManager: feedManager,
                customHabitManager: customHabitManager
            )
            loadingManager.completeLoadingTask("Processing app data")
            
            // Avatar is already loaded earlier in the startup process via ensureAvatarReady()
            print("✅ [SplashScreenView] Network data loaded (avatar already cached)")
            
            // Cache the data for future use - FIX: Use correct CachedAppData structure
            let cachedData = CachedAppData(
                habits: preloadedData.habits,
                friends: preloadedData.friends,
                friendsWithStripe: preloadedData.friendsWithStripe,
                feedPosts: preloadedData.feedPosts,
                customHabitTypes: preloadedData.customHabitTypes,
                paymentMethod: preloadedData.paymentMethod,
                userProfile: preloadedData.userProfile,
                weeklyProgress: preloadedData.weeklyProgress,
                onboardingState: preloadedData.onboardingState,
                availableHabitTypes: preloadedData.availableHabitTypes,
                verifiedHabitsToday: preloadedData.verifiedHabitsToday,
                habitVerifications: preloadedData.habitVerifications?.mapValues { verificationDataArray in
                    verificationDataArray.map { verificationData in
                        CachedHabitVerification(
                            id: verificationData.id,
                            habitId: verificationData.habitId,
                            userId: verificationData.userId,
                            verificationType: verificationData.verificationType,
                            verifiedAt: verificationData.verifiedAt,
                            status: verificationData.status,
                            verificationResult: verificationData.verificationResult,
                            imageUrl: verificationData.imageUrl,
                            selfieImageUrl: verificationData.selfieImageUrl,
                            imageVerificationId: verificationData.imageVerificationId,
                            imageFilename: verificationData.imageFilename,
                            selfieImageFilename: verificationData.selfieImageFilename,
                            verificationImageData: nil, // Image data will be loaded separately
                            selfieImageData: nil // Selfie image data will be loaded separately
                        )
                    }
                },
                weeklyVerifiedHabits: preloadedData.weeklyVerifiedHabits,
                stagedDeletions: preloadedData.stagedDeletions,
                contactsOnTally: preloadedData.contactsOnTally
            )
            dataCacheManager.saveToCache(cachedData)
            
            // ENHANCED: Schedule consistency checks for network-loaded data too
            if (authManager.currentUser?.id) != nil {
                scheduleAppLaunchConsistencyCheck(token: token)
            }
            
            // Continue with additional loading for non-onboarding users
            if (authManager.currentUser?.id) != nil {
                await loadImagesInBackground()
            }
            
            if authManager.isAuthenticated {
                await loadContactsInBackground()
            }
            
        } catch {
            loadingManager.completeLoadingTask("Loading app data")
        }
    }
    
    // Helper function to get the most reliable onboarding state
    private func getEffectiveOnboardingState() -> Int? {
        
        // First, try to use cached onboarding state (available immediately on startup)
        if let cachedState = authManager.cachedOnboardingState {
            return cachedState
        }
        
        // If no currentUser yet but we're authenticated, try startup cached state
        if authManager.currentUser == nil && authManager.isAuthenticated {
            if let startupState = authManager.startupCachedOnboardingState {
                return startupState
            }
        }
        
        // Fall back to current user's onboarding state (from backend)
        if let userState = authManager.currentUser?.onboardingState {
            return userState
        }
        
        return nil
    }
    
    // Helper function to determine if onboarding intro should be shown
    private func shouldShowOnboardingIntro() -> Bool {
        guard let state = getEffectiveOnboardingState() else {
            return false
        }
        
        
        guard state <= 4 else {
            return false
        }
        
        // Protection against race condition: don't show onboarding intro if signup was just completed
        let timeSinceSignup = recentSignupCompletionTime?.timeIntervalSinceNow ?? -999
        let shouldSuppressOnboarding = timeSinceSignup > -5.0 // within last 5 seconds
        
        if shouldSuppressOnboarding {
            return false
        } else {
            return true
        }
    }
}

// MARK: - Typing Text View
private struct TypingTextView: View {
    let phrases: [String]
    let typingSpeed: Double    // Seconds per character
    let pauseDuration: Double  // Seconds to wait at end of phrase before deleting
    
    @State private var displayedText: String = ""
    @State private var phraseIndex: Int = 0
    @State private var charIndex: Int = 0
    @State private var isDeleting: Bool = false
    @State private var timer: Timer? = nil
    
    var body: some View {
        Text(displayedText)
            .font(.custom("EBGaramond-Regular", size: 22))
            .foregroundColor(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .onAppear {
                // Randomize the first phrase displayed each time the view appears
                phraseIndex = Int.random(in: 0..<phrases.count)
                charIndex = 0
                displayedText = ""
                isDeleting = false
                startTyping()
            }
            .onDisappear { timer?.invalidate() }
    }
    
    private func startTyping() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { _ in
            let currentPhrase = phrases[phraseIndex]
            if isDeleting {
                if charIndex > 0 {
                    charIndex -= 1
                    displayedText = String(currentPhrase.prefix(charIndex))
                } else {
                    // Move to next phrase
                    isDeleting = false
                    phraseIndex = (phraseIndex + 1) % phrases.count
                }
            } else {
                if charIndex < currentPhrase.count {
                    charIndex += 1
                    displayedText = String(currentPhrase.prefix(charIndex))
                } else {
                    // Completed typing current phrase — wait, then start deleting
                    DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                        isDeleting = true
                    }
                }
            }
        }
    }
} 

