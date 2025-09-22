import SwiftUI
import Charts

// MARK: – HabitViewRoot ==========================================================
/// A dashboard where each habit has a **weekly quota** and a **cost‑per‑miss**.
/// If the user falls short of quota by week‑end, the app charges:
///   `charge = (quota – completions) × costPerMiss`.
/// This UI surfaces the live remaining count and the potential charge so
/// users stay motivated (or forewarned!).
struct HabitView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var friendsManager: FriendsManager
    @EnvironmentObject var customHabitManager: CustomHabitManager
    @State private var selectedDate = Date()
    @State private var showingAddHabit = false
    @State private var selectedWeekday = Calendar.current.component(.weekday, from: Date()) - 1 // 0-6, default to current day
    @State private var viewMode: ViewMode = .daily  // Toggle between daily and weekly view
    @State private var hasTypedRecapOnAppear = false
    
    // Add onDismiss closure for sheet/back arrow
    var onDismiss: (() -> Void)? = nil
    
    // Add drag-to-dismiss state
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragging = false
    // Track swipe direction for day animation
    @State private var daySwipeEdge: Edge = .trailing
    
    // Typing animation for recap label
    @State private var recapAnimatedText: String = ""
    @State private var recapTypingTimer: Timer? = nil
    
    /// Width (in points) from the left screen-edge within which a drag should be
    /// recognised as a **back-swipe** that can dismiss this view. Any drags that
    /// start outside this zone will be ignored by the back-swipe logic so that
    /// horizontal interactions elsewhere (e.g. day⇄week swipe) don't cause an
    /// accidental dismissal.
    private let backSwipeEdgeWidth: CGFloat = 60
    
    enum ViewMode: String, CaseIterable {
        case daily = "day"
        case weekly = "week"
        case all = "all"
    }
    
    var body: some View {
        ZStack {
            AppBackground()
                .overlay(content)
                .offset(x: dragOffset)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.95), value: dragOffset)
        }
        // Hot zones for edge-swipe (back) and header-swipe (toggle day↔week)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        // Edge back-swipe gesture; attach simultaneously so it doesn't steal priority from card swipes
        .simultaneousGesture(dragGesture)
        .sheet(isPresented: $showingAddHabit) {
            AddHabitView()
                .environmentObject(habitManager)
                .environmentObject(authManager)
                .environmentObject(friendsManager)
                .environmentObject(customHabitManager)
        }
    }
    
    // MARK: - Main Content
    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            // Custom Navigation Bar
            ZStack {
                // Center the title in the ZStack
                Text("habits")
                    .jtStyle(.title2)
                    .fontWeight(.thin)
                    .foregroundColor(.white)
                // Back arrow in leading HStack
                HStack {
                    if let onDismiss = onDismiss {
                        Button(action: { onDismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                        }
                    } else {
                        Spacer().frame(width: 44)
                    }
                    Spacer()
                }
            }
            .frame(height: 44)
            .padding(.top, 4)
            .padding(.bottom, 16)
            
            // Main content based on view mode
            switch viewMode {
            case .daily:
                DailyHabitsView(
                    selectedWeekday: $selectedWeekday,
                    viewMode: $viewMode,
                    recapAnimatedText: $recapAnimatedText,
                    hasTypedRecapOnAppear: $hasTypedRecapOnAppear,
                    daySwipeEdge: $daySwipeEdge,
                    backSwipeEdgeWidth: backSwipeEdgeWidth,
                    onTypingRecap: startTypingRecap
                )
                .environmentObject(habitManager)
                .environmentObject(authManager)
                .environmentObject(friendsManager)
                .environmentObject(customHabitManager)
            case .weekly:
                WeeklyHabitsView(
                    selectedWeekday: $selectedWeekday,
                    viewMode: $viewMode
                )
                .environmentObject(habitManager)
                .environmentObject(authManager)
                .environmentObject(friendsManager)
                .environmentObject(customHabitManager)
            case .all:
                AllHabitsView(
                    viewMode: $viewMode,
                    recapAnimatedText: $recapAnimatedText,
                    hasTypedRecapOnAppear: $hasTypedRecapOnAppear,
                    onTypingRecap: startTypingRecap
                )
                .environmentObject(habitManager)
                .environmentObject(authManager)
                .environmentObject(friendsManager)
                .environmentObject(customHabitManager)
            }
        }
    }
    
    // MARK: - Drag Gesture
    private var dragGesture: some Gesture {
        // Only enable drag-to-dismiss if onDismiss is provided
        DragGesture()
            .onChanged { value in
                guard onDismiss != nil else { return }
                if value.startLocation.x < backSwipeEdgeWidth && abs(value.translation.height) < 120 {
                    if !isHorizontalDragging { isHorizontalDragging = true }
                    let progress = min(value.translation.width / 100, 1.0)
                    dragOffset = value.translation.width * 0.8 * progress
                }
            }
            .onEnded { value in
                guard let onDismiss = onDismiss else { dragOffset = 0; isHorizontalDragging = false; return }
                if value.startLocation.x < backSwipeEdgeWidth && value.translation.width > 40 && abs(value.translation.height) < 120 {
                    // Trigger dismissal without forcibly resetting the offset first – this avoids
                    // a competing animation that caused a visible "snap-back" before the slide-out.
                    onDismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) { dragOffset = 0 }
                }
                isHorizontalDragging = false
            }
    }
    
    // MARK: - Helper Methods
    
    // Set recap text immediately
    private func startTypingRecap() {
        recapTypingTimer?.invalidate()
        let selectedDayLabel = HabitViewHelpers.getSelectedDayLabel(for: selectedWeekday)
        recapAnimatedText = "\(selectedDayLabel)."
    }
}

// MARK: – Previews ----------------------------------------------------------
#Preview("HabitView") { 
    HabitView()
        .environmentObject(AuthenticationManager.shared)
} 