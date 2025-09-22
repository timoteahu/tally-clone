import SwiftUI
import UIKit
import Contacts

// MARK: - Main Friends screen
// Components have been extracted to separate files for better organization:
// - FriendsModels.swift: Data models and helper structs
// - FriendsUtilities.swift: Utility functions and activity helpers
// - GlobalSearchComponents.swift: Search-related components and rows

struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject internal var unifiedFriendManager = UnifiedFriendManager.shared
    @StateObject internal var friendRecommendationsManager = FriendRecommendationsManager.shared
    @State internal var isLoading = false
    @State internal var errorMessage: String?
    @State internal var showError = false
    @State private var showingAllContacts = false
    @State private var showingQRCode = false
    @State private var isAnimationComplete = false
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var gestureEnabled = true  // Add this state
    @State internal var processingRequests: Set<String> = []
    @State internal var selectedTab = 0 // 0: Friends, 1: Discover, 2: Requests
    
    // Search functionality for discover tab
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Global user search functionality
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    
    // Track which tabs have been visited to show cache vs skeleton
    @State private var visitedTabs: Set<Int> = []
    
    // Track which tabs are doing initial load vs refresh
    @State private var tabsInInitialLoad: Set<Int> = []
    
    var onDismiss: (() -> Void)?

    var body: some View {
        ZStack {
            AppBackground()
            mainContent
        }
        .offset(x: dragOffset)
        .overlay(
            Rectangle()
                .fill(Color.clear)
                .frame(width: 24) // 24-pt hot zone
                .contentShape(Rectangle())
                .highPriorityGesture(gestureEnabled ? screenEdgeDragGesture : nil, including: .all)
            , alignment: .leading
        )
        .sheet(isPresented: $showingAllContacts) {
            AllContactsView()
                .environmentObject(authManager)
                .environmentObject(unifiedFriendManager)
        }
        .sheet(isPresented: $showingQRCode) {
            QRCodeView()
                .environmentObject(authManager)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimationComplete = true
            }
            
            Task {
                await loadDataIntelligently()
            }
            
            // Add notification observers
            NotificationCenter.default.addObserver(forName: NSNotification.Name("DisableFriendsViewGesture"), object: nil, queue: .main) { _ in
                gestureEnabled = false
            }
            NotificationCenter.default.addObserver(forName: NSNotification.Name("EnableFriendsViewGesture"), object: nil, queue: .main) { _ in
                gestureEnabled = true
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            Task {
                await handleTabChange(to: newValue)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            customHeader
            tabView
        }
        .animation(.easeInOut(duration: 0.3), value: isAnimationComplete)
    }

    private var customHeader: some View {
        HStack {
            Button(action: {
                guard isAnimationComplete else { return }
                dismissView()
            }) {
                Image(systemName: "chevron.left")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .disabled(!isAnimationComplete)
            
            Spacer()
            
            Text("friends")
                .jtStyle(.title2)
                .fontWeight(.thin)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                showAddFriendAction()
            }) {
                Image(systemName: "plus")
                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var tabView: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                TabButton(title: "friends", isSelected: selectedTab == 0) {
                    guard selectedTab != 0 else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 0
                    }
                }
                
                TabButton(title: "discover", isSelected: selectedTab == 1) {
                    guard selectedTab != 1 else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 1
                    }
                }
                
                TabButton(
                    title: "requests", 
                    isSelected: selectedTab == 2,
                    badgeCount: unifiedFriendManager.receivedRequests.count
                ) {
                    guard selectedTab != 2 else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = 2
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Tab Content
            TabView(selection: $selectedTab) {
                FriendsTabContent(
                    unifiedFriendManager: unifiedFriendManager,
                    tabsInInitialLoad: tabsInInitialLoad,
                    visitedTabs: visitedTabs
                )
                .tag(0)
                
                DiscoverTabContent(
                    searchText: $searchText,
                    isSearchFocused: $isSearchFocused,
                    searchResults: $searchResults,
                    isSearching: $isSearching,
                    searchError: $searchError,
                    unifiedFriendManager: unifiedFriendManager,
                    friendRecommendationsManager: friendRecommendationsManager,
                    tabsInInitialLoad: tabsInInitialLoad,
                    visitedTabs: visitedTabs,
                    onSearchUsers: searchUsers
                )
                .tag(1)
                
                RequestsTabContent(
                    unifiedFriendManager: unifiedFriendManager,
                    tabsInInitialLoad: tabsInInitialLoad,
                    visitedTabs: visitedTabs
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
        }
    }

    // MARK: - Gesture handling
    private var screenEdgeDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isAnimationComplete else { return }
                // Start only from left edge & prioritise horizontal drags
                if value.startLocation.x < 80 && abs(value.translation.width) > abs(value.translation.height) {
                    if !isHorizontalDragging { isHorizontalDragging = true }
                    let progress = min(value.translation.width / 100, 1.0)
                    dragOffset = value.translation.width * 0.8 * progress
                }
            }
            .onEnded { value in
                guard isAnimationComplete else { dragOffset = 0; isHorizontalDragging = false; return }
                if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                    dismissView()
                } else {
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) { dragOffset = 0 }
                }
                isHorizontalDragging = false
            }
    }

    // MARK: - Helper Methods
    
    private func dismissView() {
        NotificationCenter.default.post(name: NSNotification.Name("FriendsViewDismissed"), object: nil)
        onDismiss?() ?? dismiss()
    }
    
    private func showAddFriendAction() {
        showingQRCode = true
    }

    // MARK: - Data Loading Logic
    
    @MainActor
    private func loadDataIntelligently() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        tabsInInitialLoad.insert(0)
        visitedTabs.insert(0)
        
        await unifiedFriendManager.refreshFriendsOnly(token: token)
        
        tabsInInitialLoad.remove(0)
    }
    
    @MainActor
    private func handleTabChange(to newTab: Int) async {
        if visitedTabs.contains(newTab) {
            return
        }
        
        tabsInInitialLoad.insert(newTab)
        visitedTabs.insert(newTab)
        
        await loadDataForTab(newTab)
        
        tabsInInitialLoad.remove(newTab)
    }
    
    @MainActor
    private func loadDataForTab(_ tab: Int) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        switch tab {
        case 0: // Friends tab
            await unifiedFriendManager.refreshFriendsOnly(token: token)
        case 1: // Discover tab
            await unifiedFriendManager.refreshContactsOnly(token: token)
        case 2: // Requests tab
            await unifiedFriendManager.refreshRequestsOnly(token: token)
        default:
            break
        }
    }
    
    // MARK: - Global User Search
    
    @MainActor
    private func searchUsers(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            searchError = "Authentication required"
            return
        }
        
        isSearching = true
        searchError = nil
        
        do {
            let url = URL(string: "\(AppConfig.baseURL)/friends/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let results = try JSONDecoder().decode([UserSearchResult].self, from: data)
                    searchResults = results
                } else {
                    searchError = "Search failed with status: \(httpResponse.statusCode)"
                }
            }
        } catch {
            searchError = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isSearching = false
    }
}

#Preview {
    FriendsView().environmentObject(AuthenticationManager.shared)
}

// MARK: - Tab Button Component
struct TabButton: View {
    let title: String
    let isSelected: Bool
    var badgeCount: Int = 0
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Text(title)
                        .jtStyle(.body)
                        .fontWeight(isSelected ? .medium : .thin)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    
                    // Badge for request count
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.custom("EBGaramond-Regular", size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 12, y: -8)
                    }
                }
                
                Rectangle()
                    .fill(isSelected ? Color.white.opacity(0.8) : Color.clear)
                    .frame(height: 1)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
