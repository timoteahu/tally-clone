import SwiftUI

struct FriendRecommendationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var friendRecommendationsManager = FriendRecommendationsManager.shared
    
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var processingRequests: Set<String> = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Content
                if friendRecommendationsManager.isLoading || isLoading {
                    loadingView
                } else if filteredRecommendations.isEmpty {
                    emptyState
                } else {
                    recommendationsList
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Friend Recommendations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadRecommendations()
        }
        .refreshable {
            await loadRecommendations(forceRefresh: true)
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .font(.custom("EBGaramond-Regular", size: 16))
            TextField("Search recommendations", text: $searchText)
                .font(.ebGaramondBody)
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
            Text("Loading recommendations...")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.custom("EBGaramond-Regular", size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No Recommendations")
                .jtStyle(.title)
                .foregroundColor(.white)
            Text("Check back later for new friend recommendations")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recommendationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredRecommendations) { recommendation in
                    FriendRecommendationRow(recommendation: recommendation) {
                        await sendFriendRequest(to: recommendation)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private var filteredRecommendations: [FriendRecommendation] {
        if searchText.isEmpty {
            return friendRecommendationsManager.recommendations
        }
        return friendRecommendationsManager.recommendations.filter { recommendation in
            recommendation.userName.lowercased().contains(searchText.lowercased()) ||
            recommendation.recommendationReason.lowercased().contains(searchText.lowercased())
        }
    }
    
    @MainActor
    private func loadRecommendations(forceRefresh: Bool = false) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        // Always refresh recommendations - they should never be cached
        isLoading = true
        do {
            _ = try await friendRecommendationsManager.getFriendRecommendations(token: token)
        } catch {
            errorMessage = "Failed to load recommendations: \(error.localizedDescription)"
            showError = true
        }
        isLoading = false
    }
    
    private func sendFriendRequest(to recommendation: FriendRecommendation) async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            return
        }
        
        processingRequests.insert(recommendation.recommendedUserId.uuidString)
        
        do {
            let response = try await friendRecommendationsManager.sendFriendRequest(
                to: recommendation.recommendedUserId,
                token: token
            )
            print("✅ [FriendRecommendationsView] Friend request sent to \(recommendation.userName): \(response.message)")
        } catch {
            errorMessage = "Failed to send friend request: \(error.localizedDescription)"
            showError = true
            print("❌ [FriendRecommendationsView] Failed to send friend request: \(error)")
        }
        
        processingRequests.remove(recommendation.recommendedUserId.uuidString)
    }
}

#Preview {
    FriendRecommendationsView()
        .environmentObject(AuthenticationManager.shared)
} 
