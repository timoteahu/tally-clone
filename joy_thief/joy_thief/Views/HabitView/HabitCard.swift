import SwiftUI

// MARK: - Habit Card
struct HabitCard: View, Equatable {
    let habit: Habit
    let habitManager: HabitManager
    var showWeekdayIndicators: Bool = true
    var showWeeklyProgress: Bool = false
    @State private var showingDetail = false
    
    static func == (lhs: HabitCard, rhs: HabitCard) -> Bool {
        lhs.habit == rhs.habit &&
        lhs.showWeekdayIndicators == rhs.showWeekdayIndicators &&
        lhs.showWeeklyProgress == rhs.showWeeklyProgress
    }
    
    var body: some View {
        Button(action: { 
            showingDetail = true
            // Refresh friends with Stripe Connect for habit detail view
            Task {
                await FriendsManager.shared.preloadFriendsWithStripeConnect()
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                Spacer(minLength: 0)
                if let recipientName = habit.getRecipientName() {
                    recipientSection(name: recipientName)
                }
                if showWeekdayIndicators && !habit.isWeeklyHabit {
                    weekdaySection
                }
                if showWeeklyProgress && habit.isWeeklyHabit {
                    weeklyProgressSection
                }
            }
            .contentShape(Rectangle())
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .drawingGroup()
        .sheet(isPresented: $showingDetail) {
            HabitDetailView(habit: habit, habitManager: habitManager)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            Group {
                if habit.habitType.hasPrefix("health_") {
                    // Health habits use SF Symbols
                    Image(systemName: habitIcon)
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.clear)
                } else if habit.habitType == "league_of_legends" || habit.habitType == "valorant" || habit.habitType == "github_commits" {
                    Image(habitIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .background(Color.clear)
                        .clipShape(Circle())
                } else {
                    Image(habitIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .background(Color.clear)
                        .clipShape(Circle())
                }
            }
            .drawingGroup()
            
            Text(habit.name)
                .font(.custom("EBGaramond-Regular", size: 22))
                .foregroundColor(.white)
            Spacer()
            if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                Text("$\(habit.hourlyPenaltyRate ?? 0, specifier: "%.2f")/hr")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                Text("$\(habit.penaltyAmount, specifier: "%.2f")")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }
    
    // MARK: - Recipient Section
    private func recipientSection(name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(.white.opacity(0.9))
            Text(name)
                .font(.custom("EBGaramond-Regular", size: 14))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.2, green: 0.2, blue: 0.3).opacity(0.4))
        .clipShape(Capsule())
    }
    
    // MARK: - Weekday Section
    private var weekdaySection: some View {
        HStack(spacing: 4) {
            weekdayIndicators
            Spacer()
            habitTypeTags
        }
    }
    
    private var weekdayIndicators: some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { index in
                weekdayIndicator(index: index)
            }
        }
    }
    
    private func weekdayIndicator(index: Int) -> some View {
        let isActive = habit.weekdays.contains(index)
        return Text(["S", "M", "T", "W", "T", "F", "S"][index])
            .font(.custom("EBGaramond-Regular", size: 14))
            .foregroundColor(isActive ? .white : .blue.opacity(0.8))
            .frame(width: 20, height: 20)
    }
    
    // MARK: - Habit Type Tags
    private var habitTypeTags: some View {
        HStack(spacing: 6) {
            if habit.isCustomHabit {
                habitTypeTag("Custom", icon: HabitIconProvider.iconName(for: "custom"), color: .white)
            }
            else if habit.isHealthHabit {
                healthHabitTypeTag()
            }
            else if habit.isGymHabit {
                habitTypeTag("Gym", icon: HabitIconProvider.iconName(for: "gym"), color: .white)
            }
            else if habit.isAlarmHabit {
                habitTypeTag("Alarm", icon: HabitIconProvider.iconName(for: "alarm"), color: .white)
            }
            else if habit.isYogaHabit {
                habitTypeTag("Yoga", icon: HabitIconProvider.iconName(for: "yoga"), color: .white)
            }
            else if habit.isOutdoorsHabit {
                habitTypeTag("Outdoors", icon: HabitIconProvider.iconName(for: "outdoors"), color: .white)
            }
            else if habit.isCyclingHabit {
                habitTypeTag("Cycling", icon: HabitIconProvider.iconName(for: "cycling"), color: .white)
            }
            else if habit.isCookingHabit {
                habitTypeTag("Cooking", icon: HabitIconProvider.iconName(for: "cooking"), color: .white)
            }
            else if habit.habitType == "league_of_legends" {
                habitTypeTag("League of Legends", icon: HabitIconProvider.iconName(for: "league_of_legends"), color: .white)
            }
            else if habit.habitType == "valorant" {
                habitTypeTag("Valorant", icon: HabitIconProvider.iconName(for: "valorant"), color: .white)
            }
            else if habit.habitType == "github_commits" {
                habitTypeTag("GitHub", icon: HabitIconProvider.iconName(for: "github_commits"), color: .white)
            }
        }
    }
    
    private func healthHabitTypeTag() -> some View {
        let displayName: String
        let icon: String
        
        switch habit.habitType {
        case "health_steps":
            displayName = "Steps"
            icon = "figure.walk"
        case "health_walking_running_distance":
            displayName = "Walking/Running"
            icon = "figure.run"
        case "health_flights_climbed":
            displayName = "Flights"
            icon = "figure.stairs"
        case "health_exercise_minutes":
            displayName = "Exercise"
            icon = "heart.circle"
        case "health_cycling_distance":
            displayName = "Cycling"
            icon = "bicycle"
        case "health_sleep_hours":
            displayName = "Sleep"
            icon = "bed.double"
        case "health_calories_burned":
            displayName = "Calories"
            icon = "flame"
        case "health_mindful_minutes":
            displayName = "Meditation"
            icon = "brain.head.profile"
        default:
            displayName = "Health"
            icon = "heart.circle"
        }
        
        return healthHabitTag(displayName, icon: icon, color: .white)
    }
    
    private func healthHabitTag(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color.opacity(0.8))
            Text(text)
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
    
    private func habitTypeTagSF(_ text: String, systemIcon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 12))
                .foregroundColor(color.opacity(0.8))
            Text(text)
                .jtStyle(.caption)
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func habitTypeTag(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 10, height: 10)
                .foregroundColor(color)
            Text(text.lowercased())
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
    
    // MARK: - Weekly Progress Section
    private var weeklyProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let currentProgress = habitManager.getWeeklyHabitProgress(for: habit.id)
            let weeklyTarget = getWeeklyTarget()
            let progressPercentage = weeklyTarget > 0 ? Double(currentProgress) / Double(weeklyTarget) : 0
            let isCompleted = habitManager.isWeeklyHabitCompleted(for: habit)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isCompleted ? Color.green : Color.white.opacity(0.6))
                        .frame(width: geometry.size.width * min(progressPercentage, 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progressPercentage)
                }
            }
            .frame(height: 6)
            
            // Progress text
            HStack {
                if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                    let hoursPlayed = Double(currentProgress) / 60.0
                    Text("\(String(format: "%.1f", hoursPlayed))h / \(weeklyTarget)h limit")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    Text("\(currentProgress) / \(weeklyTarget) completed")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if isCompleted {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    private func getWeeklyTarget() -> Int {
        if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
            return Int(habit.dailyLimitHours ?? 0)
        }
        if habit.habitType == "github_commits" && habit.isWeeklyHabit {
            return habit.commitTarget ?? 7
        }
        return habit.weeklyTarget ?? 1
    }
    
    // MARK: - Computed Properties
    private var habitIcon: String {
        HabitIconProvider.iconName(for: habit.habitType, variant: .filled)
    }
}

// MARK: - Date Button Component
struct DateButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .jtStyle(.caption)
                    .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                Text(date.formatted(.dateTime.day()))
                    .jtStyle(.body)
                    .foregroundColor(isSelected ? .black : .white)
            }
            .frame(width: 40, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
            )
        }
    }
} 