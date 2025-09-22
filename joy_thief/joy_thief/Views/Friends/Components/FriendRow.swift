////
//  FriendRow.swift
//  joy_thief
//
//  Extracted from FriendsView on 2025-06-18 for better modularity.
//

import SwiftUI

/// A single friend cell shown under the "YOUR FRIENDS" or recommendations section.
struct FriendRow: View {
    let friend: LocalFriend
    @Binding var added: Set<UUID>
    @Binding var removed: Set<UUID>
    @State private var isAdded = false
    @State private var showingFriendMenu = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Avatar – cached image, explicit image, or generated initials
            if friend.avatarUrl200 != nil || friend.avatarUrl80 != nil {
                CachedAvatarView(
                    url80: friend.avatarUrl80,
                    url200: friend.avatarUrl200,
                    urlOriginal: friend.avatarUrlOriginal,
                    size: .medium
                )
                .frame(width: 54, height: 54)
            } else if let image = friend.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text(initials(for: friend.name))
                            .jtStyle(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                if let mutuals = friend.mutuals, friend.isRecommended {
                    HStack(spacing: 4) {
                        Text("🤝")
                        Text("\(mutuals) mutual friend\(mutuals == 1 ? "" : "s")")
                            .jtStyle(.caption)
                            .foregroundColor(.yellow.opacity(0.8))
                    }
                } else if !friend.isRecommended, let activityText = friend.activityText {
                    // Only show activity for existing friends, not recommendations
                    Text(activityText)
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(friend.isActive ? .green.opacity(0.8) : .white.opacity(0.5))
                }
            }

            Spacer()

            // For existing friends, show 3-dot menu
            if !friend.isRecommended {
                Button(action: {
                    showingFriendMenu = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.custom("EBGaramond-Regular", size: 18)).fontWeight(.medium)
                        .frame(width: 32, height: 32)
                }
            }
            // ADD / ADDED UI for recommended friends
            else {
                if !added.contains(friend.id) && !isAdded {
                    Button(action: {
                        added.insert(friend.id)
                        isAdded = true
                    }) {
                        Text("ADD")
                            .jtStyle(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(12)
                    }
                } else {
                    Text("ADDED")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                }

                if !isAdded {
                    Button(action: { removed.insert(friend.id) }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.red)
                            .font(.custom("EBGaramond-Regular", size: 18)).fontWeight(.medium)
                            .padding(.leading, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle()) // Make the entire row tappable
        .onTapGesture {
            onTap?()
        }
        .sheet(isPresented: $showingFriendMenu) {
            FriendMenuSheet(friend: friend)
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
    }
}

/// A slide-up sheet that shows when the 3-dot menu is tapped
struct FriendMenuSheet: View {
    let friend: LocalFriend
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isRemoving = false
    @State private var showConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar area
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            // Friend info section
            HStack(spacing: 16) {
                // Avatar
                if friend.avatarUrl200 != nil || friend.avatarUrl80 != nil {
                    CachedAvatarView(
                        url80: friend.avatarUrl80,
                        url200: friend.avatarUrl200,
                        urlOriginal: friend.avatarUrlOriginal,
                        size: .medium
                    )
                    .frame(width: 60, height: 60)
                } else if let image = friend.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(initials(for: friend.name))
                                .jtStyle(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .jtStyle(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            
            // Remove friend button
            Button(action: {
                showConfirmation = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.minus")
                        .font(.custom("EBGaramond-Regular", size: 18)).fontWeight(.medium)
                        .foregroundColor(.red)
                    
                    Text("Remove Friend")
                        .jtStyle(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .disabled(isRemoving)
            
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .alert("Remove Friend", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeFriend()
            }
        } message: {
            Text("Are you sure you want to remove \(friend.name) as a friend? This action cannot be undone.")
        }
    }
    
    private func removeFriend() {
        guard let friendshipId = friend.friendshipId,
              let friendId = friend.friendId,
              let token = AuthenticationManager.shared.storedAuthToken else {
            dismiss()
            return
        }
        
        isRemoving = true
        
        Task {
            do {
                // Use FriendsManager to remove the friend
                try await FriendsManager.shared.removeFriend(
                    userId: authManager.currentUser?.id ?? "",
                    friendId: friendshipId, // This is actually the friendship ID for the DELETE endpoint
                    token: token
                )
                
                await MainActor.run {
                    // Remove the friend from UnifiedFriendManager's friends list
                    UnifiedFriendManager.shared.friends.removeAll { $0.friendId == friendId }
                    
                    // Also remove from the legacy FriendsManager if it exists there
                    FriendsManager.shared.preloadedFriends.removeAll { $0.friendId == friendId }
                    
                    // Dismiss the sheet
                    dismiss()
                }
                
                print("✅ Friend removed successfully and UI updated")
            } catch {
                await MainActor.run {
                    isRemoving = false
                }
                print("❌ Failed to remove friend: \(error)")
            }
        }
    }
}
