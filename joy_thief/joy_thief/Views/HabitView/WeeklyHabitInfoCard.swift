import SwiftUI

// MARK: - Weekly Habit Info Card
struct WeeklyHabitInfoCard: View {
    let habit: Habit
    let habitManager: HabitManager
    @State private var showingDetail = false
    
    private var currentProgress: Int {
        // NEW: Track user interaction when viewing progress
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.getWeeklyHabitProgress(for: habit.id)
    }
    
    private var target: Int {
        // For gaming habits, target represents hours limit
        if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
            return Int(habit.dailyLimitHours ?? 0)  // For weekly gaming habits, dailyLimitHours contains the weekly limit
        }
        // For GitHub weekly habits, the actual weekly commit goal is stored in commitTarget
        // weeklyTarget is set to 1 for database consistency, but commitTarget has the real goal
        if habit.habitType == "github_commits" && habit.isWeeklyHabit {
            return habit.commitTarget ?? 7  // Default to 7 if commitTarget is nil
        }
        return habit.weeklyTarget ?? 1
    }
    
    private var isVerifiedToday: Bool {
        habitManager.verifiedHabitsToday[habit.id] == true
    }
    
    // NEW: Check if the weekly habit is completed
    private var isWeeklyCompleted: Bool {
        habitManager.isWeeklyHabitCompleted(for: habit)
    }
    
    var body: some View {
        Button(action: { 
            // NEW: Track interaction when user taps weekly habit card
            DataCacheManager.shared.trackUserInteraction()
            showingDetail = true 
            // Refresh friends with Stripe Connect for habit detail view
            Task {
                await FriendsManager.shared.preloadFriendsWithStripeConnect()
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with name and progress
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                            Text("$\(habit.hourlyPenaltyRate ?? 0, specifier: "%.2f")/hr")
                                .font(.custom("EBGaramond-Regular", size: 20))
                                .foregroundColor(.white)
                        } else {
                            Text("$\(habit.penaltyAmount, specifier: "%.2f")")
                                .font(.custom("EBGaramond-Regular", size: 20))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Progress bar
                progressSection
                
                // Status and info
                statusSection
            }
            .contentShape(Rectangle())
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.9),
                                Color(red: 0.04, green: 0.04, blue: 0.07).opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            HabitDetailView(habit: habit, habitManager: habitManager)
        }
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("progress")
                    .font(.custom("EBGaramond-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                    Text("\(currentProgress)h / \(target)h limit")
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    Text("\(currentProgress)/\(target)")
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.7))
                        .frame(width: geometry.size.width * min(Double(currentProgress) / Double(target), 1.0), height: 8)
                        .animation(.smooth(duration: 0.3), value: currentProgress)
                }
            }
            .frame(height: 8)
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        HStack {
            // Weekly completion status or daily status
            HStack(spacing: 8) {
                Circle()
                    .fill(isWeeklyCompleted ? Color.green : (isVerifiedToday ? Color.green : Color.white.opacity(0.3)))
                    .frame(width: 8, height: 8)
                
                if isWeeklyCompleted {
                    Text("habit completed")
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(.green.opacity(0.9))
                } else {
                    Text(isVerifiedToday ? "completed today" : "not completed today")
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Spacer()
            // Tap hint
            HStack {
                Text("tap to edit")
                    .font(.custom("EBGaramond-Regular", size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.custom("EBGaramond-Regular", size: 10)).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Weekly Habit Card for Daily View
struct WeeklyHabitCardForDaily: View {
    let habit: Habit
    let habitManager: HabitManager
    
    var body: some View {
        HabitCard(habit: habit, habitManager: habitManager)
            .overlay(weeklyIndicatorOverlay)
    }
    
    private var weeklyIndicatorOverlay: some View {
        VStack {
            HStack {
                Spacer()
                weeklyProgressBadge
            }
            Spacer()
        }
        .padding(16)
    }
    
    private var weeklyProgressBadge: some View {
        VStack(spacing: 2) {
            Text("WEEKLY")
                .jtStyle(.caption)
                .foregroundColor(.blue)
            // For gaming habits, show hours played vs limit
            if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                let hoursPlayed = habitManager.getWeeklyHabitProgress(for: habit.id)
                let hoursLimit = Int(habit.dailyLimitHours ?? 0)
                Text("\(hoursPlayed)h/\(hoursLimit)h")
                    .jtStyle(.caption)
                    .foregroundColor(.blue)
            } else {
                // For GitHub weekly habits, use commitTarget instead of weeklyTarget
                let targetValue = (habit.habitType == "github_commits" && habit.isWeeklyHabit) ? 
                    (habit.commitTarget ?? 7) : (habit.weeklyTarget ?? 1)
                Text("\(habitManager.getWeeklyHabitProgress(for: habit.id))/\(targetValue)")
                    .jtStyle(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
} 