import SwiftUI

struct AllHabitsView: View {
    @EnvironmentObject var habitManager: HabitManager
    @Binding var viewMode: HabitView.ViewMode
    @Binding var recapAnimatedText: String
    @Binding var hasTypedRecapOnAppear: Bool
    let onTypingRecap: () -> Void
    
    private var allUniqueHabits: [Habit] {
        var uniqueHabitsDict: [String: Habit] = [:]  // Using habit ID as key
        
        // Add weekly habits
        for habit in habitManager.weeklyHabits {
            uniqueHabitsDict[habit.id] = habit
        }
        
        // Add daily habits from all days
        for dayHabits in habitManager.habitsbydate.values {
            for habit in dayHabits {
                uniqueHabitsDict[habit.id] = habit
            }
        }
        
        // Convert back to array and sort by name
        return Array(uniqueHabitsDict.values).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with recap and view mode switch
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Text("your")
                        .font(.custom("EBGaramond-Regular", size: 28))
                    Text("habits.")
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
            
            // Habit count
            HStack {
                Text("\(allUniqueHabits.count) total habits")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.leading, 22)
                Spacer()
            }
            .padding(.top, 4)
            
            // All Habits List
            ScrollView {
                if allUniqueHabits.isEmpty {
                    emptyStateContent
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(allUniqueHabits) { habit in
                            HabitCard(habit: habit, habitManager: habitManager, showWeekdayIndicators: true, showWeeklyProgress: true)
                                .id(habit.id)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !hasTypedRecapOnAppear {
                onTypingRecap()
                hasTypedRecapOnAppear = true
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateContent: some View {
        VStack(spacing: 32) {
            Spacer()
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 360)))
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: Date().timeIntervalSince1970)
                .overlay {
                    Image(systemName: "bell.and.waves.left.and.right")
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(.white)
                }
            VStack(spacing: 12) {
                Text("No Habits Yet")
                    .font(.custom("EBGaramond-Regular", size: 22)).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Create habits to track your progress")
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
    }
}

