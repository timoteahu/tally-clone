import SwiftUI

// MARK: - Weekly Habits View
struct WeeklyHabitsView: View {
    @EnvironmentObject var habitManager: HabitManager
    @Binding var selectedWeekday: Int
    @Binding var viewMode: HabitView.ViewMode
    
    var body: some View {
        VStack(spacing: 24) {
            // Recap label and switch side by side (switch right-aligned)
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Text("your")
                        .font(.custom("EBGaramond-Regular", size: 28))
                    Text("week.")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                }
                .padding(.leading, 2)
                Spacer()
                ViewModeSwitch(viewMode: $viewMode)
                    .padding(.trailing, -12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            
            // Week progress overview
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("weekly habits")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(weeklyHabitsCount)")
                        .font(.custom("EBGaramond-Regular", size: 22))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("completed this week")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(completedWeeklyHabitsCount)")
                        .font(.custom("EBGaramond-Regular", size: 22))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            
            // Weekly habits list using simple info cards - Show ALL weekly habits with smart ordering
            let sortedWeeklyHabits = habitManager.weeklyHabits.sorted { habit1, habit2 in
                let isCompleted1 = habitManager.isWeeklyHabitCompleted(for: habit1)
                let isCompleted2 = habitManager.isWeeklyHabitCompleted(for: habit2)
                
                // Show incomplete habits first, then completed habits
                if isCompleted1 != isCompleted2 {
                    return !isCompleted1 // incomplete (false) comes before completed (true)
                }
                
                // Within the same completion status, sort alphabetically
                return habit1.name.lowercased() < habit2.name.lowercased()
            }
            
            ScrollView {
                if sortedWeeklyHabits.isEmpty {
                    weeklyEmptyStateContent
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(sortedWeeklyHabits) { habit in
                            HabitCard(habit: habit, habitManager: habitManager, showWeekdayIndicators: false, showWeeklyProgress: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // NEW: Track when user views weekly habits
            DataCacheManager.shared.trackUserInteraction()
        }
    }
    
    // MARK: - Helper Properties
    
    private var selectedDayLabel: String {
        HabitViewHelpers.getSelectedDayLabel(for: selectedWeekday)
    }
    
    // NEW: Computed properties that track user interaction
    private var weeklyHabitsCount: Int {
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.weeklyHabits.count
    }
    
    private var completedWeeklyHabitsCount: Int {
        DataCacheManager.shared.trackUserInteraction()
        return habitManager.weeklyHabits.count - habitManager.incompleteWeeklyHabits.count
    }
    
    // MARK: - Empty State
    private var weeklyEmptyStateContent: some View {
        VStack(spacing: 32) {
            Spacer()
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 360)))
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: Date().timeIntervalSince1970)
                .overlay {
                    Image(systemName: "calendar.badge.clock")
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(.white)
                }
            VStack(spacing: 12) {
                Text("No Weekly Habits")
                    .font(.custom("EBGaramond-Regular", size: 22)).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Create weekly habits to track flexible goals")
                    .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.regular)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 