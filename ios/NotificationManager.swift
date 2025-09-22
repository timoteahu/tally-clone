import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var permissionGranted = false
    @Published var deviceToken: String?
    
    private override init() {
        super.init()
    }
    
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            self.permissionGranted = granted
            
            if granted {
                await registerForRemoteNotifications()
            }
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }
    
    @MainActor
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func setDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
        
        // Register token with backend
        Task {
            await registerTokenWithBackend(token: token)
        }
    }
    
    private func registerTokenWithBackend(token: String) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/notifications/register-device-token") else {
            print("Invalid URL for token registration")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth header if user is logged in
        if let authToken = KeychainManager.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let requestBody: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("Device token registered successfully")
                } else {
                    print("Failed to register device token: HTTP \(httpResponse.statusCode)")
                    if let responseData = String(data: data, encoding: .utf8) {
                        print("Response: \(responseData)")
                    }
                }
            }
        } catch {
            print("Error registering device token: \(error)")
        }
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
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleNotification(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotification(response.notification.request.content.userInfo)
        completionHandler()
    }
} 