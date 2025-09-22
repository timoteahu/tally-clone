import SwiftUI
import AVFoundation
import StoreKit


struct SwipeableHabitCard: View {
  
   // MARK: - Types
  
   enum CameraMode {
       case selfie
       case content
   }
  
   let habit: Habit
   @ObservedObject var habitManager: HabitManager
   let onVerify: () -> Void
   let onSwipeLeft: () -> Void
   let onSwipeRight: () -> Void
   let isCurrentCard: Bool
   let cardWidth: CGFloat
   let cardHeight: CGFloat
   let cardIndex: Int
   let currentIndex: Int
   let parentDragOffset: CGFloat
  
   // Use computed property to check verification status directly from habitManager
   private var isHabitVerified: Bool {
       habitManager.verifiedHabitsToday[habit.id] == true
   }
   
   // NEW: Post preview callback for 120Hz device fix
   let onPreviewRequested: (HabitVerification) -> Void
  
   @State private var verticalDragOffset = CGSize.zero
   @State private var isGestureReady: Bool
   @State private var cachedImage: UIImage? // Cache UIImage directly for better performance
   @State private var cachedSelfieImage: UIImage? // Cache for selfie image
   @State private var cachedContentImage: UIImage? // Cache for content image
   @State private var showingSelfieAsMain = false // Track which image is displayed as main
   @StateObject private var imageCacheManager = ImageCacheManager.shared
   @State private var showVerificationView = false // New state for inline verification view
   @State private var selfieImageData: Data? = nil
   @State private var contentImageData: Data? = nil
   @State private var isVerifying: Bool = false
   @State private var showingCamera: Bool = false
   @State private var cameraMode: CameraMode = .selfie // New state to track which image we're taking
   @State private var studySessionId: String?
   @State private var isStudySessionActive = false
   @State private var alarmCheckInTime: Date?
   @State private var isWithinCheckInWindow = false
   @State private var isWithinVerificationWindow = false
   @State private var firstImageTaken = false // Track if first image has been taken
   @State private var firstImageWasSelfie = true // Track what type the first image was
   @State private var bothImagesComplete = false // Track when both images are captured
   @State private var frontCameraImageData: Data? // Data from front camera
   @State private var rearCameraImageData: Data? // Data from rear camera
   @State private var showingErrorAlert = false // New state for error popup
   @State private var errorAlertMessage = "" // New state for error message
   @State private var showHelpBubble = false // New state for help bubble
   @State private var showInCardError = false // New state for in-card error display
   @State private var errorShakeOffset: CGFloat = 0 // For error shake animation
   @StateObject private var verificationManager = HabitVerificationManager()
   @EnvironmentObject var authManager: AuthenticationManager
  
   // Callback to update parent drag state
   let onDragChanged: ((CGFloat) -> Void)?
  
   init(habit: Habit, habitManager: HabitManager, onVerify: @escaping () -> Void, onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void, isCurrentCard: Bool, cardWidth: CGFloat, cardHeight: CGFloat, cardIndex: Int, currentIndex: Int, parentDragOffset: CGFloat = 0, onDragChanged: ((CGFloat) -> Void)? = nil, onPreviewRequested: @escaping (HabitVerification) -> Void) {
       self.habit = habit
       self._habitManager = ObservedObject(wrappedValue: habitManager)
       self.onVerify = onVerify
       self.onSwipeLeft = onSwipeLeft
       self.onSwipeRight = onSwipeRight
       self.isCurrentCard = isCurrentCard
       self.cardWidth = cardWidth
       self.cardHeight = cardHeight
       self.cardIndex = cardIndex
       self.currentIndex = currentIndex
       self.parentDragOffset = parentDragOffset
       self.onDragChanged = onDragChanged
       self.onPreviewRequested = onPreviewRequested
       self._isGestureReady = State(initialValue: isCurrentCard)
   }
  
   var body: some View {
       // Main card content with conditional layout
       ZStack {
           Group {
               unverifiedCardLayout
           }
           .frame(width: cardWidth, height: cardHeight)
           .background(cardBackground)
           .scaleEffect(cardScale)
           .opacity(cardOpacity)
           .offset(y: cardOffset)
           .gesture(cardGesture)
           .onAppear {
               // Ensure gesture is ready immediately for all cards
               isGestureReady = true
           }
           .onChange(of: isCurrentCard) { oldValue, newValue in
               if newValue {
                   // Reset any drag offsets when becoming current card
                   verticalDragOffset = .zero
                   isGestureReady = true
               } else {
                   // Reset verification view when card is no longer current
                   showVerificationView = false
                   showHelpBubble = false
               }
           }
           .fullScreenCover(isPresented: $showingCamera) {
               DualCameraCapture(
                   frontCameraImageData: $frontCameraImageData,
                   rearCameraImageData: $rearCameraImageData,
                   bothImagesComplete: $bothImagesComplete,
                   startingCameraMode: cameraMode
               )
               .onDisappear {
                   // Only process when both images are complete
                   if bothImagesComplete {
                       // Map the camera-specific data to selfie/content based on camera position
                       selfieImageData = frontCameraImageData
                       contentImageData = rearCameraImageData
                       
                       // Reset tracking variables
                       firstImageTaken = false
                       firstImageWasSelfie = true
                       bothImagesComplete = false
                       frontCameraImageData = nil
                       rearCameraImageData = nil
                       
                       // Automatically flip to verification view to show the captured photos
                       withAnimation(.easeInOut(duration: 0.28)) {
                           showVerificationView = true
                       }
                   }
               }
           }
          
           // Verification animation overlay
           if isVerifying {
               HabitVerificationAnimationView(
                   habitType: habit.habitType,
                   habitName: habit.name,
                   isVerifying: $isVerifying
               )
               .frame(width: cardWidth, height: cardHeight)
               .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.07))
               .transition(.opacity)
           }
           
           // In-card error overlay
           if showInCardError {
               InCardErrorView(
                   message: errorAlertMessage,
                   cardWidth: cardWidth,
                   cardHeight: cardHeight,
                   onDismiss: {
                       withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                           showInCardError = false
                           errorShakeOffset = 0
                       }
                   }
               )
               .frame(width: cardWidth, height: cardHeight)
               .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.07))
               .transition(.scale.combined(with: .opacity))
           }
       }
       .offset(x: errorShakeOffset)
       .onChange(of: showInCardError) { _, newValue in
           if newValue {
               // Trigger error haptic and shake animation
               HapticFeedbackManager.shared.playVerificationError()
               withAnimation(.spring(response: 0.1, dampingFraction: 0.2).repeatCount(3, autoreverses: true)) {
                   errorShakeOffset = 8
               }
               DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                   errorShakeOffset = 0
               }
           }
       }
   }
  
   private var unverifiedCardLayout: some View {
       ZStack {
           // FRONT
           unverifiedCardContent
               .opacity(showVerificationView ? 0 : 1)


           // BACK
           VerificationView(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               verificationContentView: AnyView(verificationContentView),
               setupVerificationView: setupVerificationView,
               onBack: {
                   // Flip the view first
                   withAnimation {
                       showVerificationView = false
                   }
                   
                   // Clear captured photos after a brief delay
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                       selfieImageData = nil
                       contentImageData = nil
                   }
               }
           )
               .opacity(showVerificationView ? 1 : 0)
       }
       // one liner that animates any change in `showVerificationView`
       .animation(.easeInOut(duration: 0.28), value: showVerificationView)
   }
   @ViewBuilder
   private var unverifiedCardContent: some View {
       if habit.habitType == "alarm" {
           // Special unified layout for alarm cards
           AlarmUnifiedCardContent(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               isWithinCheckInWindow: isWithinCheckInWindow,
               isWithinVerificationWindow: isWithinVerificationWindow,
               alarmCheckInTime: alarmCheckInTime,
               formattedTime: formattedTime,
               formattedAlarmTime: formattedAlarmTime,
               checkInForAlarm: checkInForAlarm,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               habitTypeAccentColor: habitTypeAccentColor,
               getHabitIcon: getHabitIcon,
               weeklyProgressBadge: AnyView(weeklyProgressBadge),
               getTimeWindows: getTimeWindows,
               setupVerificationView: setupVerificationView,
               onExpand: { 
                   // Flip the card to show verification view
                   showVerificationView.toggle()
               },
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               habitManager: habitManager
           )
       } else if habit.habitType == "gym" {
           // Special unified layout for gym cards
           GymUnifiedCardContent(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               habitTypeAccentColor: habitTypeAccentColor,
               getHabitIcon: getHabitIcon,
               weeklyProgressBadge: AnyView(weeklyProgressBadge),
               onVerify: onVerify,
               onExpand: {
                   showVerificationView.toggle()
               },
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               habitManager: habitManager
           )
       } else if habit.habitType == "github_commits" {
           GitHubCommitCard(
               habit: habit,
               commits: habit.isWeeklyHabit ? 
                   (habitManager.weeklyCommitCounts[habit.id] ?? 0) : 
                   (habitManager.todayCommitCounts[habit.id] ?? 0),
               cardWidth: cardWidth,
               cardHeight: cardHeight
           )
       } else if habit.habitType == "leetcode" {
           LeetCodeCard(
               habit: habit,
               problemsSolved: habit.isWeeklyHabit ?
                   (habitManager.weeklyLeetCodeCounts[habit.id] ?? 0) :
                   (habitManager.todayLeetCodeCounts[habit.id] ?? 0),
               cardWidth: cardWidth,
               cardHeight: cardHeight
           )
       } else if habit.habitType == "league_of_legends" || habit.habitType == "valorant" {
           GamingCard(
               habit: habit,
               hoursPlayed: habitManager.todayGamingHours[habit.id] ?? 0,
               cardWidth: cardWidth,
               cardHeight: cardHeight
           )
       } else if habit.isHealthHabit {
           HealthUnifiedCardContent(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               habitTypeAccentColor: habitTypeAccentColor,
               getHabitIcon: getHabitIcon,
               weeklyProgressBadge: AnyView(weeklyProgressBadge),
               onVerify: onVerify,
               onExpand: {
                   showVerificationView.toggle()
               },
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               habitManager: habitManager
           )
       } else {
           // Standard layout for other habit types
           StandardUnverifiedCardContent(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               habitTypeAccentColor: habitTypeAccentColor,
               getHabitIcon: getHabitIcon,
               weeklyProgressBadge: AnyView(weeklyProgressBadge),
               onVerify: onVerify,
               onExpand: {
                   showVerificationView.toggle()
               },
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               habitManager: habitManager
           )
       }
   }


   // MARK: - Days of Week Indicator
  
   private var daysOfWeekIndicator: some View {
       HStack(spacing: cardWidth * 0.008) {
           ForEach(0..<7, id: \.self) { dayIndex in
               let dayLetter = ["S", "M", "T", "W", "T", "F", "S"][dayIndex]
               let dayNumber = dayIndex == 0 ? 7 : dayIndex // Convert Sunday from 0 to 7 to match habit.weekdays format
               let isSelected = habit.weekdays.contains(dayNumber)
              
               Circle()
                   .fill(isSelected ? Color.white : Color.black.opacity(0.6))
                   .frame(width: cardWidth * 0.055, height: cardWidth * 0.055)
                   .overlay(
                       Text(dayLetter)
                           .font(.custom("EBGaramond-Regular", size: cardWidth * 0.022)).fontWeight(.medium)
                           .foregroundColor(isSelected ? .black : .white)
                   )
                   .overlay(
                       Circle()
                           .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                   )
           }
       }
       .padding(.horizontal, cardWidth * 0.015)
       .padding(.vertical, cardHeight * 0.008)
       .background(
           Capsule()
               .fill(Color.black.opacity(0.4))
               .blur(radius: 8)
       )
   }
  
   // MARK: - Weekly Progress Badge
  
   private var weeklyProgressBadge: some View {
       VStack(spacing: cardHeight * 0.003) {
           Text("WEEKLY")
               .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025)).fontWeight(.bold)
               .foregroundColor(.blue)
           // For GitHub weekly habits, use commitTarget instead of weeklyTarget
           let targetValue = (habit.habitType == "github_commits" && habit.isWeeklyHabit) ? 
               (habit.commitTarget ?? 7) : (habit.weeklyTarget ?? 1)
           Text("\(weeklyProgress)/\(targetValue)")
               .font(.custom("EBGaramond-Regular", size: cardWidth * 0.025)).fontWeight(.semibold)
               .foregroundColor(.blue)
       }
       .padding(.horizontal, cardWidth * 0.02)
       .padding(.vertical, cardHeight * 0.008)
       .background(Color.blue.opacity(0.1))
       .clipShape(Capsule())
       .overlay(
           Capsule()
               .stroke(Color.blue.opacity(0.3), lineWidth: 1)
       )
       .onAppear {
           // NEW: Track when user views weekly progress badge
           DataCacheManager.shared.trackUserInteraction()
       }
   }
  
   // NEW: Computed property that tracks user interaction
   private var weeklyProgress: Int {
       DataCacheManager.shared.trackUserInteraction()
       return habitManager.getWeeklyHabitProgress(for: habit.id)
   }
  
   // MARK: - View Components
  
   private var headerSection: some View {
       HStack {
           VStack(alignment: .leading, spacing: cardHeight * 0.008) {  // 0.8% of card height
               Text(habit.name)
                   .jtStyle(.title)  // Reduced from title
                   .foregroundColor(isHabitVerified ? .white.opacity(0.6) : .white)
                   .lineLimit(2)
              
               if let recipientName = habit.getRecipientName() {
                   HStack(spacing: cardWidth * 0.015) {  // 1.5% of card width
                       Image(systemName: "person.fill")
                           .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))  // 3.5% of card width
                           .foregroundColor(.white.opacity(0.7))
                       Text(recipientName)
                           .jtStyle(.body)  // Reduced from body
                           .foregroundColor(.white.opacity(0.7))
                           .lineLimit(1)
                   }
               }
           }
          
           Spacer()
          
           if isHabitVerified {
               Image(systemName: "checkmark.circle.fill")
                   .foregroundColor(.green)
                   .font(.custom("EBGaramond-Regular", size: cardWidth * 0.07))  // 7% of card width (reduced from fixed 28)
           }
       }
   }
  
  
   private var penaltySection: some View {
       HStack {
           Spacer()
           VStack(alignment: .trailing, spacing: cardHeight * 0.008) {  // 0.8% of card height
               HStack(spacing: cardWidth * 0.015) {  // 1.5% of card width
                   Image(systemName: isHabitVerified ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                       .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035))  // 3.5% of card width
                       .foregroundColor(isHabitVerified ? .green : .orange)
                  
                   Text(isHabitVerified ? "Completed" : "Penalty")
                       .jtStyle(.caption)  // Reduced from subheadline
                       .foregroundColor(.white.opacity(0.8))
               }
              
               Text("$\(String(format: "%.2f", habit.penaltyAmount))")
                   .jtStyle(.title)  // Reduced from title2
                   .foregroundColor(isHabitVerified ? .green : .red)
                   .shadow(color: isHabitVerified ? Color.green.opacity(0.3) : Color.red.opacity(0.3), radius: 2, x: 0, y: 1)
           }
           .padding(.horizontal, cardWidth * 0.04)  // 4% of card width (reduced from 5%)
           .padding(.vertical, cardHeight * 0.015)  // 1.5% of card height (reduced from 2.5%)
           .background(
               RoundedRectangle(cornerRadius: cardWidth * 0.03)  // 3% of card width (reduced from 3.5%)
                   .fill(Color.black.opacity(0.2))
                   .overlay(
                       RoundedRectangle(cornerRadius: cardWidth * 0.03)  // 3% of card width
                           .stroke(
                               isHabitVerified ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                               lineWidth: 1
                           )
                   )
           )
       }
   }
  
   @ViewBuilder
   private var swipeInstructionSection: some View {
       if !isHabitVerified && isCurrentCard {
           HStack(spacing: cardWidth * 0.03) {  // 3% of card width
               Image(systemName: "hand.tap.fill")
                   .font(.custom("EBGaramond-Regular", size: cardWidth * 0.06))  // 6% of card width (reduced from 8%)
                   .foregroundColor(.blue.opacity(0.8))
              
               VStack(alignment: .leading, spacing: cardHeight * 0.005) {  // 0.5% of card height
                   Text("Tap to verify")
                       .jtStyle(.body)  // Reduced from headline
                       .foregroundColor(.white.opacity(0.9))
                  
                   Text("Complete your habit now")
                       .jtStyle(.caption)  // Reduced from caption
                       .foregroundColor(.white.opacity(0.6))
               }
              
               Spacer()
           }
           .padding(.horizontal, cardWidth * 0.04)  // 4% of card width (reduced from 6%)
           .padding(.vertical, cardHeight * 0.02)  // 2% of card height (reduced from 3.5%)
           .background(
               RoundedRectangle(cornerRadius: cardWidth * 0.035)  // 3.5% of card width (reduced from 4.5%)
                   .fill(
                       LinearGradient(
                           gradient: Gradient(colors: [
                               Color.blue.opacity(0.15),
                               Color.blue.opacity(0.05)
                           ]),
                           startPoint: .leading,
                           endPoint: .trailing
                       )
                   )
                   .overlay(
                       RoundedRectangle(cornerRadius: cardWidth * 0.035)  // 3.5% of card width
                           .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                   )
           )
           .frame(maxWidth: .infinity)
       }
   }
  
   // MARK: - Computed Properties
  
   private var cardBackground: some View {
       RoundedRectangle(cornerRadius: cardWidth * 0.07)
           .fill(
               LinearGradient(
                   gradient: Gradient(stops: [
                       Gradient.Stop(color: Color(hex: "01050B"), location: 0.0),
                       Gradient.Stop(color: Color(hex: "03070E"), location: 0.1),
                       Gradient.Stop(color: Color(hex: "060B12"), location: 0.2),
                       Gradient.Stop(color: Color(hex: "080D15"), location: 0.3),
                       Gradient.Stop(color: Color(hex: "0A0F17"), location: 0.4),
                       Gradient.Stop(color: Color(hex: "0C111A"), location: 0.55),
                       Gradient.Stop(color: Color(hex: "0F141F"), location: 0.7),
                       Gradient.Stop(color: Color(hex: "131824"), location: 0.85),
                       Gradient.Stop(color: Color(hex: "161C29"), location: 1.0)
                   ]),
                   startPoint: .topLeading,
                   endPoint: .bottomTrailing
               )
           )
           .overlay(
               RoundedRectangle(cornerRadius: cardWidth * 0.07)
                   .stroke(Color.white.opacity(0.3), lineWidth: 1)
           )
   }


  
   private var habitTypeAccentColor: Color {
       switch habit.habitType {
       case "studying": return .blue
       case "screenTime": return .purple
       case "gym": return .red
       case "alarm": return .orange
       case "yoga": return .green
       case "outdoors": return .teal
       case "cycling": return .cyan
       case "cooking": return .yellow
       case let type where type.hasPrefix("custom_"): return .purple
       default: return .gray
       }
   }
  
   private var cardScale: CGFloat {
       if isCurrentCard {
           // Ultra-simplified scale calculation
           let dragFactor = min(abs(verticalDragOffset.height) * 0.0001, 0.05)
           return 1.0 - dragFactor
       } else {
           let distance = abs(cardIndex - currentIndex)
           return distance == 1 ? 0.88 : 0.75
       }
   }
  
   private var cardOpacity: Double {
       if isCurrentCard {
           // Ultra-simplified opacity calculation
           let dragFactor = min(abs(verticalDragOffset.height) * 0.0001, 0.03)
           return 1.0 - dragFactor
       } else {
           // All cards are fully opaque - no transparency
           return 1.0
       }
   }
  
   private var cardOffset: CGFloat {
       isCurrentCard ? verticalDragOffset.height : 0
   }
  
   private var cardGesture: some Gesture {
       DragGesture()
           .onChanged { value in
               // Disable gesture when verification view is showing
               guard isCurrentCard && isGestureReady && !showVerificationView else { return }
              
               // Simplified drag detection - less computation
               let absHeight = abs(value.translation.height)
               let absWidth = abs(value.translation.width)
              
               if absWidth > absHeight * 1.5 {
                   // Handle horizontal swipe for navigation - immediate response
                   let dampedTranslation = value.translation.width * 0.8
                   onDragChanged?(dampedTranslation)
               }
           }
           .onEnded { value in
               // Disable gesture when verification view is showing
               guard isCurrentCard && isGestureReady && !showVerificationView else { return }
              
               // Simplified drag detection for end gesture
               let absHeight = abs(value.translation.height)
               let absWidth = abs(value.translation.width)
              
               var didTriggerAction = false
              
               if absWidth > absHeight * 1.5 {
                   // Horizontal swipe for navigation
                   let swipeThreshold: CGFloat = 50
                  
                   if value.translation.width > swipeThreshold {
                       didTriggerAction = true
                       onSwipeRight()
                   } else if value.translation.width < -swipeThreshold {
                       didTriggerAction = true
                       onSwipeLeft()
                   }
               }
              
               // Reset parent drag state
               onDragChanged?(0)
              
               // Reset offsets
               if !didTriggerAction {
                   withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                       verticalDragOffset = .zero
                   }
               } else {
                   verticalDragOffset = .zero
               }
           }
   }
  
   // MARK: - Helper Methods
  
  
   private func getHabitIcon() -> String {
       // Determine the canonical habit type string used by the backend.
       let type = habit.habitType
       return HabitIconProvider.iconName(for: type, variant: .filled)
   }
  
   private func getCurrentTimeFormatted() -> String {
       let formatter = DateFormatter()
       formatter.dateFormat = "HH:mm"
       return formatter.string(from: Date())
   }
  
   @ViewBuilder
   private var verificationContentView: some View {
       switch habit.habitType {
       case "gym":
           CompactImageVerificationView(
               placeholderText: "Take a photo of your gym session",
               habitType: "gym",
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       case "alarm":
           CompactAlarmVerificationView(
               habit: habit,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               isVerifying: isVerifying,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage
           )
       case "yoga":
           CompactImageVerificationView(
               placeholderText: "Take a photo of your yoga practice",
               habitType: "yoga",
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       case "outdoors":
           CompactImageVerificationView(
               placeholderText: "Take a photo of your outdoor activity",
               habitType: "outdoors",
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       case "cycling":
           CompactImageVerificationView(
               placeholderText: "Take a photo of your cycling activity",
               habitType: "cycling",
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       case "cooking":
           CompactImageVerificationView(
               placeholderText: "Take a photo of your cooking activity",
               habitType: "cooking",
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       case let type where type.contains("study"):
           CompactStudyVerificationView(
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               isStudySessionActive: isStudySessionActive,
               startStudySession: startStudySession,
               completeStudySession: completeStudySession
           )
       case let type where type.hasPrefix("health_"):
           // For health habits, provide dual verification options (with/without photos)
           CompactHealthVerificationView(
               habit: habit,
               placeholderText: "Health goal achieved! Share your progress",
               habitType: type,
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState,
               onBack: { showVerificationView = false },
               onVerify: onVerify,
               habitManager: habitManager
           )
       case let type where type.hasPrefix("custom_"):
           // For custom habits, use image verification with a generic message
           let customTypeIdentifier = String(type.dropFirst(7)) // Remove "custom_" prefix
           let displayName = customTypeIdentifier.replacingOccurrences(of: "_", with: " ").capitalized
           CompactImageVerificationView(
               placeholderText: "Take a photo of your \(displayName) activity",
               habitType: type,
               selfieImageData: $selfieImageData,
               contentImageData: $contentImageData,
               cardWidth: cardWidth,
               cardHeight: cardHeight,
               cameraMode: $cameraMode,
               showingCamera: $showingCamera,
               isVerifying: $isVerifying,
               firstImageTaken: $firstImageTaken,
               verifyWithBothImages: verifyWithBothImages,
               getSuccessMessage: getSuccessMessage,
               resetVerificationState: resetVerificationState
           )
       default:
           Text("Unsupported habit type")
               .jtStyle(.body)
               .foregroundColor(.white)
       }
   }
  
   // MARK: - Compact Verification Views
  
   // MARK: - Verification Setup and Logic
  
   private func setupVerificationView() async {
       if habit.habitType == "screenTime" {
           //
       } else if habit.habitType == "alarm" {
           loadCheckInState()
           updateTimeWindowStatus()
       }
   }
  
   private func resetVerificationState() {
       selfieImageData = nil
       contentImageData = nil
       isVerifying = false
       studySessionId = nil
       isStudySessionActive = false
       cameraMode = .selfie
       firstImageTaken = false
       firstImageWasSelfie = true
       bothImagesComplete = false
       frontCameraImageData = nil
       rearCameraImageData = nil
      
//       // NEW: Reset post preview states
//       showingPostPreview = false
//       verificationId = nil
//       currentVerificationData = nil // Clear stored verification data
//       postPreviewPresentationId = UUID() // Reset presentation ID
   }
   
   // NEW: Reset only verification states
   private func resetVerificationStateOnly() {
       selfieImageData = nil
       contentImageData = nil
       isVerifying = false
       studySessionId = nil
       isStudySessionActive = false
       cameraMode = .selfie
       firstImageTaken = false
       firstImageWasSelfie = true
       bothImagesComplete = false
       frontCameraImageData = nil
       rearCameraImageData = nil
       // Post preview is now handled by HomeView, so no local state to reset
   }
  
   private func verifyWithBothImages(endpoint: String, successMessage: String) async {
       do {
           try await PerformanceMonitor.shared.monitorCriticalSection(PerformanceMonitor.Operation.habitVerification) {
           // Regular verification for non-onboarding mode
           let token = getAuthToken()
           guard !token.isEmpty,
                 let selfieData = selfieImageData,
                 let contentData = contentImageData else {
               showError("please take both photos to verify")
               return
           }
           
           // Load images asynchronously off main thread
           guard let selfieImage = await AsyncImageLoader.loadImage(from: selfieData),
                 let contentImage = await AsyncImageLoader.loadImage(from: contentData) else {
               showError("failed to process images. please try again.")
               return
           }
          
           isVerifying = true
           defer { isVerifying = false }
      
       do {
           let result: (isVerified: Bool, verification: HabitVerification?)
          
           // Use the appropriate public method based on endpoint
           switch endpoint {
           case "gym":
               result = try await verificationManager.verifyGymHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case "alarm":
               result = try await verificationManager.verifyAlarmHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case "yoga":
               result = try await verificationManager.verifyYogaHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case "outdoors":
               result = try await verificationManager.verifyOutdoorsHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case "cycling":
               result = try await verificationManager.verifyCyclingHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case "cooking":
               result = try await verificationManager.verifyCookingHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case let type where type.hasPrefix("custom_"):
               // For custom habits, use the custom endpoint
               result = try await verificationManager.verifyCustomHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           case let type where type.hasPrefix("health_"):
               // For health habits, use the health endpoint with images
               result = try await verificationManager.verifyHealthHabitWithBothImages(
                   habitId: habit.id,
                   selfieImage: selfieImage,
                   contentImage: contentImage,
                   token: token
               )
           default:
               showError("verification type not supported")
               return
           }
          
           if result.isVerified {
               // NEW: Immediately mark habit as verified in cache before showing post preview
               // This ensures the habit card disappears right away
               if let verification = result.verification {
                   habitManager.markHabitAsVerified(habitId: habit.id, verificationData: verification)
               } else {
                   habitManager.markHabitAsVerified(habitId: habit.id)
               }
               
               // NEW: Handle post preview through callback to HomeView
               if let verification = result.verification {
                   print("🎬 [SwipeableHabitCard] Verification successful: \(verification.id)")
                   print("🔍 [SwipeableHabitCard] Verification type: \(verification.verificationType)")
                   print("🔍 [SwipeableHabitCard] Habit type: \(habit.habitType)")
                   
                   // Check if this verification type creates feed posts
                   let postCreatingTypes = ["gym", "alarm", "yoga", "outdoors", "cycling", "cooking"]
                   let isCustomType = verification.verificationType.hasPrefix("custom_")
                   // Only health habits with images (verification type "health") create posts, not health_* types
                   let isHealthWithImages = verification.verificationType == "health"
                   let shouldCreatePost = postCreatingTypes.contains(verification.verificationType) || isCustomType || isHealthWithImages
                   
                   print("🔍 [SwipeableHabitCard] Should create post: \(shouldCreatePost)")
                   
                   if shouldCreatePost {
                       // Call the callback to trigger post preview in HomeView
                       onPreviewRequested(verification)
                   } else {
                       print("🔍 [SwipeableHabitCard] Skipping post preview - verification type doesn't create posts")
                       // Navigate to feed directly since no post preview needed
                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                           print("🔍 [SwipeableHabitCard] Checking for rating prompt before navigating to feed")
                           
                           // Record verification and check if we should show rating
                           AppRatingManager.shared.recordVerification()
                           AppRatingManager.shared.requestRatingIfAppropriate {
                               // Navigate to feed after rating popup (or immediately if not shown)
                               print("🔍 [SwipeableHabitCard] Navigating to feed after rating check")
                               NotificationCenter.default.post(name: .navigateToFeed, object: nil)
                           }
                       }
                   }
                   
                   // 🎉 Play special verification success haptic feedback
                   HapticFeedbackManager.shared.playVerificationSuccess()
                   
                   // Images are now automatically saved to disk by the verification process
                   // The HabitManager will load them from disk on demand to save memory
                  
                   // Clear the image cache to force reload with new images
                   imageCacheManager.clearCache(for: habit.id)
                   imageCacheManager.clearCache(for: "\(habit.id)_selfie")
                   cachedImage = nil
                   cachedSelfieImage = nil
                   cachedContentImage = nil
                   
                   // Clear alarm check-in state if this is an alarm habit
                   if habit.habitType == "alarm" {
                       clearCheckInState()
                   }
                   
                   // Dismiss verification view immediately since habit is verified
                   withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                       showVerificationView = false
                       resetVerificationStateOnly()
                   }
                   
                   // Trigger the completion callback immediately
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                       onVerify()
                   }
               }
           } else {
               // Use the specific error message from the backend, or fallback to generic message
               let errorMessage = result.verification?.status == "failed" ?
                   "verification failed. ensure your face is visible in the selfie and the activity is clear in both photos." :
                   "verification unsuccessful. check that your face and activity are clearly visible."
               showError(errorMessage)
           }
       } catch {
           showError(error.localizedDescription)
       }
       }
       } catch {
           showError("monitoring error. please try again.")
       }
   }
  
   private func startStudySession() async {
      
       do {
           studySessionId = try await verificationManager.startStudySession(habitId: habit.id, token: getAuthToken())
           isStudySessionActive = true
       } catch {
           showError(error.localizedDescription)
       }
   }
  
   private func completeStudySession() async {
       guard let sessionId = studySessionId else {
           showError("no active study session")
           return
       }
      
       do {
           try await verificationManager.completeStudySession(habitId: habit.id, sessionId: sessionId, token: getAuthToken())
           // Immediately mark the habit as verified for study sessions as well
           habitManager.markHabitAsVerified(habitId: habit.id)
           
           // 🎉 Play special verification success haptic feedback
           HapticFeedbackManager.shared.playVerificationSuccess()
           
           // Images are now automatically saved to disk by the verification process
           // The HabitManager will load them from disk on demand to save memory
          
           // Clear the image cache to force reload with new images
           imageCacheManager.clearCache(for: habit.id)
           imageCacheManager.clearCache(for: "\(habit.id)_selfie")
           cachedImage = nil
           cachedSelfieImage = nil
           cachedContentImage = nil
          
           // Dismiss verification view first, then trigger callback
           withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
               showVerificationView = false
               resetVerificationState()
           }
          
           // Trigger the completion callback and navigate to feed
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
               onVerify()
           }
           
           // Navigate to feed after study session completion
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
               // Record verification and check if we should show rating
               AppRatingManager.shared.recordVerification()
               AppRatingManager.shared.requestRatingIfAppropriate {
                   // Navigate to feed after rating popup (or immediately if not shown)
                   NotificationCenter.default.post(name: .navigateToFeed, object: nil)
               }
           }
       } catch {
           showError(error.localizedDescription)
       }
   }
  
   // MARK: - Alarm Logic
  
   private func checkInForAlarm() {
       let checkInTime = Date()
       alarmCheckInTime = checkInTime
       UserDefaults.standard.set(checkInTime.timeIntervalSince1970, forKey: checkInStorageKey)
       updateTimeWindowStatus()
   }
  
   private func loadCheckInState() {
       if let checkInTimeInterval = UserDefaults.standard.object(forKey: checkInStorageKey) as? TimeInterval {
           let checkInTime = Date(timeIntervalSince1970: checkInTimeInterval)
           if Date().timeIntervalSince(checkInTime) < 24 * 60 * 60 {
               alarmCheckInTime = checkInTime
           } else {
               clearCheckInState()
           }
       }
   }
  
   private func clearCheckInState() {
       UserDefaults.standard.removeObject(forKey: checkInStorageKey)
       alarmCheckInTime = nil
   }
  
   private func updateTimeWindowStatus() {
       guard let alarmTime = habit.alarmTime else {
           isWithinCheckInWindow = false
           isWithinVerificationWindow = false
           return
       }
      
       let windows = getTimeWindows(for: alarmTime)
       let now = Date()
      
       isWithinCheckInWindow = now >= windows.checkInStart && now <= windows.checkInEnd
      
       if let checkInTime = alarmCheckInTime {
           let verificationEnd = checkInTime.addingTimeInterval(30 * 60)
           isWithinVerificationWindow = now <= verificationEnd
       } else {
           isWithinVerificationWindow = false
       }
   }
  
   private func getTimeWindows(for alarmTimeString: String) -> (checkInStart: Date, checkInEnd: Date) {
       let formatter = DateFormatter()
       formatter.dateFormat = "HH:mm"
      
       guard let alarmTime = formatter.date(from: alarmTimeString) else {
           let now = Date()
           return (checkInStart: now.addingTimeInterval(-15 * 60), checkInEnd: now.addingTimeInterval(15 * 60))
       }
      
       let calendar = Calendar.current
       let today = Date()
       let alarmComponents = calendar.dateComponents([.hour, .minute], from: alarmTime)
      
       guard let todayAlarmTime = calendar.date(bySettingHour: alarmComponents.hour ?? 0,
                                                minute: alarmComponents.minute ?? 0,
                                                second: 0,
                                                of: today) else {
           let now = Date()
           return (checkInStart: now.addingTimeInterval(-15 * 60), checkInEnd: now.addingTimeInterval(15 * 60))
       }
      
       return (
           checkInStart: todayAlarmTime.addingTimeInterval(-15 * 60), // 15 minutes before alarm
           checkInEnd: todayAlarmTime.addingTimeInterval(15 * 60)     // 15 minutes after alarm
       )
   }
   // MARK: - Screen Time Logic

  
   // MARK: - Helper Methods
  
   private var checkInStorageKey: String {
       "alarm_checkin_\(habit.id)_\(Date().formatted(.dateTime.year().month().day()))"
   }
  
   private func getAuthToken() -> String {
       return AuthenticationManager.shared.storedAuthToken ?? ""
   }
  
   private func showError(_ message: String) {
       // Convert generic error messages to user-friendly ones
       let userFriendlyMessage: String
      
       if message.contains("VerificationError") || message.contains("error 0") {
           userFriendlyMessage = "couldn't detect your face clearly. make sure your face is visible and well-lit"
       } else if message.contains("Network connection error") || message.contains("network") || message.contains("URLError") {
           userFriendlyMessage = "network connection issue. check your internet and try again"
       } else if message.contains("Authentication") || message.contains("401") || message.contains("log in") {
           userFriendlyMessage = "authentication expired. please log out and log back in"
       } else if message.contains("Too many") || message.contains("rate limit") || message.contains("429") {
           userFriendlyMessage = "too many attempts. wait a moment before trying again"
       } else if message.contains("server") || message.contains("Server") || message.contains("500") {
           userFriendlyMessage = "server temporarily unavailable. try again in a few minutes"
       } else if message.contains("Premium") || message.contains("premium") {
           userFriendlyMessage = "premium subscription required for this feature"
       } else if message.isEmpty {
           userFriendlyMessage = "unexpected error occurred. please try again"
       } else {
           // Pass through backend messages directly (they should already be clean)
           userFriendlyMessage = message.lowercased()
       }
      
       errorAlertMessage = userFriendlyMessage
       withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
           showInCardError = true
       }
   }
  
   private func formattedAlarmTime(_ timeString: String) -> String {
       let formatter = DateFormatter()
       formatter.dateFormat = "HH:mm"
      
       if let date = formatter.date(from: timeString) {
           formatter.dateFormat = "h:mm a"
           return formatter.string(from: date)
       }
       return timeString
   }
  
   private func formattedTime(_ date: Date) -> String {
       let formatter = DateFormatter()
       formatter.dateFormat = "h:mm a"
       return formatter.string(from: date)
   }
  
   private func getSuccessMessage(for habitType: String) -> String {
       switch habitType {
       case "gym":
           return "💪 Great workout!"
       case "yoga":
           return "🧘‍♀️ Namaste!"
       case "outdoors":
           return "🌲 Fresh air achieved!"
       case "cycling":
           return "🚴‍♀️ Nice ride!"
       case "cooking":
           return "👨‍🍳 Delicious!"
       case "alarm":
           return "🌅 Good morning!"
       case let type where type.hasPrefix("custom_"):
           return "✨ Well done!"
       case let type where type.hasPrefix("health_"):
           // Health-specific success messages
           if type.contains("steps") {
               return "👟 Steps completed!"
           } else if type.contains("exercise") {
               return "💪 Exercise completed!"
           } else if type.contains("sleep") {
               return "😴 Sleep goal achieved!"
           } else if type.contains("calories") {
               return "🔥 Calories burned!"
           } else if type.contains("cycling") {
               return "🚴‍♀️ Cycling completed!"
           } else if type.contains("distance") {
               return "🏃‍♀️ Distance covered!"
           } else if type.contains("flights") {
               return "🏔️ Flights climbed!"
           } else if type.contains("mindful") {
               return "🧘‍♀️ Mindfulness completed!"
           } else {
               return "🍏 Health goal achieved!"
           }
       default:
           return "🎉 Habit completed!"
       }
   }
  
  
   // MARK: - Helper Methods
  
   private var helpBubbleView: some View {
       VStack(alignment: .leading, spacing: cardHeight * 0.01) {
           Text(getHelpText())
               .font(.custom("EBGaramond-Regular", size: cardWidth * 0.032))
               .foregroundColor(.white)
               .multilineTextAlignment(.leading)
               .lineLimit(nil)
               .fixedSize(horizontal: false, vertical: true)
       }
       .padding(.horizontal, cardWidth * 0.04)
       .padding(.vertical, cardHeight * 0.02)
       .background(
           RoundedRectangle(cornerRadius: cardWidth * 0.025)
               .fill(Color.black.opacity(0.9))
               .overlay(
                   RoundedRectangle(cornerRadius: cardWidth * 0.025)
                       .stroke(Color.white.opacity(0.2), lineWidth: 1)
               )
       )
       .frame(maxWidth: cardWidth * 0.85)
       .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
   }

   private func getHelpText() -> String {
       switch habit.habitType {
       case "gym":
           return """
           📱 Take two photos:
           • A selfie of yourself at the gym
           • A photo of your workout equipment or gym are
           Make sure both you and the gym environment are clearly visible.
           """
       case "alarm":
           return """
           ⏰ Alarm verification process:
           • Check in during your alarm window (1 hour before to 15 minutes after)
           • Take a selfie and a photo of your bathroom/morning routine
           • Complete verification within 30 minutes of check-in
           """
       case "studying", "study":
           return """
           📚 Study session verification:
           • Tap 'Start Study Session' to begin tracking
           • Study for your intended duration
           • Tap 'Complete Session' when finished

           The app will track your study time automatically.
           """
       case "screenTime":
           return """
           📱 Screen time monitoring:
           • Grant Screen Time access when prompted
           • Set daily usage limits for selected apps
           • The app will automatically track your compliance

           No photos needed - just stay within your limits!
           """
       case "yoga":
           return """
           🧘‍♀️ Take two photos:
           • A selfie of yourself in a yoga pose
           • A photo of your yoga mat/practice space

           Show your yoga practice clearly in both photos.
           """
       case "outdoors":
           return """
           🌲 Take two photos:
           • A selfie of yourself outdoors
           • A photo of the outdoor environment/activity

           Make sure you're clearly outside and the activity is visible.
           """
       case "cycling":
           return """
           🚴‍♀️ Take two photos:
           • A selfie of yourself with your bike or while cycling
           • A photo of your bike, route, or cycling environment

           Show your cycling activity clearly in both photos.
           """
       case "cooking":
           return """
           👨‍🍳 Take two photos:
           • A selfie of yourself while cooking
           • A photo of what you're preparing or your cooking setup

           Show yourself actively cooking and your meal preparation.
           """
       case let type where type.hasPrefix("custom_"):
           // For custom habits, try to get the description from the habit
           if let description = getCustomHabitDescription() {
               return """
               ⭐ Custom Habit:
               \(description)

               Take two photos:
               • A selfie of yourself doing the activity
               • A photo showing the activity or environment
               """
           } else {
               return """
               ⭐ Custom Habit Verification:
               • Take a selfie of yourself doing the activity
               • Take a photo showing the activity or environment

               Make sure both photos clearly show you completing your custom habit.
               """
           }
       default:
           return """
           📸 General verification:
           • Take a selfie of yourself doing the activity
           • Take a photo showing the activity or environment

           Make sure both photos clearly demonstrate habit completion.
           """
       }
   }

   private func getCustomHabitDescription() -> String? {
       // Check if habit has a customHabitTypeId (newer approach)
       if let customHabitTypeId = habit.customHabitTypeId {
           return CustomHabitManager.shared.customHabitTypes.first { $0.id == customHabitTypeId }?.description
       }

       // Fall back to extracting from habit type string (older approach)
       if let typeIdentifier = habit.customTypeIdentifier {
           return CustomHabitManager.shared.getCustomHabitType(by: typeIdentifier)?.description
       }

       return nil
   }


   // ===============================================
   //  MARK: - Helper Methods
   // ===============================================

   // OLD: Post Preview Completion Handlers - REMOVED
   // These are no longer needed since post preview is now handled by HomeView
}








#Preview {
   SwipeableHabitCard(
       habit: Habit(
           id: "1",
           name: "Morning Workout",
           recipientId: nil,
           weekdays: [1, 2, 3, 4, 5],
           penaltyAmount: 5.0,
           userId: "user1",
           createdAt: "",
           updatedAt: "",
           habitType: "gym",
           currentWeekCommitCount: nil
       ),
       habitManager: HabitManager.shared,
       onVerify: {},
       onSwipeLeft: {},
       onSwipeRight: {},
       isCurrentCard: true,
       cardWidth: 300,
       cardHeight: 480,
       cardIndex: 0,
       currentIndex: 0,
       parentDragOffset: 0,
       onDragChanged: nil,
       onPreviewRequested: { _ in }
   )
   .background(Color.black)
}


