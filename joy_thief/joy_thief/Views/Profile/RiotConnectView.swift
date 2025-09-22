import SwiftUI

struct RiotConnectView: View {
    @Environment(\.dismiss) var dismiss
    @State private var riotId: String = ""
    @State private var tagline: String = ""
    // Game selection removed - accounts work for both games
    @State private var selectedRegion: String = "americas"
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var connectedAccounts: [RiotAccount] = []
    @State private var isLoadingAccounts = false
    @State private var deletingAccountId: UUID? = nil
    
    let preloadedAccounts: [RiotAccount]?
    
    init(preloadedAccounts: [RiotAccount]? = nil) {
        self.preloadedAccounts = preloadedAccounts
    }
    
    // Games are automatically detected based on match history
    
    let regions = [
        ("americas", "Americas"),
        ("europe", "Europe"),
        ("asia", "Asia"),
        ("sea", "Southeast Asia")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoadingAccounts {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !connectedAccounts.isEmpty {
                                connectedAccountsSection
                            }
                            
                            // Only show add account section if no accounts are connected
                            if connectedAccounts.isEmpty {
                                addAccountSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Riot Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let preloaded = preloadedAccounts, !preloaded.isEmpty {
                connectedAccounts = preloaded
                isLoadingAccounts = false
            } else {
                isLoadingAccounts = true
                loadConnectedAccounts()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTED ACCOUNT")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            if let account = connectedAccounts.first {
                connectedAccountRow(account)
            }
            
            Text("Your Riot account is connected and ready to track gaming habits.")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(.bottom, 10)
    }
    
    private func connectedAccountRow(_ account: RiotAccount) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(account.riotId)#\(account.tagline)")
                    .font(.ebGaramondBody)
                    .foregroundColor(.white)
                Text(gameNameDisplay(account.gameName))
                    .jtStyle(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            Button(action: { disconnectAccount(account) }) {
                if deletingAccountId == account.id {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.system(size: 20))
                }
            }
            .disabled(deletingAccountId != nil)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var addAccountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNECT YOUR RIOT ACCOUNT")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text("Connect your Riot account to track League of Legends and Valorant gaming time.")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 8)
            
            regionSelectionView
            riotIdInputView
            helpTextView
            connectButtonView
        }
    }
    
    // Game selection removed - accounts work for both games
    
    private func gameNameDisplay(_ gameName: String) -> String {
        switch gameName {
        case "lol":
            return "League of Legends"
        case "valorant":
            return "Valorant"
        case "both":
            return "League of Legends & Valorant"
        default:
            return gameName
        }
    }
    
    private var regionSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Region")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(regions, id: \.0) { region in
                        regionButton(region: region)
                    }
                }
            }
        }
    }
    
    private func regionButton(region: (String, String)) -> some View {
        Button(action: { selectedRegion = region.0 }) {
            Text(region.1)
                .jtStyle(.body)
                .foregroundColor(selectedRegion == region.0 ? .black : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedRegion == region.0 ? Color.white : Color.white.opacity(0.1))
                .cornerRadius(20)
        }
    }
    
    private var riotIdInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Riot ID")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            HStack(spacing: 8) {
                usernameTextField
                
                Text("#")
                    .jtStyle(.body)
                    .foregroundColor(.white.opacity(0.4))
                
                taglineTextField
            }
        }
    }
    
    private var usernameTextField: some View {
        TextField("Username", text: $riotId)
            .textFieldStyle(PlainTextFieldStyle())
            .font(.ebGaramondBody)
            .foregroundColor(.white)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var taglineTextField: some View {
        TextField("TAG", text: $tagline)
            .textFieldStyle(PlainTextFieldStyle())
            .font(.ebGaramondBody)
            .foregroundColor(.white)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(width: 80)
    }
    
    private var helpTextView: some View {
        Text("Enter your Riot ID exactly as it appears in game (e.g., Username#TAG)")
            .jtStyle(.caption)
            .foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.leading)
    }
    
    private var connectButtonView: some View {
        Button(action: connectAccount) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                } else {
                    Text("Connect Account")
                        .jtStyle(.body)
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .cornerRadius(12)
        }
        .disabled(riotId.isEmpty || tagline.isEmpty || isLoading)
        .opacity(riotId.isEmpty || tagline.isEmpty || isLoading ? 0.5 : 1)
    }
    
    private func loadConnectedAccounts() {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        Task {
            do {
                guard let url = URL(string: "\(AppConfig.baseURL)/gaming/riot-accounts") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                let decoder = JSONDecoder()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    // Try various date formats that Supabase might use
                    let dateFormatters: [DateFormatter] = [
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"  // Handles 6 decimal places with Z
                            f.locale = Locale(identifier: "en_US_POSIX")
                            f.timeZone = TimeZone(abbreviation: "UTC")
                            return f
                        }(),
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"  // 6 decimal places with literal Z
                            f.locale = Locale(identifier: "en_US_POSIX")
                            f.timeZone = TimeZone(abbreviation: "UTC")
                            return f
                        }(),
                        {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                            f.locale = Locale(identifier: "en_US_POSIX")
                            f.timeZone = TimeZone(abbreviation: "UTC")
                            return f
                        }()
                    ]
                    
                    // Try DateFormatter formats
                    for formatter in dateFormatters {
                        if let date = formatter.date(from: dateString) {
                            return date
                        }
                    }
                    
                    // Try ISO8601DateFormatter
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = isoFormatter.date(from: dateString) {
                        return date
                    }
                    
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string: \(dateString)")
                }
                
                let accounts = try decoder.decode([RiotAccount].self, from: data)
                
                await MainActor.run {
                    self.connectedAccounts = accounts
                    self.isLoadingAccounts = false
                }
            } catch {
                print("Error loading connected accounts: \(error)")
                await MainActor.run {
                    self.isLoadingAccounts = false
                }
            }
        }
    }
    
    private func connectAccount() {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        isLoading = true
        
        Task {
            do {
                guard let url = URL(string: "\(AppConfig.baseURL)/gaming/riot-account") else { return }
                
                let accountData = RiotAccountCreate(
                    riotId: riotId,
                    tagline: tagline,
                    region: selectedRegion,
                    gameName: "both"
                )
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(accountData)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        // Success
                        await MainActor.run {
                            riotId = ""
                            tagline = ""
                            loadConnectedAccounts()
                            isLoading = false
                        }
                    } else {
                        // Error
                        if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                           let detail = errorData["detail"] {
                            await MainActor.run {
                                errorMessage = detail
                                showError = true
                                isLoading = false
                            }
                        } else {
                            await MainActor.run {
                                errorMessage = "Failed to connect account"
                                showError = true
                                isLoading = false
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func disconnectAccount(_ account: RiotAccount) {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        
        deletingAccountId = account.id
        
        Task {
            do {
                guard let url = URL(string: "\(AppConfig.baseURL)/gaming/riot-account/\(account.id.uuidString)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        await MainActor.run {
                            deletingAccountId = nil
                            loadConnectedAccounts()
                        }
                    } else if httpResponse.statusCode == 400 {
                        // Parse error message
                        if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                           let detail = errorData["detail"] {
                            await MainActor.run {
                                deletingAccountId = nil
                                errorMessage = detail
                                showError = true
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    deletingAccountId = nil
                    errorMessage = "Failed to disconnect account"
                    showError = true
                }
            }
        }
    }
}