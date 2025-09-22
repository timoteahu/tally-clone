import Foundation
import Contacts
import SwiftUI

class ContactManager: ObservableObject {
    static let shared = ContactManager()
    private let contactStore = CNContactStore()
    
    @Published var suggestedFriends: [SuggestedFriend] = []
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var hasLoadedOnce = false
    
    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "lastContactSync"
    private let cachedContactsKey = "cachedSuggestedFriends"
    private let hasLoadedOnceKey = "hasLoadedContactsOnce"
    
    // Cache contacts for 7 days (longer since we load once)
    private let cacheExpirationInterval: TimeInterval = 60 * 60
    
    private init() {
        loadCachedContacts()
        hasLoadedOnce = userDefaults.bool(forKey: hasLoadedOnceKey)
    }
    
    func requestAccess() async -> Bool {
        #if targetEnvironment(simulator)
        // In simulator, simulate having contacts
        await MainActor.run {
        isAuthorized = true
            errorMessage = nil
        }
        return true
        #else
        do {
            let authorized = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                isAuthorized = authorized
                errorMessage = authorized ? nil : "Contacts access denied"
            }
            return authorized
        } catch {
            await MainActor.run {
                isAuthorized = false
                errorMessage = "Error requesting contacts access: \(error.localizedDescription)"
            }
            print("Error requesting contacts access: \(error)")
            return false
        }
        #endif
    }
    
    func findSuggestedFriends() async {
        
        guard isAuthorized else {
            await MainActor.run {
                errorMessage = "Contacts access not authorized"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        #if targetEnvironment(simulator)
        // Add some test contacts in simulator
        await MainActor.run {
        suggestedFriends = [
            SuggestedFriend(userId: "1250fabb-ec52-4820-b366-ff5d770b2481", name: "John Doe", phoneNumber: "+1234567890", isExistingUser: true, avatarVersion: 1, avatarUrl80: nil, avatarUrl200: nil, avatarUrlOriginal: nil),
            SuggestedFriend(userId: nil, name: "Jane Smith", phoneNumber: "+1987654321", isExistingUser: false, avatarVersion: nil, avatarUrl80: nil, avatarUrl200: nil, avatarUrlOriginal: nil)
        ]
            errorMessage = nil
        }
        cacheContacts()
        return
        #endif
        
        let keys = [CNContactPhoneNumbersKey, CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        do {
            var contactsData: [(name: String, phoneNumber: String)] = []
            
            
            // First, collect all contacts and their phone numbers
            try contactStore.enumerateContacts(with: request) { contact, stop in
                let phoneNumbers = contact.phoneNumbers.compactMap { number -> String? in
                    let phoneNumber = number.value.stringValue
                    // Remove any non-digit characters except +
                    let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                    
                    // Ensure number starts with + and has reasonable length
                    var finalNumber: String
                    if cleaned.hasPrefix("+") {
                        finalNumber = cleaned
                    } else {
                        // If no country code, assume US (+1)
                        finalNumber = "+1\(cleaned)"
                    }
                    
                    // Basic validation: must be at least 10 digits after country code
                    let digitsOnly = finalNumber.replacingOccurrences(of: "+", with: "")
                    if digitsOnly.count >= 10 && digitsOnly.count <= 15 {
                        return finalNumber
                    } else {
                        return nil
                    }
                }
                
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                
                // Only add contacts with valid names and phone numbers
                guard !name.isEmpty else { return }
                
                for phoneNumber in phoneNumbers {
                    contactsData.append((name: name, phoneNumber: phoneNumber))
                }
            }
            
            
            // Extract unique phone numbers for batch check
            let phoneNumbers = Array(Set(contactsData.map { $0.phoneNumber }))
            
            // Always make the API call, even if no contacts (for testing/debugging)
            let batchResults: [BatchCheckResult]
            if phoneNumbers.isEmpty {
                batchResults = []
            } else {
                // Split into batches of 500 to avoid server limits
                let batchSize = 500
                var allResults: [BatchCheckResult] = []
                
                for i in stride(from: 0, to: phoneNumbers.count, by: batchSize) {
                    let endIndex = min(i + batchSize, phoneNumbers.count)
                    let batch = Array(phoneNumbers[i..<endIndex])
                    
                    let batchResults = await checkUsersExistBatch(phoneNumbers: batch)
                    allResults.append(contentsOf: batchResults)
                }
                
                batchResults = allResults
            }
            
            // Create lookup dictionary for fast access
            var userLookup: [String: (userId: String?, isExisting: Bool)] = [:]
            for result in batchResults {
                userLookup[result.phoneNumber] = (userId: result.userId, isExisting: result.isExistingUser)
            }
            
            // Build suggested friends list
            let newSuggestedFriends: [SuggestedFriend] = contactsData.compactMap { contact in
                guard let userInfo = userLookup[contact.phoneNumber] else { return nil }
                return SuggestedFriend(
                    userId: userInfo.userId,
                    name: contact.name,
                    phoneNumber: contact.phoneNumber,
                    isExistingUser: userInfo.isExisting
                )
            }
            
            
            // Update UI on main thread
            await MainActor.run {
                self.suggestedFriends = newSuggestedFriends
                self.errorMessage = nil
            }
            
            // Cache the results
            cacheContacts()
        } catch {
            await MainActor.run {
                self.suggestedFriends = []
                self.errorMessage = "Error fetching contacts: \(error.localizedDescription)"
            }
        }
    }
    
    private func checkUsersExistBatch(phoneNumbers: [String]) async -> [BatchCheckResult] {
        #if targetEnvironment(simulator)
        // In simulator, return random results
        return phoneNumbers.map { phoneNumber in
            let isExisting = Bool.random()
            return BatchCheckResult(
                phoneNumber: phoneNumber,
                userId: isExisting ? "1250fabb-ec52-4820-b366-ff5d770b2481" : nil,
                isExistingUser: isExisting
            )
        }
        #else
        
        // Validate and clean phone numbers before sending
        let validPhoneNumbers = phoneNumbers.compactMap { phoneNumber -> String? in
            let cleaned = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            // Basic validation: must have at least 10 digits and start with +
            if cleaned.isEmpty || cleaned.count < 10 {
                return nil
            }
            return cleaned
        }
        
        guard !validPhoneNumbers.isEmpty else {
            return []
        }
        
        
        guard let url = URL(string: "\(AppConfig.baseURL)/users/batch-check-phones") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["phone_numbers": validPhoneNumbers]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {                return []
            }
            
            if httpResponse.statusCode != 200 {
                // Try to get error details from response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    print("Server error when batch checking phone numbers: \(httpResponse.statusCode) - \(detail)")
                } else {
                    print("Server error when batch checking phone numbers: \(httpResponse.statusCode)")
                }
                return []
            }
            
            // Parse the response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            
            guard let results = json["results"] as? [[String: Any]] else {
                return []
            }
            
            
            let batchResults = results.compactMap { result -> BatchCheckResult? in
                guard let phoneNumber = result["phone_number"] as? String,
                      let exists = result["exists"] as? Bool else {
                    return nil
                }
                
                let userId = result["user_id"] as? String
                let batchResult = BatchCheckResult(
                    phoneNumber: phoneNumber,
                    userId: userId,
                    isExistingUser: exists
                )
                
                return batchResult
            }
            
            return batchResults
            
        } catch {
            return []
        }
        #endif
    }
    
    private func loadCachedContacts() {
        if let cachedContacts = userDefaults.object(forKey: cachedContactsKey) as? Data {
            if let cachedSuggestedFriends = try? JSONDecoder().decode([SuggestedFriend].self, from: cachedContacts) {
                Task { @MainActor in
                    self.suggestedFriends = cachedSuggestedFriends
                }
            }
        }
    }
    
    private func cacheContacts() {
        if let encoded = try? JSONEncoder().encode(suggestedFriends) {
            userDefaults.set(encoded, forKey: cachedContactsKey)
            userDefaults.set(Date(), forKey: lastSyncKey)
            userDefaults.set(true, forKey: hasLoadedOnceKey)
            Task { @MainActor in
                hasLoadedOnce = true
            }
        }
    }
    
    private func shouldRefreshContacts() -> Bool {
        guard let lastSync = userDefaults.object(forKey: lastSyncKey) as? Date else {
            return true // Never synced before
        }
        return Date().timeIntervalSince(lastSync) > cacheExpirationInterval
    }
    
    // Method to be called during app startup
    func loadContactsOnAppStartup() async {
        
        // During app startup, be more aggressive about loading
        // Load if we haven't loaded before, cache is expired, OR if we have no contacts
        guard !hasLoadedOnce || shouldRefreshContacts() || suggestedFriends.isEmpty else {
            return
        }
        
        await forceRefreshContacts()
    }
    
    func refreshContactsIfNeeded() async {
        
        // If we've never loaded and have no contacts, force load
        if !hasLoadedOnce && suggestedFriends.isEmpty {
            await forceRefreshContacts()
            return
        }
        
        // If we've never loaded but somehow have contacts, wait for startup unless forced
        guard hasLoadedOnce else {
            return
        }
        
        // Check if we need to refresh due to cache expiration
        guard shouldRefreshContacts() else {
            return
        }
        // Request access if needed
        let authorized = await requestAccess()
        guard authorized else {
            await MainActor.run {
                errorMessage = "Contacts access not authorized"
            }
            return
        }
        
        // Refresh contacts
        await findSuggestedFriends()
    }
    
    func forceRefreshContacts() async {
        let authorized = await requestAccess()
        guard authorized else {
            await MainActor.run {
                errorMessage = "Contacts access not authorized"
            }
            return
        }
        
        await findSuggestedFriends()
    }
    
    /// Get all contact phone numbers for unified friend data loading
    func getContactPhoneNumbers() async -> [String] {
        #if targetEnvironment(simulator)
        // Return test phone numbers in simulator
        return ["+1234567890", "+1987654321", "+1555123456"]
        #else
        
        // Check authorization first
        let authorized = await requestAccess()
        guard authorized else {
            print("❌ [ContactManager] Contacts access not authorized")
            return []
        }
        
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        var phoneNumbers: [String] = []
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, stop in
                let contactPhoneNumbers = contact.phoneNumbers.compactMap { number -> String? in
                    let phoneNumber = number.value.stringValue
                    // Remove any non-digit characters except +
                    let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                    
                    // Ensure number starts with + and has reasonable length
                    var finalNumber: String
                    if cleaned.hasPrefix("+") {
                        finalNumber = cleaned
                    } else {
                        // If no country code, assume US (+1)
                        finalNumber = "+1\(cleaned)"
                    }
                    
                    // Basic validation: must be at least 10 digits after country code
                    let digitsOnly = finalNumber.replacingOccurrences(of: "+", with: "")
                    if digitsOnly.count >= 10 && digitsOnly.count <= 15 {
                        return finalNumber
                    } else {
                        return nil
                    }
                }
                
                phoneNumbers.append(contentsOf: contactPhoneNumbers)
            }
            
            // Remove duplicates and return
            let uniquePhoneNumbers = Array(Set(phoneNumbers))
            
            return uniquePhoneNumbers
            
        } catch {
            return []
        }
        #endif
    }
}

struct SuggestedFriend: Identifiable, Codable {
    var id = UUID()
    let userId: String?
    let name: String
    let phoneNumber: String
    let isExistingUser: Bool
    // Avatar fields for existing users
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    
    // Convenience initializer for backward compatibility
    init(userId: String? = nil, name: String, phoneNumber: String, isExistingUser: Bool, avatarVersion: Int? = nil, avatarUrl80: String? = nil, avatarUrl200: String? = nil, avatarUrlOriginal: String? = nil) {
        self.userId = userId
        self.name = name
        self.phoneNumber = phoneNumber
        self.isExistingUser = isExistingUser
        self.avatarVersion = avatarVersion
        self.avatarUrl80 = avatarUrl80
        self.avatarUrl200 = avatarUrl200
        self.avatarUrlOriginal = avatarUrlOriginal
    }
}

struct BatchCheckResult {
    let phoneNumber: String
    let userId: String?
    let isExistingUser: Bool
} 
