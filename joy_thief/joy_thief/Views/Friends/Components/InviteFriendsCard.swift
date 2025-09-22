////
//  InviteFriendsCard.swift
//  joy_thief
//
//  Extracted from FriendsView on 2025-06-18.
//

import SwiftUI
import UIKit

struct InviteFriendsCard: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(BranchService.self) private var branchService

    @State private var showingShare = false
    @State private var inviteLink: String?
    @State private var isGeneratingLink = false
    @State private var isPressing = false

    // Simple in-memory cache for invite links (valid for 5 minutes)
    @State private var cachedInviteLink: String?
    @State private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    var body: some View {
        Button(action: {
            generateAndShareInviteLink()
        }) {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.custom("EBGaramond-Regular", size: 32))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite friends on Tally")
                        .jtStyle(.body)
                        .foregroundColor(.white)
                    if let link = inviteLink {
                        Text(link)
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if isGeneratingLink {
                        Text("Generating link…")
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                Group {
                    switch branchService.linkGenerationState {
                    case .generating:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    case .failed:
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.orange)
                            .font(.custom("EBGaramond-Regular", size: 20))
                    default:
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                            .font(.custom("EBGaramond-Regular", size: 20))
                    }
                }
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.13))
                .clipShape(Circle())
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .scaleEffect(isPressing ? 0.95 : 1.0)
            .opacity(isPressing ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressing)
        }
        .disabled(branchService.linkGenerationState == .generating)
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.0).onChanged { _ in
                isPressing = true
            }.onEnded { _ in
                isPressing = false
            }
        )
        .sheet(isPresented: $showingShare) {
            if let link = inviteLink {
                if let inviterName = authManager.currentUser?.name {
                    let message = "Hey! \(inviterName) invited you to join Tally – an app to build better habits together. Check it out: \(link)"
                    ShareSheet(items: [message])
                } else {
                    ShareSheet(items: [link])
                }
            }
        }
    }

    // MARK: - Private helpers

    private func generateAndShareInviteLink() {
        // Get the current user
        guard let currentUser = authManager.currentUser else {
            print("No current user available for invite link generation")
            return
        }

        isGeneratingLink = true

        Task {
            do {
                let inviteLink = try await branchService.generateInviteLink(for: currentUser)
                await MainActor.run {
                    self.isGeneratingLink = false
                    self.inviteLink = inviteLink.url
                    self.cachedInviteLink = inviteLink.url
                    self.cacheTimestamp = Date()
                    self.showingShare = true
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingLink = false
                    print("Failed to generate invite link: \(error.localizedDescription)")
                }
            }
        }
    }
} 