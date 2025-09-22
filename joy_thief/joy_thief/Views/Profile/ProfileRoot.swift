import SwiftUI

/// A full-screen wrapper around `ProfileView` that provides:
/// • Slide-in/out animation identical to `PaymentRoot`
/// • Edge-pan (from the left edge) to dismiss – horizontal drags only
/// • A persistent black bar at the very top to avoid content under the Dynamic Island
struct ProfileRoot: View {
    // Logout confirmation state
    @State private var showLogoutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    let onDismiss: (() -> Void)?
    
    // Environment objects
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var owedAmountManager: OwedAmountManager
    @EnvironmentObject var identitySnapshotManager: IdentitySnapshotManager
    @EnvironmentObject var paymentStatsManager: PaymentStatsManager
    
    // Gesture state
    @State private var isHorizontalDragging = false
    @State private var dragOffset: CGFloat = 0
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            content
                .offset(x: dragOffset)
                .gesture(edgeSwipeGesture)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        }
        .preferredColorScheme(.dark)
        // Listen for logout confirmation trigger
        .onReceive(NotificationCenter.default.publisher(for: .showLogoutConfirmation)) { _ in
            showLogoutConfirmation = true
        }
        // Listen for delete account confirmation trigger
        .onReceive(NotificationCenter.default.publisher(for: .showDeleteAccountConfirmation)) { _ in
            showDeleteAccountConfirmation = true
        }
        // Logout confirmation overlay
        .overlay(
            ZStack {
                if showLogoutConfirmation {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showLogoutConfirmation = false }
                    // Dialog content (reuse design)
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button(action: { showLogoutConfirmation = false }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.bottom, 8)
                        Text("log out?")
                            .font(.custom("EBGaramond-Bold", size: 24))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("log out of your account?")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button(action: { showLogoutConfirmation = false }) {
                                Text("No")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            Button(action: {
                                showLogoutConfirmation = false
                                Task { await authManager.logout() }
                            }) {
                                Text("Yes")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.9)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)))
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        )
        .animation(.easeInOut(duration: 0.2), value: showLogoutConfirmation)
        // Delete account confirmation overlay
        .overlay(
            ZStack {
                if showDeleteAccountConfirmation {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showDeleteAccountConfirmation = false }
                    // Dialog content
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button(action: { showDeleteAccountConfirmation = false }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.bottom, 8)
                        Text("delete account?")
                            .font(.custom("EBGaramond-Bold", size: 24))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("this will submit a request to delete your account. it will take place as soon as possible.")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button(action: { showDeleteAccountConfirmation = false }) {
                                Text("Cancel")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            Button(action: {
                                showDeleteAccountConfirmation = false
                                Task { await authManager.deleteAccount() }
                            }) {
                                Text("Delete")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.9)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)))
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        )
        .animation(.easeInOut(duration: 0.2), value: showDeleteAccountConfirmation)
    }
    
    private func dismissView() {
        if let callback = onDismiss {
            callback()
        }
    }
    
    @ViewBuilder private var content: some View {
        ProfileView(showPaymentView: showPaymentFromProfile, onDismiss: dismissView)
            .environmentObject(authManager)
            .environmentObject(habitManager)
            .environmentObject(owedAmountManager)
            .environmentObject(identitySnapshotManager)
            .environmentObject(paymentStatsManager)
            .disabled(isHorizontalDragging)
    }

    // MARK: – Payment trigger for nested overlay
    private var showPaymentFromProfile: () -> Void {
        {
            // Post a notification – OverlayViews listens & presents payment
            NotificationCenter.default.post(name: Notification.Name("TriggerPaymentOverlay"), object: nil)
        }
    }

    // MARK: – Edge-swipe gesture (horizontal priority)
    private var edgeSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Start only from left edge & prioritise horizontal drags
                if value.startLocation.x < 80 && abs(value.translation.width) > abs(value.translation.height) {
                    if !isHorizontalDragging { isHorizontalDragging = true }
                    let progress = min(value.translation.width / 100, 1.0)
                    dragOffset = value.translation.width * 0.8 * progress
                }
            }
            .onEnded { value in
                if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                    dismissView()
                } else {
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) { dragOffset = 0 }
                }
                isHorizontalDragging = false
            }
    }
}

// MARK: – Thin compatibility wrapper so OverlayViews can use ProfileRoot()
// Notification names for confirmation triggers
extension Notification.Name {
    static let showLogoutConfirmation = Notification.Name("ShowLogoutConfirmation")
    static let showDeleteAccountConfirmation = Notification.Name("ShowDeleteAccountConfirmation")
}

struct ProfileOverlay: View {
    let onDismiss: (() -> Void)?
    var body: some View { ProfileRoot(onDismiss: onDismiss) }
}

#Preview {
    NavigationStack {
        ProfileRoot(onDismiss: nil)
            .environmentObject(AuthenticationManager.shared)
            .environmentObject(HabitManager.shared)
            .environmentObject(OwedAmountManager())
            .environmentObject(IdentitySnapshotManager.shared)
            .environmentObject(PaymentStatsManager.shared)
    }
} 
