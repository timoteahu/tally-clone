import SwiftUI

/// Enhanced balance section that shows detailed balance information
struct BalanceSectionView: View {
    let balance: Double
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AVAILABLE BALANCE")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)

            VStack(spacing: 16) {
                // Main balance display
                HStack(spacing: 16) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 4) {
                        if isLoading {
                            Text("Loading balance…")
                                .jtStyle(.body)
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text("\(String(format: "%.2f", balance)) credits")
                                .jtStyle(.title)
                                .foregroundColor(.white)
                            Text("Available for withdrawal")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    Spacer()
                }
                
                // Balance info cards
                if !isLoading {
                    HStack(spacing: 12) {
                        BalanceInfoCard(
                            title: "Min Withdrawal",
                            value: "5 credits",
                            icon: "arrow.down.circle",
                            color: balance >= 5.00 ? .green : .orange
                        )
                        
                        BalanceInfoCard(
                            title: "Processing Fee",
                            value: "Free",
                            icon: "checkmark.circle",
                            color: .green
                        )
                    }
                }
                
                // Status message
                if !isLoading && balance < 5.00 && balance > 0 {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Minimum withdrawal amount is 5 credits")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                
                // Website redirect message
                if !isLoading && balance > 0 {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                        Text("Visit our website to withdraw funds")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}

struct BalanceInfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(color)
                Text(title)
                    .jtStyle(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            
            Text(value)
                .jtStyle(.body)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .center)
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BalanceSectionView(balance: 42.50, isLoading: false)
        BalanceSectionView(balance: 2.50, isLoading: false)
        BalanceSectionView(balance: 0.0, isLoading: true)
    }
    .preferredColorScheme(.dark)
    .background(Color.black)
} 