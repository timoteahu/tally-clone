import SwiftUI

/// Extracted sub-view that displays the **Stripe Connect** account status.
struct StripeConnectSectionView: View {
    let connectStatus: ConnectStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("receive payments")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stripe Connect")
                            .jtStyle(.body)
                            .foregroundColor(.white)
                        Text("connect your account to receive habit contract payments")
                            .font(.custom("EBGaramond", size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()
                }

                switch connectStatus {
                case .notConnected:
                    VStack(spacing: 8) {
                        Text("Account not connected")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.6))
                        Text("Visit our website to connect your account")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                case .pending:
                    VStack(spacing: 8) {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Account setup in progress…")
                                .jtStyle(.body)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text("Complete setup on our website")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                case .connected:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Account Connected")
                            .jtStyle(.body)
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
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

// MARK: - Previews

#Preview {
    StripeConnectSectionView(connectStatus: .pending)
        .preferredColorScheme(.dark)
        .background(Color.black)
} 