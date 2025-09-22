import SwiftUI
import UIKit

struct LoginFlowView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    // Bind to parent to allow switching to signup if desired in future
    @Binding var isNewUser: Bool
    @Binding var phoneNumber: String

    @State private var verificationCode = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            Spacer().frame(height: 250)

            VStack(spacing: 18) {
                if !codeSent {
                    HStack(spacing: 2) {
                        CustomTextField(placeholder: "please enter your phone number", text: $phoneNumber, keyboardType: .phonePad)
                            .onChange(of: phoneNumber) { oldValue, newValue in
                                // Reset error state when user starts typing a new number
                                if showError {
                                    showError = false
                                    errorMessage = nil
                                }
                            }
                        if !phoneNumber.isEmpty {
                            Button(action: { Task { await primaryAction() } }) {
                                Image(systemName: "arrow.right")
                                    .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.trailing, 80)
                                    .padding(.vertical, 8)
                            }
                            .transition(.move(edge: .trailing))
                            .disabled(disablePrimaryButton)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: phoneNumber.isEmpty)
                } else {
                    VStack(spacing: 18) {
                        HStack(spacing: 2) {
                            OTPCodeField(code: $verificationCode)
                            if !verificationCode.isEmpty {
                                Button(action: { Task { await primaryAction() } }) {
                                    Image(systemName: "arrow.right")
                                        .font(.custom("EBGaramond-Regular", size: 20)).fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.trailing, 80)
                                        .padding(.vertical, 8)
                                }
                                .transition(.move(edge: .trailing))
                                .disabled(disablePrimaryButton)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: verificationCode.isEmpty)
                        
                        // Back to phone number option
                        Button(action: { resetToPhoneNumber() }) {
                            Image(systemName: "arrow.left")
                                .font(.custom("EBGaramond-Regular", size: 20))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.top, 24)
                    }
                }
            }

            Spacer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? authManager.errorMessage ?? "An error occurred")
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .onAppear {
            // Reset to clean state whenever this view appears
            // This is especially important when returning from signup flow
            resetToCleanState()
        }
    }

    // MARK: - State Management Helpers
    
    private func resetToCleanState() {
        isNewUser = false
        codeSent = false
        verificationCode = ""
        showError = false
        errorMessage = nil
    }
    
    private var disablePrimaryButton: Bool {
        if isLoading { return true }
        if codeSent { return verificationCode.count < 6 }
        return phoneNumber.isEmpty
    }

    private func primaryAction() async {
        if codeSent {
            await verify()
        } else {
            await sendCode()
        }
    }

    private func sendCode() async {
        isLoading = true
        defer { isLoading = false }
        
        // Completely reset all state at start of each phone number attempt
        await MainActor.run {
            resetToCleanState()
        }
        
        do {
            // First, query backend to see if this phone number already has an account
            let exists = try await authManager.checkUserExists(phoneNumber: phoneNumber)

            if exists {
                // Existing user – proceed to send verification code for login
                try await authManager.requestVerificationCode(phoneNumber: phoneNumber)
                await MainActor.run {
                    codeSent = true
                }
            } else {
                // No account exists, but let's try to send verification code for signup
                // Only redirect to signup if the code sending also succeeds
                try await authManager.requestVerificationCode(phoneNumber: phoneNumber)
                
                // Add small delay to ensure state is properly reset first
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    self.isNewUser = true
                }
            }
        } catch {
            await MainActor.run {
                // Ensure we stay in login flow on error so user can retry
                resetToCleanState()
                showError = true
                errorMessage = "there was an error in authenticating your phone number"
            }
        }
    }

    private func verify() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.login(phoneNumber: phoneNumber, verificationCode: verificationCode)
        } catch {
            await MainActor.run {
                verificationCode = "" // Clear code on error so user can retry
                showError = true
                errorMessage = "there was an error in authenticating your phone number"
            }
        }
    }

    private func resetToPhoneNumber() {
        resetToCleanState()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
} 