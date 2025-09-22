//
//  PersonalUserAccount.swift
//  joy_thief
//
//  Created by Timothy Hu on 7/19/25.
//

import SwiftUI
import Kingfisher

struct PersonalUserAccount: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var feedManager: FeedManager
    @EnvironmentObject var paymentStatsManager: PaymentStatsManager
    @State private var userProfile: User?
    @State private var userPosts: [FeedPost] = []
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedTab = 0
    @State private var selectedPost: FeedPost? = nil
    
    // Avatar/Photo editing states
    @State private var avatarManager = AvatarManager()
    @State private var selectedImage: Data?
    @State private var showingImagePicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var showingPhotoActionSheet = false
    @State private var tempImage: UIImage?
    @State private var showingCropper = false
    
    // Stats for the profile
    @State private var totalHabits = 0
    @State private var completedHabits = 0
    @State private var totalStreak = 0
    @State private var totalSaved = 0.0
    @State private var totalCredits = 97  // Add this state variable
    @State private var profileKey = 0
    
    // Cache-related properties
    private static var cachedStats: HabitStatsToday?
    private static var cachedPosts: [FeedPost] = []
    private static var lastCacheTime: Date?
    private static let cacheValidityDuration: TimeInterval = 60 // Cache valid for 60 seconds
    
    // Computed properties for additional stats
    private var currentWeekGoals: Int {
        // Count total goals scheduled for the current week
        let calendar = Calendar.current
        let today = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return 0
        }
        
        var totalGoals = 0
        // First, add all daily habits for each day of the week
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                continue
            }
            
            let weekdayIndex = calendar.component(.weekday, from: date) - 1 // 0 = Sunday
            let dailyHabits = habitManager.habitsbydate[weekdayIndex] ?? []
            totalGoals += dailyHabits.count
        }
        
        // Then add weekly habits just once (they apply to the whole week)
        totalGoals += habitManager.weeklyHabits.count
        
        return totalGoals
    }
    
    private var currentWeekCompleted: Int {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        // Get the start of the current week (Sunday)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return 0
        }
        
        // Count completed goals for each day of the week
        var totalCompleted = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                continue
            }
            
            let dateString = formatter.string(from: date)
            let verifiedHabitsForDate = habitManager.weeklyVerifiedHabits[dateString] ?? [:]
            
            // Count how many habits were completed on this date
            totalCompleted += verifiedHabitsForDate.values.filter { $0 }.count
        }
        
        return totalCompleted
    }
    
    // Calculate accountability score based on completion rate and consistency
    private var accountabilityScore: Int {
        let completionRate = currentWeekGoals > 0 ? Double(currentWeekCompleted) / Double(currentWeekGoals) : 0.0
        let consistencyBonus = calculateConsistencyBonus()
        let baseScore = Int(completionRate * 100)
        let finalScore = min(100, baseScore + consistencyBonus)
        return max(0, finalScore)
    }
    
    // Calculate consistency bonus based on how many days they completed at least one habit
    private func calculateConsistencyBonus() -> Int {
        let calendar = Calendar.current
        let today = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else { return 0 }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var daysWithCompletions = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start),
                  date <= today else { continue }
            
            let dateString = formatter.string(from: date)
            let verifiedHabitsForDate = habitManager.weeklyVerifiedHabits[dateString] ?? [:]
            
            if !verifiedHabitsForDate.values.filter({ $0 }).isEmpty {
                daysWithCompletions += 1
            }
        }
        
        // Bonus points for consistency: up to 20 points for completing habits on 5+ days
        return min(20, daysWithCompletions * 4)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                // Background gradient matching UserAccount
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
                            UserAccountSkeleton(onDismiss: nil) // No dismiss for tab view
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                // Profile Header (no back button for tab view)
                                profileHeaderForTab
                                // Thin gray line separator
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                // Content based on selected tab
                                contentView
                            }
                            .padding(.top, 20) // Less padding since no back button
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
                        .refreshable {
                            // Allow manual refresh with pull-to-refresh
                            forceRefresh()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .accentColor(.white)
            .scrollIndicators(.hidden)
        }
        .onAppear {
            loadUserProfile()
        }
        .alert("error", isPresented: $showError) {
            Button("ok") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoActionSheet, actions: {
            Button("camera") { showingCamera = true }
            Button("photo library") { showingPhotoLibrary = true }
            // Only show Remove Photo if user has an avatar
            if let currentUser = authManager.currentUser,
               (currentUser.avatarUrl80 != nil || currentUser.avatarUrl200 != nil || currentUser.avatarUrlOriginal != nil || currentUser.profilePhotoUrl != nil) {
                Button("remove photo", role: .destructive) { deleteProfilePhoto() }
            }
            Button("cancel", role: .cancel) {}
        })
        .sheet(isPresented: $showingPhotoLibrary) {
            PhotoLibraryPicker(selectedImage: $tempImage)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(capturedImage: $tempImage)
        }
        .onChange(of: tempImage) { oldValue, newValue in
            if newValue != nil {
                // Add a small delay to ensure sheet dismissal completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCropper = true
                }
            }
        }
        .fullScreenCover(isPresented: $showingCropper) {
            if let image = tempImage {
                ImageCropperView(originalImage: image, isPresented: $showingCropper) { croppedImage in
                    // Ensure the image is properly oriented before converting to JPEG
                    if let jpegData = croppedImage.jpegData(compressionQuality: 0.8),
                       let reloadedImage = UIImage(data: jpegData) {
                        selectedImage = reloadedImage.jpegData(compressionQuality: 0.8)
                    }
                    tempImage = nil
                }
            }
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            handleImageSelection(newValue)
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("profile photo"),
                message: Text(alertMessage),
                dismissButton: .default(Text("ok"))
            )
        }
    }
    
    // MARK: - Profile Header for Tab (no back button)
    private var profileHeaderForTab: some View {
        VStack(spacing: 24) {
            // Profile Avatar - centered at top, bigger, editable
            if let currentUser = authManager.currentUser {
                Button(action: {
                    showingPhotoActionSheet = true
                }) {
                    ZStack {
                        // Show avatar or initials
                        if currentUser.avatarUrl80 != nil || currentUser.avatarUrl200 != nil || currentUser.avatarUrlOriginal != nil {
                            // Avatar using CachedAvatarView
                            CachedAvatarView(
                                user: currentUser,
                                size: .large // Using large size for 120pt avatar
                            )
                            .frame(width: 120, height: 120)
                            .transaction { transaction in
                                transaction.animation = .easeInOut(duration: 0.3)
                            }
                            .id(profileKey)
                        } else {
                            // Show initials when no avatar
                            Circle()
                                .fill(Color.black)
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Text(currentUser.name.initials())
                                        .font(.custom("EBGaramond-Bold", size: 36))
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                )
                                .id(profileKey)
                        }
                        
                        // Profile photo border
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                            .frame(width: 120, height: 120)
                        
                        // Upload indicator overlay
                        if avatarManager.isUploading {
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 120, height: 120)
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        // Edit icon overlay
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 40, y: 40)
                    }
                }
                .disabled(avatarManager.isUploading)
                
                // Username - centered below stats, bigger
                Text(currentUser.name)
                    .font(.custom("EBGaramond-Bold", size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            
            // Stats - horizontal row below profile picture, bigger
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(totalHabits)")
                            .font(.custom("EBGaramond-Bold", size: 24))
                            .foregroundColor(.white)
                        VStack(spacing: 0) {
                            Text("habits")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Text("today")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    VStack(spacing: 2) {
                        Text("\(completedHabits)")
                            .font(.custom("EBGaramond-Bold", size: 24))
                            .foregroundColor(.white)
                        VStack(spacing: 0) {
                            Text("habits")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Text("done")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    VStack(spacing: 2) {
                        Text("\(totalStreak)")
                            .font(.custom("EBGaramond-Bold", size: 24))
                            .foregroundColor(.white)
                        VStack(spacing: 0) {
                            Text("longest")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Text("streak")
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
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
                    
                    Text("no posts yet")
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
        guard let currentUser = authManager.currentUser else {
            isLoading = false
            return
        }
        
        isLoading = true
        
        // Set user profile to current user
        userProfile = currentUser
        
        Task {
            // Check if cache is valid
            let shouldRefresh = Self.lastCacheTime == nil || 
                              Date().timeIntervalSince(Self.lastCacheTime!) > Self.cacheValidityDuration
            
            if shouldRefresh {
                // Calculate stats
                await calculateUserStats(userId: currentUser.id)
                
                // Get all posts for this user from FeedManager's cache
                let userUUID = UUID(uuidString: currentUser.id)
                let posts = feedManager.feedPosts.filter { $0.userId == userUUID }
                
                // Update cache
                Self.cachedStats = try? await fetchUserHabitStatsToday(userId: currentUser.id)
                Self.cachedPosts = posts
                Self.lastCacheTime = Date()
                
                await MainActor.run {
                    self.userPosts = posts
                    self.isLoading = false
                }
            } else {
                // Use cached data
                if let cachedStats = Self.cachedStats {
                    await MainActor.run {
                        self.totalHabits = cachedStats.totalHabitsToday
                        self.completedHabits = cachedStats.completedHabitsToday
                        self.totalStreak = cachedStats.longestStreak ?? 0
                        self.userPosts = Self.cachedPosts
                        self.isLoading = false
                    }
                } else {
                    // Fallback to fresh load if cache is somehow empty
                    await calculateUserStats(userId: currentUser.id)
                    let userUUID = UUID(uuidString: currentUser.id)
                    let posts = feedManager.feedPosts.filter { $0.userId == userUUID }
                    await MainActor.run {
                        self.userPosts = posts
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    // Add a method to force refresh
    private func forceRefresh() {
        Self.lastCacheTime = nil // Invalidate cache
        loadUserProfile() // Reload data
    }

    private func calculateUserStats(userId: String) async {
        do {
            let stats = try await fetchUserHabitStatsToday(userId: userId)
            await MainActor.run {
                self.totalHabits = stats.totalHabitsToday
                self.completedHabits = stats.completedHabitsToday
                self.totalStreak = stats.longestStreak ?? 0
            }
        } catch {
            await MainActor.run {
                self.totalHabits = 0
                self.completedHabits = 0
                self.totalStreak = 0
            }
        }
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
    
    // MARK: - Photo Handling Methods
    
    private func handleImageSelection(_ imageData: Data?) {
        if let imageData = imageData,
           let image = UIImage(data: imageData) {
            uploadProfilePhoto(image: image)
        }
    }
    
    private func uploadProfilePhoto(image: UIImage) {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            alertMessage = "authentication error. please log in again."
            showAlert = true
            return
        }
        
        Task {
            do {
                let avatarResponse = try await avatarManager.uploadAvatar(image: image, token: token)
                // Clear cached images for old avatar URLs
                if let oldUser = authManager.currentUser {
                    // Clear from AvatarImageStore first (immediate effect)
                    let oldUrls = [oldUser.avatarUrl80, oldUser.avatarUrl200, oldUser.avatarUrlOriginal, oldUser.profilePhotoUrl]
                        .compactMap { $0 }
                    for urlString in oldUrls {
                        await MainActor.run {
                            AvatarImageStore.shared.remove(for: urlString)
                        }
                    }
                    
                    // Also clear from Kingfisher cache
                    if let url80 = oldUser.avatarUrl80, let url = URL(string: url80) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                    if let url200 = oldUser.avatarUrl200, let url = URL(string: url200) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                    if let originalUrl = oldUser.avatarUrlOriginal, let url = URL(string: originalUrl) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                }
                
                // Cache the uploaded image BEFORE updating authManager to avoid race condition
                let newUrls = [avatarResponse.avatarUrl80, avatarResponse.avatarUrl200, avatarResponse.avatarUrlOriginal]
                    .compactMap { $0 }
                for urlString in newUrls {
                    await MainActor.run {
                        AvatarImageStore.shared.set(image, for: urlString)
                    }
                    // Also update Kingfisher memory cache
                    try? await ImageCache.default.store(image, forKey: urlString, toDisk: false)
                    // Force sync to disk to ensure persistence
                    try? await ImageCache.default.store(image, forKey: urlString, toDisk: true)
                }
                
                // Small delay to ensure cache operations complete
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                await MainActor.run {
                    authManager.updateUserAvatar(
                        avatarVersion: avatarResponse.avatarVersion,
                        avatarUrl80: avatarResponse.avatarUrl80,
                        avatarUrl200: avatarResponse.avatarUrl200,
                        avatarUrlOriginal: avatarResponse.avatarUrlOriginal
                    )
                    alertMessage = "avatar updated successfully!"
                    showAlert = true
                    profileKey += 1
                }
            } catch {
                await MainActor.run {
                    alertMessage = "failed to upload avatar. please try again."
                    showAlert = true
                }
            }
        }
    }
    
    private func deleteProfilePhoto() {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            alertMessage = "authentication error. please log in again."
            showAlert = true
            return
        }
        
        Task {
            do {
                // Clear cached images for old avatar URLs
                if let oldUser = authManager.currentUser {
                    // Clear from AvatarImageStore first (immediate effect)
                    let oldUrls = [oldUser.avatarUrl80, oldUser.avatarUrl200, oldUser.avatarUrlOriginal, oldUser.profilePhotoUrl]
                        .compactMap { $0 }
                    for urlString in oldUrls {
                        await MainActor.run {
                            AvatarImageStore.shared.remove(for: urlString)
                        }
                    }
                    
                    // Clear from Kingfisher memory and disk cache
                    if let url80 = oldUser.avatarUrl80, let url = URL(string: url80) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                    if let url200 = oldUser.avatarUrl200, let url = URL(string: url200) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                    if let originalUrl = oldUser.avatarUrlOriginal, let url = URL(string: originalUrl) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                    if let profilePhotoUrl = oldUser.profilePhotoUrl, let url = URL(string: profilePhotoUrl) {
                        try? await KingfisherManager.shared.cache.removeImage(forKey: url.absoluteString)
                    }
                }
                
                try await avatarManager.deleteAvatar(token: token)
                await MainActor.run {
                    authManager.updateUserAvatar(
                        avatarVersion: nil,
                        avatarUrl80: nil,
                        avatarUrl200: nil,
                        avatarUrlOriginal: nil,
                        profilePhotoUrl: nil  // Clear profilePhotoUrl to prevent fallback
                    )
                    alertMessage = "avatar removed successfully!"
                    showAlert = true
                    profileKey += 1
                }
            } catch {
                await MainActor.run {
                    alertMessage = "failed to remove avatar. please try again."
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    PersonalUserAccount()
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(HabitManager.shared)
        .environmentObject(PaymentStatsManager.shared)
        .environmentObject(FeedManager.shared)
}

