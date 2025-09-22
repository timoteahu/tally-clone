import SwiftUI

struct SupportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @FocusState private var isMessageFocused: Bool
    
    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 0) {
                backButton
                headerSection
                messageSection
                Spacer()
                sendButton
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            keyboardToolbar
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your message has been sent. We'll get back to you soon!")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - View Components
    
    private var backButton: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.custom("EBGaramond-Regular", size: 16)).fontWeight(.semibold)
                    Text("Back")
                        .jtStyle(.body)
                }
                .foregroundColor(.white)
                .padding(.leading, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10) // Reduced padding to bring back button closer to top
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("contact us")
                .jtStyle(.title)
            
            Text("share feedback, report issues, or suggest improvements")
                .jtStyle(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10) // Reduced from 20 since we have back button now
        .padding(.bottom, 30)
    }
    
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("your message")
                .jtStyle(.bodyBold)
                .foregroundColor(.white)
            
            messageTextEditor
        }
        .padding(.horizontal, 20)
    }
    
    private var messageTextEditor: some View {
        ZStack(alignment: .topLeading) {
            if message.isEmpty {
                Text("tell us what's on your mind - bug reports, feature ideas, or just say hi!")
                    .font(.ebGaramondBody)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: $message)
                .focused($isMessageFocused)
                .font(.ebGaramondBody)
                .padding(12)
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
                .background(Color.clear)
        }
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(minHeight: 150)
    }
    
    private var sendButton: some View {
        Button(action: sendMessage) {
            sendButtonContent
        }
        .disabled(isButtonDisabled)
        .opacity(isButtonDisabled ? 0.5 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
    
    private var sendButtonContent: some View {
        HStack {
            if isSubmitting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    .scaleEffect(0.8)
            } else {
                Text("send message")
                    .jtStyle(.bodyBold)
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Color.white)
        .cornerRadius(28)
    }
    
    private var isButtonDisabled: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting
    }
    
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .keyboard) {
            HStack {
                Spacer()
                Button("done") {
                    isMessageFocused = false
                }
                .foregroundColor(.white)
            }
        }
    }
    
    private func sendMessage() {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSubmitting = true
        isMessageFocused = false
        
        Task {
            do {
                guard let token = authManager.storedAuthToken else {
                    throw NetworkError.unauthorized
                }
                
                let url = URL(string: "\(AppConfig.baseURL)/support/messages")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["message": message]
                request.httpBody = try JSONEncoder().encode(body)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                guard httpResponse.statusCode == 200 else {
                    throw NetworkError.serverError(httpResponse.statusCode)
                }
                
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to send message. Please try again."
                }
            }
        }
    }
}