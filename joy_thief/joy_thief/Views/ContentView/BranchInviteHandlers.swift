import SwiftUI
import Foundation

// MARK: - Branch Invite Handlers
// Extracted from ContentView to keep invite logic separate

extension ContentView {
    
    func handleBranchInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let branchData = userInfo["branchInviteData"] as? BranchInviteData else {
            print("❌ [ContentView] Invalid Branch invite data received")
            print("❌ [ContentView] UserInfo keys: \(notification.userInfo?.keys.map { "\($0)" } ?? [])")
            return
        }
        
        // Only proceed if the user is authenticated – otherwise we'll handle it after login
        guard authManager.isAuthenticated, let currentUser = authManager.currentUser else {
            return
        }

        // 1️⃣ Ignore invites coming from yourself
        if branchData.inviterId == currentUser.id || branchData.inviterPhone == currentUser.phoneNumber {
            branchService.clearPendingInvite()
            return
        }

        // 2️⃣ Ignore invites from users you are already friends with
        let alreadyFriends = friendsManager.preloadedFriends.contains { $0.friendId == branchData.inviterId }
        
        if alreadyFriends {
            branchService.clearPendingInvite()
            return
        }

        // 🔧 FIX: Ensure UI updates happen on main thread with explicit state changes
        DispatchQueue.main.async {
            self.pendingInviteData = branchData
            self.showInviteAcceptanceView = true
        }

        // Clear pending invite from BranchService now that it's being handled
        branchService.clearPendingInvite()
    }
    
    func handleBranchInviteData(_ inviteData: BranchInviteData) {
        guard inviteData.isValid else {
            return
        }

        // Ensure user is authenticated
        guard authManager.isAuthenticated, let currentUser = authManager.currentUser else {
            print("🔒 User not authenticated – invite will be processed after login")
            return
        }

        // 1️⃣ Self-invite guard
        if inviteData.inviterId == currentUser.id || inviteData.inviterPhone == currentUser.phoneNumber {
            branchService.clearPendingInvite()
            return
        }

        // 2️⃣ Already friends guard
        let alreadyFriends = friendsManager.preloadedFriends.contains { $0.friendId == inviteData.inviterId }
        if alreadyFriends {
            branchService.clearPendingInvite()
            return
        }

        // 🔧 FIX: Ensure UI updates happen on main thread with explicit state changes
        DispatchQueue.main.async {
            self.pendingInviteData = inviteData
            self.showInviteAcceptanceView = true
        }

        // Clear pending invite once handled
        branchService.clearPendingInvite()
    }
} 