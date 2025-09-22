import SwiftUI

// MARK: - Recipient Summary Card

struct RecipientSummaryCard: View {
    let summaryStats: RecipientSummaryStats?
    let totalEarningsFromManager: String?
    let totalPendingFromManager: String?
    @EnvironmentObject var analyticsManager: RecipientAnalyticsManager
    
    var body: some View {
        HStack(spacing: 20) {
            // Total earned all time
            metricView(
                title: "all time",
                value: totalEarningsFromManager ?? summaryStats?.formattedTotalEarned ?? "0 credits"
            )
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
            
            // This week earnings
            metricView(
                title: "this week",
                value: analyticsManager.formattedEarningsThisWeek
            )
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
            
            // Success rate
            metricView(
                title: "success",
                value: summaryStats?.formattedSuccessRate ?? "0%"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        )
    }
    
    // MARK: - Metric View
    
    private func metricView(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("EBGaramond-Bold", size: 22))
                .foregroundColor(.white)
            
            Text(title)
                .font(.custom("EBGaramond-Regular", size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
}

// MARK: - Empty State Card

struct RecipientEmptyStateCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("No Partner Habits")
                .font(.custom("EBGaramond-Bold", size: 20))
                .foregroundColor(.white)
            
            Text("You're not currently an accountability partner for any habits.")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        )
    }
    
}

// MARK: - Loading State Card

struct RecipientLoadingCard: View {
    var body: some View {
        HStack(spacing: 20) {
            // Loading skeleton for each metric
            ForEach(0..<3, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 70, height: 22)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 50, height: 14)
                }
                .frame(maxWidth: .infinity)
                
                if index < 2 {
                    Divider()
                        .frame(height: 40)
                        .background(Color.white.opacity(0.1))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        )
        .redacted(reason: .placeholder)
    }
    
}

// MARK: - Previews

struct RecipientSummaryCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Summary with data
            RecipientSummaryCard(
                summaryStats: sampleSummaryStats,
                totalEarningsFromManager: "150 credits",
                totalPendingFromManager: "45 credits"
            )
            
            // Empty state
            RecipientEmptyStateCard()
            
            // Loading state
            RecipientLoadingCard()
        }
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .preferredColorScheme(.dark)
    }
    
    static var sampleSummaryStats: RecipientSummaryStats {
        RecipientSummaryStats(
            totalHabitsMonitored: 5,
            totalEarnedAllTime: 150.75,
            totalPendingAllHabits: 45.00,
            overallSuccessRate: 82.5,
            totalCompletionsAllHabits: 42,
            totalFailuresAllHabits: 9
        )
    }
} 