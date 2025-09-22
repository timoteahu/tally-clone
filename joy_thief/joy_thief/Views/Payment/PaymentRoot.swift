import SwiftUI
import Foundation
import WebKit
import StripePaymentSheet
import UIKit

// MARK: - Local helper types (embedded)

enum ConnectStatus {
    case notConnected
    case pending
    case connected
}

struct ConnectStatusResponse: Codable {
    let status: String
    let details_submitted: Bool?
    let charges_enabled: Bool?
    let payouts_enabled: Bool?
}

struct BalanceResponse: Codable {
    let balance: Double
    let currency: String
}

struct WithdrawalResponse: Codable {
    let status: String
    let amount: Double
    let payout_id: String
}

// MARK: – Payment Flow Root ---------------------------------------------------

/// Container view for the payment & payout experience. This is the logic that was
/// previously hosted in `Views/PaymentView.swift`, extracted into the `Views/Payment` 
/// sub-folder alongside its helper sub-views.
struct PaymentRoot: View {
    let onDismiss: (() -> Void)?

    // MARK: ­– Environment
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var paymentManager: PaymentManager
    @Environment(\.dismiss) private var dismiss

    // MARK: ­– State
    @State private var connectStatus: ConnectStatus = .notConnected
    @State private var balance: Double = 0
    @State private var isLoadingBalance = false
    @State private var isHorizontalDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var expandedFAQItems: String? = nil
    @State private var showCopiedMessage = false

    // Polling timer for Connect status when onboarding is in progress
    @State private var statusRefreshTimer: Timer? = nil

    // Cache key for storing last known connect status
    private let connectStatusCacheKey = "cachedConnectStatus"

    // MARK: – Init
    init(onDismiss: (() -> Void)? = nil) { self.onDismiss = onDismiss }

    // MARK: – Helpers
    private func dismissView() {
        if let callback = onDismiss {
            callback()
        } else {
            dismiss()
        }
    }

    // MARK: – View
    var body: some View {
        ZStack {
            AppBackground()
                .overlay(content)
                .offset(x: dragOffset)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.95), value: dragOffset)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear {
            loadCachedConnectStatus()
            Task { await checkConnectStatus(); fetchBalance() }
        }
        // Re-check status whenever app returns to foreground (e.g. after Safari flow)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await checkConnectStatus(); fetchBalance()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshBalance"))) { _ in
            Task {
                fetchBalance()
            }
        }
        .onDisappear { stopStatusPolling() }
        .gesture(dragGesture)
    }

    // MARK: – Sub-tree
    @ViewBuilder private var content: some View {
        VStack {
            // Nav
            navBar

            ScrollView {
                VStack(spacing: 24) {
                    PaymentMethodSectionView()
                    StripeConnectSectionView(connectStatus: connectStatus)
                    // if connectStatus == .connected {
                    //     BalanceSectionView(balance: balance, isLoading: isLoadingBalance)
                    // }
                    paymentUrlQuote
                    faqSection
                }
                .padding(.bottom, 24)
            }
            .disabled(isHorizontalDragging)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: dismissView) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                    Text("Back").jtStyle(.body)
                }
                .foregroundColor(.white)
                .padding(.leading, 8)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: – Payment URL helper
    private var paymentUrlQuote: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Visit our website to manage your payment settings")
                .font(.custom("EBGaramond-Regular", size: 14))
                .foregroundColor(.white.opacity(0.8))
            HStack(spacing: 12) {
                Text("jointally.app/payment")
                    .jtStyle(.body)
                    .foregroundColor(.white.opacity(0.5))
                Button {
                    UIPasteboard.general.string = "jointally.app/payment"
                    withAnimation { showCopiedMessage = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { showCopiedMessage = false } }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            if showCopiedMessage {
                Text("Copied to clipboard")
                    .jtStyle(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }

    // MARK: – Drag Gesture
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.startLocation.x < 80 && abs(value.translation.height) < 120 {
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

    // MARK: – Networking helpers (unchanged)
    private func fetchBalance() {
        isLoadingBalance = true
        Task {
            do {
                guard let url = URL(string: "\(AppConfig.baseURL)/payments/connect/balance") else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                if let token = UserDefaults.standard.string(forKey: "authToken") {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, resp) = try await URLSession.shared.data(for: request)
                if let httpResp = resp as? HTTPURLResponse {
                    guard httpResp.statusCode == 200 else { await MainActor.run { isLoadingBalance = false }; return }
                }
                let decoded = try JSONDecoder().decode(BalanceResponse.self, from: data)
                await MainActor.run {
                    balance = decoded.balance
                    isLoadingBalance = false
                }
            } catch {
                print("❌ Error fetching balance: \(error)")
                await MainActor.run { isLoadingBalance = false }
            }
        }
    }

    private func checkConnectStatus() async {
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/payments/connect/account-status") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            if let token = UserDefaults.standard.string(forKey: "authToken") {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 { return }
            let decoded = try JSONDecoder().decode(ConnectStatusResponse.self, from: data)
            await MainActor.run {
                switch decoded.status {
                case "connected":
                    if decoded.details_submitted == true && decoded.charges_enabled == true && decoded.payouts_enabled == true {
                        connectStatus = .connected; saveCachedConnectStatus(.connected); stopStatusPolling()
                    } else {
                        connectStatus = .pending; saveCachedConnectStatus(.pending); startStatusPolling()
                    }
                case "pending":
                    connectStatus = .pending; saveCachedConnectStatus(.pending); startStatusPolling()
                case "not_connected": fallthrough
                default:
                    connectStatus = .notConnected; saveCachedConnectStatus(.notConnected); stopStatusPolling()
                }
            }
        } catch { print("❌ Error checking connect status: \(error)") }
    }





    // MARK: – FAQ (unchanged)
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("frequently asked questions")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)
            VStack(spacing: 8) {
                faqItem(q: "how do payment methods work?", a: "your payment method is inputted on our website and uses stripe.")
                faqItem(q: "is my payment information really secure?", a: "yes! we use Stripe, a leading payment processor, to handle all payment information. your card details are never stored on our servers and are encrypted using industry-standard security measures.")
                faqItem(q: "how do i create a new habit?", a: "tap the '+' button on the home screen to create a new habit. you'll need to set a name, penalty amount, and choose an accountability partner who will receive your penalty payments if you fail.")
                faqItem(q: "what types of habits can i track?", a: "you can track various habits including gym workouts, study sessions, screen time limits, and custom habits. each habit type has specific verification methods to ensure accountability.")
                faqItem(q: "how does habit verification work?", a: "different habits have different verification methods. for example, gym habits require photos, screen time habits track your device usage, and study habits use a timer.")
                faqItem(q: "what happens if i miss a habit?", a: "if you fail to verify a habit within its verification window, the penalty amount will be automatically charged to your payment method and sent to your accountability partner.")
            }
            .padding(.horizontal, 20)
        }
    }

    private func faqItem(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedFAQItems == q {
                        expandedFAQItems = nil
                    } else {
                        expandedFAQItems = q
                    }
                }
            } label: {
                HStack {
                    Text(q).font(.custom("EBGaramond-Regular", size: 16)).foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .rotationEffect(.degrees(expandedFAQItems == q ? 180 : 0))
                }
            }
            if expandedFAQItems == q {
                Text(a).font(.custom("EBGaramond-Regular", size: 14)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: – Polling helpers
    private func startStatusPolling() {
        stopStatusPolling()
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { 
                await checkConnectStatus()
                await MainActor.run {
                    fetchBalance()
                }
            }
        }
    }

    private func stopStatusPolling() {
        statusRefreshTimer?.invalidate(); statusRefreshTimer = nil
    }

    // MARK: – Caching helpers
    private func loadCachedConnectStatus() {
        if let raw = UserDefaults.standard.string(forKey: connectStatusCacheKey) {
            switch raw {
            case "connected": connectStatus = .connected
            case "pending": connectStatus = .pending
            default: connectStatus = .notConnected
            }
        }
    }

    private func saveCachedConnectStatus(_ status: ConnectStatus) {
        let raw: String
        switch status {
        case .connected: raw = "connected"
        case .pending: raw = "pending"
        case .notConnected: raw = "not_connected"
        }
        UserDefaults.standard.setValue(raw, forKey: connectStatusCacheKey)
    }
}

// MARK: – Thin compatibility wrapper ----------------------------------------

/// Maintains existing `PaymentView()` call-sites while delegating to the new root.
struct PaymentView: View {
    let onDismiss: (() -> Void)?
    init(onDismiss: (() -> Void)? = nil) { self.onDismiss = onDismiss }
    var body: some View { PaymentRoot(onDismiss: onDismiss) }
}

// MARK: – Preview

#Preview {
    NavigationStack { PaymentRoot() }
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(HabitManager.shared)
        .environmentObject(PaymentManager.shared)
} 
