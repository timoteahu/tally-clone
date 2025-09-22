import SwiftUI

struct FriendRecommendationRow: View {
    let recommendation: FriendRecommendation
    let onAddFriend: () async throws -> Void
    
    @State private var isLoading = false
    @State private var isRequestSent = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with special styling for recommendations
            ZStack {
                if recommendation.avatarUrl200 != nil || recommendation.avatarUrl80 != nil {
                    CachedAvatarView(
                        url80: recommendation.avatarUrl80,
                        url200: recommendation.avatarUrl200,
                        urlOriginal: recommendation.avatarUrlOriginal,
                        size: .medium
                    )
                    .frame(width: 48, height: 48)
                    .onAppear {
                        print("🖼️ [FriendRecommendationRow] Loading avatar for \(recommendation.userName):")
                        print("  - avatarUrl80: \(recommendation.avatarUrl80 ?? "nil")")
                        print("  - avatarUrl200: \(recommendation.avatarUrl200 ?? "nil")")
                        print("  - avatarUrlOriginal: \(recommendation.avatarUrlOriginal ?? "nil")")
                        print("  - avatarVersion: \(recommendation.avatarVersion ?? -1)")
                    }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(initials(for: recommendation.userName))
                                .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.bold)
                                .foregroundColor(.blue)
                        )
                        .onAppear {
                            print("🖼️ [FriendRecommendationRow] No avatar URL for \(recommendation.userName) - showing initials")
                        }
                }
                
                // Recommendation indicator
                Circle()
                    .fill(Color.blue)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.custom("EBGaramond-Regular", size: 8)).fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                    .offset(x: 16, y: -16)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // User name
                Text(recommendation.userName)
                    .jtStyle(.body)
                    .foregroundColor(.white)
                
                // Recommendation reason
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(.blue.opacity(0.8))
                    
                    Text(recommendation.recommendationReason)
                        .jtStyle(.caption)
                        .foregroundColor(.blue.opacity(0.8))
                }
                
                // Mutual friends preview
                if !recommendation.mutualFriendsPreview.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.custom("EBGaramond-Regular", size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(mutualFriendsText)
                            .jtStyle(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Add button or loading indicator
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else if isRequestSent {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.custom("EBGaramond-Regular", size: 16))
                    Text("SENT")
                        .font(.custom("EBGaramond-Regular", size: 14)).fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button(action: {
                    Task {
                        await addFriend()
                    }
                }) {
                    Text("ADD")
                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Private Methods
    
    private func addFriend() async {
        guard !isLoading && !isRequestSent else { return }
        
        isLoading = true
        
        do {
            try await onAddFriend()
            // Success - show sent state
            withAnimation(.easeInOut(duration: 0.3)) {
                isRequestSent = true
            }
        } catch {
            // Error - show error message
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
    
    private var mutualFriendsText: String {
        let preview = recommendation.mutualFriendsPreview
        if preview.isEmpty {
            return ""
        } else if preview.count == 1 {
            return preview[0].name
        } else if preview.count == 2 {
            return "\(preview[0].name), \(preview[1].name)"
        } else {
            return "\(preview[0].name), \(preview[1].name) + \(recommendation.mutualFriendsCount - 2) more"
        }
    }
} 