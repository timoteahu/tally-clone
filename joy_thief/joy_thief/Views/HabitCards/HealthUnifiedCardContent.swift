//
//  HealthUnifiedCardContent.swift
//  joy_thief
//
//  Unified front card content for health habits
//

import SwiftUI

struct HealthUnifiedCardContent: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let habitTypeAccentColor: Color
    let getHabitIcon: () -> String
    let weeklyProgressBadge: AnyView
    var onVerify: (() -> Void)? = nil
    var onExpand: (() -> Void) // Callback to flip to verification view
    
    // Add camera and verification state bindings
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    @Binding var isVerifying: Bool
    @Binding var firstImageTaken: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    
    // Add habitManager and detail view state
    @ObservedObject var habitManager: HabitManager
    @State private var showingDetailView = false
    @State private var currentValue: Double = 0
    @State private var progressPercentage: Double = 0
    @State private var isLoading = true
    
    // Computed property to get the current habit data from HabitManager
    private var currentHabit: Habit {
        if let updatedHabit = habitManager.habits.first(where: { $0.id == habit.id }) {
            return updatedHabit
        }
        return habit
    }
    
    // Check if habit is verified today
    private var isVerifiedToday: Bool {
        habitManager.verifiedHabitsToday[habit.id] == true
    }
    
    // Check if target is reached and can be verified
    private var canVerify: Bool {
        !isLoading && !isVerifiedToday && currentValue >= (currentHabit.healthTargetValue ?? 0)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: cardHeight * 0.15)
                
                // Large centered icon
                Image(systemName: healthIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardWidth * 0.22, height: cardWidth * 0.22)
                    .foregroundColor(.white)
                    .padding(.bottom, cardHeight * 0.04)
                
                // Centered habit name
                Text(currentHabit.name.isEmpty ? "Insert Habit Name" : currentHabit.name)
                    .font(.custom("EB Garamond", size: cardWidth * 0.09).weight(.medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                // Recipient display (if exists)
                if let recipientName = currentHabit.getRecipientName() {
                    HStack(spacing: cardWidth * 0.015) {
                        Image(systemName: "person.fill")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))
                            .foregroundColor(.white.opacity(0.7))
                        Text(recipientName)
                            .font(.custom("EB Garamond", size: cardWidth * 0.055))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
                
                // Subtitle
                Text("\(healthDisplayName) habit.")
                    .font(.custom("EB Garamond", size: cardWidth * 0.055))
                    .italic()
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                
                Spacer(minLength: cardHeight * 0.08)
                
                // Progress section
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .frame(width: geometry.size.width * min(progressPercentage / 100, 1.0), height: 6)
                                .animation(.easeInOut(duration: 0.8), value: progressPercentage)
                        }
                    }
                    .frame(height: 6)
                    
                    // Current/Target display
                    Text("\(formatValue(currentValue)) / \(formatValue(currentHabit.healthTargetValue ?? 0))")
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, cardWidth * 0.15)
                
                // Verification button (only show when target is reached and not verified)
                if canVerify {
                    Button(action: {
                        // Flip to verification view
                        onExpand()
                    }) {
                        Text("verify")
                            .font(.custom("EB Garamond", size: cardWidth * 0.065))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: cardHeight * 0.11)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .disabled(isVerifying)
                    .padding(.horizontal, cardWidth * 0.3)
                    .padding(.top, cardHeight * 0.03)
                    .padding(.bottom, cardHeight * 0.18)
                } else {
                    Spacer().frame(height: cardHeight * 0.24)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .padding(.top, cardHeight * 0.1)
            
            // Progress percentage in bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: cardWidth * 0.01) {
                        if isLoading {
                            Text("loading...")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.6))
                        } else if isVerifiedToday {
                            Text("✅ verified today")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Text("\(Int(progressPercentage))% complete")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(.white.opacity(0.6))
                            Image(systemName: progressPercentage >= 100 ? "checkmark.circle.fill" : "circle")
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                                .foregroundColor(progressPercentage >= 100 ? .white : .white.opacity(0.6))
                        }
                    }
                    .padding(.trailing, cardWidth * 0.05)
                    .padding(.bottom, cardHeight * 0.075)
                }
            }
            
            // View details button in top right
            Button(action: {
                showingDetailView = true
                Task {
                    await FriendsManager.shared.preloadFriendsWithStripeConnect()
                }
            }) {
                HStack(spacing: 4) {
                    Text("view details")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.right")
                        .font(.system(size: cardWidth * 0.03, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .offset(x: -cardWidth * 0.08, y: cardHeight * 0.08)
        }
        .sheet(isPresented: $showingDetailView) {
            HabitDetailView(habit: currentHabit, habitManager: habitManager)
        }
        .onAppear {
            loadHealthData()
        }
        .onChange(of: habitManager.habits) { oldValue, newValue in
            loadHealthData()
        }
    }
    
    // MARK: - Computed Properties
    
    private var healthIcon: String {
        switch currentHabit.habitType {
        case "health_steps": return "figure.walk"
        case "health_walking_running_distance": return "figure.run"
        case "health_flights_climbed": return "figure.stairs"
        case "health_exercise_minutes": return "heart.fill"
        case "health_cycling_distance": return "bicycle"
        case "health_sleep_hours": return "bed.double.fill"
        case "health_calories_burned": return "flame.fill"
        case "health_mindful_minutes": return "brain.head.profile"
        default: return "heart.fill"
        }
    }
    
    private var healthDisplayName: String {
        switch currentHabit.habitType {
        case "health_steps": return "steps"
        case "health_walking_running_distance": return "distance"
        case "health_flights_climbed": return "flights climbed"
        case "health_exercise_minutes": return "exercise"
        case "health_cycling_distance": return "cycling"
        case "health_sleep_hours": return "sleep"
        case "health_calories_burned": return "calories"
        case "health_mindful_minutes": return "mindfulness"
        default: return "health"
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatValue(_ value: Double) -> String {
        let unit = currentHabit.healthTargetUnit ?? ""
        
        switch unit {
        case "steps":
            return "\(Int(value)) \(unit)"
        case "flights", "minutes", "calories":
            return "\(Int(value)) \(unit)"
        case "miles", "liters", "hours":
            return String(format: "%.1f %@", value, unit)
        case "bpm":
            return "\(Int(value)) \(unit)"
        default:
            return String(format: "%.1f %@", value, unit)
        }
    }
    
    private func loadHealthData() {
        let healthKitManager = HealthKitManager.shared
        
        Task {
            do {
                let realCurrentValue: Double
                
                switch currentHabit.habitType {
                case "health_steps":
                    realCurrentValue = try await healthKitManager.getTodaySteps()
                case "health_walking_running_distance":
                    realCurrentValue = try await healthKitManager.getTodayWalkingRunningDistance()
                case "health_flights_climbed":
                    realCurrentValue = try await healthKitManager.getTodayFlightsClimbed()
                case "health_exercise_minutes":
                    realCurrentValue = try await healthKitManager.getTodayExerciseMinutes()
                case "health_cycling_distance":
                    realCurrentValue = try await healthKitManager.getTodayCyclingDistance()
                case "health_sleep_hours":
                    realCurrentValue = try await healthKitManager.getLastNightSleepHours()
                case "health_calories_burned":
                    realCurrentValue = try await healthKitManager.getTodayCaloriesBurned()
                case "health_mindful_minutes":
                    realCurrentValue = try await healthKitManager.getTodayMindfulMinutes()
                default:
                    realCurrentValue = 0
                }
                
                await MainActor.run {
                    let target = currentHabit.healthTargetValue ?? 1
                    self.currentValue = realCurrentValue
                    self.progressPercentage = min(100, (realCurrentValue / target) * 100)
                    self.isLoading = false
                }
                
                print("✅ HealthUnifiedCardContent loaded real data for \(currentHabit.habitType): \(realCurrentValue)/\(currentHabit.healthTargetValue ?? 0)")
                
            } catch {
                print("⚠️ HealthKit data loading failed for \(currentHabit.habitType): \(error)")
                await MainActor.run {
                    simulateHealthData()
                }
            }
        }
    }
    
    private func simulateHealthData() {
        let target = currentHabit.healthTargetValue ?? 1
        currentValue = Double.random(in: 0...(target * 0.8))
        progressPercentage = min(100, (currentValue / target) * 100)
        isLoading = false
        print("⚠️ HealthUnifiedCardContent using simulated data for \(currentHabit.habitType): \(currentValue)/\(target)")
    }
} 