import SwiftUI
import Charts

/// A modern, visually engaging stats dashboard for your goals app.
/// Requires iOS 16+ for `Charts`.
struct StatsView: View {
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    // MARK: – Mock Data (replace with your own model)
    @State private var completionRate: Double = 0.78
    @State private var monthlyData: [DayCompletion] = DayCompletion.sample

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar
            HStack {
                Spacer()
                Text("stats")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .foregroundColor(.white)
                    .tracking(0.5)
                Spacer()
            }
            .frame(height: 44)
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 4) {
                            Text(Date(), format: .dateTime.month(.wide).year())
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Text("Your Progress")
                                .font(.largeTitle).bold()
                                .foregroundColor(.white)
                        }
                        .padding(.top) // Add padding below custom bar

                        // Stats Grid - Including Streaks
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCard(
                                title: "Current Streak",
                                value: "3",
                                subtitle: "days",
                                icon: "flame.fill",
                                color: .orange
                            )
                            StatCard(
                                title: "Best Streak",
                                value: "12",
                                subtitle: "days",
                                icon: "trophy.fill",
                                color: .yellow
                            )
                            StatCard(
                                title: "Total Habits",
                                value: "\(habitManager.habits.count)",
                                subtitle: "active",
                                icon: "target",
                                color: .blue
                            )
                            StatCard(
                                title: "Weekly Habits",
                                value: "\(habitManager.weeklyHabits.count)",
                                subtitle: "this week",
                                icon: "calendar.circle.fill",
                                color: .blue
                            )
                        }
                        .padding(.horizontal)

                        // Progress Ring 
                        ProgressCard(completionRate: weeklyCompletionRate)

                        // Weekly Overview
                        WeeklyOverviewCard(habitManager: habitManager)
                    }
                    .padding() // Original padding
                }
            }
        }
        .navigationBarBackButtonHidden(true) // Hide system bar
        .preferredColorScheme(.dark)
    }
    
    private var weeklyCompletionRate: Double {
        // NEW: Track user interaction with weekly progress calculation
        DataCacheManager.shared.trackUserInteraction()
        
        // Calculate real weekly completion rate from weekly progress data
        let weeklyHabits = habitManager.weeklyHabits
        guard !weeklyHabits.isEmpty else { return 0.0 }
        
        var totalProgress: Double = 0.0
        var totalTargets: Double = 0.0
        
        for habit in weeklyHabits {
            let currentProgress = habitManager.getWeeklyHabitProgress(for: habit.id)
            // For GitHub weekly habits, use commitTarget instead of weeklyTarget
            let target = (habit.habitType == "github_commits") ? 
                (habit.commitTarget ?? 7) : (habit.weeklyTarget ?? 1)
            
            totalProgress += Double(currentProgress)
            totalTargets += Double(target)
        }
        
        return totalTargets > 0 ? min(1.0, totalProgress / totalTargets) : 0.0
    }
}

// MARK: – Sub‑Views =========================================================

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .jtStyle(.title)
                    .foregroundColor(.white)
                Text(subtitle)
                    .jtStyle(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(title)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct WeeklyOverviewCard: View {
    let habitManager: HabitManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("this week")
                .jtStyle(.body)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed")
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(completedCount)/\(totalWeeklyHabits)")
                        .jtStyle(.title)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Penalties Avoided")
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(String(format: "%.0f", penaltiesAvoided)) credits")
                        .jtStyle(.title)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal)
        .onAppear {
            // NEW: Track when user views weekly overview
            DataCacheManager.shared.trackUserInteraction()
        }
    }
    
    // NEW: Computed properties that track user interaction
    private var completedCount: Int {
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.completedHabitsThisWeek.count
    }
    
    private var totalWeeklyHabits: Int {
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.weeklyHabits.count
    }
    
    private var penaltiesAvoided: Double {
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.penaltiesAvoidedThisWeek
    }
}

struct ProgressCard: View {
    var completionRate: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .shadow(radius: 8)
            VStack(spacing: 16) {
                ProgressRing(progress: completionRate, lineWidth: 16, size: 160)
                Text("\(Int(completionRate * 100))% Complete")
                    .font(.title2).bold()
                    .foregroundColor(.white)
            }
            .padding(32)
        }
        .padding(.horizontal)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.green, .blue, .purple]),
                                    center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)

            Text("\(Int(progress * 100))%")
                .font(.title3).bold()
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

struct MetricsGrid: View {
    var rate: Double
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            MetricTile(title: "Days Tracked", value: "30")
            MetricTile(title: "Current Streak", value: "12 🔥")
            MetricTile(title: "Avg / Day", value: "\(Int(rate * 24)) hrs")
            MetricTile(title: "Best Day", value: "100%")
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var body: some View {
        VStack {
            Text(value)
                .font(.title2).bold()
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 4)
    }
}

// MARK: – Sample Model & Data ==============================================

struct DayCompletion: Identifiable {
    var id = UUID()
    var day: Date
    var value: Double

    /// Generates 30 days of random sample data.
    static var sample: [DayCompletion] {
        let cal = Calendar.current
        let today = Date()
        return (0..<30).map { offset in
            DayCompletion(
                day: cal.date(byAdding: .day, value: -offset, to: today) ?? today,
                value: Double.random(in: 0.5...1)
            )
        }
    }
}

// MARK: – Previews ==========================================================

#Preview {
    StatsView()
        .environmentObject(HabitManager.shared)
}

