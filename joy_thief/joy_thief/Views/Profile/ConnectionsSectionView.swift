import SwiftUI

struct ConnectionsSectionView: View {
    @Binding var githubStatus: ConnectStatus
    @Binding var riotStatus: ConnectStatus
    @Binding var leetCodeStatus: ConnectStatus
    let onConnectGitHub: () -> Void
    let onConnectRiot: () -> Void
    let onConnectLeetCode: () -> Void

    private func statusLabel(for status: ConnectStatus) -> some View {
        switch status {
        case .connected:
            return AnyView(Text("Connected")
                .jtStyle(.caption)
                .foregroundColor(.green))
        case .pending:
            return AnyView(ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.6))
        case .notConnected:
            return AnyView(Text("Connect")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.6)))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTIONS")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                // GitHub Integration
                Button(action: onConnectGitHub) {
                    HStack {
                        ProfileRowContent(label: "GitHub", icon: "github", isAssetImage: true)
                        Spacer()
                        statusLabel(for: githubStatus)
                        Image(systemName: "chevron.right")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)
                
                // LeetCode Integration
                Button(action: onConnectLeetCode) {
                    HStack {
                        ProfileRowContent(label: "LeetCode", icon: "github", isAssetImage: true)
                        Spacer()
                        statusLabel(for: leetCodeStatus)
                        Image(systemName: "chevron.right")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                }
                
                // Riot Games Integration
                // Button(action: onConnectRiot) {
                //     HStack {
                //         ProfileRowContent(label: "Riot Games", icon: "gamecontroller")
                //         Spacer()
                //         statusLabel(for: riotStatus)
                //         Image(systemName: "chevron.right")
                //             .font(.custom("EBGaramond-Regular", size: 14))
                //             .foregroundColor(.white.opacity(0.4))
                //     }
                //     .padding(.horizontal, 16)
                //     .padding(.vertical, 16)
                //     .background(Color.clear)
                // }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
} 