//
//  GymUnifiedCardContent.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct GymUnifiedCardContent: View {
    let habit: Habit
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let habitTypeAccentColor: Color
    let getHabitIcon: () -> String
    let weeklyProgressBadge: AnyView
    var onVerify: (() -> Void)? = nil // Add a callback for the verify button
    var onExpand: (() -> Void) // Add a callback for the expand button
    
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

                // Subtitle (e.g., Gym Bro or recipient)
                if let recipientName = habit.getRecipientName(), !recipientName.isEmpty {
                    Text("with \(recipientName)")
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                } else {
                    Text("gym habit.")
                        .font(.custom("EB Garamond", size: cardWidth * 0.055))
                        .italic()
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Spacer(minLength: cardHeight * 0.08)
                // Compact verify button
                Button(action: {
                    // Start the camera flow directly
                    cameraMode = .selfie
                    firstImageTaken = false
                    showingCamera = true
                }) {
                    Text("verify")
                        .font(.custom("EB Garamond", size: cardWidth * 0.065))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: cardHeight * 0.11)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, cardWidth * 0.3)
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
}

