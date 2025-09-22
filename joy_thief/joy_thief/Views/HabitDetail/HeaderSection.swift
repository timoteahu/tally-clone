////
//  HeaderSection.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Header section for HabitDetailView.
//

import SwiftUI

extension HabitDetailRoot {
    struct HeaderSection: View {
        let habit: Habit
        let habitColor: Color
        let habitIcon: String
        let formattedDate: String
        let isScheduledForDeletion: Bool
        @Binding var showingDeleteConfirmation: Bool
        let alarmTime: String?
        let formattedAlarmTime: (String) -> String
        
        var body: some View {
            // Replicate the original header card UI
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [habitColor.opacity(0.6), habitColor.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 16) {
                        HStack {
                            // Habit Icon
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 60, height: 60)
                                
                                Group {
                                    if habit.habitType.hasPrefix("health_") || HabitIconProvider.isSystemIcon(habitIcon) {
                                        // Health habits and other system icons use SF Symbols
                                        Image(systemName: habitIcon)
                                            .font(.custom("EBGaramond-Regular", size: 28)).fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    } else {
                                        // Custom and other habits use asset images
                                        Image(habitIcon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 28, height: 28)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(habit.name)
                                    .jtStyle(.title)
                                    .foregroundColor(.white)
                                
                                Text("Created \(formattedDate)")
                                    .jtStyle(.body)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Spacer()
                            
                            Button(action: { showingDeleteConfirmation = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: isScheduledForDeletion ? "checkmark" : "trash")
                                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                                        .foregroundColor(isScheduledForDeletion ? .green : .red)
                                }
                            }
                            .disabled(isScheduledForDeletion)
                        }
                        
                        // Alarm notification if applicable
                        if habit.isAlarmHabit, let alarmTime {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "alarm")
                                        .font(.custom("EBGaramond-Regular", size: 14)).fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }
                                
                                Text("Wake up at \(formattedAlarmTime(alarmTime))")
                                    .jtStyle(.body)
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(24)
                }
                .cornerRadius(20, corners: [.topLeft, .topRight])
            }
            .background(Color(.systemGray6).opacity(0.05))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
} 