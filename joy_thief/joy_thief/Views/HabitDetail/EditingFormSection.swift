////
//  EditingFormSection.swift
//  joy_thief
//
//  Extracted editing form from HabitDetailView.
//

import SwiftUI

extension HabitDetailRoot {
    struct EditingFormSection: View {
        let habit: Habit
        @EnvironmentObject var friendsManager: FriendsManager
        
        // Dropdown UI state
        @State private var showingFriendsDropdown: Bool = false
        @State private var partnerSearchText: String = ""
        
        // Focus state for keyboard dismissal
        @FocusState private var isInputFocused: Bool
        @FocusState private var isGitHubCommitFocused: Bool
        @FocusState private var isPenaltyFocused: Bool
        @FocusState private var isHealthTargetFocused: Bool
        
        // Bindings for all editable fields
        @Binding var editedName: String
        @Binding var editedRecipientId: String?
        @Binding var editedWeekdays: [Int]
        @Binding var editedPenaltyAmount: Float
        @Binding var editedIsPrivate: Bool
        @Binding var editedAlarmTime: Date
        @Binding var editedWeeklyTarget: Int
        @Binding var editedWeekStartDay: Int
        @Binding var editedDailyLimitHours: Double
        @Binding var editedHourlyPenaltyRate: Double
        
        // Health-specific bindings
        @Binding var editedHealthTargetValue: Double
        @Binding var editedHealthTargetUnit: String
        
        // GitHub-specific bindings
        @Binding var editedCommitTarget: Int
        
        let errorMessage: String
        
        // Static weekdays array for quick reference
        private let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        
        private var habitTypeDisplayName: String {
            if let enumType = HabitType(rawValue: habit.habitType) {
                return enumType.displayName
            } else if habit.habitType == "github_commits" {
                return "GitHub Commits"
            } else if habit.isCustomHabit {
                return "custom"
            }
            return habit.habitType
        }
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // --- Editable Habit Title ---
                        TextField("insert habit name", text: $editedName, prompt: Text("insert habit name").foregroundColor(.white.opacity(0.4)))
                            .font(.ebGaramondTitle)
                            .textCase(.lowercase)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .focused($isInputFocused)
                        
                        // --- Schedule preview row matching detail styling ---
                        schedulePreviewSection
                            .id("scheduleSection") // ID for GitHub sections
                        
                        // --- Alarm Time (if applicable) ---
                        if habit.isAlarmHabit {
                            alarmTimeSection
                        }

                        // --- Accountability Partner Picker ---
                        accountabilityPartnerSection
                        
                        // --- Habit-Specific Sections ---
                        habitSpecificSections
                            .id("habitSpecific") // ID for scrolling to penalty sections
                        
                        // --- Error Display ---
                        if !errorMessage.isEmpty {
                            errorDisplay
                        }
                    }
                    .padding(.vertical, 24)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                    KeyboardUtils.dismiss()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    // Add small delay to ensure focus states are updated before scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Smart scrolling based on which field is focused
                        if isGitHubCommitFocused {
                            // For GitHub fields, scroll to schedule section to keep them visible
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("scheduleSection", anchor: .top)
                            }
                        } else if isPenaltyFocused {
                            // For penalty fields, scroll to penalty section
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("habitSpecific", anchor: .top)
                            }
                        } else if !isHealthTargetFocused {
                            // For other fields (but not health fields), scroll to penalty section
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("habitSpecific", anchor: .top)
                            }
                        }
                        // For health target fields, don't auto-scroll (they're already in a good position)
                    }
                }
            }
        }
        
        // MARK: - Sub-Views & Helpers ----------------------------------------------------
        
        private var schedulePreviewSection: some View {
            VStack(alignment: .leading, spacing: 6) {
                // Days or Amount label - hide for gaming habits and GitHub habits
                if habit.habitType != "league_of_legends" && habit.habitType != "valorant" && habit.habitType != "github_commits" {
                    Text(habit.isWeeklyHabit ? "amount" : "days")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                }
                
                if habit.isWeeklyHabit {
                    if let first = editedWeekdays.first {
                        Text("every \(weekdays[first])")
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 8)
                            .padding(.leading, 8)
                    }
                } else if !editedWeekdays.isEmpty {
                    let daysString = editedWeekdays.sorted().map { weekdays[$0] }.joined(separator: ", ")
                    Text(daysString)
                        .font(.custom("EBGaramond-Regular", size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 8)
                }

                // Don't show frequency editors for gaming habits and GitHub habits
                if habit.habitType != "league_of_legends" && habit.habitType != "valorant" && habit.habitType != "github_commits" {
                    if habit.isWeeklyHabit {
                        WeeklyScheduleEditor(editedWeeklyTarget: $editedWeeklyTarget, editedWeekStartDay: $editedWeekStartDay, habitTypeDisplayName: habitTypeDisplayName)
                    } else {
                        DailyScheduleEditor(editedWeekdays: $editedWeekdays, habitTypeDisplayName: habitTypeDisplayName)
                    }
                }
                
                Text("habit")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.top, 16)
                HStack(alignment: .top, spacing: 8) {
                    Text(habitTypeDisplayName.lowercased())
                        .font(.custom("EBGaramond-Regular", size: 20))
                        .foregroundColor(.white.opacity(0.8))
                    
                    if habit.isAlarmHabit {
                        Text("by \(formattedAlarmTime(editedAlarmTime))")
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 24)
        }
        
        @ViewBuilder
        private var habitSpecificSections: some View {
            // Health habits - show target configuration
            if habit.isHealthHabit {
                healthTargetSection
            }
            
            // GitHub habits - show commit target
            if habit.habitType == "github_commits" {
                githubCommitTargetSection
            }
            
            // Gaming habits - show limits and penalties
            if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                gamingLimitSection
            }
            
            // Penalty amount section - show for health, GitHub, and regular habits
            // Gaming habits use hourly penalty rate instead of fixed penalty amount
            if habit.habitType != "league_of_legends" && habit.habitType != "valorant" {
                penaltyAmountSection
            }
        }
        
        private var accountabilityPartnerSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("recipient")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.leading, -2)
                if friendsManager.preloadedFriendsWithStripeConnect.isEmpty {
                    noFriendsView
                } else {
                    partnerPickerMenu
                }
            }
            .padding(.horizontal, 20)
        }
        
        private var noFriendsView: some View {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "person.slash").font(.custom("EBGaramond-Regular", size: 20)).foregroundColor(.white.opacity(0.6)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No friends available")
                            .jtStyle(.body)
                            .foregroundColor(.white.opacity(0.8))
                        Text("No friends with Stripe Connect found")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                Text("💳 Accountability partners need Stripe Connect set up to receive penalty payments")
                    .jtStyle(.caption)
                    .foregroundColor(.orange.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        
        private var partnerPickerMenu: some View {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingFriendsDropdown.toggle()
                    }
                }) {
                    HStack {
                        Text(selectedFriendName)
                            .font(.custom(selectedFriendName == "recipient" ? "EBGaramond-Italic" : "EBGaramond-Regular", size: 16))
                            .foregroundColor(selectedFriendName == "RECIPIENT" ? .white.opacity(0.7) : .white)
                        Spacer()
                        Image(systemName: showingFriendsDropdown ? "chevron.up" : "chevron.down")
                            .font(.custom("EBGaramond-Regular", size: 24))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(height: 70)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                if showingFriendsDropdown {
                    dropdownContent
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        
        private var dropdownContent: some View {
            Group {
                if friendsManager.preloadedFriendsWithStripeConnect.isEmpty {
                    Text("No friends with Stripe Connect found")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if editedRecipientId != nil {
                            Button(action: {
                                editedRecipientId = nil
                                showingFriendsDropdown = false
                            }) {
                                Text("Remove Partner")
                                    .font(.custom("EBGaramond-Regular", size: 18))
                                    .foregroundColor(.red)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 18)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            Divider().background(Color.white.opacity(0.12))
                        }
                        ForEach(friendsManager.preloadedFriendsWithStripeConnect) { friend in
                            Button(action: {
                                editedRecipientId = friend.friendId
                                showingFriendsDropdown = false
                            }) {
                                HStack {
                                    Text(friend.name)
                                        .font(.custom("EBGaramond-Regular", size: 18))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if editedRecipientId == friend.friendId {
                                        Image(systemName: "checkmark").foregroundColor(.green)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(editedRecipientId == friend.friendId ? Color.white.opacity(0.10) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.95))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
                    )
                }
            }
        }
        
        private var selectedFriendName: String {
            if let id = editedRecipientId, let f = friendsManager.preloadedFriendsWithStripeConnect.first(where: { $0.friendId == id }) {
                return f.name.split(separator: " ").first.map(String.init) ?? f.name
            }
            return "RECIPIENT"
        }
        private var penaltyAmountSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("penalty per day")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.leading, -2)
                
                CurrencyTextField(
                    value: $editedPenaltyAmount,
                    range: 0.5...500,
                    step: 0.5,
                    quickSelectValues: [5, 10, 20, 25],
                    onFocusChange: { isFocused in
                        isPenaltyFocused = isFocused
                    }
                )
            }
            .padding(.horizontal, 20)
        }
        
        // MARK: - Health Target Section
        private var healthTargetSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("health target")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.leading, -2)
                
                // Use SegmentedNumberPicker for appropriate health types
                Group {
                    switch habit.habitType {
                    case "health_steps":
                        SegmentedNumberPicker(
                            value: $editedHealthTargetValue,
                            presets: [5000, 8000, 10000, 15000],
                            customRange: 1000...30000,
                            step: 500,
                            unit: editedHealthTargetUnit
                        )
                    case "health_walking_running_distance", "health_cycling_distance":
                        SegmentedNumberPicker(
                            value: $editedHealthTargetValue,
                            presets: [1, 3, 5, 10],
                            customRange: 0.5...20,
                            step: 0.5,
                            unit: editedHealthTargetUnit,
                            formatter: { String(format: "%.1f", $0) }
                        )
                    case "health_exercise_minutes", "health_mindful_minutes":
                        SegmentedNumberPicker(
                            value: $editedHealthTargetValue,
                            presets: habit.habitType == "health_exercise_minutes" ? [15, 30, 45, 60] : [10, 15, 20, 30],
                            customRange: habit.habitType == "health_exercise_minutes" ? 10...180 : 5...120,
                            step: 5,
                            unit: editedHealthTargetUnit
                        )
                    case "health_flights_climbed":
                        // Use StepperField for small range
                        StepperField(
                            value: Binding(
                                get: { Int(editedHealthTargetValue) },
                                set: { editedHealthTargetValue = Double($0) }
                            ),
                            range: 1...50,
                            label: editedHealthTargetUnit
                        )
                    case "health_calories_burned":
                        SegmentedNumberPicker(
                            value: $editedHealthTargetValue,
                            presets: [500, 750, 1000, 1500],
                            customRange: 100...2000,
                            step: 50,
                            unit: editedHealthTargetUnit
                        )
                    case "health_sleep_hours":
                        SegmentedNumberPicker(
                            value: $editedHealthTargetValue,
                            presets: [6, 7, 8, 9],
                            customRange: 4...12,
                            step: 0.5,
                            unit: editedHealthTargetUnit,
                            formatter: { String(format: "%.1f", $0) }
                        )
                    default:
                        // Fallback to original TextField for unknown types
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                TextField("Enter target", value: $editedHealthTargetValue, format: .number)
                                    .font(.custom("EBGaramond-Regular", size: 18))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                                    .focused($isHealthTargetFocused)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Unit")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(editedHealthTargetUnit)
                                    .font(.custom("EBGaramond-Regular", size: 18))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                            )
                                    )
                            }
                            .frame(width: 100)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        
        // MARK: - GitHub Commit Target Section
        private var githubCommitTargetSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text(habit.isWeeklyHabit ? "weekly commit goal" : "daily commit goal")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.leading, -2)
                
                // Clean stepper without background box
                HStack(spacing: 16) {
                    // Decrement button
                    Button(action: {
                        let range = habit.isWeeklyHabit ? 1...100 : 1...50
                        if editedCommitTarget > range.lowerBound {
                            editedCommitTarget -= 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(editedCommitTarget > (habit.isWeeklyHabit ? 1 : 1) ? .white : .white.opacity(0.3))
                    }
                    .disabled(editedCommitTarget <= (habit.isWeeklyHabit ? 1 : 1))
                    
                    Spacer()
                    
                    // Value display
                    VStack(spacing: 4) {
                        TextField("\(editedCommitTarget)", text: Binding(
                            get: { String(editedCommitTarget) },
                            set: { newValue in
                                if let intValue = Int(newValue.filter { $0.isNumber }), 
                                   intValue >= (habit.isWeeklyHabit ? 1 : 1) && 
                                   intValue <= (habit.isWeeklyHabit ? 100 : 50) {
                                    editedCommitTarget = intValue
                                }
                            }
                        ))
                            .font(.custom("EBGaramond-Regular", size: 32))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .focused($isGitHubCommitFocused)
                            .multilineTextAlignment(.center)
                        
                        Text("commit\(editedCommitTarget == 1 ? "" : "s") / \(habit.isWeeklyHabit ? "week" : "day")")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Increment button
                    Button(action: {
                        let range = habit.isWeeklyHabit ? 1...100 : 1...50
                        if editedCommitTarget < range.upperBound {
                            editedCommitTarget += 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(editedCommitTarget < (habit.isWeeklyHabit ? 100 : 50) ? .white : .white.opacity(0.3))
                    }
                    .disabled(editedCommitTarget >= (habit.isWeeklyHabit ? 100 : 50))
                }
                .padding(.horizontal, 16)
                
                // Quick select values
                if habit.isWeeklyHabit {
                    HStack(spacing: 12) {
                        Spacer()
                        ForEach([5, 10, 20, 30], id: \.self) { quickValue in
                            Button(action: {
                                editedCommitTarget = quickValue
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(quickValue)")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(editedCommitTarget == quickValue ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(editedCommitTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                    )
                            }
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: 12) {
                        Spacer()
                        ForEach([1, 3, 5, 10], id: \.self) { quickValue in
                            Button(action: {
                                editedCommitTarget = quickValue
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(quickValue)")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(editedCommitTarget == quickValue ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(editedCommitTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                    )
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        
        private var gamingLimitSection: some View {
            VStack(alignment: .leading, spacing: 20) {
                // Daily/Weekly Limit
                VStack(alignment: .leading, spacing: 16) {
                    Text(habit.habitScheduleType == "weekly" ? "weekly limit" : "daily limit")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.leading, -2)
                    
                    HoursStepperField(
                        hours: $editedDailyLimitHours,
                        isWeekly: habit.habitScheduleType == "weekly"
                    )
                }
                .padding(.horizontal, 20)
                
                // Hourly Penalty Rate
                VStack(alignment: .leading, spacing: 16) {
                    Text("penalty per hour over")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.leading, -2)
                    
                    CurrencyTextField(
                        value: Binding(
                            get: { Float(editedHourlyPenaltyRate) },
                            set: { editedHourlyPenaltyRate = Double($0) }
                        ),
                        range: 1...500,
                        step: 1,
                        quickSelectValues: [5, 10, 15, 20],
                        onFocusChange: { isFocused in
                            isPenaltyFocused = isFocused
                        }
                    )
                }
                .padding(.horizontal, 20)
            }
        }
        
        private var alarmTimeSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("alarm time")
                    .font(.custom("EBGaramond-Regular", size: 28))
                    .italic()
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.leading, -2)
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "alarm.fill").font(.custom("EBGaramond-Regular", size: 24))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("WAKE UP TIME").jtStyle(.caption).foregroundColor(.white.opacity(0.5)).tracking(0.5)
                            Text(DateFormatter().apply { $0.dateFormat = "HH:mm" }.string(from: editedAlarmTime)).jtStyle(.title).foregroundColor(.white).contentTransition(.numericText())
                        }
                    }
                    DatePicker("", selection: $editedAlarmTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))).clipped()
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 20)
        }
        
        private var errorDisplay: some View {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(errorMessage).foregroundColor(.red)
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1)))
            .padding(.horizontal, 20)
        }
        
        private func formattedAlarmTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
    }
} 
