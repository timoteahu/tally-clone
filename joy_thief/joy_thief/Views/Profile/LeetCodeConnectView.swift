import SwiftUI

struct LeetCodeConnectView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var leetCodeManager = LeetCodeManager.shared
    
    @State private var username = ""
    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var isUsernameValid = false
    @State private var showError = false
    @State private var showErrorAlert = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var showDisconnectAlert = false
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("github")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.white.opacity(0.8))
            
            Text("Connect LeetCode")
                .jtStyle(.title)
            
            Text("Enter your LeetCode username to connect your account")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 40)
    }
    
    private var usernameInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LeetCode Username")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            HStack {
                TextField("username", text: $username)
                    .font(.custom("EBGaramond-Regular", size: 17))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: username) { _, newValue in
                        // Cancel previous validation
                        debounceTask?.cancel()
                        
                        // Reset validation when user types
                        validationMessage = ""
                        isUsernameValid = false
                        showError = false
                        
                        // Validate after a short delay
                        if !newValue.isEmpty {
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                if !Task.isCancelled {
                                    await validateUsernameInline()
                                }
                            }
                        }
                    }
                
                if isValidating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showError ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
            )
            
            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .jtStyle(.caption)
                    .foregroundColor(showError ? .red : .green)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
    }
    
    // Removed validate button - validation happens automatically
    
    private var connectButton: some View {
        Button(action: connectAccount) {
            HStack {
                Text("Connect Account")
                    .jtStyle(.body)
                    .foregroundColor(.white)
                
                if leetCodeManager.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isUsernameValid ? Color.green.opacity(0.8) : Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(!isUsernameValid || leetCodeManager.isProcessing)
        .padding(.horizontal)
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions:")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(alignment: .leading, spacing: 8) {
                instructionItem(number: "1", text: "Enter your LeetCode username")
                instructionItem(number: "2", text: "Wait for automatic validation")
                instructionItem(number: "3", text: "If your profile is private, make it public in LeetCode settings")
                instructionItem(number: "4", text: "Click 'Connect Account' when username is validated")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func instructionItem(number: String, text: String) -> some View {
        HStack {
            Image(systemName: "\(number).circle.fill")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text(text)
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private var connectedSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Connected to LeetCode")
                    .jtStyle(.title)
                
                if let username = leetCodeManager.connectedUsername {
                    Text("@\(username)")
                        .jtStyle(.body)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
            
            Button(action: { showDisconnectAlert = true }) {
                Text("Disconnect Account")
                    .jtStyle(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .confirmationDialog("Disconnect LeetCode?", isPresented: $showDisconnectAlert, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await leetCodeManager.disconnectAccount()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to disconnect your LeetCode account?")
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                
                VStack(spacing: 24) {
                    headerSection
                    
                    if leetCodeManager.connectionStatus == .connected {
                        connectedSection
                    } else {
                        usernameInputSection
                        
                        connectButton
                        
                        instructionsSection
                    }
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Connection Error", isPresented: $showErrorAlert) {
            Button("OK") {
                showErrorAlert = false
            }
        } message: {
            Text(leetCodeManager.lastError ?? "An error occurred")
        }
        .onReceive(leetCodeManager.$lastError) { error in
            showErrorAlert = (error != nil)
        }
        .onAppear {
            // Clear any previous errors
            leetCodeManager.lastError = nil
            
            Task {
                await leetCodeManager.checkStatus()
                // Pre-fill username if already connected
                if let connectedUsername = leetCodeManager.connectedUsername {
                    username = connectedUsername
                }
            }
        }
    }
    
    private func validateUsernameInline() async {
        guard !username.isEmpty else { return }
        
        await MainActor.run {
            isValidating = true
            validationMessage = ""
        }
        
        let result = await leetCodeManager.validateUsername(username)
        
        await MainActor.run {
            isValidating = false
            isUsernameValid = result.valid
            validationMessage = result.message
            showError = !result.valid
        }
    }
    
    private func connectAccount() {
        guard isUsernameValid else { return }
        
        Task {
            await leetCodeManager.connectAccount(username: username)
            
            // If successful, dismiss the view
            if leetCodeManager.connectionStatus == .connected {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}