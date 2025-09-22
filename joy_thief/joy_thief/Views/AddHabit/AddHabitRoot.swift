////
//  AddHabitRoot.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Root container for the Add Habit flow extracted from AddHabitView.
//

import SwiftUI

// MARK: - Add Habit Wizard Root

struct AddHabitRoot: View {
    @StateObject private var vm = AddHabitViewModel()
    // Environment objects that the original AddHabitView relied on. We inject them here so
    // that all sub-steps can still access the same managers.
    @EnvironmentObject var customHabitManager: CustomHabitManager
    @EnvironmentObject var friendsManager: FriendsManager

    // Onboarding support
    let isOnboarding: Bool
    let onOnboardingComplete: (() -> Void)?
    let onStepChanged: ((Int) -> Void)?
    
    // Wizard step index
    @State private var currentStep: Int = 0 // 0 = type selection, 1 = details, 2 = schedule/penalty
    
    init(isOnboarding: Bool = false, onOnboardingComplete: (() -> Void)? = nil, onStepChanged: ((Int) -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onOnboardingComplete = onOnboardingComplete
        self.onStepChanged = onStepChanged
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "161C29"), location: 0.0),
                    .init(color: Color(hex: "131824"), location: 0.15),
                    .init(color: Color(hex: "0F141F"), location: 0.3),
                    .init(color: Color(hex: "0C111A"), location: 0.45),
                    .init(color: Color(hex: "0A0F17"), location: 0.6),
                    .init(color: Color(hex: "080D15"), location: 0.7),
                    .init(color: Color(hex: "060B12"), location: 0.8),
                    .init(color: Color(hex: "03070E"), location: 0.9),
                    .init(color: Color(hex: "01050B"), location: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Wizard content
                Group {
                    switch currentStep {
                    case 0:
                        // Step 1 – Habit type selection
                        HabitTypeSelectionView(
                            selectedHabitType: $vm.selectedHabitType,
                            selectedCustomHabitTypeId: $vm.selectedCustomHabitTypeId,
                            isOnboarding: isOnboarding,
                            embeddedInWizard: true,
                            onDone: { currentStep = 1 }
                        )
                        .environmentObject(customHabitManager)

                    case 1:
                        // Step 2 – details form (name, partner, etc.)
                        DetailsFormStepWrapper(vm: vm, isOnboarding: isOnboarding, proceed: {
                            currentStep = 2
                        }, goBack: {
                            currentStep = max(0, currentStep - 1)
                        })

                    case 2:
                        // Step 3 – schedule & penalty
                        ScheduleAndPenaltyStepWrapper(vm: vm, isOnboarding: isOnboarding, onOnboardingComplete: onOnboardingComplete, goBack: {
                            currentStep = max(0, currentStep - 1)
                        })

                    default:
                        Color.clear // should never hit
                    }
                }
                .background(
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
                ) // solid sheet background
                .cornerRadius(32, corners: [.topLeft, .topRight])
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
        .onChange(of: currentStep) { oldValue, newValue in
            if isOnboarding {
                onStepChanged?(newValue)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddHabitStepBack"))) { _ in
            if currentStep > 0 {
                currentStep = max(0, currentStep - 1)
            } else {
                NotificationCenter.default.post(name: NSNotification.Name("DismissAddHabitOverlay"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddHabitStepForward"))) { _ in
            if isOnboarding && currentStep < 2 {
                currentStep = min(2, currentStep + 1)
            }
        }
        .onAppear {
            // Preload friends with Stripe Connect when opening the add habit page
            Task {
                print("🔄 [AddHabitRoot] Preloading friends with Stripe Connect...")
                await friendsManager.refreshFriendsWithStripeConnect()
                print("✅ [AddHabitRoot] Friends with Stripe Connect preloaded: \(friendsManager.preloadedFriendsWithStripeConnect.count)")
            }
        }
        .onDisappear {
            // Clean up when view disappears
            vm.errorMessage = nil
            vm.showError = false
        }
        .onChange(of: vm.selectedHabitType) { oldValue, newValue in
            // Update type-specific fields when habit type changes
            vm.updateFieldsForHabitType()
        }
    }
}

// MARK: - Thin compatibility wrapper
// Other views in the app still reference `AddHabitView()`. We keep those call-sites working
// by providing a tiny shim that delegates to the new wizard container.

struct AddHabitView: View {
    var body: some View {
        AddHabitRoot()
    }
}

// MARK: - Simple wrapper helpers
// Placeholder wrapper views so we can attach navigation buttons without modifying the generated
// placeholder step files.

private struct DetailsFormStepWrapper: View {
    @ObservedObject var vm: AddHabitViewModel
    let isOnboarding: Bool
    var proceed: () -> Void
    var goBack: () -> Void

    var body: some View {
        AddHabitRoot.HabitDetailsFormStep(vm: vm, isOnboarding: isOnboarding, onNext: proceed, onBack: goBack)
    }
}

private struct ScheduleAndPenaltyStepWrapper: View {
    @ObservedObject var vm: AddHabitViewModel
    let isOnboarding: Bool
    let onOnboardingComplete: (() -> Void)?
    var goBack: () -> Void

    var body: some View {
        AddHabitRoot.ScheduleAndPenaltyStep(vm: vm, isOnboarding: isOnboarding, onOnboardingComplete: onOnboardingComplete, onBack: goBack)
    }
} 