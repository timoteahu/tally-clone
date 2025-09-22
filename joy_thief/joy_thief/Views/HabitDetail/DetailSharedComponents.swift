////
//  DetailSharedComponents.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Shared helper components & styles for HabitDetailView.
//

import SwiftUI

extension HabitDetailRoot {
    // TODO: Move shared helper views and styles here.

    // Helper to derive initials from a full name.
    static func initials(for name: String) -> String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))"
        } else if let first = components.first {
            return String(first.prefix(2))
        }
        return "??"
    }

    // Card used throughout the detail view (accountability partner, penalty, etc.)
    @ViewBuilder
    func enhancedDetailCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.semibold)
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .jtStyle(.body)
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .jtStyle(.body)
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
} 