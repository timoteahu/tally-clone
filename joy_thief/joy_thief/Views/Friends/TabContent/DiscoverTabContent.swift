import SwiftUI

// MARK: - Discover Tab Content
struct DiscoverTabContent: View {
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    @Binding var searchResults: [UserSearchResult]
    @Binding var isSearching: Bool
    @Binding var searchError: String?
    @ObservedObject var unifiedFriendManager: UnifiedFriendManager
    @ObservedObject var friendRecommendationsManager: FriendRecommendationsManager
    let tabsInInitialLoad: Set<Int>
    let visitedTabs: Set<Int>
    let onSearchUsers: (String) async -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            ScrollView {
                if tabsInInitialLoad.contains(1) || (!visitedTabs.contains(1)) {
                    // Show skeleton during initial load OR for unvisited tab
                    discoverTabSkeleton
                } else {
                    // Show actual content with loading indicator if needed
                    LazyVStack(spacing: 12) {
                        if !searchText.isEmpty {
                            // Show global search results
                            globalSearchResultsSection
                        } else {
                            // Show unified recommendations section
                            unifiedRecommendationsSection
                            
                            // Empty state if no recommendations (after filtering)
                            if filteredContactsOnTally.isEmpty && filteredRecommendations.isEmpty && !unifiedFriendManager.isLoading {
                                VStack(spacing: 16) {
                                    Text("🔍 find friends")
                                        .jtStyle(.title2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                    Text("people you might know will show up here from your contacts and mutual friends")
                                        .jtStyle(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 32)
                                .padding(.top, 40)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .refreshable {
                await refreshDiscoverData()
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping on the view
            isSearchFocused.wrappedValue = false
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce search to avoid too many API calls
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                if newValue == searchText { // Only search if text hasn't changed
                    await onSearchUsers(newValue)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("search usernames...", text: $searchText)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(.white)
                    .focused(isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: searchText) { oldValue, newValue in
                        // Filter out invalid characters in real-time (same validation as usernames)
                        let validCharacterSet = CharacterSet.letters.union(.decimalDigits).union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
                        let filteredString = String(newValue.unicodeScalars.filter { validCharacterSet.contains($0) })
                        
                        // Update searchText only if it changed after filtering
                        if filteredString != newValue {
                            searchText = filteredString
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearchFocused.wrappedValue = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    private var unifiedRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !filteredContactsOnTally.isEmpty || !filteredRecommendations.isEmpty {
                HStack {
                    Text("PEOPLE YOU MIGHT KNOW")
                        .jtStyle(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                VStack(spacing: 12) {
                    // Contacts on Tally (from contacts) - filtered
                    ForEach(filteredContactsOnTally) { contact in
                        UnifiedRecommendationRow(
                            userId: contact.userId,
                            name: contact.name,
                            phoneNumber: contact.phoneNumber,
                            avatarVersion: contact.avatarVersion,
                            avatarUrl80: contact.avatarUrl80,
                            avatarUrl200: contact.avatarUrl200,
                            avatarUrlOriginal: contact.avatarUrlOriginal,
                            sourceType: .fromContacts,
                            mutualFriendsCount: nil
                        )
                    }
                    
                    // Friend recommendations (from mutual friends) - filtered
                    ForEach(filteredRecommendations) { recommendation in
                        UnifiedRecommendationRow(
                            userId: recommendation.recommendedUserId.uuidString,
                            name: recommendation.userName,
                            phoneNumber: "",
                            avatarVersion: recommendation.avatarVersion,
                            avatarUrl80: recommendation.avatarUrl80,
                            avatarUrl200: recommendation.avatarUrl200,
                            avatarUrlOriginal: recommendation.avatarUrlOriginal,
                            sourceType: .fromMutuals,
                            mutualFriendsCount: recommendation.mutualFriendsCount
                        )
                    }
                }
            }
        }
    }
    
    private var globalSearchResultsSection: some View {
        VStack(spacing: 16) {
            if isSearching {
                HStack {
                    Text("SEARCHING...")
                        .jtStyle(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 32)
            } else if let error = searchError {
                VStack(spacing: 8) {
                    Text("Error: \(error)")
                        .jtStyle(.body)
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
            } else if !searchResults.isEmpty {
                VStack(spacing: 12) {
                    ForEach(searchResults) { result in
                        GlobalSearchResultRow(result: result)
                    }
                }
            } else if !searchText.isEmpty && !isSearching {
                VStack(spacing: 20) {
                    Text("🔍 no results")
                        .jtStyle(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("no users found matching \"\(searchText)\"")
                        .jtStyle(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 40)
            }
        }
    }
    
    // MARK: - Filtered Data for Discover Tab
    
    private var filteredContactsOnTally: [ContactOnTally] {
        return unifiedFriendManager.contactsOnTally.filter { contact in
            // Exclude if already friends
            let isAlreadyFriend = unifiedFriendManager.friends.contains { friend in
                friend.friendId == contact.userId
            }
            
            // Exclude only if received a request from them (not if we sent one)
            let hasReceivedRequest = unifiedFriendManager.receivedRequests.contains { request in
                request.senderId == contact.userId
            }
            
            // Apply search filter
            let matchesSearch = searchText.isEmpty || 
                contact.name.contains(searchText)
            
            return !isAlreadyFriend && !hasReceivedRequest && matchesSearch
        }
    }
    
    private var filteredRecommendations: [FriendRecommendation] {
        return friendRecommendationsManager.recommendations.filter { recommendation in
            let userId = recommendation.recommendedUserId.uuidString
            
            // Exclude if already friends
            let isAlreadyFriend = unifiedFriendManager.friends.contains { friend in
                friend.friendId == userId
            }
            
            // Exclude only if received a request from them (not if we sent one)
            let hasReceivedRequest = unifiedFriendManager.receivedRequests.contains { request in
                request.senderId == userId
            }
            
            // Apply search filter
            let matchesSearch = searchText.isEmpty || 
                recommendation.userName.contains(searchText)
            
            return !isAlreadyFriend && !hasReceivedRequest && matchesSearch
        }
    }
    
    private var discoverTabSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    skeletonSectionHeader
                    // Discover recommendations skeleton
                    ForEach(0..<5, id: \.self) { _ in
                        skeletonRecommendationRow
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(true)
    }
    
    private var skeletonSectionHeader: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 120, height: 12)
            .cornerRadius(6)
            .shimmer()
    }
    
    private var skeletonRecommendationRow: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 4) {
                // Name placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 16)
                    .shimmer()
                
                // Subtitle placeholder (mutual friends)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 12)
                    .shimmer()
            }
            
            Spacer()
            
            // Add button placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 32)
                .cornerRadius(16)
                .shimmer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    @MainActor
    private func refreshDiscoverData() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        await unifiedFriendManager.refreshContactsOnly(token: token)
    }
} 