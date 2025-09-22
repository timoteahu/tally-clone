////
//  HabitTypeSelection.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Step 1 of Add Habit wizard – habit type selection.
//

import SwiftUI

extension AddHabitRoot {
    struct HabitTypeSelectionStep: View {
        var body: some View {
            Text("Habit Type Selection – placeholder")
        }
    }
}

// MARK: - Habit Categories

enum HabitCategory: String, CaseIterable, Identifiable {
    case photo = "photo"
    case health = "health" 
    case api = "api"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .photo: return "photo"
        case .health: return "health"
        case .api: return "other"
        }
    }
    
    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .health: return "heart.fill"
        case .api: return "network"
        }
    }
    
    var description: String {
        switch self {
        case .photo: return "Habits verified with photos"
        case .health: return "Track with Apple Health data (steps, exercise, sleep, and more)"
        case .api: return "Automatically tracked via apps"
        }
    }
}

// MARK: - Display Habit Type for UI

enum DisplayHabitType: String, CaseIterable, Identifiable {
    // Photo verification habits
    case gym = "gym"
    case alarm = "alarm"
    case yoga = "yoga"
    case outdoors = "outdoors"
    case cycling = "cycling"
    case cooking = "cooking"
    case custom = "custom"
    
    // Apple Health habits
    case health_steps = "health_steps"
    case health_walking_running_distance = "health_walking_running_distance"
    case health_flights_climbed = "health_flights_climbed"
    case health_exercise_minutes = "health_exercise_minutes"
    case health_cycling_distance = "health_cycling_distance"
    case health_sleep_hours = "health_sleep_hours"
    case health_calories_burned = "health_calories_burned"
    case meditation = "health_mindful_minutes" // Renamed from mindful_minutes
    
    // API integration habits
    case github_commits = "github_commits"
    case leetcode = "leetcode"
    case league_of_legends = "league_of_legends"
    case valorant = "valorant"
    
    var id: String { rawValue }
    
    var category: HabitCategory {
        switch self {
        case .gym, .alarm, .yoga, .outdoors, .cycling, .cooking, .custom:
            return .photo
        case .health_steps, .health_walking_running_distance, .health_flights_climbed,
             .health_exercise_minutes, .health_cycling_distance, .health_sleep_hours,
             .health_calories_burned, .meditation:
            return .health
        case .github_commits, .leetcode, .league_of_legends, .valorant:
            return .api
        }
    }
    
    var displayName: String {
        switch self {
        case .gym: return "gym"
        case .alarm: return "alarm"
        case .outdoors: return "outdoors"
        case .github_commits: return "github commits"
        case .leetcode: return "leetcode problems"
        case .league_of_legends: return "league of legends"
        case .valorant: return "valorant"
        // Apple Health habit types
        case .health_steps: return "steps"
        case .health_walking_running_distance: return "walking + running"
        case .health_flights_climbed: return "flights climbed"
        case .health_exercise_minutes: return "exercise minutes"
        case .health_cycling_distance: return "cycling distance"
        case .health_sleep_hours: return "sleep"
        case .health_calories_burned: return "calories burned"
        case .meditation: return "meditation"
        case .custom: return "custom"
        case .yoga: return "yoga"
        case .cycling: return "cycling"
        case .cooking: return "cooking"
            
        }
    }
    
    var icon: String {
        HabitIconProvider.iconName(for: rawValue)
    }
    
    /// Filled variant of the icon used elsewhere in the app (e.g., front of feed cards).
    var filledIcon: String {
        HabitIconProvider.iconName(for: rawValue, variant: .filled)
    }
    
    // Convert to existing HabitType for compatibility
    var toHabitType: HabitType? {
        switch self {
        case .gym: return .gym
        case .alarm: return .alarm
        case .yoga: return .yoga
        case .outdoors: return .outdoors
        case .cycling: return .cycling
        case .cooking: return .cooking
        case .github_commits: return nil // handled separately
        case .leetcode: return nil // handled separately
        case .league_of_legends: return .league_of_legends
        case .valorant: return .valorant
        // Apple Health habit types
        case .health_steps: return .health_steps
        case .health_walking_running_distance: return .health_walking_running_distance
        case .health_flights_climbed: return .health_flights_climbed
        case .health_exercise_minutes: return .health_exercise_minutes
        case .health_cycling_distance: return .health_cycling_distance
        case .health_sleep_hours: return .health_sleep_hours
        case .health_calories_burned: return .health_calories_burned
        case .meditation: return .health_mindful_minutes
        case .custom: return nil
        }
    }
    
    // Create from existing HabitType
    static func from(habitType: HabitType) -> DisplayHabitType {
        switch habitType {
        case .gym: return .gym
        case .alarm: return .alarm
        case .yoga: return .yoga
        case .outdoors: return .outdoors
        case .cycling: return .cycling
        case .cooking: return .cooking
        case .league_of_legends: return .league_of_legends
        case .valorant: return .valorant
        // Apple Health habit types
        case .health_steps: return .health_steps
        case .health_walking_running_distance: return .health_walking_running_distance
        case .health_flights_climbed: return .health_flights_climbed
        case .health_exercise_minutes: return .health_exercise_minutes
        case .health_cycling_distance: return .health_cycling_distance
        case .health_sleep_hours: return .health_sleep_hours
        case .health_calories_burned: return .health_calories_burned
        case .health_mindful_minutes: return .meditation
        }
    }
    
    var isHealthHabit: Bool {
        category == .health
    }
    
    var requiresAppleWatch: Bool {
        switch self {
        case .health_calories_burned, .health_exercise_minutes, .health_sleep_hours:
            return true // These work much better with Apple Watch
        case .health_steps, .health_walking_running_distance, .health_flights_climbed:
            return false // iPhone can track these reasonably well
        case .health_cycling_distance, .meditation:
            return false // These are often manual entry or third-party apps
        default:
            return false
        }
    }
}

// MARK: - Habit Type Tile Component

struct HabitTypeTile: View {
    let habitType: DisplayHabitType
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        Button(action: {
            // Add haptic feedback on tap
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 16) {
                // Icon: use SF Symbol for special tiles and health habits, images for built-ins
                if habitType == .custom {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                } else if habitType == .github_commits || habitType == .leetcode || habitType == .league_of_legends || habitType == .valorant {
                    Image(habitType.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white)
                } else if habitType.isHealthHabit {
                    // Use proper SF Symbols for health habits
                    Image(systemName: healthIconForHabitType(habitType))
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                } else {
                    Image(habitType.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white)
                        .scaleEffect(1.3)
                }
                Text(habitType.displayName)
                    .font(.custom("EBGaramond-Regular", size: 22))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                    )
            )
            .overlay(
                // Device requirement badge for health habits - positioned within the card
                deviceRequirementBadge,
                alignment: .topTrailing
            )
            .contentShape(Rectangle()) // Expand tap target to full visual bounds
        }
        .buttonStyle(PlainButtonStyle()) // Use plain button style to avoid conflicts
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(
            .easeInOut(duration: 0.1),
            value: isPressed
        )
        .animation(
            .spring(response: 0.3, dampingFraction: 0.9),
            value: isSelected
        )
        .onLongPressGesture(
            minimumDuration: 0.5,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
                if habitType == .custom && pressing {
                    onLongPress?()
                }
            },
            perform: {}
        )
        .accessibilityLabel(habitType.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(habitType == .custom ? "Tap to select, long press to create custom habit" : "Tap to select")
    }
    
    // Helper function to get proper SF Symbol for health habits
    private func healthIconForHabitType(_ habitType: DisplayHabitType) -> String {
        switch habitType {
        case .health_steps:
            return "figure.walk"
        case .health_walking_running_distance:
            return "figure.run"
        case .health_flights_climbed:
            return "figure.stairs"
        case .health_exercise_minutes:
            return "heart.circle"
        case .health_cycling_distance:
            return "bicycle"
        case .health_sleep_hours:
            return "bed.double"
        case .health_calories_burned:
            return "flame"
        case .meditation:
            return "brain.head.profile"
        default:
            return "heart.fill"
        }
    }
    
    @ViewBuilder
    private var deviceRequirementBadge: some View {
        if habitType.isHealthHabit {
            HStack(spacing: 4) {
                if habitType.requiresAppleWatch {
                    Image(systemName: "applewatch")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("Watch")
                        .font(.custom("EBGaramond-Regular", size: 10))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "iphone")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("iPhone")
                        .font(.custom("EBGaramond-Regular", size: 10))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }
}

// MARK: - Custom Habit Type Tile

struct CustomHabitTypeTile: View {
    let customHabit: CustomHabitType
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?
    
    @GestureState private var isLongPressing = false
    @State private var isProcessingGesture = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        VStack(spacing: 16) {
            Image("custom")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.white)
            Text(customHabit.displayName)
                .font(.custom("EBGaramond-Regular", size: 22))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? Color.white : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isLongPressing)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isSelected)
        .onTapGesture {
            guard !isProcessingGesture else { return }
            HapticFeedbackManager.shared.mediumImpact()
            onTap()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .updating($isLongPressing) { currentState, gestureState, _ in
                    gestureState = currentState
                }
                .onEnded { _ in
                    guard let longPress = onLongPress else { return }
                    isProcessingGesture = true
                    HapticFeedbackManager.shared.mediumImpact()
                    longPress()
                    
                    // Reset the processing flag after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isProcessingGesture = false
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(customHabit.displayName)
        .accessibilityAddTraits([.isButton, isSelected ? .isSelected : []])
        .accessibilityHint(onLongPress != nil ? "Tap to select, long press to delete" : "Tap to select")
        .accessibilityAction {
            // For VoiceOver users, perform tap action
            onTap()
        }
    }
}

// MARK: - Custom Habit Pill Button

struct CustomHabitPillButton: View {
    let onTap: () -> Void
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        Button(action: {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.18, dampingFraction: 0.7)) {
                isPressed = true
            }
            HapticFeedbackManager.shared.lightImpact()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.18, dampingFraction: 0.7)) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(NSLocalizedString("custom", comment: "Custom habit button label"))
                    .font(.custom("EBGaramond-Regular", size: 22))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("Create custom habit")
                    .accessibilityHint("Tap to create a custom habit.")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.clear)
                    )
            )
        }
        .scaleEffect(isPressed ? 1.07 : 1.0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.18, dampingFraction: 0.7), value: isPressed)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Category Pill Component

struct CategoryPill: View {
    let category: HabitCategory
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .black : .white)
                
                Text(category.displayName)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(isSelected ? .black : .white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Main Habit Type Selection View

struct HabitTypeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var customHabitManager: CustomHabitManager
    @Binding var selectedHabitType: String
    @Binding var selectedCustomHabitTypeId: String?
    @State private var selectedTypes: Set<DisplayHabitType> = []
    @State private var selectedCategory: HabitCategory = .photo // Default to photo category
    @State private var showingCreateCustomType = false
    @State private var showContinueButton = false
    @State private var customHabitToDelete: CustomHabitType?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletionError = false
    @State private var deletionErrorMessage = ""
    
    // Connection status states
    @State private var githubConnected = false
    @State private var leetCodeConnected = false
    @State private var showConnectionAlert = false
    @State private var connectionAlertTitle = ""
    @State private var connectionAlertMessage = ""
    
    let isOnboarding: Bool
    var embeddedInWizard: Bool = false
    var onDone: (() -> Void)? = nil
    
    // MARK: - Background Gradient
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color(hex: "161C29"), location: 0.0),
                .init(color: Color(hex: "131824"), location: 0.15),
                .init(color: Color(hex: "0F141F"), location: 0.3),
                .init(color: Color(hex: "0C111A"), location: 0.45),
                .init(color: Color(hex: "0A0F17"), location: 0.6),
                .init(color: Color(hex: "080D15"), location: 0.7),
                .init(color: Color(hex: "060B12"), location: 0.8),
                .init(color: Color(hex: "03070E"), location: 0.9),
                .init(color: Color(hex: "01050B"), location: 1.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    var body: some View {
        ZStack {
            // Use the same background as DetailsForm and other views
            backgroundGradient
            
            VStack(spacing: 0) {
                // Wizard header - same as DetailsForm
                wizardHeader
                
                // Title below the header - centered
                Text("pick a habit")
                    .font(.custom("EBGaramond-Regular", size: 32))
                    .foregroundColor(.white)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                
                // Category picker
                categoryPicker
                
                // Content in scrollable area with improved performance
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            categoryInfoBanner
                            .padding(.bottom, 20)
                            
                            habitSelectionGrid
                            if selectedCategory == .photo {
                                customHabitButton
                            }
                            // Add bottom padding to ensure last items are scrollable
                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                    }
                    .scrollContentBackground(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.immediately)
                }
                
                // Continue button - translucent when no selection, opaque when selected
                Button(action: {
                    handleContinue()
                }) {
                    Text("next")
                        .font(.ebGaramond(size: 17))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .opacity(showContinueButton ? 1.0 : 0.3)
                .disabled(!showContinueButton)
                .animation(.easeInOut(duration: 0.2), value: showContinueButton)
            }
        }
        .sheet(isPresented: $showingCreateCustomType) {
            CreateCustomHabitTypeView()
                .environmentObject(customHabitManager)
        }
        .alert("Delete Custom Habit?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                customHabitToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let habitToDelete = customHabitToDelete {
                    deleteCustomHabit(habitToDelete)
                }
            }
        } message: {
            if let habit = customHabitToDelete {
                Text("Are you sure you want to permanently delete \"\(habit.displayName)\"? This action cannot be undone.")
            }
        }
        .alert("Cannot Delete Custom Habit", isPresented: $showingDeletionError) {
            Button("OK", role: .cancel) {
                deletionErrorMessage = ""
            }
        } message: {
            Text(deletionErrorMessage)
        }
        .onAppear {
            initializeSelection()
            checkConnectionStatuses()
            // If custom habit types are not yet loaded, fetch them silently
            if customHabitManager.customHabitTypes.isEmpty,
               let token = AuthenticationManager.shared.storedAuthToken {
                Task {
                    try? await customHabitManager.fetchCustomHabitTypes(token: token)
                }
            }
        }
        .alert(isPresented: $showConnectionAlert) {
            Alert(
                title: Text(connectionAlertTitle),
                message: Text(connectionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: customHabitManager.customHabitTypes) { oldValue, _ in
            // Refresh selection once custom habits load (e.g., after creating a new one)
            if selectedHabitType.hasPrefix("custom_"), selectedCustomHabitTypeId == nil {
                initializeSelection()
            }
        }
        .onChange(of: selectedTypes) { oldValue, _ in
            updateContinueButtonState()
        }
        .onChange(of: selectedCustomHabitTypeId) { oldValue, _ in
            updateContinueButtonState()
        }
        .onChange(of: selectedCategory) { oldValue, _ in
            // Clear selection when category changes
            selectedTypes.removeAll()
            selectedCustomHabitTypeId = nil
            updateContinueButtonState()
        }
    }
    
    // MARK: - Category Picker
    private var categoryPicker: some View {
        VStack(spacing: 12) {
            // Category selection pills
            HStack(spacing: 12) {
                ForEach(HabitCategory.allCases) { category in
                    CategoryPill(
                        category: category,
                        isSelected: selectedCategory == category,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            

        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Category Info Banner
    private var categoryInfoBanner: some View {
        Group {
            if selectedCategory == .health {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        Text("apple health integration")
                            .font(.custom("EBGaramond-Bold", size: 16))
                            .foregroundColor(.green)
                    }
                    Text("this app connects with apple healthkit to automatically track your health habits.")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                // background removed
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else if selectedCategory == .photo {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                        Text("photo verification")
                            .font(.custom("EBGaramond-Bold", size: 16))
                            .foregroundColor(.blue)
                    }
                    Text("complete your habit by uploading a photo as proof of the activity you've committed to.")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                // background removed
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } else if selectedCategory == .api {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                        Text("external account connection")
                            .font(.custom("EBGaramond-Bold", size: 16))
                            .foregroundColor(.orange)
                    }
                    Text("these habits require connecting external accounts to automatically track your progress.")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                // background removed
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Habit Selection Grid
    private var habitSelectionGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 20) {
            // Filter habits by selected category
            ForEach(habitsForCurrentCategory) { habitType in
                HabitTypeTile(
                    habitType: habitType,
                    isSelected: selectedTypes.contains(habitType),
                    onTap: { handleTileSelection(habitType) },
                    onLongPress: nil
                )
                .overlay(
                    // Lock icon overlay for unconnected accounts
                    lockOverlay(for: habitType),
                    alignment: .topTrailing
                )
            }
            // Dynamic custom habit types – only for photo category
            if selectedCategory == .photo && !customHabitManager.customHabitTypes.isEmpty {
                ForEach(customHabitManager.customHabitTypes) { custom in
                    CustomHabitTypeTile(
                        customHabit: custom,
                        isSelected: selectedCustomHabitTypeId == custom.id,
                        onTap: { handleCustomTileSelection(custom) },
                        onLongPress: { 
                            customHabitToDelete = custom
                            showingDeleteConfirmation = true
                            HapticFeedbackManager.shared.mediumImpact()
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .animation(nil, value: selectedCategory)
    }
    
    // MARK: - Computed Properties
    private var habitsForCurrentCategory: [DisplayHabitType] {
        DisplayHabitType.allCases.filter { habitType in
            habitType.category == selectedCategory && 
            habitType != .custom &&
            habitType != .league_of_legends &&  // Filter out League of Legends
            habitType != .valorant &&  // Filter out Valorant
            habitType != .yoga &&  // Filter out pilates
            habitType != .cycling &&  // Filter out biking
            habitType != .cooking  // Filter out cooking
        }
    }
    
    // MARK: - Custom Habit Button
    private var customHabitButton: some View {
        VStack {
            Spacer().frame(height: 6)
            HStack {
                Spacer()
                CustomHabitPillButton(
                    onTap: { showingCreateCustomType = true }
                )
                .frame(width: 220)
                Spacer()
            }
            Spacer().frame(height: 12)
        }
    }
    
    // MARK: - Header
    private var wizardHeader: some View {
        HStack {
            Spacer()

            // Down arrow (dismisses overlay)
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
            }) {
                Image(systemName: "chevron.down")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .offset(x: -2, y: 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private func initializeSelection() {
        guard !selectedHabitType.isEmpty else { return }

        if selectedHabitType.hasPrefix("custom_") {
            // Extract identifier & pre-select corresponding custom type
            let identifier = String(selectedHabitType.dropFirst("custom_".count))
            if let match = customHabitManager.customHabitTypes.first(where: { $0.typeIdentifier == identifier }) {
                selectedCustomHabitTypeId = match.id
                selectedHabitType = "custom_\(identifier)"
            }
            selectedTypes.insert(.custom)
        } else if let habitType = HabitType(rawValue: selectedHabitType) {
            let displayType = DisplayHabitType.from(habitType: habitType)
            selectedTypes.insert(displayType)
        }
        updateContinueButtonState()
    }
    
    private func handleTileSelection(_ habitType: DisplayHabitType) {
        // Check if GitHub or LeetCode is selected without connection
        if habitType == .github_commits && !githubConnected {
            connectionAlertTitle = "GitHub Not Connected"
            connectionAlertMessage = "You need to connect your GitHub account first. Go to Profile > Connections to connect your GitHub account."
            showConnectionAlert = true
            return
        }
        
        if habitType == .leetcode && !leetCodeConnected {
            connectionAlertTitle = "LeetCode Not Connected"
            connectionAlertMessage = "You need to connect your LeetCode account first. Go to Profile > Connections to connect your LeetCode account."
            showConnectionAlert = true
            return
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            // Single selection mode
            selectedTypes.removeAll()
            selectedTypes.insert(habitType)
            // Clear any custom selection when choosing built-ins / generic custom tile
            if habitType != .custom {
                selectedCustomHabitTypeId = nil
                if habitType == .github_commits {
                    selectedHabitType = "github_commits"
                } else if habitType == .leetcode {
                    selectedHabitType = "leetcode"
                } else if habitType == .league_of_legends {
                    selectedHabitType = HabitType.league_of_legends.rawValue
                } else if habitType == .valorant {
                    selectedHabitType = HabitType.valorant.rawValue
                } else if let builtIn = habitType.toHabitType {
                    selectedHabitType = builtIn.rawValue
                }
            }
        }
        
        // Medium haptic feedback for selection
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func handleCustomTileSelection(_ custom: CustomHabitType) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedTypes.removeAll()
            selectedTypes.insert(.custom)
            selectedCustomHabitTypeId = custom.id
            // Store full habit type string so it's ready on continue
            selectedHabitType = "custom_\(custom.typeIdentifier)"
        }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    private func handleContinue() {
        if let firstSelected = selectedTypes.first {
            if firstSelected == .custom {
                // If a specific custom type chosen, keep pre-filled selectedHabitType. Otherwise block.
                guard selectedCustomHabitTypeId != nil else { return }
            } else if firstSelected == .github_commits {
                selectedHabitType = "github_commits"
                selectedCustomHabitTypeId = nil
            } else if firstSelected == .leetcode {
                selectedHabitType = "leetcode"
                selectedCustomHabitTypeId = nil
            } else if let habitType = firstSelected.toHabitType {
                selectedHabitType = habitType.rawValue
                selectedCustomHabitTypeId = nil
            }
        }
        
        if embeddedInWizard {
            onDone?()
        } else {
            dismiss()
        }
    }
    
    private func updateContinueButtonState() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if selectedTypes.contains(.custom) {
                showContinueButton = selectedCustomHabitTypeId != nil
            } else {
                showContinueButton = !selectedTypes.isEmpty
            }
        }
    }
    
    private func deleteCustomHabit(_ habit: CustomHabitType) {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            print("No auth token available for deletion")
            return
        }
        
        Task {
            do {
                try await customHabitManager.deleteCustomHabitType(typeId: habit.id, token: token)
                
                // Clear selection if the deleted habit was selected
                await MainActor.run {
                    if selectedCustomHabitTypeId == habit.id {
                        selectedCustomHabitTypeId = nil
                        selectedTypes.remove(.custom)
                        selectedHabitType = ""
                    }
                    customHabitToDelete = nil
                    
                    // Haptic feedback for successful deletion
                    HapticFeedbackManager.shared.playQuickConfirmation()
                }
            } catch let customError as CustomHabitError {
                print("Failed to delete custom habit: \(customError)")
                await MainActor.run {
                    customHabitToDelete = nil
                    
                    switch customError {
                    case .serverError(let message):
                        // Check if it's the "in use" error
                        if message.contains("currently used by active habits:") {
                            // Extract habit names from error message
                            if let habitNameStart = message.range(of: "active habits: ") {
                                let habitNames = String(message[habitNameStart.upperBound...])
                                deletionErrorMessage = "This custom habit type cannot be deleted because you have active habits using it: \(habitNames). Please delete or change those habits first."
                            } else {
                                deletionErrorMessage = "This custom habit type cannot be deleted because it's currently being used by one or more active habits."
                            }
                        } else {
                            deletionErrorMessage = message
                        }
                    case .networkError:
                        deletionErrorMessage = "Network error. Please check your connection and try again."
                    case .validationError(let message):
                        deletionErrorMessage = message
                    case .premiumRequired(let message):
                        deletionErrorMessage = message
                    }
                    
                    showingDeletionError = true
                    
                    // Error haptic feedback
                    HapticFeedbackManager.shared.heavyImpact()
                }
            } catch {
                print("Unexpected error deleting custom habit: \(error)")
                await MainActor.run {
                    customHabitToDelete = nil
                    deletionErrorMessage = "An unexpected error occurred. Please try again."
                    showingDeletionError = true
                    HapticFeedbackManager.shared.heavyImpact()
                }
            }
        }
    }
    
    // MARK: - Connection Status Check
    private func checkConnectionStatuses() {
        // Check GitHub status from UserDefaults cache
        if let githubStatus = UserDefaults.standard.string(forKey: "cachedGithubStatus") {
            githubConnected = (githubStatus == "connected")
        }
        
        // Check LeetCode status from UserDefaults cache
        if let leetCodeStatus = UserDefaults.standard.string(forKey: "cachedLeetCodeStatus") {
            leetCodeConnected = (leetCodeStatus == "connected")
        }
        
        // Also fetch fresh status from managers
        Task {
            // Check GitHub status
            if let token = AuthenticationManager.shared.storedAuthToken {
                do {
                    guard let url = URL(string: "\(AppConfig.baseURL)/github/status") else { return }
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                        struct GitHubStatusResponse: Codable { let status: String }
                        let decoded = try JSONDecoder().decode(GitHubStatusResponse.self, from: data)
                        await MainActor.run {
                            githubConnected = (decoded.status == "connected")
                        }
                    }
                } catch {
                    print("Error checking GitHub status: \(error)")
                }
            }
            
            // Check LeetCode status
            await LeetCodeManager.shared.checkStatus()
            await MainActor.run {
                leetCodeConnected = (LeetCodeManager.shared.connectionStatus == .connected)
            }
        }
    }
    
    // MARK: - Lock Overlay
    @ViewBuilder
    private func lockOverlay(for habitType: DisplayHabitType) -> some View {
        if (habitType == .github_commits && !githubConnected) ||
           (habitType == .leetcode && !leetCodeConnected) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 28, height: 28)
                )
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    HabitTypeSelectionView(
        selectedHabitType: .constant(""),
        selectedCustomHabitTypeId: .constant(nil),
        isOnboarding: false
    )
    .environmentObject(CustomHabitManager.shared)
} 
