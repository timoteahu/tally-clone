import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeManager: StoreManager
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        subscriptionTiers
                        featuresSection
                        termsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await storeManager.loadProducts()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Subscription"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.custom("EBGaramond-Regular", size: 60))
                .foregroundColor(.yellow)
                .padding(.top, 20)
            
            Text("Upgrade to Premium")
                .jtStyle(.title)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Unlock advanced features and take your habit tracking to the next level")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
    
    private var subscriptionTiers: some View {
        VStack(spacing: 16) {
            // Tally Premium
            SubscriptionTierCard(
                title: "Tally Premium",
                subtitle: "Full premium experience",
                price: storeManager.tallyPremiumPrice,
                period: "per month",
                features: [
                    "Unlimited habit tracking",
                    "Advanced analytics & insights",
                    "Custom penalty recipients",
                    "Priority customer support",
                    "Export data capabilities"
                ],
                isPremium: true,
                action: {
                    Task {
                        await purchaseSubscription(.tallyPremium)
                    }
                },
                isLoading: isLoading
            )
            
            // Tally Insurance
            SubscriptionTierCard(
                title: "Tally Insurance",
                subtitle: "Basic protection plan",
                price: storeManager.tallyInsurancePrice,
                period: "per month",
                features: [
                    "Habit backup & recovery",
                    "Basic analytics",
                    "Email support",
                    "Data export (limited)"
                ],
                isPremium: false,
                action: {
                    Task {
                        await purchaseSubscription(.tallyInsurance)
                    }
                },
                isLoading: isLoading
            )
        }
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why Upgrade?")
                .jtStyle(.title)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                PremiumFeatureRow(icon: "chart.bar.fill", title: "Advanced Analytics", description: "Deep insights into your habit patterns")
                PremiumFeatureRow(icon: "cloud.fill", title: "Cloud Backup", description: "Never lose your progress again")
                PremiumFeatureRow(icon: "person.2.fill", title: "Custom Recipients", description: "Send penalties to anyone you choose")
                PremiumFeatureRow(icon: "headphones", title: "Priority Support", description: "Get help when you need it most")
            }
        }
        .padding(.top, 20)
    }
    
    private var termsSection: some View {
        VStack(spacing: 8) {
            Text("Subscriptions auto-renew unless canceled at least 24 hours before the end of the current period.")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
                Button("Terms of Service") {
                    // Open terms of service
                }
                .font(.ebGaramondCaption)
                .foregroundColor(.blue)
                
                Button("Privacy Policy") {
                    // Open privacy policy
                }
                .font(.ebGaramondCaption)
                .foregroundColor(.blue)
            }
        }
        .padding(.top, 20)
    }
    
    private func purchaseSubscription(_ type: SubscriptionType) async {
        isLoading = true
        
        let success = await storeManager.purchase(type)
        await MainActor.run {
            if success {
                alertMessage = "Successfully subscribed to \(type.displayName)!"
            } else {
                alertMessage = "Purchase was cancelled or failed. Please try again."
            }
            showAlert = true
        }
        
        isLoading = false
    }
}

struct SubscriptionTierCard: View {
    let title: String
    let subtitle: String
    let price: String
    let period: String
    let features: [String]
    let isPremium: Bool
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                HStack {
                    Text(title)
                        .jtStyle(.title)
                        .foregroundColor(.white)
                    
                    if isPremium {
                        Image(systemName: "crown.fill")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.yellow)
                    }
                    
                    Spacer()
                }
                
                HStack {
                    Text(subtitle)
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
            }
            
            // Price
            HStack {
                Text(price)
                    .jtStyle(.title)
                    .foregroundColor(.white)
                Text(period)
                    .jtStyle(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            
            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.green)
                        Text(feature)
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                }
            }
            
            // Subscribe Button
            Button(action: action) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Subscribe")
                            .jtStyle(.body)
                    }
                }
                .foregroundColor(isPremium ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isPremium ? .yellow : Color.white.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPremium ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .disabled(isLoading)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: isPremium ? 
                [Color.yellow.opacity(0.1), Color.orange.opacity(0.05)] :
                [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isPremium ? Color.yellow.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.custom("EBGaramond-Regular", size: 20))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .jtStyle(.body)
                    .foregroundColor(.white)
                
                Text(description)
                    .jtStyle(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
}

#Preview {
    PremiumView()
} 