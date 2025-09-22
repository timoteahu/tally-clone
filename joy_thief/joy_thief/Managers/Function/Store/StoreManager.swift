import Foundation
import StoreKit

enum SubscriptionType: String, CaseIterable {
    case tallyInsurance = "com.joythief.tally.insurance"
    case tallyPremium = "com.joythief.tally.premium"
    
    var displayName: String {
        switch self {
        case .tallyInsurance:
            return "Tally Insurance"
        case .tallyPremium:
            return "Tally Premium"
        }
    }
}

@MainActor
class StoreManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedSubscriptions: Set<String> = []
    @Published var subscriptionGroupStatus: Product.SubscriptionInfo.RenewalState?
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    var tallyInsurancePrice: String {
        guard let product = products.first(where: { $0.id == SubscriptionType.tallyInsurance.rawValue }) else {
            return "Loading..."
        }
        return product.displayPrice
    }
    
    var tallyPremiumPrice: String {
        guard let product = products.first(where: { $0.id == SubscriptionType.tallyPremium.rawValue }) else {
            return "Loading..."
        }
        return product.displayPrice
    }
    
    init() {
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // Deliver products to the user.
                    await self.updateCustomerProductStatus()
                    
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }
    
    func loadProducts() async {
        do {
            // Request products from the App Store using the identifiers that the products have in App Store Connect.
            products = try await Product.products(for: SubscriptionType.allCases.map { $0.rawValue })
            
            // Load current subscription status
            await updateCustomerProductStatus()
        } catch {
            print("Failed product request from the App Store server: \(error)")
        }
    }
    
    func purchase(_ subscriptionType: SubscriptionType) async -> Bool {
        guard let product = products.first(where: { $0.id == subscriptionType.rawValue }) else {
            return false
        }
        
        do {
            // Request a purchase from the App Store.
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check whether the transaction is verified. If it isn't, catch `failedVerification` and handle the failure.
                let transaction = try checkVerified(verification)
                
                // The transaction is verified. Deliver content to the user.
                await updateCustomerProductStatus()
                
                // Always finish a transaction.
                await transaction.finish()
                
                return true
            case .userCancelled, .pending:
                return false
            default:
                return false
            }
        } catch {
            print("Failed purchase for \(subscriptionType.displayName): \(error)")
            return false
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            // StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            // The result is verified. Return the unwrapped value.
            return safe
        }
    }
    
    @MainActor
    func updateCustomerProductStatus() async {
        var purchasedSubscriptions: Set<String> = []
        
        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                // Check whether the transaction is verified. If it isn't, catch `failedVerification` and handle the failure.
                let transaction = try checkVerified(result)
                
                switch transaction.productType {
                case .autoRenewable:
                    purchasedSubscriptions.insert(transaction.productID)
                default:
                    break
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        self.purchasedSubscriptions = purchasedSubscriptions
        
        // Update subscription group status
        if let firstSubscription = subscriptions.first,
           let subscription = firstSubscription.subscription,
           let statusInfo = try? await subscription.status.first {
            subscriptionGroupStatus = statusInfo.state
        }
    }
    
    func restorePurchases() async {
        // This will re-sync the user's purchases with the device
        try? await AppStore.sync()
        await updateCustomerProductStatus()
    }
    
    var subscriptions: [Product] {
        return products.filter { $0.type == .autoRenewable }
    }
    
    func subscriptionGroupStatus(for groupID: String) -> Product.SubscriptionInfo.RenewalState? {
        return subscriptionGroupStatus
    }
    
    var hasActiveSubscription: Bool {
        return !purchasedSubscriptions.isEmpty
    }
    
    var activePremiumSubscription: SubscriptionType? {
        if purchasedSubscriptions.contains(SubscriptionType.tallyPremium.rawValue) {
            return .tallyPremium
        } else if purchasedSubscriptions.contains(SubscriptionType.tallyInsurance.rawValue) {
            return .tallyInsurance
        }
        return nil
    }
}

public enum StoreError: Error {
    case failedVerification
}

// Extension to support subscription management
extension StoreManager {
    var currentSubscription: Product? {
        return subscriptions.first { product in
            purchasedSubscriptions.contains(product.id)
        }
    }
    
    func isPremiumActive() -> Bool {
        return purchasedSubscriptions.contains(SubscriptionType.tallyPremium.rawValue)
    }
    
    func isInsuranceActive() -> Bool {
        return purchasedSubscriptions.contains(SubscriptionType.tallyInsurance.rawValue)
    }
} 
