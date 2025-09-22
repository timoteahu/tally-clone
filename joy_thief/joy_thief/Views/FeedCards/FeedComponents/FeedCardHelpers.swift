import SwiftUI
import Foundation

// MARK: - FeedCard Helpers
struct FeedCardHelpers {
    
    // MARK: - Card Display Calculations
    
    static func calculateCardScale(isCurrentCard: Bool, cardIndex: Int, currentIndex: Int, verticalDragOffset: CGSize) -> CGFloat {
        if isCurrentCard {
            // Ultra-simplified scale calculation
            let dragFactor = min(abs(verticalDragOffset.height) * 0.0001, 0.05)
            return 1.0 - dragFactor
        } else {
            let distance = abs(cardIndex - currentIndex)
            return distance == 1 ? 0.88 : 0.75
        }
    }
    
    static func calculateCardOpacity(isCurrentCard: Bool, verticalDragOffset: CGSize) -> Double {
        if isCurrentCard {
            // Ultra-simplified opacity calculation
            let dragFactor = min(abs(verticalDragOffset.height) * 0.0001, 0.03)
            return 1.0 - dragFactor
        } else {
            // All cards are fully opaque - no transparency
            return 1.0
        }
    }
    
    // MARK: - Habit Data Computations
    
    @MainActor static func computeStreakValue(post: FeedPost, habitManager: HabitManager) -> Int {
        if let serverStreak = post.streak {
            return serverStreak
        }
        if let habitId = post.habitId {
            let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
            if let habit = habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId }) {
                return habit.currentStreak
            }
        }
        return 0
    }
    
    @MainActor static func computeHabitTypeDisplayName(post: FeedPost, habitManager: HabitManager) -> String {
        let fallbackType = "standard"
        if let habitType = post.habitType, !habitType.isEmpty {
            return displayName(for: habitType)
        }
        guard let habitId = post.habitId else { return displayName(for: fallbackType) }
        let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let habit = habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId }) {
            return displayName(for: habit.habitType)
        }
        return displayName(for: fallbackType)
    }
    
    @MainActor static func computeHabitType(post: FeedPost, habitManager: HabitManager) -> String {
        let fallbackType = "standard"
        if let habitType = post.habitType, !habitType.isEmpty {
            return habitType
        }
        guard let habitId = post.habitId else { return fallbackType }
        let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let habit = habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId }) {
            return habit.habitType
        }
        return fallbackType
    }

    @MainActor static func computeHabitProgress(post: FeedPost, habitManager: HabitManager) -> (current: Int, total: Int)? {
        guard let habitId = post.habitId else { return nil }
        let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let habit = habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId }) else { return nil }

        let current = habitManager.getWeeklyHabitProgress(for: habit.id)
        if habit.isWeeklyHabit {
            // For GitHub weekly habits, use commitTarget instead of weeklyTarget
            let total = (habit.habitType == "github_commits") ? 
                (habit.commitTarget ?? 7) : (habit.weeklyTarget ?? 1)
            return (current, total)
        } else {
            let total = habit.weekdays.isEmpty ? 7 : habit.weekdays.count
            return (current, total)
        }
    }
    
    @MainActor static func calculatePenaltyAmount(post: FeedPost, habitManager: HabitManager) -> Float {
        // ✅ Use penalty amount from server if available
        if let serverPenaltyAmount = post.penaltyAmount {
            return serverPenaltyAmount
        }
        
        // Fallback to local lookup (for backward compatibility)
        if let habitId = post.habitId {
            // Use the same trimmed comparison logic
            let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
            if let habit = habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId }) {
                return habit.penaltyAmount
            }
        }
        return 0.0
    }
    
    @MainActor static func getHabitNameDisplay(post: FeedPost, habitManager: HabitManager) -> String? {
        // Prefer the name supplied by backend
        if let backendName = post.habitName, !backendName.isEmpty {
            return backendName
        }

        // Fallback: look-up using the habitId
        guard let habitId = post.habitId else { return nil }
        let targetHabitId = habitId.trimmingCharacters(in: .whitespacesAndNewlines)
        return habitManager.habits.first(where: { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == targetHabitId })?.name
    }
    
    // MARK: - Display Name Mapping
    
    static func displayName(for habitType: String) -> String {
        // Add empty string check
        guard !habitType.isEmpty else { return "" }
        
        switch habitType {
        case "gym":          return "Gym"
        case "alarm":        return "Morning Routine"
        case "yoga":         return "Yoga"
        case "outdoors":     return "Outdoors"
        case "cycling":      return "Cycling"
        case "cooking":      return "Cooking"
        case "studying":     return "Study"
        case "screenTime":   return "Screen Time"
        case "github_commits": return "GitHub Commits"
        default:              return habitType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    // MARK: - Time Formatting
    
    static func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Comments Handling
    
    @MainActor static func handleCommentsChange(
        newValue: Bool,
        currentPost: FeedPost,
        feedManager: FeedManager,
        cachedCommentCount: Binding<Int>,
        isLoadingComments: Binding<Bool>,
        shimmerOpacity: Binding<Double>
    ) {
        if newValue {
            let needsRefresh = feedManager.commentsNeedRefresh(for: currentPost.postId)
            print("💬 [SwipeableFeedCard] Comment sheet opened:")
            print("   - Post ID: \(currentPost.postId.uuidString.prefix(8))")
            print("   - Current comment count: \(currentPost.comments.count)")
            print("   - Needs refresh: \(needsRefresh)")
            
            if needsRefresh {
                cachedCommentCount.wrappedValue = currentPost.comments.count
                isLoadingComments.wrappedValue = true
                print("💬 [SwipeableFeedCard] Setting isLoadingComments = true")
                
                withAnimation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                ) {
                    shimmerOpacity.wrappedValue = 0.8
                }
                Task {
                    await feedManager.refreshCommentsForPost(postId: currentPost.postId)
                    await MainActor.run {
                        isLoadingComments.wrappedValue = false
                        cachedCommentCount.wrappedValue = currentPost.comments.count
                        print("💬 [SwipeableFeedCard] Comments refresh completed:")
                        print("   - Setting isLoadingComments = false")
                        print("   - New comment count: \(currentPost.comments.count)")
                        print("   - Updated cached count to: \(cachedCommentCount.wrappedValue)")
                        
                        withAnimation(.easeOut(duration: 0.6)) {
                            shimmerOpacity.wrappedValue = 0.3
                        }
                    }
                }
            } else {
                isLoadingComments.wrappedValue = false
                print("💬 [SwipeableFeedCard] No refresh needed, setting isLoadingComments = false")
            }
        } else {
            print("💬 [SwipeableFeedCard] Comment sheet closed")
        }
    }
} 
