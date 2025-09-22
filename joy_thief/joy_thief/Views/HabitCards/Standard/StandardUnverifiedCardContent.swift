//
//  StandardUnverifiedCardContent.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct StandardUnverifiedCardContent: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let habitTypeAccentColor: Color
    let getHabitIcon: () -> String
    let weeklyProgressBadge: AnyView
    var onVerify: (() -> Void)? = nil // Add a callback for the verify button
    let onExpand: () -> Void // Add this closure
    
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

                // Subtitle (e.g., by 10pm.)
                if let subtitle = habitSubtitle {
                    Text(subtitle)
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Spacer(minLength: cardHeight * 0.08) // Reduced spacer height
                // Compact verify button
                Button(action: {
                    // Start the camera flow directly
                    cameraMode = .selfie
                    firstImageTaken = false
                    showingCamera = true
                }) {
                    Text("verify")
                        .font(.custom("EB Garamond", size: cardWidth * 0.065)) // Slightly increased font size
                        .foregroundColor(.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: cardHeight * 0.11) // Slightly increased height
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, cardWidth * 0.3) // Increased horizontal padding to make button narrower
                .padding(.bottom, cardHeight * 0.24)

            }
            .frame(width: cardWidth, height: cardHeight)
            .padding(.top, cardHeight * 0.1)
            
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

    // Helper for subtitle (e.g., by 10pm.)
    private var habitSubtitle: String? {
        if habit.habitType == "alarm", let alarmTime = habit.alarmTime, !alarmTime.isEmpty {
            return "by \(formattedAlarmTime(alarmTime))."
        }
        
        // For non-alarm habits, return the habit type
        switch habit.habitType {
        case "gym":
            return "gym habit."
        case "yoga": 
            return "yoga habit."
        case "outdoors":
            return "outdoor habit."
        case "cycling":
            return "cycling habit."
        case "cooking":
            return "cooking habit."
        case "studying":
            return "study habit."
        case "screenTime":
            return "screen time habit."
        case let type where type.hasPrefix("custom_"):
            return "custom habit."
        default:
            return nil
        }
    }

    private func formattedAlarmTime(_ timeString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: timeString) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }
        return timeString
    }
}
