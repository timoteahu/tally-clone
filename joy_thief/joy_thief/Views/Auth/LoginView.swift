import SwiftUI

/// Entry point for authentication screens. Switches between login & signup flows.
struct LoginView: View {
    @State private var isNewUser = false
    @State private var phoneNumber = ""

    var body: some View {
        ZStack {
            AppBackground()

            if isNewUser {
                OnboardingSignupFlowView(isPresenting: $isNewUser, initialPhoneNumber: phoneNumber)
                    .onChange(of: isNewUser) { oldValue, newValue in
                        if !newValue {
                            // Add small delay to ensure proper state transition
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNewUser = false
                            }
                        }
                    }
            } else {
                LoginFlowView(isNewUser: $isNewUser, phoneNumber: $phoneNumber)
            }
        }
    }
} 