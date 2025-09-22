import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var permissionGranted = false
    @Published var deviceToken: String?
    // Holds the target post ID from a comment notification. Cleared once the UI finishes scrolling.
    @Published var navigateToPostId: String?
    
    // ENHANCED: Track registration state to prevent duplicate calls
    private var hasRequestedPermission = false
    private var isRegisteringToken = false
    private var lastTokenRegistrationTime: Date?
    
    private override init() {
        super.init()
        
        // 👉 Register as the UNUserNotificationCenter delegate so we receive foreground / tap callbacks
        UNUserNotificationCenter.current().delegate = self
        
        // Check current permission status
        checkCurrentPermissionStatus()
    }
    
    // NEW: Check and request permissions automatically
    private func checkCurrentPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self?.permissionGranted = true
                    // If we have permission but no token, register for remote notifications
                    if self?.deviceToken == nil {
                        await self?.registerForRemoteNotifications()
                    }
                case .notDetermined:
                    // Don't auto-request here - wait for explicit call
                    self?.permissionGranted = false
                    print("🔔 [NotificationManager] Notification permission not determined")
                case .denied:
                    self?.permissionGranted = false
                    print("🔔 [NotificationManager] Notification permission denied")
                case .ephemeral:
                    self?.permissionGranted = false
                @unknown default:
                    break
                }
            }
        }
    }
    
    // FIXED: Auto-request permission when user becomes authenticated
    func requestPermissionIfAuthenticated() async {
        print("🔔 [NotificationManager] requestPermissionIfAuthenticated called")
        print("🔔 [NotificationManager] Current auth state: \(AuthenticationManager.shared.isAuthenticated)")
        print("🔔 [NotificationManager] Has requested permission: \(hasRequestedPermission)")
        
        // Check if user is authenticated
        guard AuthenticationManager.shared.isAuthenticated else {
            print("🔔 [NotificationManager] User not authenticated, skipping permission request")
            return
        }
        
        // Check current permission status first
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            print("🔔 [NotificationManager] Permission already granted")
            self.permissionGranted = true
            await registerForRemoteNotifications()
            return
        case .denied:
            print("🔔 [NotificationManager] Permission previously denied")
            self.permissionGranted = false
            return
        case .notDetermined:
            print("🔔 [NotificationManager] Permission not determined, requesting...")
            break
        case .ephemeral:
            print("🔔 [NotificationManager] Ephemeral permission granted")
            self.permissionGranted = true
            await registerForRemoteNotifications()
            return
        @unknown default:
            print("🔔 [NotificationManager] Unknown permission status")
            self.permissionGranted = false
            return
        }
        
        // FIXED: Only prevent duplicate requests if we're already in the process of requesting
        guard !hasRequestedPermission else {
            print("🔔 [NotificationManager] Permission request already in progress, skipping")
            return
        }
        
        hasRequestedPermission = true
        print("🔔 [NotificationManager] User is authenticated, requesting permission...")
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await MainActor.run {
                self.permissionGranted = granted
                // Reset the flag after request completes
                self.hasRequestedPermission = false
            }
            
            print("🔔 [NotificationManager] Permission granted: \(granted)")
            
            if granted {
                print("🔔 [NotificationManager] Registering for remote notifications...")
                await registerForRemoteNotifications()
                
                // If we already have a token, re-register it
                await registerExistingTokenWithBackend()
            } else {
                print("🔔 [NotificationManager] Permission denied by user")
            }
        } catch {
            print("❌ [NotificationManager] Failed to request permission: \(error)")
            hasRequestedPermission = false // Reset on error
        }
    }

    func requestPermission() async {
        print("🔔 [NotificationManager] Manual permission request")
        
        // Check current status first
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            print("🔔 [NotificationManager] Permission already granted")
            self.permissionGranted = true
            await registerForRemoteNotifications()
            return
        case .denied:
            print("🔔 [NotificationManager] Permission previously denied - cannot request again")
            self.permissionGranted = false
            return
        case .notDetermined:
            break
        case .ephemeral:
            print("🔔 [NotificationManager] Ephemeral permission granted")
            self.permissionGranted = true
            await registerForRemoteNotifications()
            return
        @unknown default:
            print("🔔 [NotificationManager] Unknown permission status")
            self.permissionGranted = false
            return
        }
        
        guard !hasRequestedPermission else {
            print("🔔 [NotificationManager] Permission request already in progress")
            return
        }
        
        hasRequestedPermission = true
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            self.permissionGranted = granted
            hasRequestedPermission = false // Reset after completion
            
            print("🔔 [NotificationManager] Permission request result: \(granted)")
            
            if granted {
                await registerForRemoteNotifications()
            }
        } catch {
            print("❌ [NotificationManager] Failed to request notification permission: \(error)")
            hasRequestedPermission = false // Reset on error
        }
    }
    
    @MainActor
    private func registerForRemoteNotifications() async {
        print("🔔 [NotificationManager] Registering for remote notifications...")
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func setDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        
        // ENHANCED: Prevent duplicate token if it's the same
        guard self.deviceToken != token else {
            print("🔔 [NotificationManager] Same device token received, skipping registration")
            return
        }
        
        self.deviceToken = token
        print("🔔 [NotificationManager] Device token received: \(token.prefix(20))...")
        print("🔔 [NotificationManager] Full token length: \(token.count) characters")
        
        // Register token with backend immediately
        Task {
            await registerTokenWithBackend(token: token)
        }
    }
    
    // NEW: Re-register existing token with backend
    private func registerExistingTokenWithBackend() async {
        guard let token = deviceToken else {
            print("🔔 [NotificationManager] No device token to re-register")
            return
        }
        
        print("🔔 [NotificationManager] Re-registering existing token with backend...")
        await registerTokenWithBackend(token: token)
    }
    
    private func registerTokenWithBackend(token: String) async {
        print("🔔 [NotificationManager] Starting device token registration...")
        print("🔔 [NotificationManager] Token to register: \(token.prefix(20))...")
        print("🔔 [NotificationManager] Auth state: \(AuthenticationManager.shared.isAuthenticated)")
        
        // ENHANCED: Prevent duplicate registration calls
        guard !isRegisteringToken else {
            print("🔔 [NotificationManager] Token registration already in progress, skipping")
            return
        }
        
        // Wait for authentication to be ready with multiple attempts
        var authAttempts = 0
        while !AuthenticationManager.shared.isAuthenticated && authAttempts < 5 {
            authAttempts += 1
            print("🔔 [NotificationManager] Waiting for authentication (attempt \(authAttempts)/5)...")
            
            if authAttempts == 1 {
                // On first attempt, wait 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            } else {
                // On subsequent attempts, wait 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        
        guard AuthenticationManager.shared.isAuthenticated else {
            print("❌ [NotificationManager] User not authenticated after 5 attempts, cannot register token")
            return
        }
        
        // ENHANCED: Rate limit token registration (max once per 10 seconds)
        if let lastRegistration = lastTokenRegistrationTime,
           Date().timeIntervalSince(lastRegistration) < 10.0 {
            print("🔔 [NotificationManager] Token registration rate limited, skipping")
            return
        }
        
        isRegisteringToken = true
        lastTokenRegistrationTime = Date()
        
        defer {
            isRegisteringToken = false
        }
        
        guard let url = URL(string: "\(AppConfig.baseURL)/notifications/register-device-token") else {
            print("❌ [NotificationManager] Invalid URL for token registration")
            return
        }
        
        print("🔔 [NotificationManager] Registration URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0 // 30 second timeout
        
        // Add auth header
        guard let authToken = AuthenticationManager.shared.storedAuthToken else {
            print("❌ [NotificationManager] No auth token available for device token registration")
            return
        }
        
        print("🔔 [NotificationManager] Using auth token: \(authToken.prefix(20))...")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]
        
        print("🔔 [NotificationManager] Request body: \(requestBody)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            print("🔔 [NotificationManager] Sending registration request...")
            // Run the potentially long-running network request off of the Main Actor so we don't block the UI
            let (data, response): (Data, URLResponse) = try await Task.detached(priority: .utility) {
                return try await URLSession.shared.data(for: request)
            }.value
            
            print("🔔 [NotificationManager] Received response")
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔔 [NotificationManager] HTTP Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("✅ [NotificationManager] Device token registered successfully with backend")
                    
                    // Parse response for additional info
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("🔔 [NotificationManager] Response body: \(responseString)")
                    }
                } else {
                    print("❌ [NotificationManager] Failed to register device token: HTTP \(httpResponse.statusCode)")
                    
                    if let responseData = String(data: data, encoding: .utf8) {
                        print("❌ [NotificationManager] Error response: \(responseData)")
                    }
                    
                    // Reset rate limit on error to allow retry
                    lastTokenRegistrationTime = nil
                    
                    // Retry once for certain error codes
                    if httpResponse.statusCode == 401 {
                        print("🔔 [NotificationManager] Auth error, will retry after re-authentication")
                    } else if httpResponse.statusCode >= 500 {
                        print("🔔 [NotificationManager] Server error, scheduling retry in 5 seconds...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            Task {
                                await self.registerTokenWithBackend(token: token)
                            }
                        }
                    }
                }
            }
        } catch {
            print("❌ [NotificationManager] Error registering device token: \(error)")
            print("❌ [NotificationManager] Error details: \(error.localizedDescription)")
            
            // Reset rate limit on error to allow retry
            lastTokenRegistrationTime = nil
            
            // Check if it's a network error and schedule retry
            if (error as NSError).domain == NSURLErrorDomain {
                print("🔔 [NotificationManager] Network error, scheduling retry in 10 seconds...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    Task {
                        await self.registerTokenWithBackend(token: token)
                    }
                }
            }
        }
    }
    
    // ENHANCED: Reset state when user logs out
    func resetOnLogout() async {
        print("🔔 [NotificationManager] Resetting notification state on logout")
        hasRequestedPermission = false
        isRegisteringToken = false
        lastTokenRegistrationTime = nil
        
        // Device token cleanup is now handled by backend logout endpoint
        // which automatically clears all device tokens for the user
        
        deviceToken = nil
        permissionGranted = false
    }
    
    // ADDED: Force permission request (for debugging/testing)
    func forceRequestPermission() async {
        print("🔔 [NotificationManager] Force requesting permission...")
        hasRequestedPermission = false // Reset flag
        await requestPermission()
    }
    
    // ADDED: Get current notification status for debugging
    func getCurrentNotificationStatus() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        let status = """
        🔔 Notification Status:
        • Authorization: \(settings.authorizationStatus.rawValue)
        • Alert: \(settings.alertSetting.rawValue)
        • Badge: \(settings.badgeSetting.rawValue)
        • Sound: \(settings.soundSetting.rawValue)
        • Permission Granted: \(permissionGranted)
        • Device Token: \(deviceToken != nil ? "Present (\(deviceToken!.count) chars)" : "None")
        • Has Requested: \(hasRequestedPermission)
        • Auth Status: \(AuthenticationManager.shared.isAuthenticated)
        """
        
        return status
    }
    
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        print("Received notification: \(userInfo)")
        
        // Extract notification data
        if let type = userInfo["type"] as? String {
            switch type {
            case "comment":
                handleCommentNotification(userInfo)
            case "new_post":
                handleNewPostNotification(userInfo)
            default:
                print("Unknown notification type: \(type)")
            }
        }
    }
    
    private func handleCommentNotification(_ userInfo: [AnyHashable: Any]) {
        guard let postId = userInfo["post_id"] as? String else { return }
        
        // Navigate to the post or refresh feed
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToPost"),
            object: nil,
            userInfo: ["postId": postId]
        )
        
        // Persist for cold-start routing. Any view can observe this Published var.
        navigateToPostId = postId
    }
    
    private func handleNewPostNotification(_ userInfo: [AnyHashable: Any]) {
        guard let postId = userInfo["post_id"] as? String else { return }
        
        // Refresh feed to show new post
        NotificationCenter.default.post(
            name: NSNotification.Name("RefreshFeed"),
            object: nil,
            userInfo: ["newPostId": postId]
        )
    }
    
    // DEBUG: Manual test method
    func testDeviceTokenRegistration() async {
        print("🧪 [NotificationManager] Manual device token registration test")
        
        // Use a test token if no real token exists
        let testToken = deviceToken ?? "test_token_manual_\(Int.random(in: 1000...9999))"
        
        print("🧪 [NotificationManager] Testing with token: \(testToken.prefix(20))...")
        await registerTokenWithBackend(token: testToken)
    }
    
    // MARK: - App lifecycle hooks
    /// Called by AppDelegate when the app becomes active / enters foreground.
    /// Clears the `hasRequestedPermission` flag so we don't get stuck in a state where
    /// the user force-quit the app while the system permission alert was showing.
    func handleAppWillEnterForeground() {
        hasRequestedPermission = false
    }
    
    // MARK: - Quick local notification for new feed posts
    func showFeedUpdateNotification(count: Int) {
        // Build the notification content
        let content = UNMutableNotificationContent()
        content.title = "New post\(count > 1 ? "s" : "") in your feed!"
        content.body = count == 1 ? "Your friend just shared an update." : "Your friends shared \(count) new updates."
        content.sound = .default
        content.userInfo = ["type": "feed_update"]

        // Trigger immediately – if the app is in the foreground the delegate will display a banner.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [NotificationManager] Failed to schedule feed update notification: \(error)")
            } else {
                print("🔔 [NotificationManager] Scheduled feed update local notification (\(count) new)")
            }
        }
    }

    /// Notification describing a single friend's new verified habit completion.
    func showSingleFeedPostNotification(authorName: String, habitName: String) {
        let content = UNMutableNotificationContent()
        content.title = "New habit completion!"
        content.body  = "\(authorName) just completed \(habitName), check it out in the feed!"
        content.sound = .default
        content.userInfo = ["type": "feed_update_single"]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [NotificationManager] Failed to schedule single feed post notification: \(error)")
            } else {
                print("🔔 [NotificationManager] Scheduled single feed post notification for \(authorName) / \(habitName)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handleNotification(notification.request.content.userInfo)
        }
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotification(response.notification.request.content.userInfo)
        }
        completionHandler()
    }
} 
