import SwiftUI

/// Extracted sub-view that renders the **Payment Method** card.
struct PaymentMethodSectionView: View {
    // The shared payment manager stays injected via the environment so we don't have to
    // thread it through initialisers.
    @EnvironmentObject private var paymentManager: PaymentManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("payment method")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                if let method = paymentManager.paymentMethod {
                    HStack(spacing: 16) {
                        Image(systemName: "creditcard.fill")
                            .font(.custom("EBGaramond-Regular", size: 24))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(method.brand) •••• \(method.last4)")
                                .jtStyle(.body)
                                .foregroundColor(.white)
                            Text("Expires \(method.expiry)")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: "creditcard")
                            .font(.custom("EBGaramond-Regular", size: 24))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)

                        Text("No payment method on file")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Previews

#Preview {
    PaymentMethodSectionView()
    .environmentObject(PaymentManager.shared)
    .preferredColorScheme(.dark)
    .background(Color.black)
} 