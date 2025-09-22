import SwiftUI

struct LeetCodeCard: View {
    let habit: Habit
    let problemsSolved: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    @ObservedObject private var habitManager = HabitManager.shared
    @State private var showingDetailView = false

    private var goal: Int { 
        habit.commitTarget ?? 1
    }
    private var met: Bool { problemsSolved >= goal }
    
    init(habit: Habit, problemsSolved: Int, cardWidth: CGFloat, cardHeight: CGFloat) {
        self.habit = habit
        self.problemsSolved = problemsSolved
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        print("🔍 [LeetCodeCard] Displaying habit '\(habit.name)' - Problems: \(problemsSolved)/\(habit.commitTarget ?? 1), Weekly: \(habit.isWeeklyHabit)")
    }
    
    // Check if habit is completed today (like GitHub, don't use verifiedHabitsToday)
    private var isCompletedToday: Bool {
        met
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: cardHeight * 0.33)
                // Large centered icon (GitHub logo for LeetCode)
                Image("github")
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardWidth * 0.22, height: cardWidth * 0.22)
                    .padding(.bottom, cardHeight * 0.04)

                // Centered habit name
                Text(habit.name.isEmpty ? "Insert Habit Name" : habit.name)
                    .font(.custom("EB Garamond", size: cardWidth * 0.09).weight(.medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // Subtitle
                Text("leetcode habit.")
                    .font(.custom("EB Garamond", size: cardWidth * 0.055))
                    .italic()
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                Spacer(minLength: cardHeight * 0.08)
                
                // Progress section
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(met ? Color.green : Color.white)
                                .frame(width: geometry.size.width * min(Double(problemsSolved) / Double(goal), 1.0), height: 6)
                                .animation(.easeInOut(duration: 0.8), value: problemsSolved)
                        }
                    }
                    .frame(height: 6)
                    
                    // Current/Target display
                    Text("\(problemsSolved) / \(goal) problem\(goal == 1 ? "" : "s")")
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, cardWidth * 0.15)
                .padding(.bottom, cardHeight * 0.24)
            }
            .frame(width: cardWidth, height: cardHeight)
            // Progress percentage in bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: cardWidth * 0.01) {
                        if isCompletedToday {
                            let completionText = habit.isWeeklyHabit ? "✅ completed this week" : "✅ completed today"
                            Text(completionText)
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            let progressPercentage = min(100, Int((Double(problemsSolved) / Double(goal)) * 100))
                            Text("\(progressPercentage)% complete")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.6))
                            Image(systemName: "circle")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.trailing, cardWidth * 0.05)
                    .padding(.bottom, cardHeight * 0.075)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .padding(.top, cardHeight * 0.1)

            // View details button in top right
            Button(action: {
                showingDetailView = true
                // Refresh friends with Stripe Connect for habit detail view
                Task {
                    await FriendsManager.shared.preloadFriendsWithStripeConnect()
                }
            }) {
                HStack(spacing: 4) {
                    Text("view details")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.right")
                        .font(.system(size: cardWidth * 0.03, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .offset(x: -cardWidth * 0.08, y: cardHeight * 0.08)
        }
        .sheet(isPresented: $showingDetailView) {
            HabitDetailView(habit: habit, habitManager: habitManager)
        }
    }
}