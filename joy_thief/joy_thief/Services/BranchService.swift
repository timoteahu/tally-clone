import Foundation
import BranchSDK
import SwiftUI

// MARK: - Modern Branch Service Architecture

/// Enhanced invite data structure from Branch.io deep links
struct BranchInviteData: Codable {
    let inviterId: String
    let inviterName: String
    let inviterPhone: String
    let inviterProfilePhoto: String?
    let habitId: String?
    
    init(from branchParams: [String: Any]) {
        self.inviterId = branchParams["inviter_id"] as? String ?? ""
        self.inviterName = branchParams["inviter_name"] as? String ?? "Unknown User"
        self.inviterPhone = branchParams["inviter_phone"] as? String ?? ""
        self.inviterProfilePhoto = branchParams["inviter_profile_photo"] as? String
        self.habitId = branchParams["habit_id"] as? String
    }
    
    /// Check if this is a valid invite
    var isValid: Bool {
        return !inviterId.isEmpty && !inviterName.isEmpty
    }
}

// MARK: - SwiftUI Identifiable Conformance
extension BranchInviteData: Identifiable {
    /// Use inviterId + (habitId ?? "") as a unique identifier so SwiftUI sheets can bind using `.item`.
    var id: String { "\(inviterId)-\(habitId ?? "none")" }
}

/// Branch service initialization states
enum BranchInitializationState: Equatable {
    case idle
    case initializing
    case ready
    case failed(Error)
    
    static func == (lhs: BranchInitializationState, rhs: BranchInitializationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.initializing, .initializing), (.ready, .ready):
            return true
        case (.failed, .failed):
            return true // Simplified for testing - could compare error messages if needed
        default:
            return false
        }
    }
}

/// Link generation states for better UX
enum LinkGenerationState: Equatable {
    case idle
    case generating
    case success(String)
    case failed(Error)
    
    static func == (lhs: LinkGenerationState, rhs: LinkGenerationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.generating, .generating):
            return true
        case (.success(let lhsString), .success(let rhsString)):
            return lhsString == rhsString
        case (.failed, .failed):
            return true // Simplified for testing - could compare error messages if needed
        default:
            return false
        }
    }
}

/// Enhanced invite link with metadata
struct InviteLink {
    let url: String
    let shortCode: String
    let createdAt: Date
    let inviterInfo: [String: Any]
    
    init(url: String, inviterInfo: [String: Any]) {
        self.url = url
        self.shortCode = String(url.suffix(8)) // Last 8 characters for display
        self.createdAt = Date()
        self.inviterInfo = inviterInfo
    }
}

/// Deep link processing results
struct DeepLinkResult {
    let type: DeepLinkType
    let inviteData: BranchInviteData?
    let rawParameters: [String: Any]
}

enum DeepLinkType {
    case invite
    case general
    case unknown
}

/// Branch service protocol for testability
protocol BranchServiceProtocol {
    var initializationState: BranchInitializationState { get }
    var linkGenerationState: LinkGenerationState { get }
    var pendingInviteData: BranchInviteData? { get }
    
    func initialize() async throws
    func generateInviteLink(for user: User) async throws -> InviteLink
    func processDeepLink(parameters: [AnyHashable: Any]) async -> DeepLinkResult?
    func handleScannedBranchLink(_ url: String) -> Bool
    func setUserIdentity(userId: String) async throws
    func clearUserIdentity() async
    func clearPendingInvite()
}

// MARK: - Modern BranchService Implementation

@Observable
final class BranchService: BranchServiceProtocol, @unchecked Sendable {
    static let shared = BranchService()
    
    // MARK: - Published State
    private(set) var initializationState: BranchInitializationState = .idle
    private(set) var linkGenerationState: LinkGenerationState = .idle
    private(set) var pendingInviteData: BranchInviteData?
    
    // MARK: - Private State
    private var currentUserId: String?
    private var initializationTask: Task<Void, Error>?
    private var linkCache: [String: InviteLink] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes
    
    // Thread-safe access to linkCache
    private let cacheQueue = DispatchQueue(label: "branchservice.cache.queue", qos: .utility)
    
    // MARK: - Persistence
    
    /// Storage key for persisting pending invite data between launches
    private let pendingInviteStorageKey = "BranchPendingInviteData"
    
    /// Persist the pending invite to UserDefaults so it can survive app restarts
    private func savePendingInviteToStorage(_ invite: BranchInviteData?) {
        guard let invite else {
            UserDefaults.standard.removeObject(forKey: pendingInviteStorageKey)
            return
        }
        do {
            let encoded = try JSONEncoder().encode(invite)
            UserDefaults.standard.set(encoded, forKey: pendingInviteStorageKey)
            print("💾 [BranchService] Saved pending invite to storage")
        } catch {
            print("❌ [BranchService] Failed to encode pending invite: \(error)")
        }
    }
    
    /// Load any previously saved pending invite from storage
    private func loadPendingInviteFromStorage() -> BranchInviteData? {
        guard let data = UserDefaults.standard.data(forKey: pendingInviteStorageKey) else { return nil }
        do {
            let invite = try JSONDecoder().decode(BranchInviteData.self, from: data)
            print("📤 [BranchService] Restored pending invite from storage: \(invite.inviterId)")
            return invite
        } catch {
            print("❌ [BranchService] Failed to decode stored invite: \(error)")
            return nil
        }
    }
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Call this early (e.g., from AppDelegate) to restore any persisted invite before UI renders
    func bootstrap() {
        if let savedInvite = loadPendingInviteFromStorage() {
            pendingInviteData = savedInvite
        }
    }
    
    // MARK: - Initialization
    
    func initialize() async throws {
        print("🚀 [BranchService] initialize() called")
        
        // Prevent multiple concurrent initializations
        if let existingTask = initializationTask {
            print("🔄 [BranchService] Waiting for existing initialization task")
            try await existingTask.value
            print("✅ [BranchService] Existing initialization task completed")
            return
        }
        
        // Create new initialization task
        let task = Task<Void, Error> {
            print("🎯 [BranchService] Starting new initialization task")
            await MainActor.run {
                self.initializationState = .initializing
                print("📊 [BranchService] State set to .initializing")
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Branch SDK initialization is handled by AppDelegate
                // We just need to verify it's ready
                print("🔍 [BranchService] Checking if Branch is ready")
                DispatchQueue.main.async {
                    let isUserIdentified = Branch.getInstance().isUserIdentified()
                    let isSessionReady = BranchService.shared.isBranchSessionReady()
                    
                    print("👤 [BranchService] User identified: \(isUserIdentified)")
                    print("📡 [BranchService] Session ready: \(isSessionReady)")
                    
                    if isUserIdentified || isSessionReady {
                        print("✅ [BranchService] Branch is ready")
                        continuation.resume()
                    } else {
                        print("⏳ [BranchService] Branch not ready, waiting 0.5s")
                        // Wait a brief moment for Branch to complete initialization
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let retryUserIdentified = Branch.getInstance().isUserIdentified()
                            let retrySessionReady = BranchService.shared.isBranchSessionReady()
                            
                            print("🔁 [BranchService] Retry - User identified: \(retryUserIdentified)")
                            print("🔁 [BranchService] Retry - Session ready: \(retrySessionReady)")
                            
                            if retrySessionReady {
                                print("✅ [BranchService] Branch ready after retry")
                                continuation.resume()
                            } else {
                                print("❌ [BranchService] Branch initialization failed after retry")
                                continuation.resume(throwing: BranchError.initializationFailed)
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.initializationState = .ready
                print("✅ [BranchService] Initialization completed successfully")
            }
        }
        
        self.initializationTask = task
        
        do {
            try await task.value
            print("🎉 [BranchService] Initialize() completed successfully")
        } catch {
            print("❌ [BranchService] Initialize() failed with error: \(error)")
            await MainActor.run {
                self.initializationState = .failed(error)
            }
            throw error
        }
    }
    
    private func isBranchSessionReady() -> Bool {
        // Check if Branch instance is available and has session data
        let latestParams = Branch.getInstance().getLatestReferringParams()
        let isReady = latestParams != nil
        print("🔍 [BranchService] isBranchSessionReady: \(isReady), params: \(latestParams ?? [:])")
        return isReady
    }
    
    // MARK: - User Identity Management
    
    func setUserIdentity(userId: String) async throws {
        print("👤 [BranchService] setUserIdentity() called for userId: \(userId)")
        
        guard case .ready = initializationState else {
            print("❌ [BranchService] Cannot set identity - Branch not initialized")
            throw BranchError.notInitialized
        }
        
        // Skip if already set to this user
        if currentUserId == userId && Branch.getInstance().isUserIdentified() {
            print("✅ [BranchService] User identity already set for \(userId)")
            return
        }
        
        print("🔄 [BranchService] Setting Branch identity for user: \(userId)")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Branch.getInstance().setIdentity(userId) { [weak self] (params, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ [BranchService] setIdentity failed: \(error)")
                        continuation.resume(throwing: error)
                    } else {
                        print("✅ [BranchService] setIdentity succeeded for \(userId)")
                        if let params = params {
                            print("📋 [BranchService] Identity params: \(params)")
                        }
                        self?.currentUserId = userId
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func clearUserIdentity() async {
        print("🧹 [BranchService] clearUserIdentity() called")
        currentUserId = nil
        Branch.getInstance().logout()
        print("✅ [BranchService] User identity cleared")
    }
    
    // MARK: - Link Generation
    
    func generateInviteLink(for user: User) async throws -> InviteLink {
        print("🔗 [BranchService] generateInviteLink() called for user: \(user.name) (ID: \(user.id))")
        
        guard case .ready = initializationState else {
            print("❌ [BranchService] Branch not initialized, current state: \(initializationState)")
            throw BranchError.notInitialized
        }
        
        await MainActor.run {
            self.linkGenerationState = .generating
            print("📊 [BranchService] Link generation state set to .generating")
        }
        
        do {
            // Check cache first
            let cacheKey = user.id
            let cachedLink = cacheQueue.sync { linkCache[cacheKey] }
            if let cachedLink = cachedLink,
               Date().timeIntervalSince(cachedLink.createdAt) < cacheExpiry {
                print("💾 [BranchService] Using cached link for user \(user.id)")
                await MainActor.run {
                    self.linkGenerationState = .success(cachedLink.url)
                }
                return cachedLink
            } else {
                print("🚫 [BranchService] No valid cached link found for user \(user.id)")
            }
            
            print("👤 [BranchService] Setting user identity for \(user.id)")
            // Set user identity first
            try await setUserIdentity(userId: user.id)
            
            print("🔧 [BranchService] Creating new Branch link")
            // Generate new link
            let inviteLink = try await createBranchLink(for: user)
            
            print("💾 [BranchService] Caching new link for user \(user.id)")
            // Cache the result
            let linkToCache = inviteLink
            cacheQueue.async { [weak self] in
                guard let self = self else { return }
                self.linkCache[cacheKey] = linkToCache
            }
            
            await MainActor.run {
                self.linkGenerationState = .success(inviteLink.url)
                print("✅ [BranchService] Link generation successful: \(inviteLink.url)")
            }
            
            return inviteLink
            
        } catch {
            print("❌ [BranchService] Link generation failed with error: \(error)")
            await MainActor.run {
                self.linkGenerationState = .failed(error)
            }
            throw error
        }
    }
    
    private func createBranchLink(for user: User) async throws -> InviteLink {
        print("🏗️ [BranchService] createBranchLink() for user: \(user.name)")
        
        // Use the best available photo URL, preferring cached versions
        let photoUrl = user.avatarUrl200 ?? user.profilePhotoUrl ?? ""
        
        let linkData: [String: Any] = [
            // Core invite data
            "inviter_id": user.id,
            "inviter_name": user.name,
            "inviter_phone": user.phoneNumber,
            "inviter_profile_photo": photoUrl,
            
            // Link behavior controls
            "$canonical_identifier": "invite/\(user.id)",
            "$fallback_url": "https://jointally.app.link/",
            "$desktop_url": "https://tallyapp.io",
            "$branch_link_domain": "jointally.app.link",
            
            // Social sharing metadata
            "$og_title": "\(user.name) invited you to join Tally!",
            "$og_description": "Join \(user.name) on Tally to build better habits together and stay accountable",
            "$og_image_url": photoUrl.isEmpty ? "https://tallyapp.io/assets/tally-logo-social.png" : photoUrl,
            
            // Deep link routing
            "$deeplink_path": "invite",
            "$ios_deeplink_path": "invite",
            
            // Attribution and analytics
            "utm_source": "app_invite",
            "utm_medium": "deep_link",
            "utm_campaign": "user_referral"
        ]
        
        print("📋 [BranchService] Link data prepared: \(linkData)")
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InviteLink, Error>) in
            print("📡 [BranchService] Calling Branch.getInstance().getShortURL()")
            
            Branch.getInstance().getShortURL(
                withParams: linkData,
                andTags: ["invite", "user_referral"],
                andChannel: "user_invite",
                andFeature: "friend_invite",
                andStage: "invite_share"
            ) { (url, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ [BranchService] Branch getShortURL failed: \(error)")
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        print("✅ [BranchService] Branch getShortURL succeeded: \(url)")
                        let inviteLink = InviteLink(url: url, inviterInfo: linkData)
                        continuation.resume(returning: inviteLink)
                    } else {
                        print("❌ [BranchService] Branch getShortURL returned no URL and no error")
                        continuation.resume(throwing: BranchError.linkGenerationFailed)
                    }
                }
            }
        }
    }
    
    // MARK: - Deep Link Processing
    
    func processDeepLink(parameters: [AnyHashable: Any]) async -> DeepLinkResult? {
        print("🔗 [BranchService] processDeepLink called with parameters: \(parameters)")
        
        // Convert AnyHashable keys to String keys
        var stringParams: [String: Any] = [:]
        for (key, value) in parameters {
            if let stringKey = key as? String {
                stringParams[stringKey] = value
                print("🔗 [BranchService] Parameter: \(stringKey) = \(value)")
            } else {
                print("⚠️ [BranchService] Non-string key found: \(key) = \(value)")
            }
        }
        
        print("🔗 [BranchService] Converted string params: \(stringParams)")
        
        // Check if this is an invite link
        if let inviterId = stringParams["inviter_id"] as? String, !inviterId.isEmpty {
            print("✅ [BranchService] Found invite link with inviter_id: \(inviterId)")
            
            let branchData = BranchInviteData(from: stringParams)
            print("🔗 [BranchService] Created BranchInviteData: isValid = \(branchData.isValid)")
            print("🔗 [BranchService] Inviter name: \(branchData.inviterName)")
            print("🔗 [BranchService] Inviter phone: \(branchData.inviterPhone)")
            print("🔗 [BranchService] Inviter profile photo: \(branchData.inviterProfilePhoto ?? "none")")
            
            guard branchData.isValid else {
                print("❌ [BranchService] Branch invite data is invalid")
                return DeepLinkResult(type: .unknown, inviteData: nil, rawParameters: stringParams)
            }
            
            print("📱 [BranchService] Storing pending invite data and posting notification")
            
            // Store pending invite data and post notification on MainActor
            await MainActor.run {
                self.pendingInviteData = branchData
                // Persist invite so it's not lost if the app restarts before user accepts
                self.savePendingInviteToStorage(branchData)
                print("✅ [BranchService] Pending invite data stored")
                
                // 🔧 FIX: Add a small delay to ensure everything is ready before posting notification
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("📬 [BranchService] About to post branchEnhancedInviteReceived notification")
                    NotificationCenter.default.post(
                        name: .branchEnhancedInviteReceived,
                        object: nil,
                        userInfo: [
                            "inviterId": branchData.inviterId,
                            "branchInviteData": branchData
                        ]
                    )
                    print("📬 [BranchService] Posted branchEnhancedInviteReceived notification (MainActor with delay)")
                }
            }
            
            return DeepLinkResult(type: .invite, inviteData: branchData, rawParameters: stringParams)
        } else {
            print("ℹ️ [BranchService] No inviter_id found or empty - not an invite link")
            print("ℹ️ [BranchService] Available parameters: \(stringParams.keys.joined(separator: ", "))")
        }
        
        print("🔗 [BranchService] Returning general deep link result")
        return DeepLinkResult(type: .general, inviteData: nil, rawParameters: stringParams)
    }
    
    // MARK: - Branch Link Resolution
    
    func handleScannedBranchLink(_ urlString: String) -> Bool {
        print("🔍 [BranchService] handleScannedBranchLink() called with URL: \(urlString)")
        
        guard case .ready = initializationState else {
            print("❌ [BranchService] Branch not initialized, current state: \(initializationState)")
            return false
        }
        
        guard let url = URL(string: urlString) else {
            print("❌ [BranchService] Invalid URL: \(urlString)")
            return false
        }
        
        // Use Branch's built-in URL handling to process the link
        // This will trigger the same flow as if the user clicked the link naturally
        let handled = Branch.getInstance().handleDeepLink(url)
        print("✅ [BranchService] Branch handleDeepLink returned: \(handled)")
        
        return handled
    }
    
    // MARK: - State Management
    
    func clearPendingInvite() {
        print("🧹 [BranchService] Clearing pending invite data")
        pendingInviteData = nil
        // Clear persisted invite
        savePendingInviteToStorage(nil)
    }
    
    // MARK: - Cache Management
    
    private func clearExpiredCache() {
        let now = Date()
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            self.linkCache = self.linkCache.filter { _, link in
                now.timeIntervalSince(link.createdAt) < self.cacheExpiry
            }
        }
    }
}

// MARK: - Error Types

enum BranchError: LocalizedError {
    case notInitialized
    case initializationFailed
    case linkGenerationFailed
    case invalidParameters
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Branch service is not initialized"
        case .initializationFailed:
            return "Failed to initialize Branch service"
        case .linkGenerationFailed:
            return "Failed to generate invite link"
        case .invalidParameters:
            return "Invalid parameters provided"
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let branchEnhancedInviteReceived = Notification.Name("branchEnhancedInviteReceived")
    static let branchInviteReceived = Notification.Name("branchInviteReceived") // Legacy compatibility
} 

