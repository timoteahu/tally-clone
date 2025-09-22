import SwiftUI

struct StatisticCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StatisticCard(title: "This Week", value: "4", subtitle: "Goals Completed", icon: "checkmark.circle.fill", color: .green)
            .padding()
    }
} 