import SwiftUI
import Foundation

// MARK: - Event Handlers
// Extracted from ContentView to keep it clean and focused

extension ContentView {
    
    func handleTabChange(_ newValue: Int) {
        // Onboarding removed – no special tab-switch handling needed
        
        if newValue == 2 {
            showAddHabitSheet = true
            DispatchQueue.main.async {
                selectedTab = previousTab
            }
        } else if newValue != 2 {
            previousTab = newValue
        }
        
        // Track feed visibility for potential future optimizations
        let isFeedVisible = (newValue == 3)
        
        if isFeedVisible {
            print("📡 [ContentView] Switched to feed tab")
        } else {
            print("📱 [ContentView] Switched away from feed tab")
        }
    }
    
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleAppBecameActive()
            backgroundUpdateManager.handleAppWillEnterForeground()
        case .background:
            lastBackgroundTime = Date()
            backgroundUpdateManager.handleAppDidEnterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
    
    func handleNavigateToPost(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let postId = userInfo["postId"] as? String {
            selectedTab = 3
            print("📱 [ContentView] Navigating to post: \(postId)")
            // TODO: Add logic to scroll to specific post in feed
        }
    }
    
    func handleRefreshFeed() {
        // Feed is now purely polling-driven, no manual refresh needed
        print("📡 [ContentView] Feed refresh requested - polling handles all updates automatically")
    }
    
    func handleNavigateToHabitPost(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let habitId = userInfo["habitId"] as? String {
            print("📱 [ContentView] handleNavigateToHabitPost called with habitId: \(habitId)")
            print("📱 [ContentView] Current feed posts count: \(feedManager.feedPosts.count)")
            
            // First, switch to the feed tab
            selectedTab = 3
            
            // Convert habitId to lowercase for comparison (backend stores as lowercase)
            let lowercaseHabitId = habitId.lowercased()
            
            // Debug: Log all habitIds in the feed
            let habitIds = feedManager.feedPosts.compactMap { $0.habitId }
            print("📱 [ContentView] Feed contains posts for habits: \(habitIds)")
            
            // Find posts for this habit (case-insensitive comparison)
            let postsForHabit = feedManager.feedPosts.filter { 
                $0.habitId?.lowercased() == lowercaseHabitId 
            }
            print("📱 [ContentView] Found \(postsForHabit.count) posts for habit \(habitId)")
            
            // Find the most recent post for this habit
            let mostRecentPost = postsForHabit
                .sorted { $0.createdAt > $1.createdAt }
                .first
            
            if let post = mostRecentPost {
                print("📱 [ContentView] Found post: \(post.postId.uuidString) created at: \(post.createdAt)")
                // Increase delay to ensure feed view is fully loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToPost"),
                        object: nil,
                        userInfo: ["postId": post.postId.uuidString]
                    )
                    print("📱 [ContentView] Posted NavigateToPost notification for: \(post.postId.uuidString)")
                }
            } else {
                print("📱 [ContentView] No posts found for habit: \(habitId)")
                // Trigger a refresh to get latest posts
                print("📱 [ContentView] Triggering feed refresh to find posts for this habit...")
                Task {
                    await feedManager.manualRefresh()
                    // After refresh, try again
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let refreshedPosts = feedManager.feedPosts.filter { 
                            $0.habitId?.lowercased() == lowercaseHabitId 
                        }
                        if let post = refreshedPosts.sorted(by: { $0.createdAt > $1.createdAt }).first {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToPost"),
                                object: nil,
                                userInfo: ["postId": post.postId.uuidString]
                            )
                            print("📱 [ContentView] Found post after refresh: \(post.postId.uuidString)")
                        }
                    }
                }
            }
        }
    }
} 