////
//  AllContactsView.swift
//  joy_thief
//
//  Extracted from FriendsView on 2025-06-18.
//

import SwiftUI
import UIKit

struct AllContactsView: View {
    @EnvironmentObject var contactManager: ContactManager
    @EnvironmentObject var friendsManager: FriendsManager
    @Environment(BranchService.self) private var branchService

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var onTallyDisplayCount = 50
    @State private var notOnTallyDisplayCount = 50

    // Cache the filtered lists to prevent recomputation
    @State private var cachedAllContacts: [SuggestedFriend] = []
    @State private var lastSearchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Search all contacts", text: $searchText)
                            .foregroundColor(.white)
                            .disableAutocorrection(true)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            let allContacts = filteredAllContacts
                            if allContacts.isEmpty {
                                VStack(spacing: 16) {
                                    Text("📱 No Contacts")
                                        .jtStyle(.title)
                                        .foregroundColor(.white)
                                        .padding(.top, 40)

                                    Text("No contacts found. Make sure you've granted contacts permission.")
                                        .jtStyle(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                            } else {
                                // Contacts on Tally (excluding existing friends)
                                let nonFriendsOnTally = allContacts.filter { $0.isExistingUser && !isAlreadyFriend(contact: $0) }
                                if !nonFriendsOnTally.isEmpty {
                                    Text("ON TALLY (\(nonFriendsOnTally.count))")
                                        .jtStyle(.caption)
                                        .foregroundColor(.green.opacity(0.8))
                                        .padding(.leading, 20)
                                        .padding(.top, 16)

                                    ForEach(Array(nonFriendsOnTally.prefix(onTallyDisplayCount))) { contact in
                                        ContactRow(contact: contact, isOnTally: true, isAlreadyFriend: false)
                                            .id(contact.id)
                                    }

                                    if nonFriendsOnTally.count > onTallyDisplayCount {
                                        Button(action: { onTallyDisplayCount += 50 }) {
                                            Text("Show 50 more")
                                                .jtStyle(.body)
                                                .foregroundColor(.green.opacity(0.7))
                                                .padding(.leading, 20)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }

                                // Contacts NOT on Tally
                                let nonUsers = allContacts.filter { !$0.isExistingUser }
                                if !nonUsers.isEmpty {
                                    Text("NOT ON TALLY (\(nonUsers.count))")
                                        .jtStyle(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.leading, 20)
                                        .padding(.top, 16)

                                    ForEach(Array(nonUsers.prefix(notOnTallyDisplayCount))) { contact in
                                        ContactRow(contact: contact, isOnTally: false, isAlreadyFriend: false)
                                            .id(contact.id)
                                    }

                                    if nonUsers.count > notOnTallyDisplayCount {
                                        Button(action: { notOnTallyDisplayCount += 50 }) {
                                            Text("Show 50 more")
                                                .jtStyle(.body)
                                                .foregroundColor(.white.opacity(0.7))
                                                .padding(.leading, 20)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("All Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { updateCachedContacts() }
            .onChange(of: searchText) { oldValue, newValue in updateCachedContacts() }
            .onChange(of: contactManager.suggestedFriends.count) { oldValue, newValue in updateCachedContacts() }
        }
    }

    // MARK: - Caching helpers

    private func updateCachedContacts() {
        if searchText != lastSearchText || cachedAllContacts.isEmpty {
            lastSearchText = searchText
            cachedAllContacts = contactManager.suggestedFriends.filter { contact in
                guard !contact.name.isEmpty && !contact.phoneNumber.isEmpty else { return false }
                return searchText.isEmpty ||
                       contact.name.lowercased().contains(searchText.lowercased()) ||
                       contact.phoneNumber.lowercased().contains(searchText.lowercased())
            }
        }
    }

    private var filteredAllContacts: [SuggestedFriend] { cachedAllContacts }

    private func isAlreadyFriend(contact: SuggestedFriend) -> Bool {
        guard !friendsManager.preloadedFriends.isEmpty else { return false }
        guard !contact.phoneNumber.isEmpty else { return false }
        let contactPhone = contact.phoneNumber.hasPrefix("+1") ? String(contact.phoneNumber.dropFirst(2)) : contact.phoneNumber
        return friendsManager.preloadedFriends.contains { friend in
            let friendPhone = friend.phoneNumber.hasPrefix("+1") ? String(friend.phoneNumber.dropFirst(2)) : friend.phoneNumber
            return friendPhone == contactPhone
        }
    }
}

// MARK: - Nested ContactRow

struct ContactRow: View {
    let contact: SuggestedFriend
    let isOnTally: Bool
    let isAlreadyFriend: Bool

    @StateObject private var friendRequestManager = FriendRequestManager.shared
    @EnvironmentObject var unifiedFriendManager: UnifiedFriendManager
    @State private var isAdding = false
    @State private var isRequestSent = false
    @State private var showError = false
    @State private var errorMessage = ""

    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(BranchService.self) private var branchService

    var body: some View {
        HStack(spacing: 14) {
            // Avatar – cached image or generated initials
            if contact.avatarUrl200 != nil || contact.avatarUrl80 != nil {
                CachedAvatarView(
                    url80: contact.avatarUrl80,
                    url200: contact.avatarUrl200,
                    urlOriginal: contact.avatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(initials(for: contact.name))
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .jtStyle(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                if isOnTally {
                    Text(isAlreadyFriend ? "Friend" : "On Tally")
                        .jtStyle(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isAlreadyFriend ? .blue : .green)
                }
            }

            Spacer()

            if !isAdding {
                if isOnTally && !isAlreadyFriend {
                    let hasSentRequest = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == contact.userId }) || isRequestSent

                    if !hasSentRequest {
                        Button(action: { Task { await sendFriendRequest() } }) {
                            Text("ADD")
                                .jtStyle(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                    } else {
                        Text("REQUEST SENT")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(8)
                    }
                } else if !isOnTally {
                    Button(action: { shareInviteLink() }) {
                        Text("INVITE")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                } else if isAlreadyFriend {
                    Text("FRIENDS")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
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
            isRequestSent = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == contact.userId })
        }
        .onChange(of: unifiedFriendManager.sentRequests) { oldValue, _ in
            // Update state when sent requests change (e.g., when returning to view)
            isRequestSent = unifiedFriendManager.sentRequests.contains(where: { $0.receiverId == contact.userId })
        }
    }

    // MARK: - Private helpers

    private func sendFriendRequest() async {
        guard let userId = contact.userId else { return }
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        guard !isAdding else { return }

        isAdding = true
        isRequestSent = true

        do {
            let friendRequest = try await friendRequestManager.sendFriendRequest(to: userId, message: "Friend request from all contacts", token: token)
            
            // Also add to unified manager for immediate UI consistency
            let unifiedRequest = UnifiedSentFriendRequest(
                id: friendRequest.id,
                receiverId: friendRequest.receiverId,
                receiverName: contact.name,
                receiverPhone: contact.phoneNumber,
                receiverAvatarVersion: contact.avatarVersion,
                receiverAvatarUrl80: contact.avatarUrl80,
                receiverAvatarUrl200: contact.avatarUrl200,
                receiverAvatarUrlOriginal: contact.avatarUrlOriginal,
                message: "Friend request from all contacts",
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
                    self.sendSMSToContact(phoneNumber: self.contact.phoneNumber, inviteLink: inviteLink.url, inviterName: currentUser.name)
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
