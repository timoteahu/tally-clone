import SwiftUI

// MARK: - Recipient Habit Card

struct RecipientHabitCard: View {
    let habitWithAnalytics: HabitWithAnalytics
    @State private var isExpanded = false
    @State private var isTickling = false
    @State private var showTickleAlert = false
    @State private var tickleError: String?
    @State private var showingDetailView = false
    @State private var showingTickleMessageInput = false
    @State private var tickleMessage: String = ""
    
    private var isInactive: Bool {
        // Check if habit is marked as inactive
        habitWithAnalytics.habitScheduleType == "one_time" && habitWithAnalytics.completedAt != nil ||
        !(habitWithAnalytics.isActive ?? true)
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // Compact card content (always visible)
                compactContent
                
                // Expanded details (shown when expanded)
                if isExpanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
        )
        .opacity(isInactive ? 0.6 : 1.0)
        .alert(isPresented: $showTickleAlert) {
            if let error = tickleError {
                Alert(
                    title: Text("tickle failed"),
                    message: Text(error),
                    dismissButton: .default(Text("ok"))
                )
            } else {
                Alert(
                    title: Text("tickle sent!"),
                    message: Text("\(habitWithAnalytics.ownerName ?? "User") has been tickled"),
                    dismissButton: .default(Text("ok"))
                )
            }
        }
        .sheet(isPresented: $showingDetailView) {
            HabitDetailView(
                habit: convertToHabit(), 
                habitManager: HabitManager.shared,
                ownerName: habitWithAnalytics.ownerName,
                ownerPhone: habitWithAnalytics.ownerPhone
            )
        }
        .sheet(isPresented: $showingTickleMessageInput) {
            NavigationView {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 24) {
                        Text("send a tickle")
                            .font(.custom("EBGaramond-Regular", size: 28))
                            .foregroundColor(.white)
                            .padding(.top, 20)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("message (optional)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                            
                            TextField("add a message...", text: $tickleMessage)
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                }
                .navigationBarItems(
                    leading: Button("cancel") {
                        tickleMessage = ""
                        showingTickleMessageInput = false
                    }
                    .foregroundColor(.white),
                    trailing: Button("send tickle") {
                        showingTickleMessageInput = false
                        sendTickle()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.blue.opacity(0.8))
                )
            }
            .presentationDetents([.height(300)])
        }
    }
    
    // MARK: - Compact Content
    
    private var compactContent: some View {
        HStack(spacing: 16) {
            // Habit icon using app's icon system
            habitIcon
            
            // Habit info
            VStack(alignment: .leading, spacing: 4) {
                Text(habitWithAnalytics.name)
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 0) {
                    if let ownerName = habitWithAnalytics.ownerName {
                        Text(ownerName)
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        Text(" • ")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Text(priceDisplay)
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Quick stats
            HStack(spacing: 12) {
                // Inactive badge
                if isInactive {
                    Text("inactive")
                        .font(.custom("EBGaramond-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                
                // Today's completion status
                if isTodayRequired && !isInactive {
                    HStack(spacing: 4) {
                        Image(systemName: isCompletedToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isCompletedToday ? .green : .white.opacity(0.5))
                        Text(isCompletedToday ? "done" : "pending")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(isCompletedToday ? .green : .white.opacity(0.7))
                    }
                }
                
                // Expand indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Financial metrics
            HStack(spacing: 20) {
                metricColumn(
                    title: "total earned",
                    value: habitWithAnalytics.analytics?.formattedTotalEarned ?? "0 credits"
                )
                
                metricColumn(
                    title: "success rate",
                    value: habitWithAnalytics.analytics?.formattedSuccessRate ?? "—"
                )
            }
            
            // Performance metrics
            HStack(spacing: 20) {
                metricColumn(
                    title: "times completed",
                    value: "\(habitWithAnalytics.analytics?.totalCompletions ?? 0)"
                )
                
                metricColumn(
                    title: "times failed",
                    value: "\(habitWithAnalytics.analytics?.totalFailures ?? 0)"
                )
            }
            
            // Weekly progress (for weekly habits)
            if habitWithAnalytics.habitScheduleType == "weekly", 
               let weeklyTarget = habitWithAnalytics.weeklyTarget {
                weeklyProgressView(target: weeklyTarget)
            }
            
            // Additional stats with view details button
            HStack {
                // Only show current streak for active habits
                if !isInactive {
                    metricColumn(
                        title: "current streak",
                        value: "\(habitWithAnalytics.streak ?? 0) days"
                    )
                }
                
                Spacer()
                
                // View details button
                Button(action: {
                    showingDetailView = true
                }) {
                    HStack(spacing: 4) {
                        Text("view details")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.9))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            // Action button based on completion status
            // For alarm habits, only show view post button when completed (no nudging)
            if isTodayRequired && !isInactive && (!isAlarmHabit || isCompletedToday) {
                Button(action: {
                    if isCompletedToday {
                        // View post action
                        viewPost()
                    } else {
                        // Show tickle message input
                        showingTickleMessageInput = true
                    }
                }) {
                    HStack(spacing: 8) {
                        if isTickling && !isCompletedToday {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: isCompletedToday ? "text.bubble" : "bell.badge")
                                .font(.system(size: 14, weight: .medium))
                        }
                        
                        Text(isCompletedToday ? "view post" : isTickling ? "tickling..." : "tickle")
                            .font(.custom("EBGaramond-Medium", size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isCompletedToday ? Color.blue.opacity(0.3) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isCompletedToday ? Color.blue.opacity(0.5) : Color.white, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isTickling)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Helper Views
    
    private var habitIcon: some View {
        Group {
            if habitWithAnalytics.habitType.hasPrefix("health_") {
                // Health habits use SF Symbols
                Image(systemName: HabitIconProvider.iconName(for: habitWithAnalytics.habitType, variant: .filled))
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
            } else if habitWithAnalytics.habitType == "league_of_legends" || 
                      habitWithAnalytics.habitType == "valorant" || 
                      habitWithAnalytics.habitType == "github_commits" {
                Image(HabitIconProvider.iconName(for: habitWithAnalytics.habitType, variant: .filled))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                // Regular habits (gym, outdoor, etc.) - show as filled icons
                Image(HabitIconProvider.iconName(for: habitWithAnalytics.habitType, variant: .filled))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
    }
    
    private func metricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.custom("EBGaramond-Bold", size: 16))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func weeklyProgressView(target: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("weekly progress")
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(.white.opacity(0.5))
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.6))
                        .frame(width: progressWidth(in: geometry.size.width, target: target), height: 8)
                }
            }
            .frame(height: 8)
            
            // Progress text
            Text(target == 0 ? "—" : "\(currentWeekCompletions) of \(target) completed this week")
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    // MARK: - Computed Properties
    
    private var isAlarmHabit: Bool {
        habitWithAnalytics.habitType == "alarm"
    }
    
    private var priceDisplay: String {
        if habitWithAnalytics.habitType == "league_of_legends" || 
           habitWithAnalytics.habitType == "valorant" {
            let amount = habitWithAnalytics.hourlyPenaltyRate ?? habitWithAnalytics.penaltyAmount
            if amount == 0 {
                print("⚠️ [RecipientHabitCard] Zero hourly rate for gaming habit: \(habitWithAnalytics.name)")
                return "--/hr"
            }
            // Format with appropriate decimal places
            if amount.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f/hr", amount)
            } else {
                return String(format: "%.2f/hr", amount)
            }
        } else {
            if habitWithAnalytics.penaltyAmount == 0 {
                print("⚠️ [RecipientHabitCard] Zero penalty amount for habit: \(habitWithAnalytics.name)")
                return "--/miss"
            }
            // Format with appropriate decimal places
            if habitWithAnalytics.penaltyAmount.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f/miss", habitWithAnalytics.penaltyAmount)
            } else {
                return String(format: "%.2f/miss", habitWithAnalytics.penaltyAmount)
            }
        }
    }
    
    private var lastActiveDisplay: String? {
        return ActivityFormatter.getActivityDisplayText(from: habitWithAnalytics.ownerLastActive)
    }
    
    private var isOwnerActiveNow: Bool {
        guard let lastActive = habitWithAnalytics.ownerLastActive else {
            return false
        }
        
        let diff = Date().timeIntervalSince(lastActive)
        return diff < 300 // Active within 5 minutes
    }
    
    private var isTodayRequired: Bool {
        // For daily habits, check if today is in the weekdays
        if habitWithAnalytics.habitScheduleType == "daily" || habitWithAnalytics.habitScheduleType == nil {
            guard let weekdays = habitWithAnalytics.weekdays else { return false }
            let today = Calendar.current.component(.weekday, from: Date())
            // Convert to PostgreSQL weekday (0 = Sunday, 6 = Saturday)
            let postgresWeekday = (today - 1 + 7) % 7
            return weekdays.contains(postgresWeekday)
        }
        
        // For weekly habits, always show status
        if habitWithAnalytics.habitScheduleType == "weekly" {
            return true
        }
        
        // For one-time habits, check if not completed
        if habitWithAnalytics.habitScheduleType == "one_time" {
            return habitWithAnalytics.completedAt == nil
        }
        
        return false
    }
    
    private var isCompletedToday: Bool {
        // Check if there's a verification for today
        let hasVerificationToday: Bool = {
            guard let lastVerification = habitWithAnalytics.analytics?.lastVerificationDate else {
                return false
            }
            
            // Get the owner's timezone or fall back to current timezone
            let ownerTimeZone = habitWithAnalytics.ownerTimezone.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
            
            // Create calendar with owner's timezone
            var calendar = Calendar.current
            calendar.timeZone = ownerTimeZone
            
            // Get "today" in the owner's timezone
            let nowInOwnerTZ = Date()
            let todayInOwnerTZ = calendar.dateComponents([.year, .month, .day], from: nowInOwnerTZ)
            
            // Get verification date components in owner's timezone
            let verificationDateInOwnerTZ = calendar.dateComponents([.year, .month, .day], from: lastVerification)
            
            return todayInOwnerTZ.year == verificationDateInOwnerTZ.year && 
                   todayInOwnerTZ.month == verificationDateInOwnerTZ.month && 
                   todayInOwnerTZ.day == verificationDateInOwnerTZ.day
        }()
        
        // For weekly habits, check if posted today OR if target is met
        if habitWithAnalytics.habitScheduleType == "weekly" {
            let currentCompletions = habitWithAnalytics.weeklyProgress?.currentCompletions ?? 0
            let targetCompletions = habitWithAnalytics.weeklyProgress?.targetCompletions ?? 1
            let isTargetMet = currentCompletions >= targetCompletions
            
            return hasVerificationToday || isTargetMet
        }
        
        // For daily/one-time habits, check if verified today
        return hasVerificationToday
    }
    
    private var currentWeekCompletions: Int {
        // Use real weekly progress data if available
        return habitWithAnalytics.weeklyProgress?.currentCompletions ?? 0
    }
    
    private func progressWidth(in totalWidth: CGFloat, target: Int) -> CGFloat {
        let progress = min(CGFloat(currentWeekCompletions) / CGFloat(target), 1.0)
        return totalWidth * progress
    }
    
    // MARK: - Habit Conversion
    
    private func convertToHabit() -> Habit {
        // Convert dates to string format
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let createdAtString = habitWithAnalytics.createdAt.map { dateFormatter.string(from: $0) } ?? ""
        let updatedAtString = habitWithAnalytics.updatedAt.map { dateFormatter.string(from: $0) } ?? ""
        
        return Habit(
            id: habitWithAnalytics.id.uuidString,
            name: habitWithAnalytics.name,
            recipientId: habitWithAnalytics.recipientId?.uuidString,
            weekdays: habitWithAnalytics.weekdays ?? [],
            penaltyAmount: Float(habitWithAnalytics.penaltyAmount),
            userId: habitWithAnalytics.userId.uuidString,
            createdAt: createdAtString,
            updatedAt: updatedAtString,
            habitType: habitWithAnalytics.habitType,
            screenTimeLimitMinutes: habitWithAnalytics.screenTimeLimitMinutes,
            restrictedApps: habitWithAnalytics.restrictedApps,
            studyDurationMinutes: habitWithAnalytics.studyDurationMinutes,
            isPrivate: habitWithAnalytics.isPrivate,
            alarmTime: habitWithAnalytics.alarmTime,
            customHabitTypeId: habitWithAnalytics.customHabitTypeId?.uuidString,
            habitScheduleType: habitWithAnalytics.habitScheduleType,
            weeklyTarget: habitWithAnalytics.weeklyTarget,
            weekStartDay: habitWithAnalytics.weekStartDay,
            streak: habitWithAnalytics.streak,
            commitTarget: habitWithAnalytics.commitTarget,
            todayCommitCount: nil,
            currentWeekCommitCount: nil,
            dailyLimitHours: nil,
            hourlyPenaltyRate: habitWithAnalytics.hourlyPenaltyRate,
            gamesTracked: nil
        )
    }
    
    // MARK: - Actions
    
    private func viewPost() {
        // Navigate to feed tab and scroll to the most recent post for this habit
        let habitId = habitWithAnalytics.id.uuidString
        print("📱 [RecipientHabitCard] viewPost called for habit: \(habitWithAnalytics.name) with id: \(habitId)")
        NotificationCenter.default.post(
            name: Notification.Name("NavigateToHabitPost"), 
            object: nil,
            userInfo: ["habitId": habitId]
        )
    }
    
    private func sendTickle() {
        Task {
            await sendTickleNotification()
        }
    }
    
    @MainActor
    private func sendTickleNotification() async {
        guard !isTickling else { return }
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            tickleError = "authentication required"
            showTickleAlert = true
            return
        }
        
        isTickling = true
        tickleError = nil
        
        do {
            // Create the API request (use lowercase UUID for database compatibility)
            let url = URL(string: "\(AppConfig.baseURL)/habits/\(habitWithAnalytics.id.uuidString.lowercased())/tickle")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add message to request body
            let body: [String: Any] = ["message": tickleMessage]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                // Show success feedback
                showTickleAlert = true
                
                // Clear the message for next time
                tickleMessage = ""
                
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showTickleAlert = false
                }
            } else if httpResponse.statusCode == 429 {
                // Rate limit error - parse the error message
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    throw NSError(domain: "RateLimit", code: 429, userInfo: [NSLocalizedDescriptionKey: detail])
                } else {
                    throw NSError(domain: "RateLimit", code: 429, userInfo: [NSLocalizedDescriptionKey: "you're tickling too fast! please wait a moment."])
                }
            } else {
                throw NSError(domain: "APIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "failed to send tickle"])
            }
        } catch {
            tickleError = error.localizedDescription
            showTickleAlert = true
        }
        
        isTickling = false
    }
}

// MARK: - Preview

struct RecipientHabitCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RecipientHabitCard(habitWithAnalytics: sampleHabitWithAnalytics)
            RecipientHabitCard(habitWithAnalytics: sampleWeeklyHabit)
        }
        .padding(.horizontal, 20)
        .background(AppBackground())
        .preferredColorScheme(.dark)
    }
    
    static var sampleHabitWithAnalytics: HabitWithAnalytics {
        HabitWithAnalytics(
            id: UUID(),
            name: "Morning Gym Session",
            recipientId: UUID(),
            habitType: "gym",
            weekdays: [1, 2, 3, 4, 5],
            penaltyAmount: 25.0,
            hourlyPenaltyRate: nil,
            userId: UUID(),
            createdAt: Date().addingTimeInterval(-86400 * 7),
            updatedAt: Date(),
            studyDurationMinutes: nil,
            screenTimeLimitMinutes: nil,
            restrictedApps: nil,
            alarmTime: "07:00",
            isPrivate: false,
            customHabitTypeId: nil,
            habitScheduleType: "daily",
            weeklyTarget: nil,
            weekStartDay: nil,
            streak: 5,
            commitTarget: nil,
            isActive: true,
            completedAt: nil,
            analytics: sampleAnalytics,
            ownerName: "John Doe",
            ownerPhone: "+1234567890",
            ownerLastActive: Date().addingTimeInterval(-86400 * 2), // 2 days ago
            ownerTimezone: "America/New_York",
            weeklyProgress: nil // Daily habits don't have weekly progress
        )
    }
    
    static var sampleWeeklyHabit: HabitWithAnalytics {
        HabitWithAnalytics(
            id: UUID(),
            name: "Study Sessions",
            recipientId: UUID(),
            habitType: "studying",
            weekdays: nil,
            penaltyAmount: 20.0,
            hourlyPenaltyRate: nil,
            userId: UUID(),
            createdAt: Date().addingTimeInterval(-86400 * 14),
            updatedAt: Date(),
            studyDurationMinutes: 60,
            screenTimeLimitMinutes: nil,
            restrictedApps: nil,
            alarmTime: nil,
            isPrivate: false,
            customHabitTypeId: nil,
            habitScheduleType: "weekly",
            weeklyTarget: 5,
            weekStartDay: 0,
            streak: 12,
            commitTarget: nil,
            isActive: true,
            completedAt: nil,
            analytics: sampleAnalytics,
            ownerName: "Jane Smith",
            ownerPhone: "+0987654321",
            ownerLastActive: Date(), // Active today
            ownerTimezone: "America/Los_Angeles",
            weeklyProgress: WeeklyProgress(
                currentCompletions: 3,
                targetCompletions: 5,
                weekStartDate: Date().addingTimeInterval(-86400 * 3) // 3 days ago
            )
        )
    }
    
    static var sampleAnalytics: RecipientAnalytics {
        RecipientAnalytics(
            id: UUID(),
            recipientId: UUID(),
            habitId: UUID(),
            habitOwnerId: UUID(),
            totalEarned: 75.0,
            pendingEarnings: 25.0,
            totalCompletions: 15,
            totalFailures: 3,
            totalRequiredDays: 18,
            successRate: 83.3,
            firstRecipientDate: Date().addingTimeInterval(-86400 * 21),
            lastVerificationDate: Date().addingTimeInterval(-86400),
            lastPenaltyDate: Date().addingTimeInterval(-86400 * 3),
            createdAt: Date().addingTimeInterval(-86400 * 21),
            updatedAt: Date()
        )
    }
}
