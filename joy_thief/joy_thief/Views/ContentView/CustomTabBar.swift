import SwiftUI

// MARK: - Custom Tab Bar Component

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showAddHabitSheet: Bool
    let showFriendsViewAction: () -> Void
    
    var body: some View {
        ZStack {
            VStack {
                Spacer()
                
                RoundedRectangle(cornerRadius: 25)
                    .fill(.ultraThinMaterial)
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -2)
                    .overlay(
                        TabBarContent(selectedTab: $selectedTab,
                                      showAddHabitSheet: $showAddHabitSheet,
                                      showFriendsViewAction: showFriendsViewAction)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }

            // Center floating Add button overlayed above the tab bar
            VStack {
                Spacer()
                FloatingAddButton(showAddHabitSheet: $showAddHabitSheet)
                    // Lift the button up so it overlaps the bar like a FAB
                    .padding(.bottom, 24 + 6)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .ignoresSafeArea(.keyboard)
    }
}

struct TabBarContent: View {
    @Binding var selectedTab: Int
    @Binding var showAddHabitSheet: Bool
    let showFriendsViewAction: () -> Void
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showUserAccountOverlay = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Home (left)
            TabBarButton(
                selectedIcon: "house.fill", 
                unselectedIcon: "house", 
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            .frame(maxWidth: .infinity)
            
            // Partner Habits (second)
            TabBarButton(
                selectedIcon: "bell.badge.fill", 
                unselectedIcon: "bell.badge", 
                isSelected: selectedTab == 5
            ) {
                selectedTab = 5
            }
            .frame(maxWidth: .infinity)
            
            TabBarButton(
                selectedIcon: "plus.app.fill", 
                unselectedIcon: "plus.app", 
                isSelected: showAddHabitSheet,
                size: 26
            ) {
                // Intentionally no-op; this is a visual spacer only
            }
            .opacity(0) // keep spacing but hide the content
            .allowsHitTesting(false) // prevent accidental taps
            .frame(maxWidth: .infinity)
            
            TabBarButton(
                selectedIcon: "photo.stack.fill", 
                unselectedIcon: "photo.stack", 
                isSelected: selectedTab == 3
            ) {
                selectedTab = 3
            }
            .frame(maxWidth: .infinity)
            
            // Profile Tab (right) - navigates to PersonalUserAccount
            Button(action: { 
                selectedTab = 4
            }) {
                ZStack {
                    Circle()
                        .fill(selectedTab == 4 ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: 35, height: 35)
                    
                    if let currentUser = authManager.currentUser,
                       (currentUser.avatarUrl80 != nil || currentUser.avatarUrl200 != nil || currentUser.avatarUrlOriginal != nil) {
                        CachedAvatarView(
                            user: currentUser,
                            size: AvatarDisplaySize.small,
                            contentMode: SwiftUI.ContentMode.fit
                        )
                        .id(currentUser.avatarVersion ?? 0)
                    } else if let currentUser = authManager.currentUser {
                        // Show initials when no avatar
                        Text(currentUser.name.initials())
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    } else {
                        // Fallback icon if no user
                        Image(systemName: "person.crop.circle.fill")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .overlay(
                    Circle()
                        .stroke(selectedTab == 4 ? Color.white : Color.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 35, height: 35)
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Custom Tab Bar Button

struct TabBarButton: View {
    let selectedIcon: String
    let unselectedIcon: String
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void
    
    init(selectedIcon: String, unselectedIcon: String, isSelected: Bool, size: CGFloat = 22, action: @escaping () -> Void) {
        self.selectedIcon = selectedIcon
        self.unselectedIcon = unselectedIcon
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? selectedIcon : unselectedIcon)
                .font(.custom("EBGaramond-Regular", size: size))
                .foregroundColor(.white)
                .animation(nil, value: isSelected)
        }
    }
} 

// MARK: - Floating Add Button (center overlay)

struct FloatingAddButton: View {
    @Binding var showAddHabitSheet: Bool
    
    var body: some View {
        Button(action: {
            showAddHabitSheet = true
            // Refresh friends with Stripe Connect for habit creation
            Task {
                await FriendsManager.shared.preloadFriendsWithStripeConnect()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color(hex: "1E2833").opacity(0.4)) // slightly opaque brand-matching fill
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 48, height: 48)
            )
        }
        .accessibilityLabel("Add Habit")
    }
}