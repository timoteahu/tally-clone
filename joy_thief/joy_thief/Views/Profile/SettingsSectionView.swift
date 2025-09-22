import SwiftUI

struct SettingsSectionView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showCancelledAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Delete / Cancel-Deletion Button FIRST
            if authManager.hasAccountDeletionRequest {
                Button(action: {
                    print("[DEBUG] Cancel deletion button tapped")
                    Task {
                        await authManager.cancelAccountDeletion()
                        await MainActor.run {
                            showCancelledAlert = true
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.custom("EBGaramond-Regular", size: 16))
                        Text("Cancel Deletion")
                            .jtStyle(.body)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.clear)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
            } else {
                Button(action: {
                    NotificationCenter.default.post(name: .showDeleteAccountConfirmation, object: nil)
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .font(.custom("EBGaramond-Regular", size: 16))
                        Text("Delete Account")
                            .jtStyle(.body)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.clear)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
            }

            // Logout Button SECOND
            Button(action: {
                NotificationCenter.default.post(name: .showLogoutConfirmation, object: nil)
            }) {
                HStack {
                    Image(systemName: "arrow.right.square.fill")
                        .font(.custom("EBGaramond-Regular", size: 16))
                    Text("logout")
                        .jtStyle(.body)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.clear)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
        }
        .alert("Account Deletion Cancelled", isPresented: $showCancelledAlert) {
            Button("OK", role: .cancel) {
                print("[DEBUG] Alert OK button tapped")
            }
        } message: {
            Text("Your account deletion request has been cancelled.")
        }

        .onAppear {
            print("[DEBUG] SettingsSectionView appeared")
            Task {
                await authManager.refreshAccountDeletionRequestStatus()
            }
        }
    }
}

#Preview {
    SettingsSectionView()
        .environmentObject(AuthenticationManager.shared)
        .background(Color.black)
} 
