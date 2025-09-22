import SwiftUI

struct CreateCustomHabitTypeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var customHabitManager: CustomHabitManager
    @FocusState private var focusedField: Field?
    
    @State private var typeIdentifier = ""
    @State private var description = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isCreating = false
    @State private var dragOffset: CGFloat = 0
    
    enum Field {
        case typeIdentifier
        case description
    }
    
    private func endEditing() {
        focusedField = nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background overlay that appears during swipe to simulate previous view
                if dragOffset > 0 {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .offset(x: -200 + (dragOffset * 2))
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
                }
                
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
                
                VStack {
                    if customHabitManager.isLoading {
                        loadingView
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                headerView
                                typeIdentifierInputView
                                descriptionInputView
                                createButton
                            }
                            .padding(20)
                            .padding(.horizontal, 16)
                            .onTapGesture { endEditing() }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("cancel")
                            .jtStyle(.body)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("create custom habit")
                        .jtStyle(.title3)
                        .foregroundColor(.white)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .offset(x: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Even more responsive - larger detection area and less resistance
                        if value.startLocation.x < 80 && abs(value.translation.height) < 120 {
                            // More direct translation with minimal resistance
                            let progress = min(value.translation.width / 100, 1.0)
                            dragOffset = value.translation.width * 0.8 * progress
                        }
                    }
                    .onEnded { value in
                        // Lower threshold for even quicker response
                        if value.startLocation.x < 80 && value.translation.width > 40 && abs(value.translation.height) < 120 {
                            dismiss()
                        } else {
                            // Very quick spring back
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Creating custom habit type...")
                .foregroundColor(.white)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Text("create custom habit type")
                .font(.custom("EBGaramond-Regular", size: 22))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Define a new habit type that you can use when creating habits. Be specific about what this habit involves.")
                .jtStyle(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    private var typeIdentifierInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("habit type name")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.6))
            
            TextField("", text: $typeIdentifier, prompt: Text("e.g., reading, meditation, cooking").foregroundColor(.white.opacity(0.3)))
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .foregroundColor(.white)
                .focused($focusedField, equals: .typeIdentifier)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            Text("use lowercase letters, numbers, and underscores only. this will be used internally.")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var descriptionInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("description")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.6))
            
            TextField("", text: $description, prompt: Text("describe what this habit involves and how it should be verified").foregroundColor(.white.opacity(0.3)), axis: .vertical)
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .foregroundColor(.white)
                .focused($focusedField, equals: .description)
            
            Text("be detailed and specific. this helps the system understand how to verify your habit.")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var createButton: some View {
        Button(action: {
            Task {
                await createCustomHabitType()
            }
        }) {
            Text("CREATE HABIT TYPE")
                .jtStyle(.body)
                .foregroundColor(isFormValid ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isFormValid ? Color.white : Color.white.opacity(0.3))
                .cornerRadius(16)
        }
        .disabled(customHabitManager.isLoading || !isFormValid)
        .padding(.top, 8)
    }
    
    private var isFormValid: Bool {
        !typeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func createCustomHabitType() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else {
            errorMessage = "Authentication error. Please try again."
            showError = true
            return
        }
        
        let cleanedTypeIdentifier = typeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            _ = try await customHabitManager.createCustomHabitType(
                typeIdentifier: cleanedTypeIdentifier,
                description: cleanedDescription,
                token: token
            )
            
            // Refresh available types after successful creation
            await customHabitManager.refreshAfterCreation(token: token)
            
            dismiss()
        } catch let error as CustomHabitError {
            switch error {
            case .validationError(let message):
                errorMessage = message
            case .serverError(let message):
                errorMessage = message
            case .premiumRequired(_):
                errorMessage = "Cannot create more than 1 custom habit as a non-premium user. Please upgrade to premium to create unlimited custom habits."
            case .networkError:
                errorMessage = "Network error. Please check your connection and try again."
            }
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    CreateCustomHabitTypeView()
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(CustomHabitManager.shared)
} 
