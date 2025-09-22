import SwiftUI

struct ProfileRow: View {
    let label: String
    let icon: String
    var iconColor: Color = .white
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.custom("EBGaramond-Regular", size: 18))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
            
            Text(label)
                .jtStyle(.body)
                .foregroundColor(.white)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.custom("EBGaramond-Regular", size: 12)).fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ProfileRow(label: "Upgrade to Premium", icon: "crown.fill", iconColor: .yellow)
            .padding()
    }
} 