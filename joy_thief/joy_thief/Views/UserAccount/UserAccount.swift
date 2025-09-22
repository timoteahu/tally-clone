//
//  UserAccount.swift
//  joy_thief
//
//  Created by Timothy Hu on 7/17/25.
//


import SwiftUI
import Kingfisher
import Foundation
// Add import for FeedManager

// MARK: - Models
struct UserHabitStats: Codable {
    let userId: String
    let totalHabits: Int
    let completedHabits: Int
    let totalStreak: Int
    let totalSaved: Double
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case totalHabits = "total_habits"
        case completedHabits = "completed_habits"
        case totalStreak = "total_streak"
        case totalSaved = "total_saved"
    }
}

// Add this struct at the top-level (outside the view struct)
struct HabitStatsToday: Codable {
    let totalHabitsToday: Int
    let completedHabitsToday: Int
    let longestStreak: Int?  // Make it optional
    
    enum CodingKeys: String, CodingKey {
        case totalHabitsToday = "total_habits_today"
        case completedHabitsToday = "completed_habits_today"
        case longestStreak = "longest_streak"
    }
}


struct UserAccount: View {
    let userId: String
    let userName: String?
    let userAvatarUrl: String?
    let onDismiss: (() -> Void)?

    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var habitManager = HabitManager.shared
    // Inject FeedManager as EnvironmentObject
    @EnvironmentObject var feedManager: FeedManager
    @State private var userProfile: User?
    @State private var userPosts: [FeedPost] = []
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCurrentUser = false
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedTab = 0
    @State private var isFriend = false // Add friend status state
    @State private var selectedPost: FeedPost? = nil

    // Stats for the profile
    @State private var totalHabits = 0
    @State private var completedHabits = 0
    @State private var totalStreak = 0
    @State private var totalSaved = 0.0

    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                // Dismiss/back arrow (if onDismiss is provided)
                if let onDismiss = onDismiss {
                    Button(action: { onDismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44) // Minimum tap target size
                            .contentShape(Rectangle()) // Make entire frame tappable
                    }
                    .padding(.top, 8)
                    .padding(.leading, 16)
                    .zIndex(10)
                }
               // Background gradient matching HomeView
               LinearGradient(
                   gradient: Gradient(stops: [
                       Gradient.Stop(color: Color(hex: "161C29"), location: 0.0),
                       Gradient.Stop(color: Color(hex: "131824"), location: 0.15),
                       Gradient.Stop(color: Color(hex: "0F141F"), location: 0.3),
                       Gradient.Stop(color: Color(hex: "0C111A"), location: 0.45),
                       Gradient.Stop(color: Color(hex: "0A0F17"), location: 0.6),
                       Gradient.Stop(color: Color(hex: "080D15"), location: 0.7),
                       Gradient.Stop(color: Color(hex: "060B12"), location: 0.8),
                       Gradient.Stop(color: Color(hex: "03070E"), location: 0.9),
                       Gradient.Stop(color: Color(hex: "01050B"), location: 1.0)
                   ]),
                   startPoint: .topLeading,
                   endPoint: .bottomTrailing
               )
               .ignoresSafeArea()
                Group {
                    if isLoading {
                        VStack(spacing: 20) {
                            UserAccountSkeleton(onDismiss: onDismiss)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                // Profile Header
                                profileHeader
                                // Thin gray line separator
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                // Content based on selected tab
                                contentView
                            }
                            .padding(.top, 48) // Move only the content down, not the scroll area
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            scrollOffset = value
                        }
                    }
                }
           }
           .navigationBarTitleDisplayMode(.inline)
           .navigationBarBackButtonHidden(true)
           .toolbar {
               ToolbarItem(placement: .navigationBarTrailing) {
                   if isCurrentUser {
                       Button("Edit") {
                           // TODO: Navigate to edit profile
                       }
                       .foregroundColor(.white)
                       .font(.custom("EBGaramond-Regular", size: 16))
                   }
               }
           }
           .toolbarBackground(.hidden, for: .navigationBar)
           .toolbarColorScheme(.dark, for: .navigationBar)
           .accentColor(.white)
           .scrollIndicators(.hidden)
       }
       .onAppear {
           loadUserProfile()
       }
       .alert("Error", isPresented: $showError) {
           Button("OK") { }
       } message: {
           Text(errorMessage)
       }
       .sheet(item: $selectedPost) { post in
           PostDetailView(post: post)
       }
   }
  
   // MARK: - Profile Header
   private var profileHeader: some View {
       VStack(spacing: 24) {
           // Profile Avatar - centered at top, bigger
           KFImage(URL(string: userAvatarUrl ?? ""))
               .placeholder {
                   Circle()
                       .fill(Color.gray.opacity(0.3))
                       .overlay(
                           Image(systemName: "person.fill")
                               .foregroundColor(.gray)
                               .font(.system(size: 50))
                       )
               }
               .resizable()
               .aspectRatio(contentMode: .fill)
               .frame(width: 120, height: 120)
               .clipShape(Circle())
               .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
           

                      // Username - centered below stats, bigger
           Text(userName ?? "Unknown User")
               .font(.custom("EBGaramond-Bold", size: 24))
               .foregroundColor(.white)
               .multilineTextAlignment(.center)
           
           // Stats - horizontal row below profile picture, bigger
           HStack(spacing: 40) {
               VStack(spacing: 6) {
                   Text("\(totalHabits)")
                       .font(.custom("EBGaramond-Bold", size: 28))
                       .foregroundColor(.white)
                   VStack(spacing: 0) {
                       Text("Habits")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                       Text("Today")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                   }
               }
               
               VStack(spacing: 6) {
                   Text("\(completedHabits)")
                       .font(.custom("EBGaramond-Bold", size: 28))
                       .foregroundColor(.white)
                   VStack(spacing: 0) {
                       Text("Habits")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                       Text("Done")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                   }
               }
               
               VStack(spacing: 6) {
                   Text("\(totalStreak)")
                       .font(.custom("EBGaramond-Bold", size: 28))
                       .foregroundColor(.white)
                   VStack(spacing: 0) {
                       Text("Longest")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                       Text("Streak")
                           .font(.custom("EBGaramond-Regular", size: 14))
                           .foregroundColor(.white.opacity(0.7))
                   }
               }
           }
           
           

       }
       .padding(.horizontal, 20)
       .padding(.top, 10)
       .padding(.bottom, 20)
   }

   // MARK: - Content Tabs
   private var contentTabs: some View {
       HStack(spacing: 0) {
           Button(action: { selectedTab = 0 }) {
               VStack(spacing: 6) {
                   Image(systemName: "square.grid.3x3")
                       .font(.system(size: 24))
                       .foregroundColor(.white)
               }
           }
           .frame(maxWidth: .infinity)
       }
       .padding(.horizontal, 20)
       .padding(.bottom, 10)
   }
   
   // MARK: - Content View
   @ViewBuilder
   private var contentView: some View {
       postsGrid
   }
   
   // MARK: - Posts Grid
   private var postsGrid: some View {
       Group {
           if userPosts.isEmpty {
               VStack(spacing: 20) {
                   Image(systemName: "square.grid.3x3")
                       .font(.system(size: 40))
                       .foregroundColor(.white.opacity(0.3))
                   Text("No posts yet")
                       .font(.custom("EBGaramond-Regular", size: 16))
                       .foregroundColor(.white.opacity(0.7))
               }
               .frame(maxWidth: .infinity)
               .padding(.vertical, 40)
           } else {
               LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 2), spacing: 1) {
                   ForEach(userPosts) { post in
                       Button {
                           selectedPost = post
                       } label: {
                           PostThumbnail(post: post)
                       }
                       .buttonStyle(PlainButtonStyle())
                   }
               }
           }
       }
   }
  
   // MARK: - Helper Methods
   private func loadUserProfile() {
       isLoading = true
      
       // Check if this is the current user
       isCurrentUser = authManager.currentUser?.id == userId
      
       // Load user profile data
       Task {
           do {
               // Fetch user profile
               let profile = try await fetchUserProfile(userId: userId)
               await MainActor.run {
                   self.userProfile = profile
               }
              
               // Calculate stats (simplified for now)
               await calculateUserStats(userId: userId)
               
               // Get all posts for this user from FeedManager's cache (fix UUID vs String)
               let userUUID = UUID(uuidString: userId)
               let posts = feedManager.feedPosts.filter { $0.userId == userUUID }
               await MainActor.run {
                   self.userPosts = posts
                   self.isLoading = false
               }
           } catch {
               await MainActor.run {
                   self.errorMessage = error.localizedDescription
                   self.showError = true
                   self.isLoading = false
               }
           }
       }
   }
   

  
   private func fetchUserProfile(userId: String) async throws -> User {
       guard let token = authManager.storedAuthToken else {
           throw NetworkError.unauthorized
       }
      
       let url = URL(string: "\(AppConfig.baseURL)/users/\(userId)")!
       var request = URLRequest(url: url)
       request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      
       let (data, response) = try await URLSession.shared.data(for: request)
      
       guard let httpResponse = response as? HTTPURLResponse else {
           throw NetworkError.invalidResponse
       }
      
       guard httpResponse.statusCode == 200 else {
           throw NetworkError.serverError(httpResponse.statusCode)
       }
      
       return try JSONDecoder().decode(User.self, from: data)
   }
  
  
   private func fetchUserHabitStatsToday(userId: String) async throws -> HabitStatsToday {
       guard let token = authManager.storedAuthToken else {
           throw NetworkError.unauthorized
       }
       let url = URL(string: "\(AppConfig.baseURL)/users/\(userId)/habit-stats-today")!
       var request = URLRequest(url: url)
       request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
       let (data, response) = try await URLSession.shared.data(for: request)
       guard let httpResponse = response as? HTTPURLResponse else {
           throw NetworkError.invalidResponse
       }
       guard httpResponse.statusCode == 200 else {
           throw NetworkError.serverError(httpResponse.statusCode)
       }
       return try JSONDecoder().decode(HabitStatsToday.self, from: data)
   }
   
   private func calculateUserStats(userId: String) async {
       do {
           let stats = try await fetchUserHabitStatsToday(userId: userId)
           await MainActor.run {
               self.totalHabits = stats.totalHabitsToday
               self.completedHabits = stats.completedHabitsToday
               self.totalStreak = stats.longestStreak ?? 0  // Use optional value
           }
       } catch {
           await MainActor.run {
               self.totalHabits = 0
               self.completedHabits = 0
               self.totalStreak = 0
           }
       }
   }
   
   private func fetchUserHabitStats(userId: String) async throws -> UserHabitStats {
       guard let token = authManager.storedAuthToken else {
           throw NetworkError.unauthorized
       }
       
       let url = URL(string: "\(AppConfig.baseURL)/habits/user/\(userId)/stats")!
       var request = URLRequest(url: url)
       request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
       
       let (data, response) = try await URLSession.shared.data(for: request)
       
       guard let httpResponse = response as? HTTPURLResponse else {
           throw NetworkError.invalidResponse
       }
       
       guard httpResponse.statusCode == 200 else {
           throw NetworkError.serverError(httpResponse.statusCode)
       }
       
       return try JSONDecoder().decode(UserHabitStats.self, from: data)
   }
   
  
   private func formatDate(_ dateString: String?) -> String {
       guard let dateString = dateString,
             let date = ISO8601DateFormatter().date(from: dateString) else {
           return "Unknown"
       }
      
       let formatter = DateFormatter()
       formatter.dateStyle = .medium
       return formatter.string(from: date)
   }
}


// MARK: - Supporting Views
struct PostThumbnail: View {
   let post: FeedPost
  
   var body: some View {
       GeometryReader { geometry in
           ZStack {
               // Verification image (contentImageUrl) as background
               if let verificationUrl = post.contentImageUrl {
                   KFImage(URL(string: verificationUrl))
                       .placeholder {
                           Rectangle()
                               .fill(Color.gray.opacity(0.3))
                               .overlay(
                                   Image(systemName: "photo")
                                       .foregroundColor(.gray)
                               )
                       }
                       .resizable()
                       .aspectRatio(2/3, contentMode: .fill)
                       .frame(width: geometry.size.width, height: geometry.size.width * 3 / 2)
                       .clipped()
               } else if let imageUrl = post.imageUrl {
                   KFImage(URL(string: imageUrl))
                       .placeholder {
                           Rectangle()
                               .fill(Color.gray.opacity(0.3))
                               .overlay(
                                   Image(systemName: "photo")
                                       .foregroundColor(.gray)
                               )
                       }
                       .resizable()
                       .aspectRatio(2/3, contentMode: .fill)
                       .frame(width: geometry.size.width, height: geometry.size.width * 3 / 2)
                       .clipped()
               }
               // Selfie (front-facing) image as overlay if available
               if let selfieUrl = post.selfieImageUrl {
                   KFImage(URL(string: selfieUrl))
                       .placeholder {
                           Rectangle()
                               .fill(Color.gray.opacity(0.3))
                               .overlay(
                                   Image(systemName: "person.crop.square")
                                       .foregroundColor(.gray)
                               )
                       }
                       .resizable()
                       .aspectRatio(3/5, contentMode: .fill)
                       .frame(width: geometry.size.width * 0.3, height: geometry.size.width * 0.3)
                       .clipped()
                       .overlay(Rectangle().stroke(Color.white, lineWidth: 2))
                       .shadow(radius: 4)
                       .position(x: (geometry.size.width * 0.3) / 2 + 8, y: (geometry.size.width * 0.3) / 2 + 8)
               }
               // Fallback if no images
               if post.contentImageUrl == nil && post.imageUrl == nil && post.selfieImageUrl == nil {
                   Rectangle()
                       .fill(Color.gray.opacity(0.3))
                       .overlay(
                           VStack {
                               Image(systemName: "checkmark.circle.fill")
                                   .foregroundColor(.green)
                                   .font(.title2)
                               Text(post.habitName ?? "Habit")
                                   .font(.caption)
                                   .foregroundColor(.secondary)
                           }
                       )
               }
           }
       }
       .aspectRatio(2/3, contentMode: .fit)
   }
}


struct PostDetailView: View {
   let post: FeedPost
   @State private var showingSelfieAsMain = false

   var body: some View {
       ZStack {
           // App-style background gradient
           LinearGradient(
               gradient: Gradient(stops: [
                   Gradient.Stop(color: Color(hex: "161C29"), location: 0.0),
                   Gradient.Stop(color: Color(hex: "131824"), location: 0.15),
                   Gradient.Stop(color: Color(hex: "0F141F"), location: 0.3),
                   Gradient.Stop(color: Color(hex: "0C111A"), location: 0.45),
                   Gradient.Stop(color: Color(hex: "0A0F17"), location: 0.6),
                   Gradient.Stop(color: Color(hex: "080D15"), location: 0.7),
                   Gradient.Stop(color: Color(hex: "060B12"), location: 0.8),
                   Gradient.Stop(color: Color(hex: "03070E"), location: 0.9),
                   Gradient.Stop(color: Color(hex: "01050B"), location: 1.0)
               ]),
               startPoint: .topLeading,
               endPoint: .bottomTrailing
           )
           .ignoresSafeArea()
           VStack(alignment: .leading, spacing: 6) { // reduced spacing
               // User info section (moved above images, no time)
               HStack {
                   KFImage(URL(string: post.userAvatarUrl80 ?? ""))
                       .placeholder {
                           Circle()
                               .fill(Color.gray.opacity(0.3))
                       }
                       .resizable()
                       .aspectRatio(contentMode: .fill)
                       .frame(width: 40, height: 40)
                       .clipShape(Circle())
                  
                   Text(post.userName)
                       .font(.headline)
                       .foregroundColor(.white)
                   Spacer()
               }
               .padding(.horizontal, 20)

               // Feed card dimensions
               let cardWidth = UIScreen.main.bounds.width
               let cardHeight = cardWidth * 1.8
               // Determine if both images are present
               let hasBothImages = (post.contentImageUrl != nil && post.selfieImageUrl != nil)
               ZStack(alignment: .topLeading) {
                   // Main image (switchable)
                   let mainUrl = (showingSelfieAsMain ? post.selfieImageUrl : post.contentImageUrl) ?? post.imageUrl
                   if let mainUrl = mainUrl {
                       KFImage(URL(string: mainUrl))
                           .placeholder {
                               RoundedRectangle(cornerRadius: cardWidth * 0.035)
                                   .fill(Color.gray.opacity(0.3)) // simple gray
                           }
                           .resizable()
                           .aspectRatio(contentMode: .fill)
                           .frame(width: cardWidth, height: cardHeight)
                           .clipped()
                           .cornerRadius(cardWidth * 0.035)
                           .animation(.easeInOut(duration: 0.3), value: showingSelfieAsMain)
                   }
                   // Overlay image (if both images are present)
                   if hasBothImages, let overlayUrl = showingSelfieAsMain ? post.contentImageUrl : post.selfieImageUrl {
                       HStack {
                           Button(action: {
                               withAnimation(.easeInOut(duration: 0.3)) {
                                   showingSelfieAsMain.toggle()
                               }
                           }) {
                               KFImage(URL(string: overlayUrl))
                                   .placeholder {
                                       RoundedRectangle(cornerRadius: cardWidth * 0.025)
                                           .fill(Color.gray.opacity(0.3)) // simple gray
                                   }
                                   .resizable()
                                   .aspectRatio(contentMode: .fill)
                                   .frame(width: cardWidth * 0.25, height: cardWidth * 0.25)
                                   .clipped()
                                   .cornerRadius(cardWidth * 0.025)
                                   .overlay(
                                       RoundedRectangle(cornerRadius: cardWidth * 0.025)
                                           .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                   )
                                   .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                           }
                           .padding(.top, cardHeight * 0.04)
                           .padding(.leading, cardWidth * 0.04)
                           Spacer()
                       }
                   }
               }
               .padding(.top, 24)

               // Caption (if present)
               if let caption = post.caption, !caption.isEmpty {
                   Text(caption)
                       .font(.custom("EBGaramond-Regular", size: 17))
                       .foregroundColor(.white.opacity(0.9))
                       .padding(.horizontal, 20)
               }
           }
       }
   }
}


// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}



// MARK: - Overlay Wrapper for Swipe-in Presentation
struct UserAccountOverlay: View {
    let userId: String
    let userName: String?
    let userAvatarUrl: String?
    let onDismiss: (() -> Void)?
    
    // Gesture state
    @State private var isHorizontalDragging = false
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Add a black background that fades in/out
            Color.black
                .opacity(0.5 - (dragOffset / UIScreen.main.bounds.width) * 0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissView()
                }
            
            // Main content
            UserAccount(userId: userId, userName: userName, userAvatarUrl: userAvatarUrl, onDismiss: onDismiss)
                .gesture(edgeSwipeGesture)
        }
        .offset(x: dragOffset) // Move entire overlay together
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
        .preferredColorScheme(.dark)
        .allowsHitTesting(true)  // Ensure this view captures all gestures
        .onAppear {
            // Disable FriendsView gesture by posting a notification
            NotificationCenter.default.post(name: NSNotification.Name("DisableFriendsViewGesture"), object: nil)
        }
        .onDisappear {
            // Re-enable FriendsView gesture
            NotificationCenter.default.post(name: NSNotification.Name("EnableFriendsViewGesture"), object: nil)
        }
    }
    
    private func dismissView() {
        if let callback = onDismiss {
            callback()
        }
    }
    
    // MARK: – Edge-swipe gesture (horizontal priority)
    private var edgeSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Start only from left edge & prioritise horizontal drags
                if value.startLocation.x < 80 && abs(value.translation.width) > abs(value.translation.height) {
                    if !isHorizontalDragging { isHorizontalDragging = true }
                    let progress = min(value.translation.width / 100, 1.0)
                    dragOffset = value.translation.width * 0.8 * progress
                }
            }
            .onEnded { value in
                if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                    dismissView()
                } else {
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) { dragOffset = 0 }
                }
                isHorizontalDragging = false
            }
    }
}











