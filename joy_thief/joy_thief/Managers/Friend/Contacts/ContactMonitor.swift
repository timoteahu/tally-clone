import Foundation
import Contacts
import CryptoKit

/// Actor for efficient contact change detection
actor ContactMonitor {
    private let contactStore = CNContactStore()
    private var lastKnownHash: String?
    
    /// Get current contacts hash using background processing
    func getCurrentContactsHash() async -> String {
        do {
            let contacts = try await fetchContacts()
            return await hashContacts(contacts)
        } catch {
            return ""
        }
    }
    
    /// Check if contacts have changed since the given hash
    func hasContactsChanged(since hash: String?) async -> Bool {
        guard hasContactsPermission() else { return false }
        
        let currentHash = await getCurrentContactsHash()
        let hasChanged = currentHash != hash
        
        return hasChanged
    }
    
    /// Get contact phone numbers for API requests
    func getContactPhoneNumbers() async -> [String]? {
        return await ContactManager.shared.getContactPhoneNumbers()
    }
    
    /// Check if contacts permission is granted
    func hasContactsPermission() -> Bool {
        return CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }
    
    /// Request contacts permission
    func requestContactsPermission() async -> Bool {
        do {
            try await contactStore.requestAccess(for: .contacts)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// Fetch contacts from the device
    private func fetchContacts() async throws -> [CNContact] {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
                    let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                    
                    var contacts: [CNContact] = []
                    
                    try self.contactStore.enumerateContacts(with: request) { contact, _ in
                        // Only include contacts with phone numbers
                        if !contact.phoneNumbers.isEmpty {
                            contacts.append(contact)
                        }
                    }
                    
                    continuation.resume(returning: contacts)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Hash contacts using cryptographic function to prevent reverse engineering
    private func hashContacts(_ contacts: [CNContact]) async -> String {
        return await Task.detached {
            // Create a deterministic string representation of contacts
            let contactStrings = contacts.map { contact in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                let phoneNumbers = contact.phoneNumbers.map { $0.value.stringValue }.sorted()
                return "\(name):\(phoneNumbers.joined(separator: ","))"
            }.sorted() // Sort to ensure consistent ordering
            
            let combinedString = contactStrings.joined(separator: "|")
            
            // Use SHA-256 for cryptographic security
            let data = Data(combinedString.utf8)
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }.value
    }
    
    /// Normalize phone number for consistent comparison
    private func normalizePhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-numeric characters
        let digitsOnly = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Handle US numbers - add country code if missing
        if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        } else if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+\(digitsOnly)"
        }
        
        // For other numbers, add + if missing
        if !digitsOnly.isEmpty && !phoneNumber.hasPrefix("+") {
            return "+\(digitsOnly)"
        }
        
        return digitsOnly
    }
} 
