import SwiftUI

struct GamingCard: View {
    let habit: Habit
    let hoursPlayed: Double
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    
    @ObservedObject private var habitManager = HabitManager.shared
    @State private var showingDetailView = false
    
    private var limit: Double { 
        // For gaming habits, daily_limit_hours contains the limit (for both daily and weekly)
        habit.dailyLimitHours ?? 2.0 
    }
    
    private var isOverLimit: Bool { hoursPlayed > limit }
    
    private var displayIcon: String {
        HabitIconProvider.iconName(for: habit.habitType)
    }
    
    private var displayName: String {
        if habit.name.isEmpty {
            return habit.habitType == "league_of_legends" ? "League of Legends" : "Valorant"
        }
        return habit.name
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: cardHeight * 0.15)
                
                // Large centered icon
                Image(displayIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardWidth * 0.22, height: cardWidth * 0.22)
                    .padding(.bottom, cardHeight * 0.04)
                
                // Centered habit name
                Text(displayName)
                    .font(.custom("EB Garamond", size: cardWidth * 0.09).weight(.medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Spacer(minLength: cardHeight * 0.08)
                
                // Progress display - hours played / limit
                Text("\(formatHours(hoursPlayed))/\(formatHours(limit)) hours")
                    .font(.custom("EB Garamond", size: cardWidth * 0.065))
                    .foregroundColor(.black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight * 0.11)
                    .background(isOverLimit ? Color.red.opacity(0.8) : Color.green)
                    .clipShape(Capsule())
                    .padding(.horizontal, cardWidth * 0.3)
                
                Spacer(minLength: cardHeight * 0.24)
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
    
    private func formatHours(_ hours: Double) -> String {
        if hours == 0 {
            return "0"
        } else if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", hours)
        } else {
            return String(format: "%.1f", hours)
        }
    }
}