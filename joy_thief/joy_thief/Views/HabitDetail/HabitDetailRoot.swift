import SwiftUI

// Alias to maintain compatibility with new subcomponent extensions
typealias HabitDetailRoot = HabitDetailView

struct HabitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var friendsManager: FriendsManager
    @ObservedObject var habitManager: HabitManager
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingUpdateConfirmation = false
    @State private var showingDeleteSuccess = false
    @State private var showingUpdateSuccess = false
    @State private var showingRestoreConfirmation = false
    @State private var showingRestoreSuccess = false
    @State private var isLoading = false
    @State private var errorMessage: String = ""
    @State private var showError = false
    @State private var deleteResponse: HabitDeleteResponse?
    @State private var updateResponse: HabitUpdateResponse?
    @State private var restoreResponse: RestoreHabitResponse?
    @State private var scheduledDeletion: StagedDeletionInfo?
    @State private var isCheckingDeletion = true
    
    // Editing states
    @State private var editedName: String
    @State private var editedRecipientId: String?
    @State private var editedWeekdays: [Int]
    @State private var editedPenaltyAmount: Float
    @State private var editedIsPrivate: Bool
    @State private var editedAlarmTime: Date
    @State private var editedWeeklyTarget: Int
    @State private var editedWeekStartDay: Int
    
    // Gaming-specific editing states
    @State private var editedDailyLimitHours: Double
    @State private var editedHourlyPenaltyRate: Double
    
    // Health-specific editing states
    @State private var editedHealthTargetValue: Double
    @State private var editedHealthTargetUnit: String
    
    // GitHub-specific editing states
    @State private var editedCommitTarget: Int
    
    let habit: Habit
    private let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    
    // Optional owner information for when viewing as recipient
    let ownerName: String?
    let ownerPhone: String?
    
    init(habit: Habit, habitManager: HabitManager, ownerName: String? = nil, ownerPhone: String? = nil) {
        self.habit = habit
        self.habitManager = habitManager
        self.ownerName = ownerName
        self.ownerPhone = ownerPhone
        _editedName = State(initialValue: habit.name)
        _editedRecipientId = State(initialValue: habit.recipientId)
        _editedWeekdays = State(initialValue: habit.weekdays)
        _editedPenaltyAmount = State(initialValue: habit.penaltyAmount)
        _editedIsPrivate = State(initialValue: habit.isPrivate ?? false)
        _editedWeeklyTarget = State(initialValue: habit.weeklyTarget ?? 3)
        _editedWeekStartDay = State(initialValue: habit.weekStartDay ?? 0)
        _editedDailyLimitHours = State(initialValue: habit.dailyLimitHours ?? 2.0)
        _editedHourlyPenaltyRate = State(initialValue: habit.hourlyPenaltyRate ?? 10.0)
        _editedHealthTargetValue = State(initialValue: habit.healthTargetValue ?? 10000.0)
        _editedHealthTargetUnit = State(initialValue: habit.healthTargetUnit ?? "steps")
        _editedCommitTarget = State(initialValue: habit.commitTarget ?? 1)
        if let alarmTime = habit.alarmTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            _editedAlarmTime = State(initialValue: formatter.date(from: alarmTime) ?? Date())
        } else {
            _editedAlarmTime = State(initialValue: Date())
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Enhanced background with subtle gradient
                LinearGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color(hex: "161C29"), location: 0.0),
                        Gradient.Stop(color: Color(hex: "131824"), location: 0.15),
                        Gradient.Stop(color: Color(hex: "0F141F"), location: 0.3),
                        Gradient.Stop(color: Color(hex: "0C111A"), location: 0.45),
                        Gradient.Stop(color: Color(hex: "0A0F17"), location: 0.6),
                        Gradient.Stop(color: Color(hex: "080D15"), location: 0.7),
                        Gradient.Stop(color: Color(hex: "060B12"), location: 0.8),
                        Gradient.Stop(color: Color(hex: "03070E"), location: 0.9),
                        Gradient.Stop(color: Color(hex: "01050B"), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isEditing {
                    editingView
                } else {
                    detailView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if isEditing {
                            resetEditedValues()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isEditing = false
                            }
                        } else {
                            dismiss()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isEditing ? "xmark" : "chevron.left")
                                .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                            Text(isEditing ? "Cancel" : "Back")
                                .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                    }
                }
                
                // Only show edit button if user is the owner
                if isHabitOwner {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isEditing {
                            Button(action: saveChanges) {
                                HStack(spacing: 4) {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "checkmark")
                                            .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                                    }
                                    Text("Save")
                                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                                }
                                .foregroundColor(isFormValid ? .white : .gray)
                            }
                            .disabled(isLoading || !isFormValid)
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isEditing = true
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                                    Text("Edit")
                                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }
                    
                    // Separate delete button (only when viewing and user is owner)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if !isEditing {
                            Button(action: { showingDeleteConfirmation = true }) {
                                Image(systemName: isScheduledForDeletion ? "checkmark" : "trash")
                                    .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                            }
                            .foregroundColor(isScheduledForDeletion ? .green : .red)
                            .disabled(isScheduledForDeletion)
                        }
                    }
                }
            }
            .onAppear {
                checkForScheduledDeletion()
                // Preload friends with Stripe Connect when opening habit detail
                Task {
                    print("🔄 [HabitDetailView] Preloading friends with Stripe Connect...")
                    await friendsManager.refreshFriendsWithStripeConnect()
                    print("✅ [HabitDetailView] Friends with Stripe Connect preloaded: \(friendsManager.preloadedFriendsWithStripeConnect.count)")
                }
            }
            .alert("Delete Habit", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: deleteHabit)
            } message: {
                if isHabitCreatedTodayAndNeverVerified() {
                    Text("This habit was created today and has never been verified, so it will be deleted immediately.\n\nNo penalties will be charged.\n\nAre you sure you want to delete this habit?")
                } else if habit.habitType == "alarm" && !habit.weekdays.contains(getTodayWeekday()) {
                    Text("This alarm habit is not scheduled for today, so it will be deleted immediately.\n\nAre you sure you want to delete this habit?")
                } else if habit.isWeeklyHabit {
                    Text("⚠️ Important: Your weekly habit will be permanently deleted at the end of this week (Sunday), not immediately.\n\nIf you haven't completed this week's target and the week ends, you will be charged the penalty amount.\n\nDeletion takes effect at the end of the week in your timezone.")
                } else {
                    Text("⚠️ Important: Your habit will be permanently deleted tomorrow, not immediately.\n\nIf you have this habit scheduled for today and haven't completed it yet, you will be charged the penalty amount at the end of the day.\n\nDeletion takes effect tomorrow in your timezone.")
                }
            }
            .alert("Edit Habit", isPresented: $showingUpdateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save Changes", action: confirmSaveChanges)
            } message: {
                Text("⚠️ Important: Your changes will take effect tomorrow, not immediately.\n\nIf you're removing today from the schedule and haven't completed today's requirement, you will be charged the penalty at the end of the day.\n\nChanges take effect tomorrow in your timezone.")
            }
            .alert("Habit Scheduled for Deletion", isPresented: $showingDeleteSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                if let response = deleteResponse {
                    Text("Habit Type: \(response.habitType.capitalized)\nDeletion Timing: \(response.deletionTiming)\nEffective Date: \(formatDate(response.effectiveDate))\nTimezone: \(response.timezone)\n\n\(response.message)")
                } else {
                    Text("Your habit has been scheduled for deletion.")
                }
            }
            .alert("Changes Scheduled", isPresented: $showingUpdateSuccess) {
                Button("OK") { }
            } message: {
                if let response = updateResponse {
                    Text("Effective Date: \(formatDate(response.effectiveDate))\nTimezone: \(response.timezone)\n\n\(response.message)")
                } else {
                    Text("Your habit changes have been scheduled.")
                }
            }
            .alert("Restore Habit", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Restore", action: restoreHabit)
            } message: {
                Text("This will cancel the scheduled deletion of your habit. Your habit will remain active and continue as normal.")
            }
            .alert("Habit Restored", isPresented: $showingRestoreSuccess) {
                Button("OK") { 
                    // Refresh the deletion status
                    checkForScheduledDeletion()
                }
            } message: {
                if let response = restoreResponse {
                    Text(response.message)
                } else {
                    Text("Your habit has been successfully restored.")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var detailView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Scheduled Deletion Banner (if applicable)
                if let deletion = scheduledDeletion,
                   deletion.scheduledForDeletion {
                    DeletionBanner(
                        scheduledDeletion: deletion,
                        showingRestoreConfirmation: $showingRestoreConfirmation,
                        formatDate: formatDate
                    )
                }

                // 1. Habit Name
                Text(habit.name.isEmpty ? "insert habit name" : habit.name)
                    .jtStyle(.title)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                // 2. Schedule Row (Day & Time if alarm)
                VStack(alignment: .leading, spacing: 4) {
                    // Days or Amount label - hide for gaming habits
                    if habit.habitType != "league_of_legends" && habit.habitType != "valorant" {
                        Text(habit.isWeeklyHabit ? "amount" : "days")
                            .font(.custom("EBGaramond-Regular", size: 28))
                            .italic()
                            .foregroundColor(.white)
                    }
                    
                    if habit.isWeeklyHabit {
                        if let startDay = habit.weekdays.first {
                            Text("every \(weekdays[startDay])")
                                .font(.custom("EBGaramond-Regular", size: 20))
                                .italic()
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.bottom, 8)
                                .padding(.leading, 8)
                        }
                        // For GitHub weekly habits, show commitTarget instead of weeklyTarget
                        if habit.habitType == "github_commits" {
                            if let commitTarget = habit.commitTarget {
                                Text("\(commitTarget) commits per week")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.leading, 8)
                            }
                        } else if let weeklyTarget = habit.weeklyTarget {
                            // Hide "times per week" for gaming habits
                            if habit.habitType != "league_of_legends" && habit.habitType != "valorant" {
                                Text("\(weeklyTarget) times per week")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.leading, 8)
                            }
                        }
                    } else if !habit.weekdays.isEmpty {
                        let daysString = habit.weekdays.map { weekdays[$0] }.joined(separator: ", ")
                        Text(daysString)
                            .font(.custom("EBGaramond-Regular", size: 20))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 8)
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
                        
                        if habit.isAlarmHabit, let alarmTime = habit.alarmTime {
                            Text("by \(formattedAlarmTime(alarmTime))")
                                .font(.custom("EBGaramond-Regular", size: 20))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 24)

                // Thin divider
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                // 3. Gaming Limit or Accountability Price
                if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
                    // Gaming habit - show daily limit and hourly penalty
                    VStack(alignment: .leading, spacing: 20) {
                        // Daily Limit
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Text(habit.habitScheduleType == "weekly" ? "weekly limit" : "daily limit")
                                    .font(.custom("EBGaramond-Regular", size: 28))
                                    .italic()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                
                                Spacer()
                                
                                Text(String(format: "%.1f hours", habit.dailyLimitHours ?? 0))
                                    .jtStyle(.body)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Hourly Penalty Rate
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Text("penalty per hour over")
                                    .font(.custom("EBGaramond-Regular", size: 28))
                                    .italic()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                
                                Spacer()
                                
                                Text(String(format: "$%.2f", habit.hourlyPenaltyRate ?? 0))
                                    .jtStyle(.body)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else if habit.isHealthHabit {
                    // Health habit - show daily target
                    VStack(alignment: .leading, spacing: 20) {
                        // Health Target
                        if let targetValue = habit.healthTargetValue, let targetUnit = habit.healthTargetUnit {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("daily target")
                                        .font(.custom("EBGaramond-Regular", size: 28))
                                        .italic()
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                    
                                    Spacer()
                                    
                                    Text(formatHealthTargetValue(targetValue, unit: targetUnit))
                                        .jtStyle(.body)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        // Penalty Amount (same as regular habits)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Text("price")
                                    .font(.custom("EBGaramond-Regular", size: 28))
                                    .italic()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                
                                Spacer()
                                
                                Text(String(format: "$%.2f", habit.penaltyAmount))
                                    .jtStyle(.body)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    // Regular habit - show penalty amount
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("penalty per day")
                                .font(.custom("EBGaramond-Regular", size: 28))
                                .italic()
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                            
                            Spacer()
                            
                            Text(String(format: "$%.2f", habit.penaltyAmount))
                                .jtStyle(.body)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // 4. Owner/Recipient Section (always shown)
                VStack(alignment: .leading, spacing: 12) {

                    Text(isHabitOwner ? "recipient" : "owner")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.leading, -2)

                    VStack(spacing: 4) {
                        if isHabitOwner {
                            // Show recipient info when user owns the habit
                            Text(recipientDisplayName ?? "None")
                                .jtStyle(.body)
                                .foregroundColor(.white)
                        } else {
                            // Show owner info when user is the recipient
                            Text(ownerName ?? "Unknown")
                                .jtStyle(.body)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 32).fill(Color.white.opacity(0.03)))
                    )
                }
                .padding(.horizontal, 20)

                // 5. How to Verify Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("how to verify")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .italic()
                        .foregroundColor(.white)
                        .padding(.leading, -2)

                    Text(verificationInstructions)
                        .jtStyle(.body)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
        }
    }
    
    private var editingView: some View {
        EditingFormSection(
            habit: habit,
            editedName: $editedName,
            editedRecipientId: $editedRecipientId,
            editedWeekdays: $editedWeekdays,
            editedPenaltyAmount: $editedPenaltyAmount,
            editedIsPrivate: $editedIsPrivate,
            editedAlarmTime: $editedAlarmTime,
            editedWeeklyTarget: $editedWeeklyTarget,
            editedWeekStartDay: $editedWeekStartDay,
            editedDailyLimitHours: $editedDailyLimitHours,
            editedHourlyPenaltyRate: $editedHourlyPenaltyRate,
            editedHealthTargetValue: $editedHealthTargetValue,
            editedHealthTargetUnit: $editedHealthTargetUnit,
            editedCommitTarget: $editedCommitTarget,
            errorMessage: errorMessage
        )
    }
    
    private var habitColor: Color {
        let name = habit.name.lowercased()
        switch true {
        case name.contains("gym") || name.contains("workout"):
            return .red
        case name.contains("run") || name.contains("jog"):
            return .orange
        case name.contains("meditate") || name.contains("mindful"):
            return .purple
        case name.contains("water") || name.contains("drink"):
            return .blue
        case name.contains("study"):
            return .green
        case name.contains("screen"):
            return .indigo
        default:
            return .cyan
        }
    }
    
    private var recipientDisplayName: String? {
        habit.getRecipientName()
    }
    
    // New helper providing per-habit verification instructions.
    private var verificationInstructions: String {
        switch habit.habitType {
        case HabitType.gym.rawValue:
            return "Verify \"\(habit.name)\" by uploading a selfie and a photo of your workout environment or equipment within an hour of finishing your session."
        case HabitType.alarm.rawValue:
            return "Verify waking up on time by snapping a well-lit selfie within 10 minutes after your scheduled alarm rings."
        case HabitType.yoga.rawValue:
            return "Verify your yoga session by taking a selfie and a photo of you in one of the poses you practiced within an hour of completion."
        case HabitType.outdoors.rawValue:
            return "Verify your outdoor activity by uploading a selfie clearly taken outside during or immediately after the activity."
        case HabitType.cycling.rawValue:
            return "Verify your ride by sharing a selfie with your bike and a photo of your ride summary or route within an hour of finishing."
        case HabitType.cooking.rawValue:
            return "Verify your cooking session by taking a selfie and a photo of the finished meal within an hour of completion."
        case "github_commits":
            return "Verify this habit by meeting your commit goal from your GitHub account. Your commits are automatically tracked and counted towards your daily or weekly target."
        case "league_of_legends", "valorant":
            return "This gaming habit is automatically tracked through your Riot account. Your play time is monitored daily and penalties are charged for each hour you exceed your \(habit.habitScheduleType == "weekly" ? "weekly" : "daily") limit of \(String(format: "%.1f", habit.dailyLimitHours ?? 0)) hours."
        case "health_steps":
            return "Put your iPhone in your pocket or carry it while walking. We automatically track your steps through Apple Health. \(getHealthTargetText())"
        case "health_walking_running_distance":
            return "Carry your iPhone while walking or running. We automatically track your distance through Apple Health using your phone's motion sensors. \(getHealthTargetText())"
        case "health_flights_climbed":
            return "Carry your iPhone while climbing stairs or hills. We automatically track flights climbed through Apple Health using your phone's built-in barometer. \(getHealthTargetText())"
        case "health_exercise_minutes":
            return "This requires an Apple Watch. We automatically track your exercise minutes through Apple Health when your Apple Watch detects workout activity. \(getHealthTargetText())"
        case "health_cycling_distance":
            return "This requires an Apple Watch or iPhone with GPS. We automatically track your cycling distance through Apple Health during bike rides. \(getHealthTargetText())"
        case "health_sleep_hours":
            return "This requires an Apple Watch or compatible sleep tracking setup. We automatically track your sleep duration through Apple Health. \(getHealthTargetText())"
        case "health_calories_burned":
            return "This requires an Apple Watch. We automatically track calories burned during workouts and daily activity through Apple Health. \(getHealthTargetText())"
        case "health_mindful_minutes":
            return "You need to download a compatible meditation app that connects to Apple Health (you can find options in the Health app under 'Browse' > 'Mind & Body' > 'Mindfulness'). Popular apps like Headspace, Calm, or the built-in Mindfulness app work. We automatically track your meditation sessions through Apple Health. \(getHealthTargetText())"
        case "leetcode":
            return "this habit is automatically tracked through your leetcode account. solve \(habit.commitTarget ?? 1) problem\(habit.commitTarget == 1 ? "" : "s") on leetcode \(habit.habitScheduleType == "weekly" ? "this week" : "today") to complete your goal. your solved problems are synced in real-time."
        default:
            // Fallback for miscellaneous or custom habits
            return "Verify \"\(habit.name)\" by snapping a photo that clearly shows you completing the habit before the end of its scheduled window."
        }
    }
    
    // Helper method to get health target text for verification instructions
    private func getHealthTargetText() -> String {
        guard let targetValue = habit.healthTargetValue,
              let targetUnit = habit.healthTargetUnit else {
            return "No target set."
        }
        
        let formattedValue: String
        switch targetUnit {
        case "steps", "flights", "minutes", "calories":
            formattedValue = "\(Int(targetValue))"
        case "miles", "hours":
            formattedValue = String(format: "%.1f", targetValue)
        default:
            formattedValue = String(format: "%.1f", targetValue)
        }
        
        return "Target: \(formattedValue) \(targetUnit) daily."
    }
    
    // Helper method to format health target values for display
    private func formatHealthTargetValue(_ value: Double, unit: String) -> String {
        switch unit {
        case "steps", "flights", "minutes", "calories":
            return "\(Int(value)) \(unit)"
        case "miles", "hours":
            return String(format: "%.1f %@", value, unit)
        default:
            return String(format: "%.1f %@", value, unit)
        }
    }
    
    private var isFormValid: Bool {
        if habit.isWeeklyHabit {
            return !editedName.isEmpty && editedWeeklyTarget >= 1 && editedWeeklyTarget <= 7
        } else {
            return !editedName.isEmpty && !editedWeekdays.isEmpty
        }
    }
    
    private func resetEditedValues() {
        editedName = habit.name
        editedRecipientId = habit.recipientId
        editedWeekdays = habit.weekdays
        editedPenaltyAmount = habit.penaltyAmount
        editedIsPrivate = habit.isPrivate ?? false
        editedWeeklyTarget = habit.weeklyTarget ?? 3
        editedWeekStartDay = habit.weekStartDay ?? 0
        if let alarmTime = habit.alarmTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            editedAlarmTime = formatter.date(from: alarmTime) ?? Date()
        } else {
            editedAlarmTime = Date()
        }
        editedDailyLimitHours = habit.dailyLimitHours ?? 2.0
        editedHourlyPenaltyRate = habit.hourlyPenaltyRate ?? 10.0
        editedHealthTargetValue = habit.healthTargetValue ?? 10000.0
        editedHealthTargetUnit = habit.healthTargetUnit ?? "steps"
        editedCommitTarget = habit.commitTarget ?? 1
    }
    
    private var habitIcon: String {
        return HabitIconProvider.iconName(for: habit.habitType, variant: .filled)
    }
    
    private func formattedDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        
        guard let date = formatter.date(from: dateString) else {
            return "Unknown date"
        }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formattedAlarmTime(_ time: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: time) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        return time
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func saveChanges() {
        // First show confirmation dialog about next-day changes
        showingUpdateConfirmation = true
    }
    
    private func confirmSaveChanges() {
        guard let userId = authManager.currentUser?.id,
              let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "You need to be logged in"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                var alarmTimeString: String? = nil
                if habit.isAlarmHabit {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    alarmTimeString = formatter.string(from: editedAlarmTime)
                }
                let updatedHabit = Habit(
                    id: habit.id,
                    name: editedName,
                    recipientId: editedRecipientId,
                    weekdays: editedWeekdays,
                    penaltyAmount: editedPenaltyAmount,
                    userId: userId,
                    createdAt: habit.createdAt,
                    updatedAt: habit.updatedAt,
                    habitType: habit.habitType,
                    screenTimeLimitMinutes: habit.screenTimeLimitMinutes,
                    restrictedApps: habit.restrictedApps,
                    studyDurationMinutes: habit.studyDurationMinutes,
                    isPrivate: editedIsPrivate,
                    alarmTime: alarmTimeString,
                    customHabitTypeId: habit.customHabitTypeId,
                    habitScheduleType: habit.habitScheduleType,
                    weeklyTarget: editedWeeklyTarget,
                    weekStartDay: editedWeekStartDay,
                    streak: habit.streak,
                    commitTarget: editedCommitTarget,
                    todayCommitCount: habit.todayCommitCount,
                    currentWeekCommitCount: habit.currentWeekCommitCount,
                    dailyLimitHours: editedDailyLimitHours,
                    hourlyPenaltyRate: editedHourlyPenaltyRate,
                    gamesTracked: habit.gamesTracked,
                    healthTargetValue: editedHealthTargetValue,
                    healthTargetUnit: editedHealthTargetUnit,
                    healthDataType: habit.healthDataType
                )
                let response = try await habitManager.updateHabit(
                    habit: updatedHabit,
                    userId: userId,
                    token: token
                )
                
                await MainActor.run {
                    isLoading = false
                    updateResponse = response
                    showingUpdateSuccess = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isEditing = false
                    }
                }
                
                // Refresh friends with Stripe Connect if recipient changed
                if editedRecipientId != habit.recipientId {
                    print("🔄 [HabitDetailView] Recipient changed, refreshing Stripe Connect recipients...")
                    await friendsManager.refreshFriendsWithStripeConnect()
                    print("✅ [HabitDetailView] Stripe Connect recipients refreshed")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func deleteHabit() {
        guard let userId = authManager.currentUser?.id,
              let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "You need to be logged in"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let response = try await habitManager.deleteHabit(habitId: habit.id, userId: userId, token: token)
                await MainActor.run {
                    isLoading = false
                    deleteResponse = response
                    
                    // Check if this is an immediate deletion
                    if response.deletionTiming == "immediate" {
                        // Remove habit from local arrays immediately
                        habitManager.habits.removeAll { $0.id == habit.id }
                        
                        // Remove from weekday arrays
                        for weekday in habit.weekdays {
                            habitManager.habitsbydate[weekday]?.removeAll { $0.id == habit.id }
                        }
                        
                        // Remove from weekly habits if applicable
                        if habit.isWeeklyHabit {
                            habitManager.weeklyHabits.removeAll { $0.id == habit.id }
                        }
                        
                        // Clear any cached data for this habit
                        DataCacheManager.shared.updateStagedDeletionStatus(for: habit.id, deleted: true)
                        
                        // Dismiss immediately for immediate deletion
                        dismiss()
                    } else {
                        // Show success alert for staged deletion
                        showingDeleteSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to delete habit: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func checkForScheduledDeletion() {
        // First, check cached data for immediate display
        if let cachedDeletion = DataCacheManager.shared.isHabitScheduledForDeletion(habit.id) {
            scheduledDeletion = cachedDeletion
            isCheckingDeletion = false
            print("✅ [HabitDetailView] Found cached scheduled deletion for habit \(habit.id)")
            return
        }
        
        // If no cached data and cache is fresh, the habit is not scheduled for deletion
        if DataCacheManager.shared.isCacheValid() {
            scheduledDeletion = nil
            isCheckingDeletion = false
            print("✅ [HabitDetailView] Cache is fresh, habit \(habit.id) not scheduled for deletion")
            return
        }
        
        // Only make API call if cache is stale or we need to verify
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            isCheckingDeletion = false
            return
        }
        
        isCheckingDeletion = true
        
        Task {
            do {
                let deletion = try await habitManager.checkStagedDeletion(habitId: habit.id, token: token)
                await MainActor.run {
                    scheduledDeletion = deletion
                    isCheckingDeletion = false
                    
                    // Update cache with fresh data
                    if let deletion = deletion, deletion.scheduledForDeletion {
                        DataCacheManager.shared.updateStagedDeletionStatus(for: habit.id, deleted: false)
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingDeletion = false
                    scheduledDeletion = nil
                    print("Error checking scheduled deletion: \(error.localizedDescription)")
                    // Don't show error to user for this background check
                }
            }
        }
    }
    
    private func restoreHabit() {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "You need to be logged in"
            showError = true
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let response = try await habitManager.restoreHabit(habitId: habit.id, token: token)
                await MainActor.run {
                    isLoading = false
                    restoreResponse = response
                    showingRestoreSuccess = true
                    
                    // Update cache immediately to reflect restoration
                    DataCacheManager.shared.updateStagedDeletionStatus(for: habit.id, deleted: true)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private var isScheduledForDeletion: Bool {
        scheduledDeletion?.scheduledForDeletion ?? false
    }
    
    private var isHabitOwner: Bool {
        // Check if the current user is the owner of this habit
        guard let currentUserId = authManager.currentUser?.id else { return false }
        return habit.userId == currentUserId
    }
    
    // Helper to get recipient phone number
    private var recipientPhoneNumber: String? {
        guard let recipientId = habit.recipientId else { return nil }
        return friendsManager.preloadedFriends.first { $0.friendId == recipientId }?.phoneNumber
    }
    
    // helper display name
    private var habitTypeDisplayName: String {
        if let enumType = HabitType(rawValue: habit.habitType) {
            return enumType.displayName
        } else if habit.habitType == "github_commits" {
            return "GitHub Commits"
        } else if habit.isCustomHabit {
            return "Custom"
        } else {
            return habit.habitType.capitalized
        }
    }
    
    private func getTodayWeekday() -> Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        // Convert from 1-7 (Sunday-Saturday) to 0-6 format
        return weekday - 1
    }
    
    private func isHabitCreatedTodayAndNeverVerified() -> Bool {
        // Check if habit was created today
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let createdDate = formatter.date(from: habit.createdAt) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let createdDate = formatter.date(from: habit.createdAt) else {
                return false
            }
            return isCreatedTodayAndNeverVerified(createdDate: createdDate)
        }
        
        return isCreatedTodayAndNeverVerified(createdDate: createdDate)
    }
    
    private func isCreatedTodayAndNeverVerified(createdDate: Date) -> Bool {
        let calendar = Calendar.current
        let isCreatedToday = calendar.isDateInToday(createdDate)
        
        if !isCreatedToday {
            return false
        }
        
        // Check if habit has any verifications
        let hasVerifications = habitManager.habitVerifications[habit.id]?.isEmpty == false
        let isVerifiedToday = habitManager.verifiedHabitsToday[habit.id] ?? false
        
        // Return true only if created today AND has no verifications at all
        return !hasVerifications && !isVerifiedToday
    }
}

// Extension for corner radius on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Extension for DateFormatter configuration
extension DateFormatter {
    func apply(_ configuration: (DateFormatter) -> Void) -> DateFormatter {
        configuration(self)
        return self
    }
} 
