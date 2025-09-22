////
//  ScheduleEditors.swift
//  joy_thief
//
//  Extracted daily & weekly schedule editors from HabitDetailView.
//

import SwiftUI

extension HabitDetailRoot {
    // MARK: - Daily Schedule Editor
    struct DailyScheduleEditor: View {
        @Binding var editedWeekdays: [Int]
        let habitTypeDisplayName: String
        private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        var body: some View {
            VStack {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if editedWeekdays.contains(index) {
                                    editedWeekdays.removeAll { $0 == index }
                                } else {
                                    editedWeekdays.append(index)
                                }
                            }
                        }) {
                            Text(weekdays[index].prefix(1))
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(editedWeekdays.contains(index) ? .black : .white.opacity(0.8))
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(editedWeekdays.contains(index) ? Color.white : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(editedWeekdays.contains(index) ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 0) // Remove horizontal padding to prevent off-centering
            }
        }
    }
    
    // MARK: - Weekly Schedule Editor
    struct WeeklyScheduleEditor: View {
        @Binding var editedWeeklyTarget: Int
        @Binding var editedWeekStartDay: Int
        let habitTypeDisplayName: String
        private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        var body: some View {
            HStack {
                Spacer()
                CompactStepperField(
                    value: $editedWeeklyTarget,
                    range: 1...7,
                    suffix: "time\(editedWeeklyTarget == 1 ? "" : "s") per week"
                )
                Spacer()
            }
        }
    }
} 
