//
//  AlarmUnifiedCardContent.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct AlarmUnifiedCardContent: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isWithinCheckInWindow: Bool
    let isWithinVerificationWindow: Bool
    let alarmCheckInTime: Date?
    let formattedTime: (Date) -> String
    let formattedAlarmTime: (String) -> String
    let checkInForAlarm: () -> Void
    @Binding var cameraMode: SwipeableHabitCard.CameraMode
    @Binding var showingCamera: Bool
    let habitTypeAccentColor: Color
    let getHabitIcon: () -> String
    let weeklyProgressBadge: AnyView
    let getTimeWindows: (String) -> (checkInStart: Date, checkInEnd: Date)
    let setupVerificationView: () async -> Void
    let onExpand: () -> Void
    
    // Add additional camera and verification state bindings
    @Binding var isVerifying: Bool
    @Binding var firstImageTaken: Bool
    let verifyWithBothImages: (String, String) async -> Void
    let getSuccessMessage: (String) -> String
    
    // Add habitManager and detail view state
    @ObservedObject var habitManager: HabitManager
    @State private var showingDetailView = false
    @State private var currentTime = Date()
    
    // Timer for updating countdown
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: cardHeight * 0.15)
                // Large centered icon
                Image(getHabitIcon())
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1.65)
                    .frame(width: cardWidth * 0.22, height: cardWidth * 0.22)
                    .foregroundColor(.white)
                    .padding(.bottom, cardHeight * 0.04)

                // Centered habit name
                Text(habit.name.isEmpty ? "Insert Habit Name" : habit.name)
                    .font(.custom("EB Garamond", size: cardWidth * 0.09).weight(.medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // Subtitle (alarm time)
                if let alarmTime = habit.alarmTime, !alarmTime.isEmpty {
                    Text("\(formattedAlarmTime(alarmTime)).")
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)

                    // Show active window or countdown text
                    let windows = getTimeWindows(alarmTime)
                    let now = currentTime
                    let timeUntilStart = windows.checkInStart.timeIntervalSince(now)
                    let minutes = Int(ceil(timeUntilStart / 60))
                    if now < windows.checkInStart && minutes > 15 {
                        if let activeWindowString = activeWindowString {
                            Text(activeWindowString)
                                .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                                .foregroundColor(countdownColor)
                                .multilineTextAlignment(.center)
                                .padding(.top, 32)
                        }
                    } else {
                        Text(countdownText)
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))
                            .foregroundColor(countdownColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 32)
                    }
                }

                Spacer(minLength: 0)
                // Compact verify button - grayed out when not in check-in window
                Button(action: {
                    // Start the camera flow directly
                    cameraMode = .selfie
                    firstImageTaken = false
                    showingCamera = true
                }) {
                    Text("verify")
                        .font(.custom("EB Garamond", size: cardWidth * 0.065))
                        .foregroundColor(isWithinCheckInWindow ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: cardHeight * 0.11)
                        .background(isWithinCheckInWindow ? Color.white : Color.white.opacity(0.3))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, cardWidth * 0.3)
                .padding(.bottom, cardHeight * 0.24)
                .disabled(!isWithinCheckInWindow)
            }
            .frame(width: cardWidth, height: cardHeight)
            .padding(.top, cardHeight * 0.1)
            .task {
                await setupVerificationView()
            }
            .onReceive(timer) { _ in
                currentTime = Date()
            }
            
            // Tap instruction in bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: cardWidth * 0.01) {
                        Text("take a photo of yourself and activity to verify")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                            .foregroundColor(.white.opacity(0.6))
                        Image(systemName: "camera")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.028))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, cardWidth * 0.05)
                    .padding(.bottom, cardHeight * 0.075)
                }
            }
            
            // View details button in top right
            Button(action: {
                showingDetailView = true
                // Refresh friends with Stripe Connect for habit detail view
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
            HabitDetailView(habit: habit, habitManager: habitManager)
        }
    }
    
    // MARK: - Computed Properties
    
    private var countdownText: String {
        guard let alarmTime = habit.alarmTime, !alarmTime.isEmpty else {
            return ""
        }
        
        let windows = getTimeWindows(alarmTime)
        let now = currentTime
        
        // Check if habit was created today after the alarm time window has passed
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        if let createdDate = formatter.date(from: habit.createdAt),
           calendar.isDateInToday(createdDate) {
            // If created today, check if it was created after the check-in window already ended
            if createdDate > windows.checkInEnd && now > windows.checkInEnd {
                // Habit was created after today's alarm window already passed, so don't show overdue
                return "verification starts tomorrow"
            }
        }
        
        if now < windows.checkInStart {
            // Before check-in window
            let timeUntilStart = windows.checkInStart.timeIntervalSince(now)
            let minutes = Int(ceil(timeUntilStart / 60))
            
            // Only show countdown if 15 minutes or less before window opens
            if minutes <= 15 {
                return "\(minutes)m until verification opens"
            } else {
                return ""
            }
        } else if now >= windows.checkInStart && now <= windows.checkInEnd {
            // Within check-in window
            if let checkInTime = alarmCheckInTime {
                // User has checked in, show verification countdown
                let verificationEnd = checkInTime.addingTimeInterval(30 * 60) // 30 minutes
                let timeLeft = verificationEnd.timeIntervalSince(now)
                
                if timeLeft > 0 {
                    let minutes = Int(ceil(timeLeft / 60))
                    return "\(minutes)m left to verify"
                } else {
                    return "verification overdue"
                }
            } else {
                // User hasn't checked in yet, show check-in window countdown
                let timeLeft = windows.checkInEnd.timeIntervalSince(now)
                let minutes = Int(ceil(timeLeft / 60))
                return "\(minutes)m left to verify"
            }
        } else {
            // Past check-in window - check if created today after the window
            let formatter = ISO8601DateFormatter()
            if let createdDate = formatter.date(from: habit.createdAt),
               calendar.isDateInToday(createdDate) && createdDate > windows.checkInEnd {
                // If created today after the alarm window already passed, don't show overdue
                return "verification starts tomorrow"
            }
            return "verification overdue"
        }
    }
    
    private var countdownColor: Color {
        return .white.opacity(0.8)
    }
    
    private var activeWindowString: String? {
        guard let alarmTime = habit.alarmTime, !alarmTime.isEmpty else { return nil }
        let windows = getTimeWindows(alarmTime)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startTime = formatter.string(from: windows.checkInStart)
        let endTime = formatter.string(from: windows.checkInEnd)
        return "open: \(startTime) - \(endTime)"
    }
}
