////
//  SuggestedFriendRow.swift
//  joy_thief
//
//  Extracted from FriendsView on 2025-06-18.
//

import SwiftUI
import UIKit

struct SuggestedFriendRow: View {
    let suggestedFriend: SuggestedFriend

    @StateObject private var friendRequestManager = FriendRequestManager.shared
    @EnvironmentObject var unifiedFriendManager: UnifiedFriendManager
    @State private var isAdding = false
    @State private var isRequestSent = false
    @State private var showError = false
    @State private var errorMessage = ""

    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(BranchService.self) private var branchService

    // MARK: - Optimized URLSession Configuration
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 20.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    var body: some View {
        HStack(spacing: 14) {
            // Avatar – cached image or generated initials
            if suggestedFriend.avatarUrl200 != nil || suggestedFriend.avatarUrl80 != nil {
                CachedAvatarView(
                    url80: suggestedFriend.avatarUrl80,
                    url200: suggestedFriend.avatarUrl200,
                    urlOriginal: suggestedFriend.avatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(initials(for: suggestedFriend.name))
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestedFriend.name)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                if suggestedFriend.isExistingUser {
                    Text("On Tally")
                        .jtStyle(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if !isAdding {
                if suggestedFriend.isExistingUser {
                    let hasSentRequest = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == suggestedFriend.userId }) || isRequestSent

                    if !hasSentRequest {
                        Button(action: {
                            Task { await sendFriendRequest() }
                        }) {
                            Text("ADD")
                                .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    } else {
                        Text("REQUEST SENT")
                            .font(.custom("EBGaramond-Regular", size: 14)).fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(12)
                    }
                } else {
                    Button(action: { shareInviteLink() }) {
                        Text("INVITE")
                            .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Check if we've already sent a request to this user
            isRequestSent = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == suggestedFriend.userId })
        }
        .onChange(of: unifiedFriendManager.sentRequests) { oldValue, newValue in
            // Update state when sent requests change (e.g., when returning to tab)
            isRequestSent = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == suggestedFriend.userId })
        }
    }

    // MARK: - Private helpers

    private func sendFriendRequest() async {
        guard let userId = suggestedFriend.userId else { return }
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        guard !isAdding else { return }

        isAdding = true
        isRequestSent = true // optimistic update

        do {
            let friendRequest = try await friendRequestManager.sendFriendRequest(to: userId, message: "Friend request from contacts", token: token)
            
            // Also add to unified manager for immediate UI consistency
            let unifiedRequest = UnifiedSentFriendRequest(
                id: friendRequest.id,
                receiverId: friendRequest.receiverId,
                receiverName: suggestedFriend.name,
                receiverPhone: suggestedFriend.phoneNumber,
                receiverAvatarVersion: suggestedFriend.avatarVersion,
                receiverAvatarUrl80: suggestedFriend.avatarUrl80,
                receiverAvatarUrl200: suggestedFriend.avatarUrl200,
                receiverAvatarUrlOriginal: suggestedFriend.avatarUrlOriginal,
                message: "Friend request from contacts",
                status: "pending",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            
            unifiedFriendManager.sentRequests.append(unifiedRequest)
        } catch {
            isRequestSent = false
            errorMessage = error.localizedDescription
            showError = true
        }

        isAdding = false
    }

    private func shareInviteLink() {
        guard let currentUser = authManager.currentUser else {
            print("No current user available for invite link generation")
            return
        }

        Task {
            do {
                let inviteLink = try await branchService.generateInviteLink(for: currentUser)
                await MainActor.run {
                    self.sendSMSToContact(phoneNumber: self.suggestedFriend.phoneNumber, inviteLink: inviteLink.url, inviterName: currentUser.name)
                }
            } catch {
                await MainActor.run {
                    print("Failed to generate invite link: \(error.localizedDescription)")
                    self.fallbackToShareSheet(inviteLink: "")
                }
            }
        }
    }

    private func sendSMSToContact(phoneNumber: String, inviteLink: String, inviterName: String) {
        let cleanPhoneNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        let message = "Hey! \(inviterName) invited you to join Tally - an app to build better habits together. Check it out: \(inviteLink)"

        guard let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode SMS message")
            return
        }

        let smsURL = URL(string: "sms:\(cleanPhoneNumber)&body=\(encoded)")

        if let url = smsURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            print("Cannot open SMS app or invalid phone number: \(phoneNumber)")
            fallbackToShareSheet(inviteLink: inviteLink)
        }
    }

    private func fallbackToShareSheet(inviteLink: String) {
        let shareMessage = "Join me on Tally to build better habits together! \(inviteLink)"
        let activityVC = UIActivityViewController(activityItems: [shareMessage], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
} 
