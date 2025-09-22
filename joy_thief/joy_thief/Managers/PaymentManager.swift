import SwiftUI
import Foundation

class PaymentManager: ObservableObject {
    static let shared = PaymentManager()
    
    @Published var paymentMethod: PaymentMethod? = nil
    
    private init() {}
    
    func fetchPaymentMethod(token: String) async -> Bool {
        guard let url = URL(string: "\(AppConfig.baseURL)/payments/get-user-payment-method") else { 
            print("❌ Invalid URL for payment method fetch")
            return false 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                return false
            }
            
            print("Payment method fetch response: \(httpResponse.statusCode)")
            guard httpResponse.statusCode == 200 else { 
                print("❌ Payment method fetch failed with status: \(httpResponse.statusCode)")
                return false 
            }
            
            let respons = try JSONDecoder().decode(PaymentMethodResponse.self, from: data)
            await MainActor.run { 
                self.paymentMethod = respons.payment_method.toPaymentMethod() 
            }
            print("✅ Payment method fetched successfully")
            return true
        } catch {
            print("❌ Failed to fetch payment method: \(error)")
            return false
        }
    }
    
    // NEW: Stripe Connect onboarding URL generation (two-step flow)
    func initiateConnectOnboarding(token: String) async throws -> String? {
        // 1️⃣ Ensure a Connect account exists (or create one)
        guard let createAccountURL = URL(string: "\(AppConfig.baseURL)/payments/connect/create-account") else {
            throw URLError(.badURL)
        }
        var accountReq = URLRequest(url: createAccountURL)
        accountReq.httpMethod = "POST"
        accountReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        accountReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (accountData, accountResp) = try await URLSession.shared.data(for: accountReq)
        guard let accountHTTP = accountResp as? HTTPURLResponse, accountHTTP.statusCode == 200 else {
            let msg = String(data: accountData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "StripeConnect", code: (accountResp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        struct CreateAccountResponse: Codable { let account_id: String }
        let accountDecoded = try JSONDecoder().decode(CreateAccountResponse.self, from: accountData)

        // 2️⃣ Create an onboarding link for that account
        guard let linkURL = URL(string: "\(AppConfig.baseURL)/payments/connect/create-account-link") else {
            throw URLError(.badURL)
        }
        let body: [String: String] = [
            "account_id": accountDecoded.account_id,
            "refresh_url": "https://jointally.app/payment/refresh",
            "return_url": "https://jointally.app/payment/return"
        ]
        var linkReq = URLRequest(url: linkURL)
        linkReq.httpMethod = "POST"
        linkReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        linkReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        linkReq.httpBody = try JSONEncoder().encode(body)

        let (linkData, linkResp) = try await URLSession.shared.data(for: linkReq)
        guard let linkHTTP = linkResp as? HTTPURLResponse, linkHTTP.statusCode == 200 else {
            let msg = String(data: linkData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "StripeConnect", code: (linkResp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        struct AccountLinkResponse: Codable { let url: String }
        let linkDecoded = try JSONDecoder().decode(AccountLinkResponse.self, from: linkData)
        return linkDecoded.url
    }
} 