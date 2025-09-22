import SwiftUI

// MARK: - PaymentHistoryRoot - Root view with gesture handling
struct PaymentHistoryRoot: View {
    let onDismiss: (() -> Void)?
    
    @EnvironmentObject var paymentStatsManager: PaymentStatsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var isAnimationComplete = false
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragging = false
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    private func dismissView() {
        if let callback = onDismiss {
            callback()
        } else {
            dismiss()
        }
    }
    
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
            // Delay to prevent automatic back button trigger during slide-in animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimationComplete = true
            }
            
            // Debug: Print current payment stats state
            print("🔍 [PaymentHistory] OnAppear - Stats loaded: \(paymentStatsManager.paymentStats != nil)")
            print("🔍 [PaymentHistory] Payment history count: \(paymentStatsManager.paymentHistory.count)")
            print("🔍 [PaymentHistory] Total payments: $\(paymentStatsManager.totalPayments)")
            print("🔍 [PaymentHistory] Is loading: \(paymentStatsManager.isLoading)")
            print("🔍 [PaymentHistory] Error message: \(paymentStatsManager.errorMessage ?? "none")")
        }
        .gesture(dragGesture)
    }
    
    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            // Fixed Header
            customHeader
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Summary Section
                    summarySection
                    
                    // Payment History Section (moved to middle)
                    historySection
                    
                    // Information Section
                    infoSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .padding(.bottom, 100)
            }
        }
        .disabled(isHorizontalDragging)
    }
    
    private var customHeader: some View {
        HStack {
            Button(action: {
                guard isAnimationComplete else { return }
                dismissView()
            }) {
                Image(systemName: "chevron.left")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .disabled(!isAnimationComplete)
            
            Spacer()
            
            Text("payment history")
                .jtStyle(.title2)
                .fontWeight(.thin)
                .foregroundColor(.white)
            
            Spacer()
            
            // Debug refresh button
            Button(action: {
                paymentStatsManager.refreshPaymentStats()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Empty space for symmetry
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("summary")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.leading, 4)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PaymentStatCard(
                        title: "Total Paid",
                        value: String(format: "$%.2f", paymentStatsManager.totalPayments),
                        subtitle: "All time",
                        color: .green
                    )
                    
                    PaymentStatCard(
                        title: "Unpaid",
                        value: String(format: "$%.2f", paymentStatsManager.unpaidPenalties),
                        subtitle: "Current balance",
                        color: .red
                    )
                }
                
                if paymentStatsManager.processingPayments > 0 {
                    PaymentStatCard(
                        title: "Processing",
                        value: String(format: "$%.2f", paymentStatsManager.processingPayments),
                        subtitle: "In progress",
                        color: .orange
                    )
                }
            }
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("payment history")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                if paymentStatsManager.isLoading {
                    HStack {
                        ProgressView("Loading payment history...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Spacer()
                    }
                    .padding()
                } else if let errorMessage = paymentStatsManager.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Error loading payment history")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.6))
                        Text(errorMessage)
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            paymentStatsManager.refreshPaymentStats()
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if paymentStatsManager.paymentHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.3))
                        Text("No payment history")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.6))
                        Text("Your payments will appear here")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        
                        // Debug info
                        VStack(spacing: 4) {
                            Text("Debug Info:")
                                .jtStyle(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, 16)
                            Text("Stats loaded: \(paymentStatsManager.paymentStats != nil ? "Yes" : "No")")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Total payments: $\(paymentStatsManager.totalPayments, specifier: "%.2f")")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Unpaid penalties: $\(paymentStatsManager.unpaidPenalties, specifier: "%.2f")")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(paymentStatsManager.paymentHistory) { payment in
                        PaymentHistoryRow(payment: payment)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("how payments work")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(
                    icon: "creditcard.fill",
                    title: "efficient charging",
                    description: "penalties are charged when the total reaches $10, reducing transaction fees"
                )
                
                InfoRow(
                    icon: "arrow.triangle.swap",
                    title: "instant transfers",
                    description: "85% goes to recipients immediately, 15% platform fee covers processing"
                )
                
                InfoRow(
                    icon: "shield.checkered",
                    title: "secure processing",
                    description: "all transactions processed securely through stripe with industry-leading protection"
                )
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
    
    // MARK: - Drag Gesture (matching PaymentRoot pattern)
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
}

// MARK: - Thin compatibility wrapper
struct PaymentHistoryView: View {
    let onDismiss: (() -> Void)?
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        PaymentHistoryRoot(onDismiss: onDismiss)
    }
}

// MARK: - PaymentHistoryOverlay wrapper for use in OverlayViews
struct PaymentHistoryOverlay: View {
    let onDismiss: (() -> Void)?
    
    var body: some View {
        PaymentHistoryRoot(onDismiss: onDismiss)
    }
}

// MARK: - Supporting Views
struct PaymentStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text(value)
                .jtStyle(.title)
                .foregroundColor(color)
            
            Text(subtitle)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct PaymentHistoryRow: View {
    let payment: PaymentHistoryItem
    
    private var statusColor: Color {
        if payment.isPaid {
            return .green
        } else if payment.paymentStatus == "processing" {
            return .orange
        } else {
            return .red
        }
    }
    
    private var statusText: String {
        if payment.isPaid {
            return "Paid"
        } else if payment.paymentStatus == "processing" {
            return "Processing"
        } else {
            return "Unpaid"
        }
    }
    
    private var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        
        if let date = inputFormatter.date(from: payment.date) {
            return outputFormatter.string(from: date)
        } else {
            return payment.date // Return original string if parsing fails
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(payment.reason)
                        .jtStyle(.body)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    Text(formattedDate)
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "$%.2f", payment.amount))
                        .jtStyle(.body)
                        .foregroundColor(.white)
                    
                    Text(statusText)
                        .jtStyle(.caption)
                        .foregroundColor(statusColor)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            
            // Show transfer breakdown for paid penalties with recipients
            if payment.isPaid && payment.amount > 0 {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transfer Details")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack {
                            Text("Recipient payout:")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "$%.2f", payment.amount * 0.85))
                                .jtStyle(.caption)
                                .foregroundColor(.green.opacity(0.8))
                        }
                        
                        HStack {
                            Text("Platform fee (15%):")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "$%.2f", payment.amount * 0.15))
                                .jtStyle(.caption)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.clear)
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.blue.opacity(0.8))
                .frame(width: 20, alignment: .center)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .jtStyle(.body)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

#Preview {
    PaymentHistoryView()
        .environmentObject(PaymentStatsManager.shared)
} 