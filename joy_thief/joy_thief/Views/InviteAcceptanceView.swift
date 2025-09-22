import SwiftUI
import Kingfisher

struct InviteAcceptanceView: View {
    enum AcceptState {
        case idle
        case loading
        case accepted
    }

    let inviterId: String
    let habitId: String?
    let branchInviteData: BranchInviteData?
    
    @StateObject private var inviteManager = InviteManager()
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var habitManager: HabitManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var invite: Invite?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoadingInvite = true
    @State private var acceptState: AcceptState = .idle
    @State private var dragOffset: CGFloat = 0
    
    // Initialize with enhanced Branch data if available
    init(inviterId: String, habitId: String? = nil, branchInviteData: BranchInviteData? = nil) {
        self.inviterId = inviterId
        self.habitId = habitId
        self.branchInviteData = branchInviteData
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background overlay that appears during swipe to simulate previous view
                if dragOffset > 0 {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .offset(x: -200 + (dragOffset * 2))
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
                }
                
                AppBackground()
                
                VStack {
                    if let branchData = branchInviteData {
                        // Use Branch.io data directly - no need to load from backend
                        enhancedInviteContentView(branchData)
                    } else if isLoadingInvite {
                        loadingView
                    } else if let invite = invite {
                        inviteContentView(invite)
                    } else {
                        errorStateView
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Leading cancel button in lowercase with EB Garamond font
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("cancel")
                            .jtStyle(.body)
                            .foregroundColor(.white)
                    }
                }

                // Center title in lowercase with EB Garamond font
                ToolbarItem(placement: .principal) {
                    Text("invite")
                        .jtStyle(.title3)
                        .foregroundColor(.white)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                // Only load from backend if we don't have Branch.io data
                if branchInviteData == nil {
                    await loadInvite()
                } else {
                    isLoadingInvite = false
                }
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Even more responsive - larger detection area and less resistance
                        if value.startLocation.x < 80 && abs(value.translation.height) < 120 {
                            // More direct translation with minimal resistance
                            let progress = min(value.translation.width / 100, 1.0)
                            dragOffset = value.translation.width * 0.8 * progress
                        }
                    }
                    .onEnded { value in
                        // Lower threshold for even quicker response
                        if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                            dismiss()
                        } else {
                            // Very quick spring back
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Loading invite...")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var errorStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.custom("EBGaramond-Regular", size: 48))
                .foregroundColor(.orange)
            
            Text("Invite Not Found")
                .jtStyle(.title2)
                .fontWeight(.bold)
            
            Text("This invite may have expired or is no longer valid. Please ask for a new invite.")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Button(action: { dismiss() }) {
                Text("CLOSE").jtStyle(.caption)
            }
            .fontWeight(.semibold)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white)
            .cornerRadius(16)
            .padding(.horizontal, 24)
        }
    }
    
    private func inviteContentView(_ invite: Invite) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                inviteHeaderView
                inviteDetailsView(invite)
                acceptButtonView
            }
            .padding(24)
        }
    }
    
    private var inviteHeaderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.custom("EBGaramond-Regular", size: 64))
                .foregroundColor(.white)
            
            Text("You're Invited!")
                .jtStyle(.title)
                .fontWeight(.bold)
            
            Text("Someone wants to connect with you on Tally")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    private func inviteDetailsView(_ invite: Invite) -> some View {
        VStack(spacing: 20) {
            // Show habit details if this is a habit-specific invite
            Group {
                if let habitId = invite.habitId {
                    habitInviteCard(habitId: habitId)
                } else {
                    friendshipInviteCard
                }
            }
            
            inviteExpirationView(invite)
        }
    }
    
    private var friendshipInviteCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friendship Invite")
                        .jtStyle(.body)
                        .fontWeight(.semibold)
                    
                    Text("Connect and support each other's habits")
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func habitInviteCard(habitId: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accountability Partnership")
                        .jtStyle(.body)
                        .fontWeight(.semibold)
                    
                    Text("Become an accountability partner for their habit")
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func inviteExpirationView(_ invite: Invite) -> some View {
        Group {
            if let expiresAt = invite.expiresAt {
                let formatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateStyle = .medium
                    f.timeStyle = .short
                    return f
                }()
                
                if let expirationDate = formatter.date(from: expiresAt) {
                    let timeRemaining = expirationDate.timeIntervalSinceNow
                    
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.white.opacity(0.6))
                        
                        if timeRemaining > 0 {
                            Text("Expires \(formatter.string(from: expirationDate))")
                                .jtStyle(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text("This invite has expired")
                                .jtStyle(.caption)
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                    }
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
    
    private var acceptButtonView: some View {
        Button(action: {
            Task {
                await acceptInvite()
            }
        }) {
            if acceptState == .loading {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                    Text("Accepting...")
                }
            } else {
                Text("Accept Invite")
            }
        }
        .font(.ebGaramondBody)
        .fontWeight(.bold)
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(16)
        .disabled(acceptState == .loading)
    }
    
    // MARK: - Enhanced Branch.io Invite View
    
    private func enhancedInviteContentView(_ branchData: BranchInviteData) -> some View {
        ScrollView {
            VStack(spacing: 40) {
                enhancedInviteHeaderView(branchData)
                    .padding(.top, 30)
                
                enhancedInviteDetailsView(branchData)
                
                enhancedAcceptButtonView(branchData)
                    .padding(.top, 10)
            }
            .padding(24)
        }
    }
    
    private func enhancedInviteHeaderView(_ branchData: BranchInviteData) -> some View {
        VStack(spacing: 20) {
            // Large central avatar (Kingfisher cached)
            CachedAvatarView(
                url80: branchData.inviterProfilePhoto,
                url200: branchData.inviterProfilePhoto,
                urlOriginal: branchData.inviterProfilePhoto,
                size: .large,
                placeholder: "person.crop.circle"
            )
            
            VStack(spacing: 8) {
                Text("\(branchData.inviterName) wants you on tally")
                    .jtStyle(.title)
                    .fontWeight(.bold)
                
                Text("come vibe & build better habits together")
                    .jtStyle(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func enhancedInviteDetailsView(_ branchData: BranchInviteData) -> some View {
        VStack(spacing: 20) {
            // Enhanced friendship invite card with inviter info
            enhancedFriendshipInviteCard(branchData)
        }
    }
    
    private func enhancedFriendshipInviteCard(_ branchData: BranchInviteData) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("friendship invite")
                        .jtStyle(.body)
                        .fontWeight(.semibold)
                    
                    Text("Connect and support each other's habits")
                        .jtStyle(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            
            // Show inviter details
            HStack(spacing: 12) {
                CachedAvatarView(
                    url80: branchData.inviterProfilePhoto,
                    url200: branchData.inviterProfilePhoto,
                    urlOriginal: branchData.inviterProfilePhoto,
                    size: .small,
                    placeholder: "person.crop.circle"
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(branchData.inviterName)
                        .jtStyle(.body)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func enhancedAcceptButtonView(_ branchData: BranchInviteData) -> some View {
        Button(action: {
            Task {
                await acceptInviteDirectly(branchData)
            }
        }) {
            switch acceptState {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("accepting…")
                        .jtStyle(.body)
                        .fontWeight(.bold)
                }
            case .accepted:
                Text("[ accepted! ]")
                    .jtStyle(.body)
                    .fontWeight(.bold)
            case .idle:
                Text({ () -> AttributedString in
                    var name = AttributedString(branchData.inviterName)
                    name.foregroundColor = .blue
                    return AttributedString("[ join ") + name + AttributedString(" ]")
                }())
                    .jtStyle(.body)
                    .fontWeight(.bold)
            }
        }
        .font(.ebGaramondBody)
        .fontWeight(.bold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(16)
        .disabled(acceptState == .loading)
    }
    
    // MARK: - Helper Functions
    
    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        // Simple phone number formatting
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if cleanPhone.count == 10 {
            return "(\(cleanPhone.prefix(3))) \(cleanPhone.dropFirst(3).prefix(3))-\(cleanPhone.suffix(4))"
        }
        return phone
    }
    
    // Accept invite directly using Branch.io data
    private func acceptInviteDirectly(_ branchData: BranchInviteData) async {
        print("🎯 [InviteAcceptanceView] acceptInviteDirectly() called")
        print("🎯 [InviteAcceptanceView] Inviter: \(branchData.inviterName) (ID: \(branchData.inviterId))")
        
        guard let token = authManager.storedAuthToken,
              let currentUser = authManager.currentUser else {
            print("❌ [InviteAcceptanceView] Authentication required")
            print("❌ [InviteAcceptanceView] Token available: \(authManager.storedAuthToken != nil)")
            print("❌ [InviteAcceptanceView] Current user: \(authManager.currentUser?.name ?? "nil")")
            errorMessage = "Authentication required. Please log in again."
            showError = true
            return
        }
        
        print("✅ [InviteAcceptanceView] Authentication validated")
        print("👤 [InviteAcceptanceView] Current user: \(currentUser.name) (ID: \(currentUser.id))")
        
        // Prevent self-invitation or existing friendship
        if currentUser.id == branchData.inviterId {
            errorMessage = "you can't accept your own invite :)"
            showError = true
            return
        }
        
        if friendsManager.preloadedFriends.contains(where: { $0.friendId == branchData.inviterId }) {
            errorMessage = "already friends 💙"
            showError = true
            return
        }
        
        print("🔄 [InviteAcceptanceView] Starting invite acceptance process...")
        await MainActor.run {
            acceptState = .loading
        }
        
        do {
            print("📡 [InviteAcceptanceView] Calling acceptBranchInvite API...")
            // Use the new Branch invite acceptance endpoint that creates immediate friendships
            let response = try await inviteManager.acceptBranchInvite(inviterId: branchData.inviterId, token: token)
            
            print("✅ [InviteAcceptanceView] API call successful")
            print("📋 [InviteAcceptanceView] Response: \(response)")
            
            print("🔄 [InviteAcceptanceView] Refreshing friends list...")
            // Refresh friends list to show the new friendship
            await friendsManager.fetchFriends()
            print("✅ [InviteAcceptanceView] Friends list refreshed")
            
            // Refresh the feed to include new friend's posts
            print("🔄 [InviteAcceptanceView] Refreshing feed after accepting invite...")
            await FeedManager.shared.refreshAfterNewFriend()
            print("✅ [InviteAcceptanceView] Feed refreshed to include posts from new friend")
            
            await MainActor.run {
                withAnimation {
                    acceptState = .accepted
                }
            }
            // Brief confirmation then auto-dismiss
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            // Clear any residual pending invite data so sheet isn't re-presented
            await MainActor.run {
                BranchService.shared.clearPendingInvite()
                dismiss()
            }
            
        } catch let error as InviteManager.InviteError {
            print("❌ [InviteAcceptanceView] InviteError: \(error)")
            print("❌ [InviteAcceptanceView] Error description: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
            await MainActor.run { acceptState = .idle }
        } catch {
            print("❌ [InviteAcceptanceView] General error: \(error)")
            errorMessage = "Failed to accept invite: \(error.localizedDescription)"
            showError = true
            await MainActor.run { acceptState = .idle }
        }
        
        print("📊 [InviteAcceptanceView] Loading state cleared & invite view dismissed")
    }
    
    // MARK: - Functions
    
    private func loadInvite() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "Authentication required. Please log in again."
            showError = true
            isLoadingInvite = false
            return
        }
        
        do {
            invite = try await inviteManager.lookupInvite(inviterId: inviterId, token: token)
            isLoadingInvite = false
        } catch let error as InviteManager.InviteError {
            isLoadingInvite = false
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            isLoadingInvite = false
            errorMessage = "Failed to load invite: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func acceptInvite() async {
        guard let invite = invite,
              let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "Unable to accept invite. Please try again."
            showError = true
            return
        }
        
        await MainActor.run {
            acceptState = .loading
        }
        
        do {
            let response = try await inviteManager.acceptInvite(inviteId: invite.id, token: token)
            
            // Refresh friends list
            await friendsManager.fetchFriends()
            
            // Refresh the feed to include new friend's posts
            print("🔄 [InviteAcceptanceView] Refreshing feed after accepting invite...")
            await FeedManager.shared.refreshAfterNewFriend()
            print("✅ [InviteAcceptanceView] Feed refreshed to include posts from new friend")
            
            // If this was a habit invite, refresh habits
            if response.habitId != nil {
                if let userId = authManager.currentUser?.id {
                    try? await habitManager.fetchHabits(userId: userId, token: token)
                }
            }
            
            await MainActor.run {
                withAnimation {
                    acceptState = .accepted
                }
            }
            // Brief confirmation then auto-dismiss
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            // Clear any residual pending invite data so sheet isn't re-presented
            await MainActor.run {
                BranchService.shared.clearPendingInvite()
                dismiss()
            }
            
        } catch let error as InviteManager.InviteError {
            errorMessage = error.localizedDescription
            showError = true
            await MainActor.run { acceptState = .idle }
        } catch {
            errorMessage = "Failed to accept invite: \(error.localizedDescription)"
            showError = true
            await MainActor.run { acceptState = .idle }
        }
    }
}

#Preview {
    InviteAcceptanceView(inviterId: "test-user-id", habitId: nil, branchInviteData: nil)
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(FriendsManager.shared)
        .environmentObject(HabitManager.shared)
} 
