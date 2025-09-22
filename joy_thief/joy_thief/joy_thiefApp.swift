//
//  joy_thiefApp.swift
//  joy_thief
//
//  Created by Timothy Hu on 4/15/25.
//

import SwiftUI
import BranchSDK
import Stripe
import CoreText
import UserNotifications
import Kingfisher
import UIKit
import BranchSDK

// AppDelegate for Branch initialization and background tasks
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("🚀 [AppDelegate] Application starting...")
        print("🚀 [AppDelegate] Starting Branch initialization...")
        
        // Print configuration for debugging
        AppConfig.printConfiguration()
        
        // Restore any pending Branch invite saved from a previous cold start
        BranchService.shared.bootstrap()
        
        // Configure Branch logging and set key
        Branch.enableLogging()
        
        // Use the centralized Branch key from AppConfig
        print("🔑 [AppDelegate] Setting Branch key from AppConfig")
        Branch.setBranchKey(AppConfig.branchKey)
        
        // Initialize Branch session
        Branch.getInstance().initSession(launchOptions: launchOptions) { (params, error) in
            DispatchQueue.main.async {
                if error != nil {
                    print("❌ [AppDelegate] Branch initialization failed: \\(error.localizedDescription)")
                } else {
                    print("✅ [AppDelegate] Branch initialization completed successfully")
                    if let params = params, !params.isEmpty {
                        print("📋 [AppDelegate] Branch params received: \\(params)")
                        print("📋 [AppDelegate] Branch params count: \\(params.count)")
                        
                        // Log specific keys we're looking for
                        if params["inviter_id"] != nil {
                            print("👤 [AppDelegate] Found inviter_id: \\(params[\"inviter_id\"]!)")
                        }
                        if params["inviter_name"] != nil {
                            print("👤 [AppDelegate] Found inviter_name: \\(params[\"inviter_name\"]!)")
                        }
                        if params["inviter_phone"] != nil {
                            print("📱 [AppDelegate] Found inviter_phone: \\(params[\"inviter_phone\"]!)")
                        }
                        if params["+clicked_branch_link"] != nil {
                            print("🔗 [AppDelegate] Clicked branch link: \\(params[\"+clicked_branch_link\"]!)")
                        }
                        
                        print("🚀 [AppDelegate] Processing deep link with BranchService")
                        Task {
                            _ = await BranchService.shared.processDeepLink(parameters: params)
                            print("🎯 [AppDelegate] Deep link processing result: \\(result)")
                        }
                    } else {
                        print("📭 [AppDelegate] No Branch params received")
                    }
                }
            }
        }
        
        // ENHANCED: Register background tasks for cache updates
        Task { @MainActor in
            BackgroundUpdateManager.shared.registerBackgroundTasks()
        }
        
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // ENHANCED: Request notification permission for authenticated users at app start
        // Use a longer delay to ensure authentication state is properly loaded
        Task { @MainActor in
            // Longer delay to ensure authentication state is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    print("AppDelegate: Attempting to request notification permission...")
                    await NotificationManager.shared.requestPermissionIfAuthenticated()
                }
            }
        }
        
        // Refresh cache timestamp immediately on cold launch to ensure foreground check considers cache fresh
        DataCacheManager.shared.refreshCacheTimestamp()
        
        return true
    }
    
    // MARK: - URL Handling for Branch Links
    
    // Handle URL when app is already running (iOS 13+)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("🔗 [AppDelegate] application(_:open:options:) called")
        print("🔗 [AppDelegate] URL: \\(url)")
        print("🔗 [AppDelegate] Options: \\(options)")
        print("🔗 [AppDelegate] URL scheme: \\(url.scheme ?? \"none\")")
        print("🔗 [AppDelegate] URL host: \\(url.host ?? \"none\")")
        print("🔗 [AppDelegate] URL path: \\(url.path)")
        print("🔗 [AppDelegate] URL query: \\(url.query ?? \"none\")")
        
        // Check if this is a Branch link
        let handled = Branch.getInstance().application(app, open: url, options: options)
        print("🔗 [AppDelegate] Branch handled URL: \\(handled)")
        
        return handled
    }
    
    // Handle universal links (iOS 13+)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("🌐 [AppDelegate] application(_:continue:restorationHandler:) called")
        print("🌐 [AppDelegate] Activity type: \\(userActivity.activityType)")
        
        if userActivity.webpageURL != nil {
            print("🌐 [AppDelegate] Universal link URL: \\(userActivity.webpageURL!)")
            print("🌐 [AppDelegate] URL host: \\(userActivity.webpageURL!.host ?? \"none\")")
            print("🌐 [AppDelegate] URL path: \\(userActivity.webpageURL!.path)")
            print("🌐 [AppDelegate] URL query: \\(userActivity.webpageURL!.query ?? \"none\")")
        }
        
        // Pass to Branch for processing
        let handled = Branch.getInstance().continue(userActivity)
        print("🌐 [AppDelegate] Branch handled universal link: \\(handled)")
        
        return handled
    }
    
    // MARK: - Push Notification Handling
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("AppDelegate: Successfully registered for remote notifications")
        Task { @MainActor in
            NotificationManager.shared.setDeviceToken(deviceToken)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("AppDelegate: Failed to register for remote notifications: \\(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("AppDelegate: Received remote notification")
        Task { @MainActor in
            NotificationManager.shared.handleNotification(userInfo)
        }
        completionHandler(.newData)
    }
    
    // ENHANCED: Handle app lifecycle for background updates
    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            BackgroundUpdateManager.shared.handleAppDidEnterBackground()
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in
            BackgroundUpdateManager.shared.handleAppWillEnterForeground()
            NotificationManager.shared.handleAppWillEnterForeground()
        }
    }
}

@main
struct TallyApp: App {
    @State private var branchService = BranchService.shared
    @StateObject var owedAmountManager = OwedAmountManager()
    @StateObject private var backgroundUpdateManager = BackgroundUpdateManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var storeManager = StoreManager()
    @StateObject private var paymentStatsManager = PaymentStatsManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var habitManager = HabitManager.shared
    @StateObject private var paymentManager = PaymentManager.shared
    @StateObject private var feedManager = FeedManager.shared
    @StateObject private var friendsManager = FriendsManager.shared
    @StateObject private var contactManager = ContactManager.shared
    @StateObject private var loadingManager = LoadingStateManager.shared
    @StateObject private var dataCacheManager = DataCacheManager.shared
    @StateObject private var customHabitManager = CustomHabitManager.shared
    @StateObject private var recipientAnalyticsManager = RecipientAnalyticsManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Set Stripe publishable key
        STPAPIClient.shared.publishableKey = AppConfig.stripePublishableKey
        
        // Configure Kingfisher for optimal avatar caching
        configureKingfisher()
        
        // Register EB Garamond font once at app startup
        registerEBGaramondFont()
    }
    
    var body: some Scene {
        WindowGroup {
            // SplashScreenView handles preloading and transition to ContentView
            SplashScreenView()
                .environment(branchService)
                .environmentObject(owedAmountManager)
                .environmentObject(backgroundUpdateManager)
                .environmentObject(notificationManager)
                .environmentObject(storeManager)
                .environmentObject(paymentStatsManager)
                .font(.ebGaramondBody)
                .onAppear {
                    // Initialize BranchService after the app loads
                    Task {
                        try await branchService.initialize()
                    }
                }
                .onOpenURL { url in
                    print("🔗 [SwiftUI] onOpenURL called with: \\(url)")
                    print("🔗 [SwiftUI] URL scheme: \\(url.scheme ?? \"none\")")
                    print("🔗 [SwiftUI] URL host: \\(url.host ?? \"none\")")
                    print("🔗 [SwiftUI] URL path: \\(url.path)")
                    print("🔗 [SwiftUI] URL query: \\(url.query ?? \"none\")")
                    
                    // 1️⃣ GitHub OAuth deep-link
                    if url.scheme == "tally", url.host == "github", url.path == "/callback" {
                        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let code = comps.queryItems?.first(where: { $0.name == "code" })?.value {
                            print("🪄 [SwiftUI] Detected GitHub OAuth callback – exchanging code…")
                            Task { await GitHubOAuthManager.shared.exchange(code: code) }
                            return  // don’t forward to Branch
                        }
                    }

                    // 2️⃣ Otherwise treat as Branch link
                    _ = Branch.getInstance().application(UIApplication.shared, open: url, options: [:])
                    print("🔗 [SwiftUI] Branch handled URL: \\(handled)")
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    print("🌐 [SwiftUI] onContinueUserActivity called")
                    print("🌐 [SwiftUI] Activity type: \\(userActivity.activityType)")
                    
                    if userActivity.webpageURL != nil {
                        print("🌐 [SwiftUI] Universal link URL: \\(userActivity.webpageURL!)")
                        print("🌐 [SwiftUI] URL host: \\(userActivity.webpageURL!.host ?? \"none\")")
                        print("🌐 [SwiftUI] URL path: \\(userActivity.webpageURL!.path)")
                        print("🌐 [SwiftUI] URL query: \\(userActivity.webpageURL!.query ?? \"none\")")
                    }
                    
                    // Pass to Branch for processing
                    _ = Branch.getInstance().continue(userActivity)
                    print("🌐 [SwiftUI] Branch handled universal link: \\(handled)")
                }
        }
    }
}

// MARK: - Kingfisher Configuration
private func configureKingfisher() {
    let cache = ImageCache.default
    
    // Configure aggressive caching
    cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024 // 100MB memory cache
    cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024 // 500MB disk cache
    cache.diskStorage.config.expiration = .days(30) // 30 days disk cache
    
    // Set global default options for all Kingfisher operations
    KingfisherManager.shared.defaultOptions = [
        .cacheOriginalImage,
        .backgroundDecode,
        .callbackQueue(.mainAsync),
        .scaleFactor(UIScreen.main.scale),
        .diskCacheExpiration(.days(30)),
        // Keep frequently-viewed feed images in memory for longer so they don't briefly
        // disappear (showing the grey placeholder) when the user returns to the feed
        // after navigating elsewhere in the app.
        .memoryCacheExpiration(.seconds(7200)) // 2 hours
    ]
    
    print("TallyApp: Kingfisher configured globally - Memory: \\(cache.memoryStorage.config.totalCostLimit / 1024 / 1024)MB, Disk: \\(cache.diskStorage.config.sizeLimit / 1024 / 1024)MB")
}

// MARK: - Font Registration
private func registerEBGaramondFont() {
    let fontNames = [
        "EBGaramond-Regular",
        "EBGaramond-Bold",
        "EBGaramond-BoldItalic",
        "EBGaramond-ExtraBold",
        "EBGaramond-ExtraBoldItalic",
        "EBGaramond-Italic",
        "EBGaramond-Medium",
        "EBGaramond-MediumItalic",
        "EBGaramond-SemiBold",
        "EBGaramond-SemiBoldItalic"
    ]

    for fontName in fontNames {
        if let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                print("✅ Successfully registered font: \(fontName)")
            } else {
                if let error = error?.takeRetainedValue() {
                    let errorDescription = CFErrorCopyDescription(error)
                    print("❌ Failed to register font \(fontName): \(errorDescription ?? "Unknown error" as CFString)")
                } else {
                    print("❌ Failed to register font \(fontName) with an unknown error.")
                }
            }
        } else {
            print("❌ Could not find font file: \(fontName).ttf")
        }
    }
}
