////
//  Step3_ScheduleAndPenalty.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Step 3 of Add Habit wizard – schedule & penalty configuration.
//

import SwiftUI

extension AddHabitRoot {
    struct ScheduleAndPenaltyStep: View {
        @ObservedObject var vm: AddHabitViewModel
        let isOnboarding: Bool
        let onOnboardingComplete: (() -> Void)?
        var onBack: () -> Void
        
        @FocusState private var isInputFocused: Bool
        @FocusState private var isGitHubCommitFocused: Bool
        @FocusState private var isPenaltyFocused: Bool
        @FocusState private var isHealthTargetFocused: Bool

        // Environment
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var authManager: AuthenticationManager
        @EnvironmentObject var habitManager: HabitManager
        @EnvironmentObject var friendsManager: FriendsManager
        @EnvironmentObject var customHabitManager: CustomHabitManager
        @EnvironmentObject var paymentManager: PaymentManager

        var body: some View {
            ZStack {
                VStack(spacing: 0) {
                    wizardHeader
                    // Title below the header
                    Text("schedule")
                        .font(.custom("EBGaramond-Regular", size: 32))
                        .foregroundColor(.white)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    
                    // Scrollable content area
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 32) {
                                scheduleSection
                                    .id("scheduleSection") // ID for GitHub sections
                                if vm.isHealthHabit {
                                    healthTargetSection
                                }
                                if vm.selectedHabitType == HabitType.league_of_legends.rawValue || 
                                   vm.selectedHabitType == HabitType.valorant.rawValue {
                                    gamingLimitSection
                                        .id("penaltySection") // ID for scrolling to penalty sections
                                } else {
                                    penaltySection
                                        .id("penaltySection") // ID for scrolling to penalty sections
                                }
                                
                                // Create habit button
                                HStack {
                                    Spacer()
                                    Button(action: { 
                                        if isOnboarding {
                                            // Complete onboarding demo
                                            onOnboardingComplete?()
                                        } else {
                                            // Create real habit
                                            Task { await createHabitAction() }
                                        }
                                    }) {
                                        if vm.isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Text(isOnboarding ? "continue onboarding" : "create habit")
                                                .font(.custom("EBGaramond-Bold", size: 22))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: 180)
                                                .padding(.vertical, 16)
                                                .background(Color.clear)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                                )
                                                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                                        }
                                    }
                                    .disabled(vm.isLoading)
                                    .opacity(vm.isLoading ? 0.5 : 1.0)
                                    Spacer()
                                }
                                .padding(.bottom, 30) // Extra bottom padding for scroll
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
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
                                    // For penalty fields, scroll to penalty section with offset for keyboard
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo("penaltySection", anchor: .bottom)
                                    }
                                } else if !isHealthTargetFocused {
                                    // For other fields (but not health fields), scroll to penalty section
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo("penaltySection", anchor: .top)
                                    }
                                }
                                // For health target fields, don't auto-scroll (they're already in a good position)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
                KeyboardUtils.dismiss()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(true)
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "Unknown error")
            }
            .onAppear {
                // Optimized: Only fetch if needed for picture habits
                vm.refreshZeroPenaltyCountIfNeeded()
            }
            .onChange(of: vm.selectedHabitType) { oldValue, newValue in
                // Optimized: Count refresh is handled in updateFieldsForHabitType
                // No need for explicit fetch here - reduces redundant calls
            }
        }

        // MARK: - Subviews
        private var scheduleSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("schedule type")
                    .font(.custom("EBGaramond-Italic", size: 18))
                    .foregroundColor(.white)
                    .padding(.bottom, 8)
                Picker("Schedule", selection: $vm.scheduleType) {
                    Text("daily")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .tag("daily")
                    Text("weekly")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .tag("weekly")
                }
                .pickerStyle(.segmented)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .padding(.bottom, 8)

                // Grace period message
                VStack(spacing: 8) {
                    Text(vm.scheduleType == "daily" 
                        ? "your grace period lasts for the first day when you create the habit"
                        : "your grace period lasts for the rest of the week and starts next monday")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.bottom, 8)

                if vm.scheduleType == "daily" {
                    weekdayPicker
                    if vm.selectedHabitType == "github_commits" {
                        githubCommitTargetSection
                    } else if vm.selectedHabitType == "leetcode" {
                        leetCodeTargetSection
                    }
                } else if !(vm.selectedHabitType == HabitType.league_of_legends.rawValue || 
                          vm.selectedHabitType == HabitType.valorant.rawValue ||
                          vm.selectedHabitType == "github_commits" ||
                          vm.selectedHabitType == "leetcode") {
                    // Only show weekly target for non-gaming, non-GitHub, and non-LeetCode habits
                    weeklyTargetPicker
                } else if vm.selectedHabitType == "github_commits" {
                    // Show GitHub-specific weekly target
                    githubWeeklyTargetSection
                } else if vm.selectedHabitType == "leetcode" {
                    // Show LeetCode-specific weekly target
                    leetCodeWeeklyTargetSection
                }
            }
        }

        private var weekdayPicker: some View {
            HStack {
                ForEach(0..<7) { day in
                    Button(action: {
                        if vm.selectedWeekdays.contains(day) {
                            vm.selectedWeekdays.removeAll { $0 == day }
                        } else {
                            vm.selectedWeekdays.append(day)
                        }
                    }) {
                        Text(Calendar.current.shortWeekdaySymbols[day].prefix(1))
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(vm.selectedWeekdays.contains(day) ? Color.white : Color.white.opacity(0.08))
                            .cornerRadius(6)
                            .foregroundColor(vm.selectedWeekdays.contains(day) ? .black : .white)
                    }
                }
            }
        }

        private var weeklyTargetPicker: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("target")
                    .font(.custom("EBGaramond-Italic", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                
                CompactStepperField(
                    value: $vm.weeklyTarget,
                    range: 1...7,
                    suffix: "time\(vm.weeklyTarget == 1 ? "" : "s") per week"
                )
            }
        }
        
        private var githubCommitTargetSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("daily commit goal")
                    .font(.custom("EBGaramond-Italic", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                
                // Clean stepper without background box
                HStack(spacing: 16) {
                    // Decrement button
                    Button(action: {
                        if vm.commitTarget > 1 {
                            vm.commitTarget -= 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(vm.commitTarget > 1 ? .white : .white.opacity(0.3))
                    }
                    .disabled(vm.commitTarget <= 1)
                    
                    Spacer()
                    
                    // Value display
                    VStack(spacing: 4) {
                        TextField("\(vm.commitTarget)", text: Binding(
                            get: { String(vm.commitTarget) },
                            set: { newValue in
                                if let intValue = Int(newValue.filter { $0.isNumber }), 
                                   intValue >= 1 && intValue <= 50 {
                                    vm.commitTarget = intValue
                                }
                            }
                        ))
                            .font(.custom("EBGaramond-Regular", size: 32))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .focused($isGitHubCommitFocused)
                            .multilineTextAlignment(.center)
                        
                        Text("commit\(vm.commitTarget == 1 ? "" : "s") / day")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Increment button
                    Button(action: {
                        if vm.commitTarget < 50 {
                            vm.commitTarget += 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(vm.commitTarget < 50 ? .white : .white.opacity(0.3))
                    }
                    .disabled(vm.commitTarget >= 50)
                }
                .padding(.horizontal, 16)
                
                // Quick select values
                HStack(spacing: 12) {
                    Spacer()
                    ForEach([1, 3, 5, 10], id: \.self) { quickValue in
                        Button(action: {
                            vm.commitTarget = quickValue
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Text("\(quickValue)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(vm.commitTarget == quickValue ? .black : .white.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(vm.commitTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                )
                        }
                    }
                    Spacer()
                }
            }
        }
        
        private var leetCodeTargetSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("daily problem goal")
                    .font(.custom("EBGaramond-Italic", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 12) {
                    // Clean inline input without box styling
                    HStack(spacing: 16) {
                        // Decrement button
                        Button(action: {
                            if vm.commitTarget > 1 {
                                vm.commitTarget -= 1
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(vm.commitTarget > 1 ? .white : .white.opacity(0.3))
                        }
                        .disabled(vm.commitTarget <= 1)
                        
                        Spacer()
                        
                        // Value display
                        VStack(spacing: 4) {
                            Text("\(vm.commitTarget)")
                                .font(.custom("EBGaramond-Regular", size: 32))
                                .foregroundColor(.white)
                            
                            Text("problem\(vm.commitTarget == 1 ? "" : "s") / day")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        // Increment button
                        Button(action: {
                            if vm.commitTarget < 10 {
                                vm.commitTarget += 1
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(vm.commitTarget < 10 ? .white : .white.opacity(0.3))
                        }
                        .disabled(vm.commitTarget >= 10)
                    }
                    .padding(.horizontal, 16)
                    
                    // Quick select buttons
                    HStack(spacing: 12) {
                        Spacer()
                        ForEach([1, 2, 3, 5], id: \.self) { quickValue in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.commitTarget = quickValue
                                }
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(quickValue)")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(vm.commitTarget == quickValue ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(vm.commitTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                vm.commitTarget == quickValue ? Color.clear : Color.white.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        
        private var githubWeeklyTargetSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("weekly commit goal")
                    .font(.custom("EBGaramond-Italic", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                
                // Clean stepper without background box
                HStack(spacing: 16) {
                    // Decrement button
                    Button(action: {
                        if vm.weeklyTarget > 1 {
                            vm.weeklyTarget -= 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(vm.weeklyTarget > 1 ? .white : .white.opacity(0.3))
                    }
                    .disabled(vm.weeklyTarget <= 1)
                    
                    Spacer()
                    
                    // Value display
                    VStack(spacing: 4) {
                        TextField("\(vm.weeklyTarget)", text: Binding(
                            get: { String(vm.weeklyTarget) },
                            set: { newValue in
                                if let intValue = Int(newValue.filter { $0.isNumber }), 
                                   intValue >= 1 && intValue <= 100 {
                                    vm.weeklyTarget = intValue
                                }
                            }
                        ))
                            .font(.custom("EBGaramond-Regular", size: 32))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .focused($isGitHubCommitFocused)
                            .multilineTextAlignment(.center)
                        
                        Text("commit\(vm.weeklyTarget == 1 ? "" : "s") / week")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Increment button
                    Button(action: {
                        if vm.weeklyTarget < 100 {
                            vm.weeklyTarget += 1
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(vm.weeklyTarget < 100 ? .white : .white.opacity(0.3))
                    }
                    .disabled(vm.weeklyTarget >= 100)
                }
                .padding(.horizontal, 16)
                
                // Quick select values
                HStack(spacing: 12) {
                    Spacer()
                    ForEach([5, 10, 20, 30], id: \.self) { quickValue in
                        Button(action: {
                            vm.weeklyTarget = quickValue
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Text("\(quickValue)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(vm.weeklyTarget == quickValue ? .black : .white.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(vm.weeklyTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                )
                        }
                    }
                    Spacer()
                }
                
                // Penalty explanation for GitHub weekly habits
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        Text("penalty structure")
                            .font(.custom("EBGaramond-Bold", size: 14))
                            .foregroundColor(.yellow)
                    }
                    
                    Text("You'll be charged for each missed commit")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Example calculation
                    let exampleTarget = min(vm.weeklyTarget, 20) // Use a reasonable example
                    let exampleMissed = max(1, min(5, exampleTarget / 4)) // Miss about 1/4 of commits
                    let exampleComplete = exampleTarget - exampleMissed
                    let examplePenalty = Float(exampleMissed) * vm.penaltyAmount
                    
                    Text("Example: \(exampleComplete)/\(exampleTarget) commits = \(exampleMissed) missed × $\(String(format: "%.2f", vm.penaltyAmount)) = $\(String(format: "%.2f", examplePenalty))")
                        .font(.custom("EBGaramond-Italic", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 2)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
            }
        }
        
        private var leetCodeWeeklyTargetSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("weekly problem goal")
                    .font(.custom("EBGaramond-Italic", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                
                VStack(spacing: 12) {
                    // Clean inline input without box styling
                    HStack(spacing: 16) {
                        // Decrement button
                        Button(action: {
                            if vm.weeklyTarget > 1 {
                                vm.weeklyTarget -= 1
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(vm.weeklyTarget > 1 ? .white : .white.opacity(0.3))
                        }
                        .disabled(vm.weeklyTarget <= 1)
                        
                        Spacer()
                        
                        // Value display
                        VStack(spacing: 4) {
                            Text("\(vm.weeklyTarget)")
                                .font(.custom("EBGaramond-Regular", size: 32))
                                .foregroundColor(.white)
                            
                            Text("problem\(vm.weeklyTarget == 1 ? "" : "s") / week")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        // Increment button
                        Button(action: {
                            if vm.weeklyTarget < 50 {
                                vm.weeklyTarget += 1
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(vm.weeklyTarget < 50 ? .white : .white.opacity(0.3))
                        }
                        .disabled(vm.weeklyTarget >= 50)
                    }
                    .padding(.horizontal, 16)
                    
                    // Quick select buttons
                    HStack(spacing: 12) {
                        Spacer()
                        ForEach([3, 5, 7, 10], id: \.self) { quickValue in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.weeklyTarget = quickValue
                                }
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }) {
                                Text("\(quickValue)")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(vm.weeklyTarget == quickValue ? .black : .white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(vm.weeklyTarget == quickValue ? Color.white : Color.white.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                vm.weeklyTarget == quickValue ? Color.clear : Color.white.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                
                // Penalty explanation for LeetCode weekly habits
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        Text("penalty structure")
                            .font(.custom("EBGaramond-Bold", size: 14))
                            .foregroundColor(.yellow)
                    }
                    
                    Text("You'll be charged for each missed problem")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Example calculation
                    let exampleTarget = min(vm.weeklyTarget, 10) // Use a reasonable example
                    let exampleMissed = max(1, min(3, exampleTarget / 3)) // Miss about 1/3 of problems
                    let exampleComplete = exampleTarget - exampleMissed
                    let examplePenalty = Float(exampleMissed) * vm.penaltyAmount
                    
                    Text("Example: \(exampleComplete)/\(exampleTarget) problems = \(exampleMissed) missed × $\(String(format: "%.2f", vm.penaltyAmount)) = $\(String(format: "%.2f", examplePenalty))")
                        .font(.custom("EBGaramond-Italic", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 2)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
            }
        }
        
        private var penaltySection: some View {
            VStack(alignment: .leading, spacing: 16) {
                // IMPORTANT: Zero-penalty toggle ONLY for PICTURE HABITS (photo verification)
                // Health habits and API habits must always use credits
                // Hide the free habit option when user already has 1 or more zero penalty habits
                if vm.isPictureHabit && vm.existingZeroPenaltyCount < 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("0 credit penalty")
                                    .font(.custom("EBGaramond-Italic", size: 18))
                                    .foregroundColor(.white)
                                
                                Text(vm.canUseZeroPenalty ?
                                     "No financial consequences (\(1 - vm.existingZeroPenaltyCount) remaining)" :
                                        "Maximum of 3 zero-penalty habits reached")
                                    .font(.custom("EBGaramond-Regular", size: 14))
                                    .foregroundColor(vm.canUseZeroPenalty ? .white.opacity(0.7) : .orange)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $vm.isZeroPenalty)
                                .disabled(!vm.canUseZeroPenalty)
                                .toggleStyle(SwitchToggleStyle(tint: .white))
                        }
                        .padding(.horizontal, 16)
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
                }
                
                // Credits slider (only show if not zero-penalty)
                if !vm.isZeroPenalty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text((vm.selectedHabitType == "github_commits" || vm.selectedHabitType == "leetcode") && vm.scheduleType == "weekly" ?
                             (vm.selectedHabitType == "github_commits" ? "credits per missed commit" : "credits per missed problem") :
                                "credits per day")
                            .font(.custom("EBGaramond-Italic", size: 18))
                            .foregroundColor(.white)
                        
                        CurrencyTextField(
                            value: $vm.penaltyAmount,
                            range: 0.5...500,
                            step: 0.5,
                            quickSelectValues: [5, 10, 20, 25],
                            onFocusChange: { isFocused in
                                isPenaltyFocused = isFocused
                            }
                        )
                        
                        // Additional explanation for weekly GitHub/LeetCode habits
                        if (vm.selectedHabitType == "github_commits" || vm.selectedHabitType == "leetcode") && vm.scheduleType == "weekly" {
                            let itemType = vm.selectedHabitType == "github_commits" ? "commits" : "problems"
                            Text("Total penalty = missed \(itemType) × \(String(format: "%.2f", vm.penaltyAmount)) credits")
                                .font(.custom("EBGaramond-Italic", size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 4)
                        }
                    }
                }
            }
        }
        
        // MARK: - Health Target Section
        private var healthTargetSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("health target")
                    .font(.custom("EBGaramond-Italic", size: 20))
                    .foregroundColor(.white)
                
                // Device requirement info
                deviceRequirementInfo
                
                // Use SegmentedNumberPicker for appropriate health types
                Group {
                    switch vm.selectedHabitType {
                    case "health_steps":
                        SegmentedNumberPicker(
                            value: $vm.healthTargetValue,
                            presets: [5000, 8000, 10000, 15000],
                            customRange: 1000...30000,
                            step: 500,
                            unit: vm.healthTargetUnit
                        )
                    case "health_walking_running_distance", "health_cycling_distance":
                        SegmentedNumberPicker(
                            value: $vm.healthTargetValue,
                            presets: [1, 3, 5, 10],
                            customRange: 0.5...20,
                            step: 0.5,
                            unit: vm.healthTargetUnit,
                            formatter: { String(format: "%.1f", $0) }
                        )
                    case "health_exercise_minutes", "health_mindful_minutes":
                        SegmentedNumberPicker(
                            value: $vm.healthTargetValue,
                            presets: vm.selectedHabitType == "health_exercise_minutes" ? [15, 30, 45, 60] : [10, 15, 20, 30],
                            customRange: vm.selectedHabitType == "health_exercise_minutes" ? 10...180 : 5...120,
                            step: 5,
                            unit: vm.healthTargetUnit
                        )
                    case "health_flights_climbed":
                        // Use StepperField for small range
                        StepperField(
                            value: Binding(
                                get: { Int(vm.healthTargetValue) },
                                set: { vm.healthTargetValue = Double($0) }
                            ),
                            range: 1...50,
                            label: vm.healthTargetUnit
                        )
                    case "health_calories_burned":
                        SegmentedNumberPicker(
                            value: $vm.healthTargetValue,
                            presets: [500, 750, 1000, 1500],
                            customRange: 100...2000,
                            step: 50,
                            unit: vm.healthTargetUnit
                        )
                    case "health_sleep_hours":
                        SegmentedNumberPicker(
                            value: $vm.healthTargetValue,
                            presets: [6, 7, 8, 9],
                            customRange: 4...12,
                            step: 0.5,
                            unit: vm.healthTargetUnit,
                            formatter: { String(format: "%.1f", $0) }
                        )
                    default:
                        // Fallback to original TextField for unknown types
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                // Target value input
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Target")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    TextField("Enter target", value: $vm.healthTargetValue, format: .number)
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
                                
                                // Unit display (read-only)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Unit")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Text(vm.healthTargetUnit)
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
                                .frame(width: 100) // Fixed width for unit
                            }
                            
                            // Health type description
                            Text(vm.getHealthHabitDescription(for: vm.selectedHabitType))
                                .font(.custom("EBGaramond-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 4)
                            
                            // Validation range info
                            let range = vm.getValidationRange(for: vm.selectedHabitType)
                            Text("Recommended range: \(Int(range.min)) - \(Int(range.max)) \(vm.healthTargetUnit)")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                
                // Verification message
                VStack(spacing: 8) {
                    Text("you must verify in app once you complete")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("otherwise, it will not count")
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
        }
        
        @ViewBuilder
        private var deviceRequirementInfo: some View {
            let requiresWatch = vm.selectedHabitType == "health_calories_burned" ||
                              vm.selectedHabitType == "health_exercise_minutes" ||
                              vm.selectedHabitType == "health_sleep_hours"
            
            HStack(spacing: 8) {
                Image(systemName: requiresWatch ? "applewatch" : "iphone")
                    .font(.system(size: 14))
                    .foregroundColor(requiresWatch ? .orange : .blue)
                
                Text(requiresWatch ? "Requires Apple Watch for accurate tracking" : "Works with iPhone and Apple Watch")
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(requiresWatch ? .orange : .blue)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((requiresWatch ? Color.orange : Color.blue).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke((requiresWatch ? Color.orange : Color.blue).opacity(0.3), lineWidth: 1)
                    )
            )
        }
        
        private var gamingLimitSection: some View {
            VStack(alignment: .leading, spacing: 20) {
                // Daily/Weekly Limit
                VStack(alignment: .leading, spacing: 12) {
                    Text(vm.scheduleType == "weekly" ? "weekly limit" : "daily limit")
                        .font(.custom("EBGaramond-Italic", size: 18))
                        .foregroundColor(.white)
                    
                    HoursStepperField(
                        hours: $vm.dailyLimitHours,
                        isWeekly: vm.scheduleType == "weekly"
                    )
                }
                
                // Hourly penalty rate
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("penalty per hour over")
                            .font(.custom("EBGaramond-Italic", size: 16))
                            .foregroundColor(.white)
                        Spacer()
                        Text("$\(String(format: "%.2f", vm.hourlyPenaltyRate))")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    CurrencyTextField(
                        value: Binding(
                            get: { Float(vm.hourlyPenaltyRate) },
                            set: { vm.hourlyPenaltyRate = Double($0) }
                        ),
                        range: 1...500,
                        step: 1,
                        quickSelectValues: [5, 10, 15, 20],
                        onFocusChange: { isFocused in
                            isPenaltyFocused = isFocused
                        }
                    )
                    
                    Text("you'll be charged for each hour over your limit")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }

        // MARK: - Logic
        private func createHabitAction() async {
            vm.isLoading = true

            do {
                // Re-use old manager call (simplified)
                guard let userId = authManager.currentUser?.id,
                      let token = AuthenticationManager.shared.storedAuthToken else {
                    throw NSError(domain: "auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Auth error"])
                }

                let recipientId = vm.selectedFriend?.friendId
                let alarmString = vm.selectedHabitType == HabitType.alarm.rawValue ? vm.formatAlarmTime24h() : nil

                let isGamingHabit = vm.selectedHabitType == HabitType.league_of_legends.rawValue || 
                                   vm.selectedHabitType == HabitType.valorant.rawValue
                
                // Check for payment method if creating a non-free habit
                let pictureHabitTypes: Set<String> = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
                let isPictureHabit = pictureHabitTypes.contains(vm.selectedHabitType) || vm.selectedHabitType.hasPrefix("custom_")
                let requiresPayment = (!vm.isZeroPenalty || !isPictureHabit) && vm.penaltyAmount > 0
                
                if requiresPayment {
                    // Fetch current payment method status
                    let hasPaymentMethod = await PaymentManager.shared.fetchPaymentMethod(token: token)
                    
                    if !hasPaymentMethod || PaymentManager.shared.paymentMethod == nil {
                        await MainActor.run {
                            vm.errorMessage = "You need to add a payment method before creating habits with penalties. Please go to jointally.app/payments to add one."
                            vm.showError = true
                            vm.isLoading = false
                        }
                        return
                    }
                }

                // Day selection validation for daily schedule
                if vm.scheduleType == "daily" && vm.selectedWeekdays.isEmpty {
                    await MainActor.run {
                        vm.errorMessage = "Select a day to continue."
                        vm.showError = true
                        vm.isLoading = false
                    }
                    return
                }

                // Health target range validation
                if vm.isHealthHabit {
                    let range = vm.getValidationRange(for: vm.selectedHabitType)
                    if vm.healthTargetValue < range.min || vm.healthTargetValue > range.max {
                        await MainActor.run {
                            vm.errorMessage = "Your target is not in the allowed range."
                            vm.showError = true
                            vm.isLoading = false
                        }
                        return
                    }
                }

                // Request HealthKit permission for health habits before creating
                if vm.isHealthHabit {
                    do {
                        print("🏥 Requesting HealthKit permission for: \(vm.selectedHabitType)")
                        try await HealthKitManager.shared.requestPermission(for: vm.selectedHabitType)
                        print("✅ HealthKit permission granted for \(vm.selectedHabitType)")
                    } catch {
                        print("❌ HealthKit permission failed: \(error)")
                        await MainActor.run {
                            vm.isLoading = false
                            if let healthError = error as? HealthKitError {
                                switch healthError {
                                case .notAvailable:
                                    #if targetEnvironment(simulator)
                                    vm.errorMessage = "Health tracking is not available on iOS Simulator. Please test on a physical device (iPhone or iPad)."
                                    #else
                                    vm.errorMessage = "Health tracking is not available on this device. Please use a physical iPhone or iPad."
                                    #endif
                                case .permissionDenied:
                                    vm.errorMessage = "Health data access issue detected. This is unusual since your permissions appear to be enabled.\n\nTry:\n1. Restart the app completely\n2. If still failing, toggle the permission off and on again in Settings > Privacy & Security > Health > Tally\n3. Make sure 'HealthKit Background Delivery' is enabled in Settings > Health"
                                case .unsupportedHabitType:
                                    vm.errorMessage = "This health habit type is not supported on your device."
                                case .dataUnavailable:
                                    vm.errorMessage = "Health data is temporarily unavailable. Please try again in a moment."
                                }
                            } else {
                                vm.errorMessage = "Health permission error: \(error.localizedDescription). Please check your Health app settings."
                            }
                            vm.showError = true
                        }
                        return // Don't create habit if HealthKit permission fails
                    }
                }
                
                try await habitManager.createHabit(
                    name: vm.name,
                    recipientId: vm.isZeroPenalty ? nil : recipientId,  // Force no recipient for zero penalty habits
                    habitType: vm.selectedHabitType,
                    weekdays: vm.scheduleType == "daily" ? vm.selectedWeekdays : [],
                    penaltyAmount: vm.isZeroPenalty ? 0 : (isGamingHabit ? 0 : vm.penaltyAmount),  // Force 0 penalty for zero penalty habits
                    userId: userId,
                    token: token,
                    isPrivate: false,
                    alarmTime: alarmString,
                    customHabitTypeId: vm.selectedCustomHabitTypeId,
                    scheduleType: vm.scheduleType,
                    weeklyTarget: vm.scheduleType == "weekly" ? vm.weeklyTarget : nil,
                    weekStartDay: vm.scheduleType == "weekly" ? vm.weekStartDay : 0,
                    commitTarget: (vm.selectedHabitType == "github_commits" || vm.selectedHabitType == "leetcode") ? 
                        (vm.scheduleType == "weekly" ? vm.weeklyTarget : vm.commitTarget) : nil,
                    dailyLimitHours: isGamingHabit ? vm.dailyLimitHours : nil,
                    hourlyPenaltyRate: isGamingHabit ? vm.hourlyPenaltyRate : nil,
                    healthTargetValue: vm.isHealthHabit ? vm.healthTargetValue : nil,
                    healthTargetUnit: vm.isHealthHabit ? vm.healthTargetUnit : nil,
                    healthDataType: vm.isHealthHabit ? vm.healthDataType : nil,
                    isZeroPenalty: vm.isZeroPenalty
                )

                await MainActor.run {
                    vm.isLoading = false
                    // Notify the overlay wrapper to dismiss the entire Add-Habit flow
                    NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
                }
            } catch {
                await MainActor.run {
                    vm.isLoading = false
                    vm.errorMessage = error.localizedDescription
                    vm.showError = true
                }
            }
        }

        // MARK: - Header
        private var wizardHeader: some View {
            HStack {
                // Back arrow (goes to previous step)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .offset(x: 2, y: 2)

                Spacer()
                // Down arrow (dismisses overlay)
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
                    dismiss()
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
    }
}

#if canImport(UIKit)
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif 
