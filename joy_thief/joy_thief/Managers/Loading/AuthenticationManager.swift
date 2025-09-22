import Foundation
import SwiftUI
import os
import Kingfisher

// MARK: - Notification Extension
extension Notification.Name {
    static let authenticationStateChanged = Notification.Name("authenticationStateChanged")
}

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    @Published var verificationCodeSent = false
    @Published var isPreloading = false
    @Published var needsPreloading = false
    @Published var hasAccountDeletionRequest = false // <-- NEW
    
    private let userDefaults = UserDefaults.standard
    private let authKey = "authToken"
    private let onboardingStateKey = "cached_onboarding_state"
    private let userIdKey = "cached_user_id"
    private let onboardingCacheExistsKey = "onboarding_cache_exists"
    
    // Add debounce protection for onboarding state updates
    private var lastOnboardingStateUpdate: Date?
    private let onboardingStateUpdateDebounceInterval: TimeInterval = 1.0 // 1 second
    
    var storedAuthToken: String? {
            userDefaults.string(forKey: authKey)
        }
    
    // Get cached onboarding state for immediate use during startup
    var cachedOnboardingState: Int? {
        print("🎭 [AuthManager] cachedOnboardingState getter called")
        
        guard let cachedUserId = userDefaults.string(forKey: userIdKey) else {
            print("🎭 [AuthManager] No cached user ID found")
            return nil
        }
        print("🎭 [AuthManager] Found cached user ID: \(cachedUserId)")
        
        guard userDefaults.bool(forKey: onboardingCacheExistsKey) else {
            print("🎭 [AuthManager] No onboarding cache exists flag")
            return nil
        }
        print("🎭 [AuthManager] Cache exists flag is true")
        
        guard let currentUserId = currentUser?.id else {
            print("🎭 [AuthManager] No current user ID, returning cached state for user: \(cachedUserId)")
            let cached = userDefaults.integer(forKey: onboardingStateKey)
            print("🎭 [AuthManager] Returning cached value: \(cached)")
            return cached
        }
        print("🎭 [AuthManager] Current user ID: \(currentUserId)")
        
        guard cachedUserId == currentUserId else {
            print("🎭 [AuthManager] Cached user ID (\(cachedUserId)) doesn't match current user (\(currentUserId)) - clearing stale cache")
            // Clear stale cache if user ID doesn't match
            clearCachedOnboardingState()
            return nil
        }
        
        let cached = userDefaults.integer(forKey: onboardingStateKey)
        print("🎭 [AuthManager] Returning cached onboarding state: \(cached) for user: \(currentUserId)")
        return cached
    }
    
    // Get cached onboarding state during app startup before user data is loaded
    // This version only requires a valid auth token, not currentUser
    var startupCachedOnboardingState: Int? {
        print("🎭 [AuthManager] startupCachedOnboardingState getter called")
        
        guard storedAuthToken != nil else {
            print("🎭 [AuthManager] No auth token - no startup cached state")
            return nil
        }
        print("🎭 [AuthManager] Auth token exists")
        
        guard let cachedUserId = userDefaults.string(forKey: userIdKey) else {
            print("🎭 [AuthManager] No cached user ID for startup state")
            return nil
        }
        print("🎭 [AuthManager] Found cached user ID for startup: \(cachedUserId)")
        
        guard userDefaults.bool(forKey: onboardingCacheExistsKey) else {
            print("🎭 [AuthManager] No startup onboarding cache exists flag")
            return nil
        }
        print("🎭 [AuthManager] Startup cache exists flag is true")
        
        let cached = userDefaults.integer(forKey: onboardingStateKey)
        print("🎭 [AuthManager] Returning startup cached onboarding state: \(cached) for cached user: \(cachedUserId)")
        return cached
    }
    
    // Cache onboarding state locally for immediate access
    private func cacheOnboardingState(_ state: Int, for userId: String) {
        print("🎭 [AuthManager] Caching onboarding state \(state) for user \(userId)")
        userDefaults.set(state, forKey: onboardingStateKey)
        userDefaults.set(userId, forKey: userIdKey)
        userDefaults.set(true, forKey: onboardingCacheExistsKey)
    }
    
    // Clear cached onboarding state
    private func clearCachedOnboardingState() {
        userDefaults.removeObject(forKey: onboardingStateKey)
        userDefaults.removeObject(forKey: userIdKey)
        userDefaults.removeObject(forKey: onboardingCacheExistsKey)
    }
    
    // Secure token storage
    private let keychain = KeychainWrapper(service: "com.joythief.auth")
    
    // Unified logger (prints are kept for now to minimise churn)
    private let logger = Logger(subsystem: "com.joythief", category: "auth")
    
    private init() {}
    
    nonisolated func requestVerificationCode(phoneNumber: String) async throws {
        let url = URL(string: "\(AppConfig.baseURL)/auth/send-verification")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct VerificationBody: Encodable { let phone_number: String }
        request.httpBody = try JSONEncoder().encode(VerificationBody(phone_number: phoneNumber))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        if httpResponse.statusCode == 200 {
            await MainActor.run { self.verificationCodeSent = true }
        } else {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse?.detail ?? "Failed to send code")
        }
    }
    
    /// Verifies the SMS code during sign-up (before collecting photos).
    /// Throws if the code is invalid or network errors occur.
    nonisolated func verifySignupCode(phoneNumber: String, verificationCode: String) async throws {
        let url = URL(string: "\(AppConfig.baseURL)/auth/verify-code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct VerifyBody: Encodable { let phone_number: String; let verification_code: String }
        request.httpBody = try JSONEncoder().encode(VerifyBody(phone_number: phoneNumber, verification_code: verificationCode))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.networkError }

        guard httpResponse.statusCode == 200 else {
            let err = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(err?.detail ?? "Invalid verification code")
        }
    }
    
    nonisolated func signUp(phoneNumber: String,
                            verificationCode: String,
                            name: String,
                            verificationImage: UIImage,
                            profileImage: UIImage? = nil) async throws {
        let url = URL(string: "\(AppConfig.baseURL)/auth/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Get timezone information
        let timeZone = TimeZone.current.identifier
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add form fields
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"phone_number\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(phoneNumber)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"verification_code\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(verificationCode)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timezone\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(timeZone)\r\n".data(using: .utf8)!)
        
        // Add mandatory verification photo
        if let verificationData = verificationImage.jpegData(compressionQuality: 0.8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"verification_photo\"; filename=\"verification.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(verificationData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        if httpResponse.statusCode == 200 {
            let signupResponse = try JSONDecoder().decode(SignupResponse.self, from: data)
            print("🎭 [AuthManager] Signup response received - onboarding state: \(signupResponse.onboardingState)")
            
            // Commit auth first to establish user session
            await commitAuth(token: signupResponse.accessToken, user: User(
                id: signupResponse.id, 
                phoneNumber: signupResponse.phoneNumber, 
                name: signupResponse.name, 
                createdAt: signupResponse.createdAt, 
                updatedAt: signupResponse.updatedAt, 
                timezone: timeZone, 
                profilePhotoUrl: signupResponse.profilePhotoUrl,
                avatarVersion: signupResponse.avatarVersion,
                avatarUrl80: signupResponse.avatarUrl80,
                avatarUrl200: signupResponse.avatarUrl200,
                avatarUrlOriginal: signupResponse.avatarUrlOriginal,
                onboardingState: signupResponse.onboardingState, 
                isPremium: signupResponse.isPremium
            ))
            
            // If user provided a profile image, upload it using the avatar system
            if let profileImage = profileImage {
                do {
                    print("🎭 [AuthManager] Uploading profile image using avatar system")
                    _ = try await AvatarManager().uploadAvatar(image: profileImage, token: signupResponse.accessToken)
                    print("✅ [AuthManager] Avatar uploaded successfully during onboarding")
                    
                    // Avatar upload already updates the auth state with new URLs
                    // No need to update again here
                } catch {
                    print("⚠️ [AuthManager] Avatar upload failed during onboarding: \(error)")
                    // Don't fail the entire signup if avatar upload fails
                }
            }
            
            print("✅ [AuthManager] Signup completed successfully")
            
            // ADDED: Request notification permission after successful signup
            Task {
                // Small delay to ensure auth state is fully set
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await NotificationManager.shared.requestPermissionIfAuthenticated()
            }
        } else {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse?.detail ?? "Signup failed")
        }
    }
    
    nonisolated func login(phoneNumber: String, verificationCode: String) async throws {
        print("🔐 [AuthManager] Starting login process for phone: \(phoneNumber)")
        
        let url = URL(string: "\(AppConfig.baseURL)/auth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get timezone information
        let timeZone = TimeZone.current.identifier
        
        let body = [
            "phone_number": phoneNumber,
            "verification_code": verificationCode,
            "timezone": timeZone
        ]
        
        print("🔐 [AuthManager] Login request body: \(body)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AuthManager] Failed to get HTTP response during login")
            throw AuthError.networkError
        }
        
        print("🔐 [AuthManager] Login response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            print("✅ [AuthManager] Login response received successfully")
            
            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            print("🔐 [AuthManager] Login response decoded successfully")
            print("🔐 [AuthManager] Received token: \(loginResponse.accessToken.prefix(20))...")
            print("🔐 [AuthManager] User ID: \(loginResponse.user.id)")
            
            await commitAuth(token: loginResponse.accessToken, user: loginResponse.user)
            // commitAuth already updated actor-isolated state
            print("✅ [AuthManager] Authentication state updated successfully")

            // Avatar loading is now handled centrally during startup with high priority
            print("✅ [AuthManager] Login completed - avatar loading will be handled during startup")
            
            // ADDED: Request notification permission after successful login
            Task {
                // Small delay to ensure auth state is fully set
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await NotificationManager.shared.requestPermissionIfAuthenticated()
            }
        } else {
            print("❌ [AuthManager] Login failed with status: \(httpResponse.statusCode)")
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ [AuthManager] Error response: \(responseData)")
            }
            
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse.detail)
        }
    }
    
    /// Checks if a user exists for the given phone number. Throws if not found, returns if found.
    nonisolated func checkUserExists(phoneNumber: String) async throws -> Bool {
        let url = URL(string: "\(AppConfig.baseURL)/users/check-phone")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct CheckUserBody: Encodable { let phone_number: String }
        request.httpBody = try JSONEncoder().encode(CheckUserBody(phone_number: phoneNumber))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError
        }
        struct CheckUserResponse: Decodable { let exists: Bool }
        let result = try JSONDecoder().decode(CheckUserResponse.self, from: data)
        return result.exists
    }
    
    nonisolated func checkNameAvailability(name: String) async throws -> Bool {
        let url = URL(string: "\(AppConfig.baseURL)/users/check-name")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct CheckNameBody: Encodable { let name: String }
        request.httpBody = try JSONEncoder().encode(CheckNameBody(name: name))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError
        }
        struct CheckNameResponse: Decodable { let available: Bool }
        let result = try JSONDecoder().decode(CheckNameResponse.self, from: data)
        return result.available
    }
    
    func updateUserProfilePhoto(photoUrl: String?) {
        guard let currentUser = currentUser else { return }
        
        let updatedUser = User(
            id: currentUser.id,
            phoneNumber: currentUser.phoneNumber,
            name: currentUser.name,
            createdAt: currentUser.createdAt,
            updatedAt: currentUser.updatedAt,
            timezone: currentUser.timezone,
            profilePhotoUrl: photoUrl,
            avatarVersion: currentUser.avatarVersion,
            avatarUrl80: currentUser.avatarUrl80,
            avatarUrl200: currentUser.avatarUrl200,
            avatarUrlOriginal: currentUser.avatarUrlOriginal,
            onboardingState: currentUser.onboardingState,
            isPremium: currentUser.isPremium
        )
        
        self.currentUser = updatedUser
    }
    
    func updateUserAvatar(avatarVersion: Int?, avatarUrl80: String?, avatarUrl200: String?, avatarUrlOriginal: String?, profilePhotoUrl: String? = nil) {
        guard let currentUser = currentUser else { return }
        
        print("AuthManager: Updating user avatar URLs:")
        print("  - avatarVersion: \(avatarVersion ?? -1)")
        print("  - avatarUrl80: \(avatarUrl80 ?? "nil")")
        print("  - avatarUrl200: \(avatarUrl200 ?? "nil")")
        print("  - avatarUrlOriginal: \(avatarUrlOriginal ?? "nil")")
        print("  - profilePhotoUrl: \(profilePhotoUrl ?? "keeping current")")
        
        // If profilePhotoUrl is not provided, keep the current one; if explicitly set to nil, clear it
        let finalProfilePhotoUrl = (profilePhotoUrl == nil && avatarVersion != nil) ? currentUser.profilePhotoUrl : profilePhotoUrl
        
        let updatedUser = User(
            id: currentUser.id,
            phoneNumber: currentUser.phoneNumber,
            name: currentUser.name,
            createdAt: currentUser.createdAt,
            updatedAt: currentUser.updatedAt,
            timezone: currentUser.timezone,
            profilePhotoUrl: finalProfilePhotoUrl,
            avatarVersion: avatarVersion,
            avatarUrl80: avatarUrl80,
            avatarUrl200: avatarUrl200,
            avatarUrlOriginal: avatarUrlOriginal,
            onboardingState: currentUser.onboardingState,
            isPremium: currentUser.isPremium
        )
        
        self.currentUser = updatedUser
        print("AuthManager: Updated currentUser with new avatar URLs")
        
        // Update the cache with the new avatar URLs
        let userProfileData = PreloadManager.UserProfileData(
            id: updatedUser.id,
            name: updatedUser.name,
            phoneNumber: updatedUser.phoneNumber,
            onboardingState: updatedUser.onboardingState,
            profilePhotoUrl: updatedUser.profilePhotoUrl,
            avatarVersion: updatedUser.avatarVersion,
            avatarUrl80: updatedUser.avatarUrl80,
            avatarUrl200: updatedUser.avatarUrl200,
            avatarUrlOriginal: updatedUser.avatarUrlOriginal
        )
        DataCacheManager.shared.updateUserProfileInCache(userProfileData)

        // Let FeedManager refresh avatars on any existing feed posts authored by this user
        Task { @MainActor in
            FeedManager.shared.updateCurrentUserAvatar(
                avatarVersion: avatarVersion,
                avatarUrl80: avatarUrl80,
                avatarUrl200: avatarUrl200,
                avatarUrlOriginal: avatarUrlOriginal
            )
        }

        // First, try to prime cache from existing stored images synchronously.
        Task { let _ = await self.primeAvatarCache(for: updatedUser) }

        // Then kick off a network fetch as a fallback if nothing found.
        if let urlString = updatedUser.avatarUrl80 ?? updatedUser.avatarUrl200 ?? updatedUser.avatarUrlOriginal,
           AvatarImageStore.shared.image(for: urlString) == nil,
           let url = URL(string: urlString) {
            Task.detached(priority: .utility) {
                let options: KingfisherOptionsInfo = [.cacheOriginalImage, .downloadPriority(0.2)]
                if let img = try? await KingfisherManager.shared.retrieveImage(with: url, options: options).image {
                    await self.cacheAvatarBitmap(img, for: updatedUser)
                }
            }
        }
    }
    
    /// Fetch fresh avatar data from the server (in case it was uploaded elsewhere)
    func refreshAvatarData() async {
        guard let token = keychain.string(forKey: authKey) else { return }
        
        do {
            let avatarManager = AvatarManager()
            if let avatarResponse = try await avatarManager.getAvatar(token: token) {
                await MainActor.run {
                    updateUserAvatar(
                        avatarVersion: nil, // Not returned by getAvatar
                        avatarUrl80: avatarResponse.avatarUrl80,
                        avatarUrl200: avatarResponse.avatarUrl200,
                        avatarUrlOriginal: avatarResponse.avatarUrlOriginal
                    )
                }
                print("AuthManager: Refreshed avatar data from server")
            }
        } catch {
            print("AuthManager: Failed to refresh avatar data: \(error)")
        }
    }
    
    private func fetchCurrentUser(token: String) async throws {
        print("🔐 [AuthManager] Validating token: \(token.prefix(20))...")
        
        let url = URL(string: "\(AppConfig.baseURL)/auth/me")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("🔐 [AuthManager] Making /auth/me request...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AuthManager] Failed to get HTTP response from /auth/me")
            throw AuthError.networkError
        }
        
        print("🔐 [AuthManager] /auth/me response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            print("✅ [AuthManager] Token validation successful")
            let user = try JSONDecoder().decode(User.self, from: data)
            print("🎭 [AuthManager] Token validation - user onboarding state: \(user.onboardingState)")
            await MainActor.run {
                self.currentUser = user
                self.errorMessage = nil
                // Set authenticated immediately - splash screen will handle preloading
                self.isAuthenticated = true
            }
            // Set Branch user identity
            Task {
                try? await BranchService.shared.setUserIdentity(userId: user.id)
            }
            // Ensure timezone is set in backend
            await updateUserTimezoneIfNeeded()
            
            // ADDED: Request notification permission after successful token validation
            Task {
                // Small delay to ensure auth state is fully set
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await NotificationManager.shared.requestPermissionIfAuthenticated()
            }
            
            // ADDED: Proactively fetch avatar data if missing from user response
            if user.avatarUrl200 == nil {
                Task(priority: .userInitiated) {
                    await refreshAvatarData()
                }
            }

            // Avatar loading is now handled with high priority immediately after authentication
            // in SplashScreenView, so we no longer need these lower-priority fallback tasks
            print("✅ [AuthManager] Authentication validated - avatar loading will be handled by SplashScreenView")
        } else if httpResponse.statusCode == 401 {
            print("❌ [AuthManager] Token validation failed - 401 Unauthorized")
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ [AuthManager] 401 Response: \(responseData)")
            }
            await MainActor.run {
                Task {
                    await self.logout()
                }
                self.errorMessage = "Session expired. Please log in again."
            }
            throw AuthError.sessionExpired
        } else {
            print("❌ [AuthManager] Token validation failed with status: \(httpResponse.statusCode)")
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ [AuthManager] Error response: \(responseData)")
            }
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse.detail)
        }
    }
    
    @MainActor func logout() async {
        // Get the current auth token before clearing it
        guard let currentToken = keychain.string(forKey: authKey) else {
            print("⚠️ [AuthManager] No auth token found for logout")
            await performLocalLogout()
            return
        }
        
        // Clear the token locally FIRST to prevent cleanup operations from using it
        keychain.remove(authKey)
        
        // Fire and forget backend logout so UI is never blocked
        Task.detached { await self.performBackendLogout(token: currentToken) }
        
        // Then perform remaining local cleanup
        await performLocalLogout()
    }
    
    private func performBackendLogout(token: String) async {
        guard let url = URL(string: "\(AppConfig.baseURL)/auth/logout") else {
            print("❌ [AuthManager] Invalid logout URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ [AuthManager] Backend logout successful")
                } else {
                    print("❌ [AuthManager] Backend logout failed: HTTP \(httpResponse.statusCode)")
                    if let responseData = String(data: data, encoding: .utf8) {
                        print("❌ [AuthManager] Response: \(responseData)")
                    }
                }
            }
        } catch {
            print("❌ [AuthManager] Error during backend logout: \(error)")
        }
    }
    
    private func performLocalLogout() async {
        // Token already cleared before backend call
        isAuthenticated     = false
        currentUser         = nil
        verificationCodeSent = false
        needsPreloading     = false

        // Remove persisted token from UserDefaults as well
        userDefaults.removeObject(forKey: authKey)
        
        // Clear cached onboarding state
        clearCachedOnboardingState()

        // Post authentication state change notification
        NotificationCenter.default.post(name: .authenticationStateChanged, object: nil)

        // Tear down background work
        DataCacheManager.shared.stopBackgroundSync()
        DataCacheManager.shared.clearCache()

        // Clear in-memory data on all managers so next login starts fresh
        HabitManager.shared.resetForLogout()

        await NotificationManager.shared.resetOnLogout()
        Task {
            await BranchService.shared.clearUserIdentity()
        }
    }

    // MARK: - Private helpers
    @MainActor
    private func commitAuth(token: String, user: User) {
        print("🔐 [AuthManager] Committing auth for user: \(user.id), onboarding state: \(user.onboardingState)")
        print("🔐 [AuthManager] Committing auth at timestamp: \(Date())")
        keychain.set(token, forKey: authKey)
        // Persist token in UserDefaults as a fallback for legacy components that still expect it
        userDefaults.set(token, forKey: authKey)

        DataCacheManager.shared.stopBackgroundSync()
        DataCacheManager.shared.markCacheAsStale()

        currentUser       = user
        isAuthenticated   = true
        needsPreloading   = true
        errorMessage      = nil
        
        // Cache onboarding state locally for immediate access on next app startup
        cacheOnboardingState(user.onboardingState, for: user.id)
        
        // Post authentication state change notification
        NotificationCenter.default.post(name: .authenticationStateChanged, object: nil)
        
        Task {
            try? await BranchService.shared.setUserIdentity(userId: user.id)
        }

        // Avatar loading is now handled centrally during startup with high priority
        // No need for redundant low-priority tasks here
        print("🔐 [AuthManager] Auth committed - avatar loading will be handled during startup")
    }

    func validateToken(_ token: String) async throws {
        try await fetchCurrentUser(token: token)
    }
    
    func updateUserTimezoneIfNeeded() async {
        guard let userId = currentUser?.id else { return }
        let timeZone = TimeZone.current.identifier
        
        // Check if timezone actually needs updating
        if currentUser?.timezone == timeZone {
            return
        }
        
        // Store current avatar data to preserve it
        let currentProfilePhotoUrl = currentUser?.profilePhotoUrl
        let currentAvatarVersion = currentUser?.avatarVersion
        let currentAvatarUrl80 = currentUser?.avatarUrl80
        let currentAvatarUrl200 = currentUser?.avatarUrl200
        let currentAvatarUrlOriginal = currentUser?.avatarUrlOriginal
        
        // Create URL with timezone as a query parameter
        var components = URLComponents(string: "\(AppConfig.baseURL)/users/\(userId)/timezone")!
        components.queryItems = [URLQueryItem(name: "timezone", value: timeZone)]
        
        guard let url = components.url else {
            print("Failed to create URL with query parameters")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(keychain.string(forKey: authKey) ?? "")", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Failed to get HTTP response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                print("Timezone update failed with status code: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }
                return
            }
            
            let updatedUser = try? JSONDecoder().decode(User.self, from: data)
            await MainActor.run {
                if let updatedUser = updatedUser {
                    // If avatar data is nil in the response but we had it before, preserve it
                    let finalProfilePhotoUrl = updatedUser.profilePhotoUrl ?? currentProfilePhotoUrl
                    let finalAvatarVersion = updatedUser.avatarVersion ?? currentAvatarVersion
                    let finalAvatarUrl80 = updatedUser.avatarUrl80 ?? currentAvatarUrl80
                    let finalAvatarUrl200 = updatedUser.avatarUrl200 ?? currentAvatarUrl200
                    let finalAvatarUrlOriginal = updatedUser.avatarUrlOriginal ?? currentAvatarUrlOriginal
                    
                    let preservedUser = User(
                        id: updatedUser.id,
                        phoneNumber: updatedUser.phoneNumber,
                        name: updatedUser.name,
                        createdAt: updatedUser.createdAt,
                        updatedAt: updatedUser.updatedAt,
                        timezone: updatedUser.timezone,
                        profilePhotoUrl: finalProfilePhotoUrl,
                        avatarVersion: finalAvatarVersion,
                        avatarUrl80: finalAvatarUrl80,
                        avatarUrl200: finalAvatarUrl200,
                        avatarUrlOriginal: finalAvatarUrlOriginal,
                        onboardingState: updatedUser.onboardingState,
                        isPremium: updatedUser.isPremium
                    )
                    self.currentUser = preservedUser
                }
            }
        } catch {
            print("Failed to update timezone: \(error)")
        }
    }

    // MARK: – Onboarding state

    /// Marks onboarding as completed for the current user (sets onboarding_state = 1).
    @MainActor
    func markOnboardingCompleted() async {
        guard let user = currentUser else { return }
        // If already marked, skip
        if user.onboardingState != 0 { return }

        guard let url = URL(string: "\(AppConfig.baseURL)/users/\(user.id)/onboarding-state/1") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = keychain.string(forKey: authKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // No body needed; state passed via path param
        request.httpBody = nil

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Parse updated user or just update state locally
                if let updated = try? JSONDecoder().decode(User.self, from: data) {
                    currentUser = updated
                } else {
                    // Fallback: manually update currentUser
                    currentUser = User(id: user.id,
                                       phoneNumber: user.phoneNumber,
                                       name: user.name,
                                       createdAt: user.createdAt,
                                       updatedAt: user.updatedAt,
                                       timezone: user.timezone,
                                       profilePhotoUrl: user.profilePhotoUrl,
                                       avatarVersion: user.avatarVersion,
                                       avatarUrl80: user.avatarUrl80,
                                       avatarUrl200: user.avatarUrl200,
                                       avatarUrlOriginal: user.avatarUrlOriginal,
                                       onboardingState: 1,
                                       isPremium: user.isPremium)
                }
            } else {
                print("Failed to mark onboarding complete, status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            print("Failed to mark onboarding complete: \(error)")
        }
    }

    /// Updates the user's onboarding_state to the provided value.
    /// Use this to track granular onboarding progress (0=ToS, 1=Intro, 2=Payment, 3+=Done).
    @MainActor
    func updateOnboardingState(to newState: Int) async {
        guard let user = currentUser else { 
            print("🎭 [AuthManager] Cannot update onboarding state - no current user")
            return 
        }

        // Avoid unnecessary network if already at or beyond requested state
        if user.onboardingState >= newState { 
            print("🎭 [AuthManager] Skipping onboarding state update - current: \(user.onboardingState), requested: \(newState)")
            return 
        }

        // Debounce protection: prevent rapid duplicate updates
        let now = Date()
        if let lastUpdate = lastOnboardingStateUpdate,
           now.timeIntervalSince(lastUpdate) < onboardingStateUpdateDebounceInterval {
            print("🎭 [AuthManager] Debouncing onboarding state update - too soon after last update")
            return
        }
        lastOnboardingStateUpdate = now

        print("🎭 [AuthManager] Updating onboarding state from \(user.onboardingState) to \(newState)")
        print("🎭 [AuthManager] Update onboarding state at timestamp: \(Date())")
        
        guard let url = URL(string: "\(AppConfig.baseURL)/users/\(user.id)/onboarding-state/\(newState)") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = keychain.string(forKey: authKey) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let updated = try? JSONDecoder().decode(User.self, from: data) {
                    currentUser = updated
                    // Cache the updated onboarding state
                    cacheOnboardingState(updated.onboardingState, for: updated.id)
                    print("🎭 [AuthManager] Successfully updated onboarding state to \(updated.onboardingState)")
                    print("🎭 [AuthManager] Onboarding state update completed at timestamp: \(Date())")
                } else {
                    // Fallback: manually mutate onboardingState locally
                    currentUser = User(id: user.id,
                                       phoneNumber: user.phoneNumber,
                                       name: user.name,
                                       createdAt: user.createdAt,
                                       updatedAt: user.updatedAt,
                                       timezone: user.timezone,
                                       profilePhotoUrl: user.profilePhotoUrl,
                                       avatarVersion: user.avatarVersion,
                                       avatarUrl80: user.avatarUrl80,
                                       avatarUrl200: user.avatarUrl200,
                                       avatarUrlOriginal: user.avatarUrlOriginal,
                                       onboardingState: newState,
                                       isPremium: user.isPremium)
                    // Cache the updated onboarding state
                    cacheOnboardingState(newState, for: user.id)
                    print("🎭 [AuthManager] Updated onboarding state locally to \(newState)")
                    print("🎭 [AuthManager] Local onboarding state update completed at timestamp: \(Date())")
                }
            } else {
                print("❌ [AuthManager] Failed to update onboarding state - HTTP ")
                if let responseData = String(data: data, encoding: .utf8) {
                    print("❌ [AuthManager] Response: \(responseData)")
                }
            }
        } catch {
            print("❌ [AuthManager] Error updating onboarding state: \(error)")
        }
    }

    /// Caches a downloaded avatar bitmap under every relevant URL key so views that
    /// reference any size/variant instantly find the image.
    private func cacheAvatarBitmap(_ bitmap: UIImage, for user: User) async {
        let urls = [user.avatarUrl80, user.avatarUrl200, user.avatarUrlOriginal, user.profilePhotoUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        await MainActor.run {
            for key in urls {
                AvatarImageStore.shared.set(bitmap, for: key)
            }
        }
    }

    /// Quickly seed `AvatarImageStore` from any image already cached in memory/disk for
    /// one of the user's avatar URLs.  Returns `true` if something was found.
    private func primeAvatarCache(for user: User) async -> Bool {
        let urls = [user.avatarUrl80, user.avatarUrl200, user.avatarUrlOriginal, user.profilePhotoUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard !urls.isEmpty else { return false }

        // If *any* of the variants is already in the shared store, propagate to the rest.
        for url in urls {
            if let img = AvatarImageStore.shared.image(for: url) {
                await cacheAvatarBitmap(img, for: user)
                return true
            }
        }

        // Try Kingfisher memory cache.
        for url in urls {
            if let img = ImageCache.default.retrieveImageInMemoryCache(forKey: url) {
                await cacheAvatarBitmap(img, for: user)
                return true
            }
        }

        // Try disk cache (async); stop at first hit.
        for url in urls {
            if let disk = try? await ImageCache.default.retrieveImageInDiskCache(forKey: url) {
                // Promote to mem
                _ = try? await ImageCache.default.store(disk, forKey: url)
                await cacheAvatarBitmap(disk, for: user)
                return true
            }
        }
        return false
    }

    /// Ensures that the current user's avatar bitmap is present in `AvatarImageStore`.
    /// This suspends until the image is cached (either via prime-from-cache or network download),
    /// returning `true` on success.
    func ensureAvatarReady() async -> Bool {
        guard let user = currentUser else { 
            print("⚠️ [AuthManager] ensureAvatarReady: No current user available")
            return false 
        }

        // Fast path – check if already in AvatarImageStore first
        let urls = [user.avatarUrl80, user.avatarUrl200, user.avatarUrlOriginal, user.profilePhotoUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        for url in urls {
            if AvatarImageStore.shared.image(for: url) != nil {
                print("✅ [AuthManager] Avatar already in AvatarImageStore for: \(url)")
                return true
            }
        }

        // Try to prime from existing caches
        if await primeAvatarCache(for: user) { 
            print("✅ [AuthManager] Avatar primed from existing cache")
            return true 
        }

        // Otherwise download the smallest available avatar and cache it synchronously.
        guard let urlString = user.avatarUrl80 ?? user.avatarUrl200 ?? user.avatarUrlOriginal ?? user.profilePhotoUrl,
              let url = URL(string: urlString) else { 
            print("⚠️ [AuthManager] No avatar URLs available for current user")
            return false 
        }

        do {
            print("🔄 [AuthManager] Downloading avatar for current user with HIGH PRIORITY: \(urlString)")
            let options: KingfisherOptionsInfo = [
                .cacheOriginalImage, 
                .downloadPriority(1.0), // HIGHEST priority for startup avatar loading
                .backgroundDecode,
                .loadDiskFileSynchronously
            ]
            let img = try await KingfisherManager.shared.retrieveImage(with: url, options: options).image
            await cacheAvatarBitmap(img, for: user)
            print("✅ [AuthManager] Successfully downloaded and cached current user avatar on startup")
            return true
        } catch {
            print("⚠️ [AuthManager] ensureAvatarReady failed to download avatar: \(error)")
            return false
        }
    }
}

struct User: Codable, Equatable {
    let id: String
    let phoneNumber: String
    let name: String
    let createdAt: String?
    let updatedAt: String?
    let timezone: String?
    let profilePhotoUrl: String?
    // Cached avatar system fields
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let onboardingState: Int
    let isPremium: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case timezone
        case profilePhotoUrl = "profile_photo_url"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
        case onboardingState = "onboarding_state"
        case isPremium = "ispremium"
    }
    
    init(id: String, phoneNumber: String, name: String, createdAt: String?, updatedAt: String?, timezone: String?, profilePhotoUrl: String? = nil, avatarVersion: Int? = nil, avatarUrl80: String? = nil, avatarUrl200: String? = nil, avatarUrlOriginal: String? = nil, onboardingState: Int = 0, isPremium: Bool = false) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.timezone = timezone
        self.profilePhotoUrl = profilePhotoUrl
        self.avatarVersion = avatarVersion
        self.avatarUrl80 = avatarUrl80
        self.avatarUrl200 = avatarUrl200
        self.avatarUrlOriginal = avatarUrlOriginal
        self.onboardingState = onboardingState
        self.isPremium = isPremium
    }
}

extension AuthenticationManager {

    /// Removes the copy of the auth token we keep in UserDefaults.
    @MainActor            // ← still lives on the main actor
    func clearPersistedToken() {
        userDefaults.removeObject(forKey: authKey)
    }

    /// Checks if the user has a pending account deletion request
    @MainActor
    func refreshAccountDeletionRequestStatus() async {
        print("[DEBUG] Starting deletion status check")
        guard let token = storedAuthToken else {
            print("[DEBUG] No auth token found!")
            return
        }
        print("[DEBUG] Token found: \(token.prefix(10))...")
        
        do {
            let url = URL(string: "\(AppConfig.baseURL)/users/account/has-account-deletion-request")!
            print("[DEBUG] Making request to: \(url)")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("[DEBUG] Response status: \(httpResponse.statusCode)")
                if let responseData = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Response data: \(responseData)")
                }
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try? JSONDecoder().decode([String: Bool].self, from: data) {
                    await MainActor.run {
                        self.hasAccountDeletionRequest = result["has_request"] ?? false
                    }
                }
            }
        } catch {
            print("[DEBUG] Error: \(error)")
        }
    }

    /// Cancels the user's account deletion request
    @MainActor
    func cancelAccountDeletion() async {
        print("[DEBUG] Starting account deletion cancellation")
        guard let token = storedAuthToken else {
            print("[DEBUG] No auth token available")
            return
        }
        
        do {
            let url = URL(string: "\(AppConfig.baseURL)/users/cancel-account-deletion")!
            print("[DEBUG] Sending cancellation request to: \(url)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[DEBUG] Cancellation response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("[DEBUG] Cancellation successful, updating state")
                    self.hasAccountDeletionRequest = false
                } else {
                    print("[DEBUG] Cancellation failed with status: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("[DEBUG] Error response: \(responseString)")
                    }
                }
            }
        } catch {
            print("[DEBUG] Error cancelling account deletion: \(error)")
        }
    }

    /// Sends a message to notify the team that a user wants to delete their account.
    @MainActor
    func deleteAccount() async {
        guard currentUser != nil, let token = storedAuthToken else {
            print("[AuthManager] No current user or token for delete account request.")
            return
        }
        do {
            let url = URL(string: "\(AppConfig.baseURL)/users/request-account-deletion")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("[AuthManager] Account deletion request response: \(httpResponse.statusCode)")
            }
            if let json = try? JSONSerialization.jsonObject(with: data) {
                print("[AuthManager] Account deletion request response body: \(json)")
            }
            await refreshAccountDeletionRequestStatus() // <-- NEW: refresh status after request
        } catch {
            print("[AuthManager] Failed to send account deletion request: \(error)")
        }
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

struct SignupResponse: Codable {
    let id: String
    let phoneNumber: String
    let name: String
    let accessToken: String
    let tokenType: String
    let createdAt: String?
    let updatedAt: String?
    let profilePhotoUrl: String?
    let avatarVersion: Int?
    let avatarUrl80: String?
    let avatarUrl200: String?
    let avatarUrlOriginal: String?
    let onboardingState: Int
    let isPremium: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case phoneNumber = "phone_number"
        case name
        case accessToken = "access_token"
        case tokenType = "token_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profilePhotoUrl = "profile_photo_url"
        case avatarVersion = "avatar_version"
        case avatarUrl80 = "avatar_url_80"
        case avatarUrl200 = "avatar_url_200"
        case avatarUrlOriginal = "avatar_url_original"
        case onboardingState = "onboarding_state"
        case isPremium = "ispremium"
    }
}

struct LoginResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

enum AuthError: Error {
    case networkError
    case invalidCredentials
    case serverError(String)
    case sessionExpired
} 
