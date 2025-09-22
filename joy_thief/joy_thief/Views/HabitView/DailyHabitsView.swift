import SwiftUI

// MARK: - Daily Habits View
struct DailyHabitsView: View {
    @EnvironmentObject var habitManager: HabitManager
    @Binding var selectedWeekday: Int
    @Binding var viewMode: HabitView.ViewMode
    @Binding var recapAnimatedText: String
    @Binding var hasTypedRecapOnAppear: Bool
    @Binding var daySwipeEdge: Edge
    let backSwipeEdgeWidth: CGFloat
    let onTypingRecap: () -> Void
    
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Recap label and switch side by side (switch right-aligned)
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 0) {
                    Text("your ")
                        .font(.custom("EBGaramond-Regular", size: 28))
                    Text(recapAnimatedText)
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
            
            weekdaySelectorSection
            habitsListSection
        }
        .onAppear {
            if !hasTypedRecapOnAppear {
                onTypingRecap()
                hasTypedRecapOnAppear = true
            }
        }
        .onChange(of: selectedWeekday) { oldValue, _ in
            onTypingRecap()
        }
    }
    
    // MARK: - Weekday Selector
    private var weekdaySelectorSection: some View {
        HStack(spacing: 8) {
            ForEach(0..<7) { index in
                Button(action: {
                    selectedWeekday = index
                }) {
                    VStack(spacing: 2) {
                        Text(weekdays[index])
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(selectedWeekday == index ? .black : .white)
                        let habitCount = habitManager.habitsbydate[index]?.count ?? 0
                        Text("\(habitCount)")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(selectedWeekday == index ? .black : .white)
                            .textCase(.lowercase)
                    }
                    .frame(width: 40, height: 48)
                    .background(
                        Group {
                            if selectedWeekday == index {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: .white.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    // MARK: - Habits List
    private var habitsListSection: some View {
        let habitsForSelectedDay = habitManager.habitsbydate[selectedWeekday] ?? []
        
        let insertionEdge: Edge = daySwipeEdge
        let removalEdge: Edge = daySwipeEdge == .trailing ? .leading : .trailing

        return ScrollView {
            if habitsForSelectedDay.isEmpty {
                emptyStateContent
            } else {
                LazyVStack(spacing: 16) {
                    DailyHabitsSection(habits: habitsForSelectedDay, habitManager: habitManager)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .id(selectedWeekday)
        .transition(.asymmetric(insertion: .move(edge: insertionEdge), removal: .move(edge: removalEdge)))
        .animation(.easeInOut(duration: 0.25), value: selectedWeekday)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Allow vertical scrolling to coexist with horizontal day-swipe by using a
        // simultaneous gesture instead of high-priority. The DragGesture itself
        // already checks for horizontal dominance, so vertical scrolls will no
        // longer be hijacked.
        .simultaneousGesture(cardSwipeGesture, including: .all)
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
    
    // MARK: - Computed Properties
    
    // MARK: - Card Swipe Gesture (switch days)
    private var cardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                // Ignore if gesture began in the left-edge back-swipe zone
                guard value.startLocation.x > backSwipeEdgeWidth else { return }
                // Ensure horizontal dominance
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 {
                    daySwipeEdge = .trailing
                    withAnimation(.easeInOut(duration: 0.25)) {
                        changeDay(by: 1) // swipe left ➜ next day
                    }
                } else if value.translation.width > 40 {
                    daySwipeEdge = .leading
                    withAnimation(.easeInOut(duration: 0.25)) {
                        changeDay(by: -1) // swipe right ➜ previous day
                    }
                }
            }
    }
    
    // Helper to increment or decrement the selected weekday cyclically
    private func changeDay(by offset: Int) {
        let newIndex = (selectedWeekday + offset + 7) % 7
        guard newIndex != selectedWeekday else { return }
        selectedWeekday = newIndex
    }
}

// MARK: - Daily Habits Section
struct DailyHabitsSection: View {
    let habits: [Habit]
    let habitManager: HabitManager
    
    var body: some View {
        ForEach(habits) { habit in
            HabitCard(habit: habit, habitManager: habitManager)
                .id(habit.id)
                .transition(.opacity)
        }
    }
} 