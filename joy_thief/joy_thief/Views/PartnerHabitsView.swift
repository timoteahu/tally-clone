import SwiftUI

struct PartnerHabitsView: View {
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var analyticsManager: RecipientAnalyticsManager
    
    // Manual refresh control
    @State private var isRefreshing = false // no longer used but kept for compatibility
    @State private var showPreviousHabits = false // Toggle to show previous habits
    
    var body: some View {
        ZStack {
            AppBackground()
            
            if analyticsManager.isManuallyRefreshing || 
               ((analyticsManager.isLoadingHabits || analyticsManager.isLoadingStats) && 
                (analyticsManager.activeHabits.isEmpty || analyticsManager.summaryStats == nil)) {
                // Show full-page skeleton during loading
                fullPageSkeleton
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.15)),
                        removal: .opacity.animation(.easeIn(duration: 0.25))
                    ))
            } else {
                // Show normal content
                VStack(spacing: 0) {
                    // Navigation bar matching HomeView
                    navigationBar
                    
                    // Content
                    contentSection
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.1)),
                    removal: .opacity.animation(.easeIn(duration: 0.15))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: analyticsManager.isManuallyRefreshing)
        .ignoresSafeArea()  // Match HomeView: ignore full safe area
        .onAppear {
            // Load active habits and summary only (exclude inactive) when view appears
            Task {
                await analyticsManager.fetchRecipientHabits(forceRefresh: false, includeInactive: false)
                await analyticsManager.fetchSummaryStats()
            }
        }
        .onDisappear {
            // Cancel any ongoing network requests
            analyticsManager.cancelAllTasks()
        }
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            // Left side - tally logo aligned with house icon
            Text("tally.")
                .font(.custom("EBGaramond-Regular", size: 32))
                .foregroundColor(.white)
                .tracking(0.5)
                .padding(.leading, 24) // Match navbar (16px) + TabBarContent (12px) padding
            
            Spacer()
        }
        .frame(height: 44)
        .padding(.top, 63)
    }
    
    // MARK: - Content Section
    
    private var headerSection: some View {
        Text("friends' habits")
            .font(.custom("EBGaramond-Bold", size: 28))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
    }
    
    private var contentSection: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Header
                headerSection

                // Summary card section
                summarySection
                    .padding(.top, UIScreen.main.bounds.height * 0.018) // Match HomeView spacing
                    .padding(.bottom, 40) // Match HomeView spacing
                
                // Habits list section
                habitsListSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, UIScreen.main.bounds.height * 0.13) // Match HomeView spacing
        }
        .refreshable {
            await refreshData()
        }
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        Group {
            if analyticsManager.hasRecipientHabits {
                // Summary with data
                RecipientSummaryCard(
                    summaryStats: analyticsManager.summaryStats,
                    totalEarningsFromManager: analyticsManager.formattedTotalEarnings,
                    totalPendingFromManager: analyticsManager.formattedTotalPendingEarnings
                )
                .environmentObject(analyticsManager)
                .transition(.opacity)
            } else {
                // Empty state
                RecipientEmptyStateCard()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: analyticsManager.hasRecipientHabits)
    }
    
    // MARK: - Habits List Section
    
    private var habitsListSection: some View {
        VStack(spacing: 32) {
            // Active habits section
            activeHabitsSection
            
            // Previous habits section
            previousHabitsSection
        }
    }
    
    // MARK: - Active Habits Section
    
    private var activeHabitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("active habits")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if analyticsManager.hasActiveHabits {
                    Text("\(analyticsManager.activeHabits.count)")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
            
            // Content
            if analyticsManager.activeHabits.isEmpty {
                // Empty state
                emptyStateCard(
                    title: "no active habits",
                    message: "you're not currently monitoring any active habits."
                )
            } else {
                // Active habit cards
                ForEach(analyticsManager.activeHabits, id: \.id) { habitWithAnalytics in
                    RecipientHabitCard(habitWithAnalytics: habitWithAnalytics)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: analyticsManager.activeHabits.count)
    }
    
    // MARK: - Previous Habits Section
    
    private var previousHabitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {  // Remove spacing to control it manually
            // Section header
            HStack {
                Text("previous habits")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                if showPreviousHabits && analyticsManager.hasInactiveHabits {
                    Text("\(analyticsManager.inactiveHabits.count)")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)  // Add explicit bottom padding
            
            // Content
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) { 
                    showPreviousHabits.toggle() 
                }
                
                // Only fetch if we're showing and haven't loaded inactive habits yet
                if showPreviousHabits && !analyticsManager.hasLoadedInactiveHabits {
                    Task {
                        await analyticsManager.fetchInactiveHabitsOnly()
                    }
                }
            }) {
                HStack {
                    Text("show previous habits")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .rotationEffect(.degrees(showPreviousHabits ? 180 : 0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            if showPreviousHabits {
                VStack(spacing: 8) {
                    if analyticsManager.isLoadingInactiveHabits {
                        // Show loading skeleton for inactive habits
                        ForEach(0..<2, id: \.self) { _ in
                            habitLoadingSkeleton
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    } else if analyticsManager.inactiveHabits.isEmpty {
                        emptyStateCard(
                            title: "no previous habits",
                            message: "completed and inactive habits will appear here."
                        )
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    } else {
                        ForEach(analyticsManager.inactiveHabits, id: \.id) { habitWithAnalytics in
                            RecipientHabitCard(habitWithAnalytics: habitWithAnalytics)
                                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        }
                    }
                }
                .padding(.top, 8)  // Increase top padding for dropdown content
            }
        }
        .padding(.bottom, 16)  // Add bottom padding to the entire section
    }
    
    // MARK: - Loading Skeleton
    
    private var habitLoadingSkeleton: some View {
        HStack(spacing: 16) {
            // Icon skeleton
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 120, height: 16)
                
                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 80, height: 12)
            }
            
            Spacer()
            
            // Stats skeleton
            VStack(alignment: .trailing, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 30, height: 11)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        )
        .redacted(reason: .placeholder)
    }
    
    // MARK: - Empty State Card
    
    private func emptyStateCard(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.custom("EBGaramond-Bold", size: 20))
                .foregroundColor(.white.opacity(0.9))
            
            Text(message)
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
    }
    
    // MARK: - Full Page Skeleton
    
    private var fullPageSkeleton: some View {
        VStack(spacing: 0) {
            // Navigation bar skeleton
            HStack {
                Text("tally.")
                    .font(.custom("EBGaramond-Regular", size: 32))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(0.5)
                    .padding(.leading, 24)
                
                Spacer()
            }
            .frame(height: 44)
            .padding(.top, 63)
            .padding(.bottom, 16)
            .redacted(reason: .placeholder)

            // Header skeleton
            Text("partnered habits")
                .font(.custom("EBGaramond-Bold", size: 28))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .redacted(reason: .placeholder)
            
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    // Summary skeleton
                    RecipientLoadingCard()
                        .padding(.top, UIScreen.main.bounds.height * 0.018)
                        .padding(.bottom, 40)
                    
                    // Habits sections skeleton
                    VStack(spacing: 32) {
                        // Active habits skeleton
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("active habits")
                                    .font(.custom("EBGaramond-Regular", size: 20))
                                    .foregroundColor(.white.opacity(0.3))
                                    .redacted(reason: .placeholder)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            
                            VStack(spacing: 16) {
                                ForEach(0..<2, id: \.self) { _ in
                                    habitLoadingSkeleton
                                }
                            }
                        }
                        
                        // Previous habits skeleton
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("previous habits")
                                    .font(.custom("EBGaramond-Regular", size: 20))
                                    .foregroundColor(.white.opacity(0.3))
                                    .redacted(reason: .placeholder)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            
                            VStack(spacing: 16) {
                                ForEach(0..<1, id: \.self) { _ in
                                    habitLoadingSkeleton
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, UIScreen.main.bounds.height * 0.13)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialData() {
        Task {
            await analyticsManager.fetchRecipientHabits()
            await analyticsManager.fetchSummaryStats()
        }
    }
    
    private func refreshData() async {
        await analyticsManager.refreshAllData(includeInactive: false) // Don't fetch inactive habits on refresh
    }
}

// MARK: - Error State View

struct RecipientErrorStateView: View {
    let errorMessage: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 12) {
                Text("something went wrong")
                    .font(.custom("EBGaramond-Bold", size: 20))
                    .foregroundColor(.white)
                
                Text(errorMessage)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            // Retry button
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("try again")
                        .font(.custom("EBGaramond-Medium", size: 16))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(32)
        .background(
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: Color(hex: "2A3441").opacity(0.8), location: 0.0),
                    Gradient.Stop(color: Color(hex: "1E2833").opacity(0.8), location: 0.5),
                    Gradient.Stop(color: Color(hex: "141C27").opacity(0.8), location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Preview

struct PartnerHabitsView_Previews: PreviewProvider {
    static var previews: some View {
        PartnerHabitsView()
            .environmentObject(HabitManager.shared)
            .environmentObject(AuthenticationManager.shared)
    }
}
