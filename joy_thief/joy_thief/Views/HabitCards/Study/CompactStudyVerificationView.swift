//
//  CompactStudyVerficiationView.swift
//  joy_thief
//
//  Created by Timothy Hu on 6/18/25.
//

import SwiftUI

struct CompactStudyVerificationView: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isStudySessionActive: Bool
    let startStudySession: () async -> Void
    let completeStudySession: () async -> Void

    var body: some View {
        VStack(spacing: cardHeight * 0.02) {
            if isStudySessionActive {
                VStack(spacing: cardHeight * 0.015) {
                    Text("Study Session Active")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.045)).fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("Keep studying! Complete when done.")
                        .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Button(action: { Task { await completeStudySession() } }) {
                        Text("Complete Session")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04)).fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, cardHeight * 0.015)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(cardWidth * 0.02)
                    }
                }
                .padding(cardWidth * 0.04)
                .background(Color.white.opacity(0.05))
                .cornerRadius(cardWidth * 0.025)
            } else {
                Button(action: { Task { await startStudySession() } }) {
                    HStack(spacing: cardWidth * 0.02) {
                        Image(systemName: "book.fill")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04))
                        Text("Start Study Session")
                            .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04)).fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, cardHeight * 0.018)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(cardWidth * 0.02)
                }
            }
        }
    }
}

