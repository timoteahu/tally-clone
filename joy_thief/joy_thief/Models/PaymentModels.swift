import Foundation

struct PaymentMethod: Codable {
    let brand: String
    let last4: String
    let expiry: String
}

struct PaymentMethodResponse: Codable {
    let payment_method: PaymentMethodDetails
}

struct PaymentMethodDetails: Codable {
    let card: CardDetails?
    func toPaymentMethod() -> PaymentMethod? {
        guard let card = card else { return nil }
        let map = [1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun", 7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec"]
        let expiryString = "\(map[card.exp_month] ?? "") \(card.exp_year % 100)"
        return PaymentMethod(brand: card.brand, last4: card.last4, expiry: expiryString)
    }
}

struct CardDetails: Codable {
    let brand: String
    let last4: String
    let exp_month: Int
    let exp_year: Int
} 