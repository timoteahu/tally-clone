////
//  AddHabitHelpers.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Shared utility functions & models for Add Habit flow.
//

import Foundation
import SwiftUI

// Shared ViewModel to hold state for the multi-step Add-Habit flow.
final class AddHabitViewModel: ObservableObject {
    // Step-agnostic fields
    @Published var selectedHabitType: String = ""
    @Published var selectedCustomHabitTypeId: String?

    // Step 2 – details
    @Published var name: String = ""
    @Published var alarmTime: Date = .init()
    @Published var selectedFriend: Friend?
    @Published var partnerSearchText: String = ""
    @Published var showingFriendsDropdown: Bool = false
    @Published var customNotification: String = ""

    // Step 3 – schedule / penalty
    @Published var scheduleType: String = "daily"   // "daily" or "weekly"
    @Published var selectedWeekdays: [Int] = []      // 0-based weekday index
    @Published var weeklyTarget: Int = 3
    // GitHub commits specific
    @Published var commitTarget: Int = 1
    let weekStartDay: Int = 0                       // Always Sunday
    @Published var penaltyAmount: Float = 5.0
    @Published var isPrivate: Bool = false
    
    // Zero-penalty picture habits (optimized)
    @Published var isZeroPenalty: Bool = false
    @Published var existingZeroPenaltyCount: Int = 0
    private var _lastCountUpdate: Date?
    private var _countNeedsRefresh: Bool = true
    
    /// Optimized count fetching - only when actually needed
    @MainActor
    func refreshZeroPenaltyCountIfNeeded() {
        // Only refresh for picture habits
        guard isPictureHabit else {
            existingZeroPenaltyCount = 0
            return
        }
        
        // Skip if recently updated (within 1 second)
        if let lastUpdate = _lastCountUpdate,
           Date().timeIntervalSince(lastUpdate) < 1.0,
           !_countNeedsRefresh {
            return // Use cached value
        }
        
        // Get count from optimized cache
        let newCount = DataCacheManager.shared.getZeroPenaltyHabitCount()
        
        // Only update if changed (avoid unnecessary UI updates)
        if newCount != existingZeroPenaltyCount {
            existingZeroPenaltyCount = newCount
        }
        
        _lastCountUpdate = Date()
        _countNeedsRefresh = false
    }
    
    /// Mark count as needing refresh (called when relevant changes occur)
    func markCountForRefresh() {
        _countNeedsRefresh = true
    }
    
    // Gaming habit specific
    @Published var dailyLimitHours: Double = 2.0
    @Published var hourlyPenaltyRate: Double = 5.0

    // Apple Health habits specific
    @Published var healthTargetValue: Double = 10000  // Default to 10,000 steps
    @Published var healthTargetUnit: String = "steps"
    @Published var healthDataType: String = "stepCount"

    // Flow control
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    
    // Stripe warning
    @Published var showingStripeWarning: Bool = false
    @Published var stripeWarningFriendName: String = ""

    // Convenience
    var formattedAlarmTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: alarmTime)
    }

    func formatAlarmTime24h() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: alarmTime)
    }
    
    // Health habit helpers
    func updateHealthFieldsForType(_ habitType: String) {
        guard habitType.hasPrefix("health_") else { return }
        
        switch habitType {
        case "health_steps":
            healthTargetValue = 8000  // More realistic than 10,000 for beginners
            healthTargetUnit = "steps"
            healthDataType = "stepCount"
        case "health_walking_running_distance":
            healthTargetValue = 2.0  // 2 miles is more achievable
            healthTargetUnit = "miles"
            healthDataType = "distanceWalkingRunning"
        case "health_flights_climbed":
            healthTargetValue = 5  // 5 flights is more realistic
            healthTargetUnit = "flights"
            healthDataType = "flightsClimbed"
        case "health_exercise_minutes":
            healthTargetValue = 20  // Start with 20 minutes
            healthTargetUnit = "minutes"
            healthDataType = "appleExerciseTime"
        case "health_cycling_distance":
            healthTargetValue = 3.0  // 3 miles cycling
            healthTargetUnit = "miles"
            healthDataType = "distanceCycling"
        case "health_sleep_hours":
            healthTargetValue = 7.5  // 7.5 hours is more realistic than 8
            healthTargetUnit = "hours"
            healthDataType = "sleepAnalysis"
        case "health_calories_burned":
            healthTargetValue = 300  // 300 active calories is more realistic
            healthTargetUnit = "calories"
            healthDataType = "activeEnergyBurned"
        case "health_mindful_minutes": // Keep the backend name but update display
            healthTargetValue = 5  // Start with just 5 minutes
            healthTargetUnit = "minutes"
            healthDataType = "mindfulSession"
        default:
            healthTargetValue = 1
            healthTargetUnit = "unit"
            healthDataType = "unknown"
        }
    }
    
    // Validation ranges for health habits
    func getValidationRange(for habitType: String) -> (min: Double, max: Double, step: Double) {
        switch habitType {
        case "health_steps":
            return (min: 1000, max: 50000, step: 500)
        case "health_walking_running_distance":
            return (min: 0.5, max: 26.2, step: 0.5)  // Up to marathon distance
        case "health_flights_climbed":
            return (min: 1, max: 100, step: 1)
        case "health_exercise_minutes":
            return (min: 5, max: 180, step: 5)  // 5 minutes to 3 hours
        case "health_cycling_distance":
            return (min: 1, max: 100, step: 1)
        case "health_sleep_hours":
            return (min: 4, max: 12, step: 0.5)
        case "health_calories_burned":
            return (min: 50, max: 2000, step: 50)
        case "health_mindful_minutes":
            return (min: 1, max: 120, step: 1)  // 1 minute to 2 hours
        default:
            return (min: 1, max: 100, step: 1)
        }
    }
    
    // Get description for health habit types
    func getHealthHabitDescription(for habitType: String) -> String {
        switch habitType {
        case "health_steps":
            return "Track your daily step count from your iPhone or Apple Watch"
        case "health_walking_running_distance":
            return "Track walking and running distance from your iPhone or Apple Watch"
        case "health_flights_climbed":
            return "Track flights of stairs climbed (requires iPhone 6 or newer)"
        case "health_exercise_minutes":
            return "Track exercise minutes from your Apple Watch (requires Apple Watch)"
        case "health_cycling_distance":
            return "Track cycling distance from workout apps or Apple Watch"
        case "health_sleep_hours":
            return "Track sleep duration from your Apple Watch or sleep apps (Apple Watch recommended)"
        case "health_calories_burned":
            return "Track active calories burned from your Apple Watch (requires Apple Watch)"
        case "health_mindful_minutes":
            return "Track meditation sessions from Breathe app or meditation apps"
        default:
            return "Track health data from Apple Health"
        }
    }
    
    var isHealthHabit: Bool {
        selectedHabitType.hasPrefix("health_")
    }
    
    var isGamingHabit: Bool {
        selectedHabitType == "league_of_legends" || selectedHabitType == "valorant"
    }
    
    var isGithubHabit: Bool {
        selectedHabitType == "github_commits"
    }
    
    var isLeetCodeHabit: Bool {
        selectedHabitType == "leetcode"
    }
    var isPictureHabit: Bool {
        // IMPORTANT: Only PICTURE HABITS can use zero-penalty option
        // Picture habits = photo verification habits (gym, alarm, yoga, outdoors, cycling, cooking, custom)
        let pictureHabitTypes = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
        return pictureHabitTypes.contains(selectedHabitType) || selectedHabitType.hasPrefix("custom_")
    }
    
    var canUseZeroPenalty: Bool {
        // STRICT ENFORCEMENT: Zero-penalty only for picture habits + under the 3-habit limit
        return isPictureHabit && existingZeroPenaltyCount < 3
    }
    
    // Function to update fields when habit type changes
    func updateFieldsForHabitType() {
        let wasPictureHabit = isPictureHabit
        
        if isHealthHabit {
            updateHealthFieldsForType(selectedHabitType)
        } else {
            // Clear health fields when switching away from health habits
            healthTargetValue = 10000
            healthTargetUnit = "steps"
            healthDataType = "stepCount"
        }
        
        // SAFETY: Reset zero-penalty if switching away from picture habits
        if !isPictureHabit {
            isZeroPenalty = false
        }
        
        // OPTIMIZATION: Only refresh count when switching TO picture habits
        if isPictureHabit && !wasPictureHabit {
            markCountForRefresh()
        }
        
        // Clear other type-specific fields when switching types
        if !isGamingHabit {
            dailyLimitHours = 2.0
            hourlyPenaltyRate = 5.0
        }
        if !isGithubHabit {
            commitTarget = 1
        }
    }
}

extension AddHabitRoot {
    // TODO: Move validation functions, API helpers, etc.
} 