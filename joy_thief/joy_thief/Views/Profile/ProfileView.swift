import SwiftUI
import Charts
import Kingfisher

struct ProfileView: View {
    let showPaymentView: () -> Void // Add closure for showing PaymentView
    let onDismiss: (() -> Void)? // Add closure for dismissing the view
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var habitManager: HabitManager
    @EnvironmentObject var owedAmountManager: OwedAmountManager
    @EnvironmentObject var identitySnapshotManager: IdentitySnapshotManager
    @EnvironmentObject var paymentManager: PaymentManager
    @EnvironmentObject var paymentStatsManager: PaymentStatsManager
    // Avatar-related states removed - now in PersonalUserAccount
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showPremiumView = false
    @State private var snapshotAlertMessage: String = ""
    @State private var showSnapshotAlert = false
    @State private var connectStatus: ConnectStatus = .notConnected
    @State private var githubStatus: ConnectStatus = .notConnected
    @State private var riotStatus: ConnectStatus = .notConnected
    @State private var leetCodeStatus: ConnectStatus = .notConnected
    @State private var showRiotConnectView = false
    @State private var showLeetCodeConnectView = false
    @State private var riotAccounts: [RiotAccount] = []
    
    @State private var identitySnapshotImage: Data?
    @State private var showingIdentitySnapshotCamera = false
    @State private var showingIdentitySnapshotPreview = false
    @State private var capturedIdentityImage: UIImage?
    
    // Helper computed property for payment notification dot
    private var needsPaymentSetup: Bool {
        paymentManager.paymentMethod == nil || connectStatus != .connected
    }
    
    // Computed properties for statistics
    private var weeklyCompletedGoals: Int {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        // Get the start of the current week (Sunday)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return 0
        }
        
        // Count completed goals for each day of the week
        var totalCompleted = 0
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                continue
            }
            
            let dateString = formatter.string(from: date)
            let verifiedHabitsForDate = habitManager.weeklyVerifiedHabits[dateString] ?? [:]
            
            // Count how many habits were completed on this date
            totalCompleted += verifiedHabitsForDate.values.filter { $0 }.count
        }
        
        return totalCompleted
    }
    
    private var weeklyPayments: Double {
        return paymentStatsManager.weeklyPayments
    }
    
    private var monthlyCompletedGoals: Int {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        // Get the start of the current month
        guard let monthInterval = calendar.dateInterval(of: .month, for: today) else {
            return 0
        }
        
        // Count completed goals for each day of the month
        var totalCompleted = 0
        var currentDate = monthInterval.start
        
        while currentDate <= today {
            let dateString = formatter.string(from: currentDate)
            let verifiedHabitsForDate = habitManager.weeklyVerifiedHabits[dateString] ?? [:]
            
            // Count how many habits were completed on this date
            totalCompleted += verifiedHabitsForDate.values.filter { $0 }.count
            
            // Move to next day
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }
        
        return totalCompleted
    }
    
    private var monthlyPayments: Double {
        return paymentStatsManager.monthlyPayments
    }
    
    private var weeklyGoalsData: [Double] {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        // Get the start of the current week (Sunday)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return Array(repeating: 0, count: 7)
        }
        
        return (0..<7).map { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                return 0
            }
            
            let dateString = formatter.string(from: date)
            let verifiedHabitsForDate = habitManager.weeklyVerifiedHabits[dateString] ?? [:]
            
            return Double(verifiedHabitsForDate.values.filter { $0 }.count)
        }
    }
    
    private var weeklyPaymentsData: [Double] {
        return paymentStatsManager.dailyPayments
    }
    
    private var weekDays: [String] {
        return paymentStatsManager.weekDays
    }

    var body: some View {
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

            ScrollView {
                VStack(spacing: 20) {
                    backButton
                    // Profile section removed - now in PersonalUserAccount
                    accountSection
                    supportSection
                    ConnectionsSectionView(
                        githubStatus: $githubStatus,
                        riotStatus: $riotStatus,
                        leetCodeStatus: $leetCodeStatus,
                        onConnectGitHub: startGitHubOAuth,
                        onConnectRiot: handleRiotConnection,
                        onConnectLeetCode: handleLeetCodeConnection
                    )
                    // statisticsSection
                    // chartsSection
                    SettingsSectionView()
                }
                .padding(.bottom, 100)
            }
        }
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            setupView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPaymentStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshGitHubStatus"))) { _ in
            Task {
                await refreshGitHubStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshLeetCodeStatus"))) { _ in
            Task {
                await refreshLeetCodeStatus()
            }
        }
        // Photo-related dialogs removed - now in PersonalUserAccount
        .alert(isPresented: $showSnapshotAlert) {
            Alert(title: Text(snapshotAlertMessage))
        }
        .onChange(of: identitySnapshotManager.uploadState) { oldValue, newValue in
            handleUploadStateChange(newValue)
        }
        .fullScreenCover(isPresented: $showingIdentitySnapshotCamera) {
            FaceDetectionCameraView(capturedImage: $identitySnapshotImage)
                .onDisappear {
                    if let data = identitySnapshotImage, let image = UIImage(data: data) {
                        capturedIdentityImage = image
                        identitySnapshotImage = nil
                        // Add a small delay to ensure fullScreenCover dismissal completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingIdentitySnapshotPreview = true
                        }
                    }
                }
        }
        .fullScreenCover(isPresented: $showingIdentitySnapshotPreview) {
            IdentitySnapshotPreviewView(
                image: capturedIdentityImage,
                isPresented: $showingIdentitySnapshotPreview,
                onSubmit: { image in
                    identitySnapshotImage = image.jpegData(compressionQuality: 0.8)
                    capturedIdentityImage = nil
                },
                onRetake: {
                    capturedIdentityImage = nil
                    showingIdentitySnapshotCamera = true
                }
            )
        }
        .onChange(of: identitySnapshotImage) { oldValue, newValue in
            if newValue != nil {
                handleIdentitySnapshotImageChange(newValue)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupView() {
        owedAmountManager.fetchOwedRecipients(token: AuthenticationManager.shared.storedAuthToken)
        
        // Only refresh if avatar URLs are missing - this avoids unnecessary delay
        if authManager.currentUser?.avatarUrl200 == nil {
            Task(priority: .userInitiated) {
                await authManager.refreshAvatarData()
            }
        }
        
        // Load payment status for notification dot
        loadConnectStatus()
        loadPaymentMethod()
        loadGitHubStatus()
        loadRiotStatus()
        loadLeetCodeStatus()
        
        // Payment stats now load automatically via PaymentStatsManager initialization
        // No manual refresh needed here
    }
    
    private func refreshPaymentStatus() {
        // Refresh payment status when app becomes active
        loadConnectStatus()
        loadPaymentMethod()
        loadGitHubStatus()
        loadLeetCodeStatus()
        // Payment stats are refreshed automatically when app comes to foreground
    }
    
    private func loadPaymentStats() {
        // This function is no longer needed as PaymentStatsManager handles loading automatically
        // Keeping for backward compatibility but it does nothing
    }

    // handleImageSelection removed - avatar editing now in PersonalUserAccount
    
    private func handleUploadStateChange(_ newState: IdentitySnapshotManager.UploadState) {
        switch newState {
        case .success(let message):
            snapshotAlertMessage = message
            showSnapshotAlert = true
        case .failure(let error):
            snapshotAlertMessage = "Update failed: \(error)"
            showSnapshotAlert = true
        case .loading, .idle:
            break
        }
    }
    
    private func handleIdentitySnapshotImageChange(_ imageData: Data?) {
        if let data = imageData, let image = UIImage(data: data) {
            Task {
                await identitySnapshotManager.upload(image: image)
            }
        }
    }
    
    // MARK: - View Components
    
    private var statisticsSection: some View {
        StatisticsSectionView(
            weeklyCompletedGoals: weeklyCompletedGoals,
            weeklyPayments: weeklyPayments,
            monthlyCompletedGoals: monthlyCompletedGoals,
            monthlyPayments: monthlyPayments
        )
    }
    
    private var chartsSection: some View {
        ChartsSectionView(
            weeklyGoalsData: weeklyGoalsData,
            weeklyPaymentsData: weeklyPaymentsData,
            weekDays: weekDays
        )
    }
    
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUPPORT")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                NavigationLink(destination: SupportView()) {
                    HStack {
                        ProfileRowContent(label: "feedback & support", icon: "message")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private var owedRecipientsList: some View {
        Group {
            if owedAmountManager.isLoadingOwed {
                loadingOwedView
            } else if let owedError = owedAmountManager.owedError {
                errorOwedView(error: owedError)
            } else if owedAmountManager.owedRecipients.isEmpty {
                emptyOwedView
            } else {
                owedRecipientsContent
            }
        }
    }
    
    private var loadingOwedView: some View {
        HStack {
            ProgressView("Loading owed amounts...")
                .padding()
            Spacer()
        }
    }
    
    private func errorOwedView(error: String) -> some View {
        HStack {
            Text("Error: \(error)")
                .foregroundColor(.red)
                .padding()
            Spacer()
        }
    }
    
    private var emptyOwedView: some View {
        HStack {
            Text("You don't owe anyone this week!")
                .foregroundColor(.white.opacity(0.7))
                .padding()
            Spacer()
        }
    }
    
    private var owedRecipientsContent: some View {
        ForEach(owedAmountManager.owedRecipients) { owed in
            owedRecipientRow(owed: owed)
        }
    }
    
    private func owedRecipientRow(owed: OwedRecipient) -> some View {
        HStack {
            Image(systemName: "person.crop.circle")
                .font(.custom("EBGaramond-Regular", size: 20))
                .foregroundColor(.white.opacity(0.7))
            Text(owed.recipient_name.isEmpty ? owed.recipient_id : owed.recipient_name)
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "$%.2f", owed.amount_owed))
                .foregroundColor(.yellow)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.clear)
    }
    
    // MARK: - Profile Components
    
    private var backButton: some View {
        HStack {
            Button(action: {
                onDismiss?()
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
    
    // Profile editing components removed - now in PersonalUserAccount
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                // Button(action: {
                //     showPaymentView()
                // }) {
                //     HStack {
                //         ProfileRowContent(label: "Payment Methods", icon: "creditcard.fill")
                        
                //         Spacer()
                        
                //         // Notification dot for payment setup
                //         if needsPaymentSetup {
                //             NotificationDot()
                //                 .padding(.trailing, 8)
                //         }
                        
                //         Image(systemName: "chevron.right")
                //             .font(.custom("EBGaramond-Regular", size: 14))
                //             .foregroundColor(.white.opacity(0.4))
                //     }
                //     .padding(.horizontal, 16)
                //     .padding(.vertical, 16)
                //     .background(Color.clear)
                // }
                
                // Divider()
                //     .background(Color.white.opacity(0.1))
                
                // Button(action: {
                //     // Post a notification to trigger PaymentHistory overlay
                //     NotificationCenter.default.post(name: Notification.Name("TriggerPaymentHistoryOverlay"), object: nil)
                // }) {
                //     ProfileRow(label: "Payment History", icon: "creditcard.circle")
                // }

                Divider()

                Button(action: {
                    showingIdentitySnapshotCamera = true
                }) {
                    ProfileRow(label: "Update Identity Snapshot", icon: "person.crop.circle.badge.checkmark")
                }
                .disabled(identitySnapshotManager.uploadState == .loading)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                Button(action: {
                    if let url = URL(string: "https://jointally.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    ProfileRow(label: "Privacy Policy", icon: "hand.raised.fill")
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                Button(action: {
                    if let url = URL(string: "https://jointally.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    ProfileRow(label: "Terms of Service", icon: "doc.text.fill")
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("payment settings")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("To change your payment settings, go to jointally.app/payment")
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showPremiumView) {
            PremiumView()
        }
        .sheet(isPresented: $showRiotConnectView) {
            RiotConnectView(preloadedAccounts: riotAccounts)
                .onDisappear {
                    // Refresh Riot status when the view closes
                    Task { await refreshRiotStatus() }
                }
        }
        .sheet(isPresented: $showLeetCodeConnectView) {
            LeetCodeConnectView()
                .onDisappear {
                    // Refresh LeetCode status when the view closes
                    Task { await refreshLeetCodeStatus() }
                }
        }
    }

    // Avatar handling methods removed - now in PersonalUserAccount

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

    // MARK: - GitHub Status Handling
    private struct GitHubStatusResponse: Codable { let status: String }

    private func loadGitHubStatus() {
        // Load cached status first – if you decide to cache it similarly to Stripe Connect
        if let raw = UserDefaults.standard.string(forKey: "cachedGithubStatus") {
            switch raw {
            case "connected": githubStatus = .connected
            case "pending": githubStatus = .pending
            default: githubStatus = .notConnected
            }
        }

        Task { await refreshGitHubStatus() }
    }

    private func refreshGitHubStatus() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/github/status") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 { return }
            let decoded = try JSONDecoder().decode(GitHubStatusResponse.self, from: data)
            await MainActor.run {
                switch decoded.status {
                case "connected": githubStatus = .connected; saveCachedGithubStatus(.connected)
                case "pending": githubStatus = .pending; saveCachedGithubStatus(.pending)
                default: githubStatus = .notConnected; saveCachedGithubStatus(.notConnected)
                }
            }
        } catch { print("❌ Error fetching GitHub status: \(error)") }
    }

    private func saveCachedGithubStatus(_ status: ConnectStatus) {
        let raw: String
        switch status {
        case .connected: raw = "connected"
        case .pending: raw = "pending"
        case .notConnected: raw = "not_connected"
        }
        UserDefaults.standard.setValue(raw, forKey: "cachedGithubStatus")
    }
    
    // MARK: - Riot Integration
    private func loadRiotStatus() {
        // Load cached status first
        if let raw = UserDefaults.standard.string(forKey: "cachedRiotStatus") {
            switch raw {
            case "connected": riotStatus = .connected
            case "pending": riotStatus = .pending
            default: riotStatus = .notConnected
            }
        }
        Task { await refreshRiotStatus() }
    }
    
    private func refreshRiotStatus() async {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        do {
            guard let url = URL(string: "\(AppConfig.baseURL)/gaming/riot-accounts") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 { return }
            
            // Setup decoder with proper date handling
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Try various date formats
                let formatters: [DateFormatter] = [
                    {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
                        f.locale = Locale(identifier: "en_US_POSIX")
                        f.timeZone = TimeZone(abbreviation: "UTC")
                        return f
                    }(),
                    {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
                        f.locale = Locale(identifier: "en_US_POSIX")
                        f.timeZone = TimeZone(abbreviation: "UTC")
                        return f
                    }()
                ]
                
                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
                
                // Fallback to ISO8601
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: dateString) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date")
            }
            
            // If we have any riot accounts, we're connected
            if let accounts = try? decoder.decode([RiotAccount].self, from: data), !accounts.isEmpty {
                await MainActor.run {
                    riotAccounts = accounts
                    riotStatus = .connected
                    saveCachedRiotStatus(.connected)
                }
            } else {
                await MainActor.run {
                    riotAccounts = []
                    riotStatus = .notConnected
                    saveCachedRiotStatus(.notConnected)
                }
            }
        } catch { 
            print("❌ Error fetching Riot status: \(error)")
            await MainActor.run {
                riotStatus = .notConnected
                saveCachedRiotStatus(.notConnected)
            }
        }
    }
    
    private func saveCachedRiotStatus(_ status: ConnectStatus) {
        let raw: String
        switch status {
        case .connected: raw = "connected"
        case .pending: raw = "pending"
        case .notConnected: raw = "not_connected"
        }
        UserDefaults.standard.setValue(raw, forKey: "cachedRiotStatus")
    }

    private func handleRiotConnection() {
        // Only show the connect view if not already connected
        if riotStatus != .connected {
            showRiotConnectView = true
        } else {
            // If already connected, show the management view
            showRiotConnectView = true
        }
    }
    
    private func startGitHubOAuth() {
        guard let token = AuthenticationManager.shared.storedAuthToken else { return }
        githubStatus = .pending
        Task {
            do {
                guard let url = URL(string: "\(AppConfig.baseURL)/github/auth-url?redirect_uri=tally://github/callback") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else { githubStatus = .notConnected; return }
                struct AuthURLResponse: Codable { let url: String }
                let decoded = try JSONDecoder().decode(AuthURLResponse.self, from: data)
                if let authUrl = URL(string: decoded.url) {
                    await MainActor.run { UIApplication.shared.open(authUrl) }
                } else { githubStatus = .notConnected }
            } catch {
                print("❌ Error initiating GitHub OAuth: \(error)"); githubStatus = .notConnected
            }
        }
    }
    
    // MARK: - LeetCode Integration
    
    private func loadLeetCodeStatus() {
        // Load cached status first
        if let raw = UserDefaults.standard.string(forKey: "cachedLeetCodeStatus") {
            switch raw {
            case "connected": leetCodeStatus = .connected
            case "pending": leetCodeStatus = .pending
            default: leetCodeStatus = .notConnected
            }
        }
        
        Task { await refreshLeetCodeStatus() }
    }
    
    private func refreshLeetCodeStatus() async {
        await LeetCodeManager.shared.checkStatus()
        await MainActor.run {
            leetCodeStatus = LeetCodeManager.shared.connectionStatus
            
            // Cache the status
            let statusString: String
            switch leetCodeStatus {
            case .connected: statusString = "connected"
            case .pending: statusString = "pending"
            case .notConnected: statusString = "notConnected"
            }
            UserDefaults.standard.set(statusString, forKey: "cachedLeetCodeStatus")
        }
    }
    
    private func handleLeetCodeConnection() {
        // Show the connect view regardless of status
        // The view will handle showing current status or allowing disconnect
        showLeetCodeConnectView = true
    }
}

// Helper view for profile row content without the full row styling
struct ProfileRowContent: View {
    let label: String
    let icon: String
    let isAssetImage: Bool
    
    init(label: String, icon: String, isAssetImage: Bool = false) {
        self.label = label
        self.icon = icon
        self.isAssetImage = isAssetImage
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if isAssetImage {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: icon)
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
            }
            
            Text(label)
                .jtStyle(.body)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    ProfileView(showPaymentView: {}, onDismiss: {})
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(HabitManager.shared)
        .environmentObject(OwedAmountManager())
        .environmentObject(IdentitySnapshotManager.shared)
        .environmentObject(PaymentManager.shared)
        .environmentObject(PaymentStatsManager.shared)
} 
