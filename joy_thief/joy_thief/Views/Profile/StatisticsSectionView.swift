import SwiftUI

struct StatisticsSectionView: View {
    let weeklyCompletedGoals: Int
    let weeklyPayments: Double
    let monthlyCompletedGoals: Int
    let monthlyPayments: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("statistics")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatisticCard(
                        title: "this week",
                        value: "\(weeklyCompletedGoals)",
                        subtitle: "goals completed",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    StatisticCard(
                        title: "this week",
                        value: String(format: "%.2f", weeklyPayments),
                        subtitle: "credits used",
                        icon: "dollarsign.circle.fill",
                        color: .red
                    )
                }
                
                HStack(spacing: 12) {
                    StatisticCard(
                        title: "this month",
                        value: "\(monthlyCompletedGoals)",
                        subtitle: "goals completed",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    StatisticCard(
                        title: "this month",
                        value: String(format: "%.2f", monthlyPayments),
                        subtitle: "credits used",
                        icon: "dollarsign.circle.fill",
                        color: .red
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StatisticsSectionView(
            weeklyCompletedGoals: 5,
            weeklyPayments: 25.50,
            monthlyCompletedGoals: 20,
            monthlyPayments: 75.00
        )
    }
} 