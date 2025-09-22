import SwiftUI
import UIKit

struct HomeView: View {
   let showFriendsView: () -> Void // Closure for showing FriendsView
   let showProfileView: () -> Void // New closure for showing Profile overlay
   let onProfileViewDismissed: () -> Void // Callback when profile view is dismissed
  
   @EnvironmentObject var authManager: AuthenticationManager
   @EnvironmentObject var habitManager: HabitManager
   @EnvironmentObject var friendsManager: FriendsManager
   @EnvironmentObject var paymentManager: PaymentManager
   @State private var selectedDate = Date()
   @State private var currentHabitIndex = 0
   @State private var dragOffset = CGSize.zero
   @State private var sharedDragOffset: CGFloat = 0
   @State private var connectStatus: ConnectStatus = .notConnected
  
   // Cache expensive computations to prevent recalculation during drag
   @State private var cachedTodaysHabits: [Habit] = []
   @State private var cachedSortedHabits: [Habit] = []
   @State private var cachedCompletedCount: Int = 0
   @State private var cachedVerificationStatus: [String: Bool] = [:]
   @StateObject private var imageCacheManager = ImageCacheManager.shared
       @State private var isFriendsViewShowing = false
    @State private var isProfileViewShowing = false
    @State private var animatedHeaderText: String = ""
   @State private var typingTimer: Timer?
   private let hapticGenerator = UIImpactFeedbackGenerator(style: .soft)
   
   // Throttling for drag updates
   @State private var dragUpdateTimer: Timer?
   @State private var pendingDragOffset: CGFloat = 0
   private let dragUpdateInterval: TimeInterval = 1.0/30.0 // 30fps max
   
   // NEW: Post preview state for 120Hz device fix
   @State private var activeVerification: HabitVerification? // nil → no sheet

   @Binding var showHabitOverlay: Bool
   @Binding var habitOverlayOffset: CGFloat
   
   // Helper computed properties for notification dots
   private var hasIncomingFriendRequests: Bool {
       let hasRequests = !UnifiedFriendManager.shared.receivedRequests.isEmpty
       if hasRequests {
           print("🔴 [HomeView] hasIncomingFriendRequests = true (\(UnifiedFriendManager.shared.receivedRequests.count) requests)")
       }
       return hasRequests
   }
   
   private var needsPaymentSetup: Bool {
       paymentManager.paymentMethod == nil || connectStatus != .connected
   }
   
   private let phraseBank = [
       "lock in twin.",
       "ok but actually do it this time.", 
       "dont fall off.. again…",
       "do NOT fold bruh.",
       "discipline over dopamine.",
       "make urself proud gang.",
       "stay locked in fr.",
       "no excuses today lmao.",
       "if u quit ur actually cooked.",
       "they're broke, ur up.",
       "one day or day one?",
       "do it for the gram."
   ]

   var body: some View {
       NavigationStack {
           GeometryReader { geometry in
               mainBackgroundAndContent
           }
           .navigationBarBackButtonHidden(true)
           .preferredColorScheme(.dark)
           .onAppear {
               updateHabitCache()
               initializeSwipeGestures()
               loadConnectStatus()
               loadPaymentMethod()
           }
           .onChange(of: habitManager.verifiedHabitsToday) { oldValue, _ in updateHabitCache() }
           .onChange(of: habitManager.habitsbydate) { oldValue, _ in updateHabitCache() }
           .onChange(of: habitManager.weeklyHabits) { oldValue, _ in updateHabitCache() }
           .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FriendsViewDismissed"))) { _ in
               isFriendsViewShowing = false
           }
           .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProfileViewDismissed"))) { _ in
               isProfileViewShowing = false
           }
           .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
               // Refresh payment status when app becomes active
               loadConnectStatus()
               loadPaymentMethod()
           }
           .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FriendRequestsUpdated"))) { _ in
               // Force UI refresh when friend requests are updated for immediate notification dot updates
               print("🔴 [HomeView] Friend requests updated, refreshing UI for notification dots")
           }
           // NEW: Post preview sheet for 120Hz device fix
           .fullScreenCover(item: $activeVerification) { verification in
               PostPreviewCard(
                   verificationId: verification.id,
                   onPublish: { _ in dismissAndNavigate() },
                   onCancel: { dismissAndNavigate() }
               )
           }
       }
   }
   @ViewBuilder
   private var mainBackgroundAndContent: some View {
       ZStack {
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
           VStack(spacing: 0) {
               navigationBar
               mainContent
           }
       }
   }
   private var navigationBar: some View {
       HStack {
           // Left side - tally logo aligned with house icon
           Text("tally.")
               .font(.custom("EBGaramond-Regular", size: 32))
               .foregroundColor(.white)
               .tracking(0.5)
               .padding(.leading, 24) // Match navbar (16px) + TabBarContent (12px) padding
          
           Spacer()
          
           // Right side - notifications and friends aligned with navbar edge
           HStack(spacing: 20) {
               // Friends button with filled/unfilled logic and notification dot
               Button(action: {
                   isFriendsViewShowing = true
                   showFriendsView()
               }) {
                   ZStack {
                       Image(systemName: isFriendsViewShowing ? "person.2.fill" : "person.2")
                           .foregroundColor(.white)
                           .font(.custom("EBGaramond-Regular", size: 22))
                           .animation(nil, value: isFriendsViewShowing)
                       
                       // Notification dot for incoming friend requests
                       if hasIncomingFriendRequests {
                           NotificationDot()
                               .offset(x: 12, y: -12)
                       }
                   }
               }
               
               // Settings button with filled/unfilled logic and notification dot
               Button(action: {
                   isProfileViewShowing = true
                   showProfileView()
               }) {
                   ZStack {
                       Image(systemName: isProfileViewShowing ? "gearshape.fill" : "gearshape")
                           .foregroundColor(.white)
                           .font(.custom("EBGaramond-Regular", size: 22))
                           .animation(nil, value: isProfileViewShowing)
                       
                       // Notification dot for payment method setup
                       if needsPaymentSetup {
                           NotificationDot()
                               .offset(x: 12, y: -12)
                       }
                   }
               }
           }
           .padding(.trailing, 16) // Match navbar horizontal padding
       }
       .frame(height: 44)
       .padding(.top, 4)
       .padding(.bottom, 16)
   }
  
   private var mainContent: some View {
       GeometryReader { geometry in
           VStack(spacing: 0) {
               // Header section with new content above cards
               VStack(spacing: UIScreen.main.bounds.height * 0.018) { // more vertical space
                   habitsSummary
                   newContentAboveCards
                    .padding(.bottom, 40)
               }
               .frame(height: geometry.size.height * 0.13)  // increased header height

               if cachedSortedHabits.isEmpty {
                   emptyStateView
                       .frame(height: geometry.size.height * 0.87)  // adjust for new header height
               } else {
                   HStack {
                       Text("HABITS, \(formattedHeaderDate).")
                           .font(.custom("EBGaramond-Italic", size: 22))
                           .italic()
                           .foregroundColor(.white)
                           .padding(.top, 6)
                           .padding(.leading, 20)
                       
                       Spacer()
                   }
                   .frame(maxWidth: .infinity, alignment: .leading)
                   
                   paginationBar
                       .frame(height: geometry.size.height * 0.02)
                       .padding(.top, 2)
                       .padding(.bottom, -8)
                   
                   habitCardsContainer
                       .frame(height: geometry.size.height * 0.78)
                       .padding(.top, -26)
               }
           }
       }
       .padding(.horizontal, UIScreen.main.bounds.width * 0.02)
   }


   private var habitsSummary: some View {
       // Empty spacer to maintain layout structure but remove text and reduce height
       Spacer()
           .frame(maxWidth: .infinity, maxHeight: .infinity)
   }


   // Add your new content here
   private var newContentAboveCards: some View {
       HStack(alignment: .center) {
           VStack(alignment: .leading, spacing: 4) {
               // Username's Day (italic, all caps)
               (
                   Text("here's your ")
                       .font(.custom("EBGaramond-Regular", size: 28))
                   +
                   Text(formattedDayOfWeek + ".")
                       .font(.custom("EBGaramond-Regular", size: 28))
                       .italic()
               )
               .foregroundColor(.white)
               .padding(.bottom, 0)
               // Animated subtitle/quote
               Text(animatedHeaderText)
                   .font(.custom("EBGaramond-Regular", size: 22))
                   .foregroundColor(.white.opacity(0.9))
           }
           Spacer()
           // Habits navigation button
            Button {
                habitOverlayOffset = UIScreen.main.bounds.width   // reset for next time
                showHabitOverlay  = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        habitOverlayOffset = 0                     // slide in from right
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "chevron.right")
                        .font(.custom("EBGaramond-Regular", size: 22))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
           .buttonStyle(PlainButtonStyle())
           .padding(.trailing, 12) // Added padding to move it slightly left
       }
       .padding(.horizontal, 16)
       .onAppear {
           startTypingHeader()
       }
   }
  
   // Helper for day of week
   private var formattedDayOfWeek: String {
       return Date().dayOfWeek
   }
  
   private var habitCardsContainer: some View {
       GeometryReader { geometry in
           let cardWidth = geometry.size.width * 0.96  // 96% of available width
           let cardHeight = geometry.size.height * 0.85  // Use your preferred card height
           let sideCardOffset: CGFloat = cardWidth * 0.75  // 75% of card width for side positioning
           let topPadding = geometry.size.height * 0.07  // 8% top padding to center cards vertically
           let windowRadius = 2
           
           // Ensure we have habits and currentHabitIndex is valid
           guard !cachedSortedHabits.isEmpty else { return AnyView(EmptyView()) }
           let safeCurrentIndex = max(0, min(currentHabitIndex, cachedSortedHabits.count - 1))
           
           let lowerBound = max(0, safeCurrentIndex - windowRadius)
           let upperBound = min(cachedSortedHabits.count - 1, safeCurrentIndex + windowRadius)
          
           return AnyView(
               ZStack {
                   // Only create ForEach if we have a valid range
                   if lowerBound <= upperBound {
                       ForEach(lowerBound...upperBound, id: \.self) { index in
                           habitCardForIndex(
                               index,
                               safeCurrentIndex: safeCurrentIndex,
                               cardWidth: cardWidth,
                               cardHeight: cardHeight,
                               sideCardOffset: sideCardOffset
                           )
                       }
                   }
               }
               .frame(width: geometry.size.width, height: cardHeight)
               .position(x: geometry.size.width / 2, y: (cardHeight / 2) + topPadding)
           )
       }
       .clipped()
   }
  
   private func habitCardForIndex(
       _ index: Int,
       safeCurrentIndex: Int,
       cardWidth: CGFloat,
       cardHeight: CGFloat,
       sideCardOffset: CGFloat
   ) -> some View {
       // Ensure index is within bounds
       guard index >= 0 && index < cachedSortedHabits.count else {
           return AnyView(EmptyView())
       }
       let habit = cachedSortedHabits[index]
       let dragHandler: ((CGFloat) -> Void)? = createDragHandler(for: index)
      
       return AnyView(HabitCardView(
           habit: habit,
           habitManager: habitManager,
           index: index,
           currentHabitIndex: safeCurrentIndex,
           cardWidth: cardWidth,
           cardHeight: cardHeight,
           sideCardOffset: sideCardOffset,
           onVerify: { postVerificationUpdate(for: habit) },
           onSwipeLeft: { handleSwipeLeft() },
           onSwipeRight: { handleSwipeRight() },
           onTapAdjacent: { handleTapAdjacent(index) },
           sharedDragOffset: sharedDragOffset,
           onDragChanged: dragHandler,
           cachedVerificationStatus: cachedVerificationStatus,
           onPreviewRequested: { verification in
               activeVerification = verification // trigger sheet
           }
       ))
   }
  

  
   // MARK: - Helper Methods
  
   private func createDragHandler(for index: Int) -> ((CGFloat) -> Void)? {
       // Capture horizontal drag changes for the *current* card and throttle updates
       // to prevent performance issues on high refresh rate displays
       guard index == currentHabitIndex else { return nil }
       return { offset in
           // Check if drag ended (offset is 0)
           if offset == 0 {
               stopDragUpdateTimer()
               sharedDragOffset = 0
               return
           }
           
           pendingDragOffset = offset
           
           // Throttle updates to 30fps max
           if dragUpdateTimer == nil {
               sharedDragOffset = offset // Immediate first update
               
               dragUpdateTimer = Timer.scheduledTimer(withTimeInterval: dragUpdateInterval, repeats: true) { _ in
                   sharedDragOffset = pendingDragOffset
               }
           }
       }
   }
   
   private func stopDragUpdateTimer() {
       dragUpdateTimer?.invalidate()
       dragUpdateTimer = nil
       pendingDragOffset = 0
   }
  
   // MARK: – Callback from SwipeableHabitCard once a habit finishes verification
   private func postVerificationUpdate(for habit: Habit) {
       // The card has already updated HabitManager; we just need to refresh our caches/UI.
       updateHabitCache()
   }
  
   private func handleSwipeLeft() {
       if currentHabitIndex < cachedSortedHabits.count - 1 {
           // Haptic feedback for successful swipe navigation
           HapticFeedbackManager.shared.lightImpact()
           stopDragUpdateTimer()
           withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
               currentHabitIndex += 1
               sharedDragOffset = 0
           }
       }
   }
  
   private func handleSwipeRight() {
       if currentHabitIndex > 0 {
           // Haptic feedback for successful swipe navigation
           HapticFeedbackManager.shared.lightImpact()
           stopDragUpdateTimer()
           withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
               currentHabitIndex -= 1
               sharedDragOffset = 0
           }
       }
   }
  
   private func handleTapAdjacent(_ index: Int) {
       // Haptic feedback for tap navigation
       HapticFeedbackManager.shared.lightImpact()
       stopDragUpdateTimer()
       withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
           currentHabitIndex = index
           sharedDragOffset = 0
       }
   }
  
   private func initializeSwipeGestures() {
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
           if !cachedSortedHabits.isEmpty {
               let currentIndex = currentHabitIndex
               currentHabitIndex = currentIndex
           }
       }
   }
  
   private var emptyStateView: some View {
       VStack(spacing: UIScreen.main.bounds.height * 0.03) {  // 3% of screen height

           // Add the header row with date
           HStack {
               Text("HABITS, \(formattedHeaderDate).")
                   .font(.custom("EBGaramond-Italic", size: 22))
                   .italic()
                   .foregroundColor(.white)
                   .padding(.top, 6)
                   .padding(.leading, 20)
               Spacer()
           }
           .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
           // Check if we have habits but they're all verified (success case) vs no habits at all
           if !cachedTodaysHabits.isEmpty && cachedSortedHabits.isEmpty {
               // All habits verified - success state
               VStack(spacing: 24) {
                   Image("success_image")
                       .resizable()
                       .scaledToFit()
                       .frame(width: UIScreen.main.bounds.width * 0.22)
                       .shadow(color: .green.opacity(0.3), radius: 10)
                  
                   VStack(spacing: 12) {
                       Text("All habits verified today!")
                           .jtStyle(.title)
                           .fontWeight(.semibold)
                           .foregroundColor(.white)
                           .multilineTextAlignment(.center)
                      
                       Text("Congratulations! Check out the feed to see your progress and connect with friends.")
                           .jtStyle(.body)
                           .foregroundColor(.white.opacity(0.7))
                           .multilineTextAlignment(.center)
                           .padding(.horizontal, 32)
                   }
                  
                   Button(action: {
                       NotificationCenter.default.post(name: .navigateToFeed, object: nil)
                   }) {
                       HStack(spacing: 12) {
                           Image(systemName: "person.2.fill")
                           Text("View Feed")
                       }
                       .font(.ebGaramondBody)
                       .fontWeight(.medium)
                       .foregroundColor(.black)
                       .padding(.horizontal, 28)
                       .padding(.vertical, 14)
                       .background(
                           RoundedRectangle(cornerRadius: 25)
                               .fill(Color.white)
                               .shadow(color: .white.opacity(0.2), radius: 8)
                       )
                   }
               }
               .padding(.vertical, 32)
           } else {
               // No habits set up
               VStack(spacing: 16) {
                   Image("home_hero_image")
                       .resizable()
                       .scaledToFit()
                       .frame(width: UIScreen.main.bounds.width * 0.4)
                       .padding(.bottom, 8)
                   Text("make it count")
                       .font(.custom("EBGaramond-Regular", size: 22))
                       .foregroundColor(.white.opacity(0.7))
                       .padding(.top, 8)
               }
           }
          Spacer()
           Spacer()
       }
       .frame(maxWidth: .infinity)
   }
  
   private var formattedHeaderDate: String {
       return Date().formattedShort
   }
   // MARK: - Cache Management
  
   private func updateHabitCache() {
       let currentWeekday = Calendar.current.component(.weekday, from: Date()) - 1 // 0-6
       let todaysHabits = habitManager.habitsbydate[currentWeekday] ?? []
       
       // Only include incomplete weekly habits (those that haven't reached their target)
       let incompleteWeeklyHabits = habitManager.incompleteWeeklyHabits.filter { habitManager.verifiedHabitsToday[$0.id] != true }
      
       let allHabitsForToday = todaysHabits + incompleteWeeklyHabits
      
       // Only show unverified habits - remove verified ones from display
       let unverified = allHabitsForToday.filter { habitManager.verifiedHabitsToday[$0.id] != true }
      
       cachedTodaysHabits = allHabitsForToday
       cachedSortedHabits = unverified // Only show unverified habits
       cachedCompletedCount = habitManager.verifiedHabitsToday.values.filter { $0 }.count
       cachedVerificationStatus = habitManager.verifiedHabitsToday
       
       // Ensure currentHabitIndex stays within bounds
       if !cachedSortedHabits.isEmpty {
           // If current index is out of bounds, reset to 0
           if currentHabitIndex >= cachedSortedHabits.count {
               currentHabitIndex = 0
           }
       } else {
           // No habits left, reset to 0
           currentHabitIndex = 0
       }
      
       // No need to preload images for verified habits since they won't be shown
       // Removed the image preloading for verified habits
   }
  
   private func clearHabitCache() {
       cachedTodaysHabits = []
       cachedSortedHabits = []
       cachedCompletedCount = 0
       cachedVerificationStatus = [:]
       currentHabitIndex = 0
       sharedDragOffset = 0
   }
  
   private func startTypingHeader() {
       typingTimer?.invalidate()
       animatedHeaderText = " " // Start with a space instead of empty string
       // Pick a random phrase from the bank
       let fullText = phraseBank.randomElement() ?? ""
       var charIndex = 0
       
       // Prepare haptic generator once
       hapticGenerator.prepare()
       
       typingTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
           if charIndex < fullText.count {
               let index = fullText.index(fullText.startIndex, offsetBy: charIndex)
               animatedHeaderText.append(fullText[index])
               charIndex += 1
               
               // Haptic feedback for each character using the single instance
               hapticGenerator.impactOccurred()
           } else {
               timer.invalidate()
               typingTimer = nil
           }
       }
   }
  
   private var fullHeaderText: String {
       "\(authManager.currentUser?.name ?? "User")'s \(formattedDayOfWeek)"
   }

   // Pagination bar above cards
   private var paginationBar: some View {
       VStack(spacing: 1) {
           if cachedSortedHabits.count > 1 {
               GeometryReader { geometry in
                   ZStack(alignment: .leading) {
                       // Background bar
                       Rectangle()
                           .fill(Color.white.opacity(0.3))
                           .frame(height: 2)
                           .cornerRadius(2)
                           .opacity(currentHabitIndex == 0 ? 0 : 1)
                       
                       // Filled portion
                       Rectangle()
                           .fill(Color.white)
                           .frame(
                               width: currentHabitIndex == 0 ? 0 : geometry.size.width * CGFloat(currentHabitIndex + 1) / CGFloat(cachedSortedHabits.count),
                               height: 2
                           )
                           .cornerRadius(2)
                           .opacity(currentHabitIndex == 0 ? 0 : 1)
                           .animation(.spring(response: 0.75), value: currentHabitIndex)
                   }
               }
               .frame(height: 4)
               .padding(.horizontal, 20)
               .gesture(
                   DragGesture(minimumDistance: 0)
                       .onEnded { value in
                           let percentage = value.location.x / UIScreen.main.bounds.width
                           let newIndex = Int(percentage * CGFloat(cachedSortedHabits.count))
                           stopDragUpdateTimer()
                           withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                               currentHabitIndex = max(0, min(newIndex, cachedSortedHabits.count - 1))
                               sharedDragOffset = 0
                           }
                       }
               )
           }
       }
   }

   // Helper for first name
   private var firstName: String {
       let fullName = authManager.currentUser?.name ?? "User"
       return fullName.split(separator: " ").first.map(String.init) ?? fullName
   }

   // MARK: - Payment Status Loading
   private func loadConnectStatus() {
       // Load cached status first
       if let raw = UserDefaults.standard.string(forKey: "cachedConnectStatus") {
           switch raw {
           case "connected": connectStatus = .connected
           case "pending": connectStatus = .pending
           default: connectStatus = .notConnected
           }
       }
       
       // Then refresh from server
       Task {
           await refreshConnectStatus()
       }
   }
   
   private func refreshConnectStatus() async {
       guard let token = AuthenticationManager.shared.storedAuthToken else { return }
       
       do {
           guard let url = URL(string: "\(AppConfig.baseURL)/payments/connect/account-status") else { return }
           var request = URLRequest(url: url)
           request.httpMethod = "GET"
           request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
           
           let (data, response) = try await URLSession.shared.data(for: request)
           guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
           
           let statusResponse = try JSONDecoder().decode(ConnectStatusResponse.self, from: data)
           
           await MainActor.run {
               switch statusResponse.status {
               case "connected":
                   if statusResponse.details_submitted == true && statusResponse.charges_enabled == true && statusResponse.payouts_enabled == true {
                       connectStatus = .connected
                   } else {
                       connectStatus = .pending
                   }
               case "pending":
                   connectStatus = .pending
               default:
                   connectStatus = .notConnected
               }
           }
       } catch {
           print("❌ Error refreshing connect status: \(error)")
       }
   }
   
   private func loadPaymentMethod() {
       guard let token = AuthenticationManager.shared.storedAuthToken else { return }
       
       Task {
           await paymentManager.fetchPaymentMethod(token: token)
       }
   }
   
   // NEW: Post preview completion handler for 120Hz device fix
   private func dismissAndNavigate() {
       activeVerification = nil
       NotificationCenter.default.post(name: .navigateToFeed, object: nil)
   }
}


// MARK: - Helper Views


struct HabitCardView: View {
   let habit: Habit
   let habitManager: HabitManager
   let index: Int
   let currentHabitIndex: Int
   let cardWidth: CGFloat
   let cardHeight: CGFloat
   let sideCardOffset: CGFloat
   let onVerify: () -> Void
   let onSwipeLeft: () -> Void
   let onSwipeRight: () -> Void
   let onTapAdjacent: () -> Void
  
   // Shared drag offset from parent
   let sharedDragOffset: CGFloat
   let onDragChanged: ((CGFloat) -> Void)?
  
   // Cache verification status to prevent repeated lookups during drag
   let cachedVerificationStatus: [String: Bool]
   
   // NEW: Post preview callback for 120Hz device fix
   let onPreviewRequested: (HabitVerification) -> Void
  
   private var isCurrentCard: Bool {
       index == currentHabitIndex
   }
  
   private var distance: Int {
       index - currentHabitIndex
   }
  
   // Simplified position calculation
   private var baseOffset: CGFloat {
       // Cache static offset calculation
       let staticOffset: CGFloat
       switch distance {
       case 0:
           staticOffset = 0 // Current card centered
       case 1:
           staticOffset = sideCardOffset // Right card
       case -1:
           staticOffset = -sideCardOffset // Left card
       default:
           // Cards further away are hidden behind adjacent cards
           staticOffset = distance > 0 ? sideCardOffset + 20 : -sideCardOffset - 20
       }
      
       // Optimized drag influence calculation
       let dragInfluence: CGFloat
       if isCurrentCard {
           dragInfluence = sharedDragOffset
       } else if abs(distance) == 1 {
           // Reduced influence and simplified calculation for better performance
           dragInfluence = sharedDragOffset * 0.25
       } else {
           dragInfluence = 0
       }
      
       return staticOffset + dragInfluence
   }
  
   var body: some View {
       SwipeableHabitCard(
           habit: habit,
           habitManager: habitManager,
           onVerify: onVerify,
           onSwipeLeft: onSwipeLeft,
           onSwipeRight: onSwipeRight,
           isCurrentCard: isCurrentCard,
           cardWidth: cardWidth,
           cardHeight: cardHeight,
           cardIndex: index,
           currentIndex: currentHabitIndex,
           parentDragOffset: sharedDragOffset,
           onDragChanged: onDragChanged,
           onPreviewRequested: onPreviewRequested
       )
       .drawingGroup() // Flatten rendering hierarchy to prevent flashing
       .offset(x: baseOffset, y: 0)
       .scaleEffect(isCurrentCard ? 1.0 : 0.88)
       .zIndex(isCurrentCard ? 2 : (abs(distance) == 1 ? 1 : 0))
       .allowsHitTesting(isCurrentCard || abs(distance) == 1)
       .onTapGesture {
           if !isCurrentCard && abs(distance) == 1 {
               onTapAdjacent()
           }
       }
       // Single animation to prevent conflicts
       .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentHabitIndex)
       .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: sharedDragOffset)
   }
}

#Preview {
       HomeView(showFriendsView: {}, showProfileView: {}, onProfileViewDismissed: {}, showHabitOverlay: .constant(false), habitOverlayOffset: .constant(0))
       .environmentObject(AuthenticationManager.shared)
       .environmentObject(HabitManager.shared)
       .environmentObject(FriendsManager.shared)
       .environmentObject(PaymentManager.shared)
}



