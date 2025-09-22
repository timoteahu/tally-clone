import SwiftUI

// Persistent user toggles
private enum PreferenceKey: String {
    case pushEnabled, emailEnabled
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var showingDebugOutput = false
    @State private var debugText = ""
    
    var body: some View {
        ZStack {
            AppBackground()
            NavigationStack {
                List {
                    Section(header: Text("Account")) {
                        if let user = authManager.currentUser {
                            Text("Name: \(user.name)")
                        }
                        
                        Button(action: {
                            Task {
                                await authManager.logout()
                            }
                        }) {
                            HStack {
                                Text("Logout")
                                    .foregroundColor(.red)
                                Spacer()
                                Image(systemName: "arrow.right.square")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Section(header: Text("Notifications")) {
                        HStack {
                            Text("Permission Status")
                            Spacer()
                            Text(notificationManager.permissionGranted ? "Granted" : "Not Granted")
                                .foregroundColor(notificationManager.permissionGranted ? .green : .red)
                        }
                        
                        HStack {
                            Text("Device Token")
                            Spacer()
                            Text(notificationManager.deviceToken != nil ? "Registered" : "None")
                                .foregroundColor(notificationManager.deviceToken != nil ? .green : .red)
                        }
                        
                        Button("Request Permission") {
                            Task {
                                await notificationManager.forceRequestPermission()
                            }
                        }
                        
                        Button("Test Token Registration") {
                            Task {
                                await notificationManager.testDeviceTokenRegistration()
                            }
                        }
                        
                        Button("Show Debug Info") {
                            showDebugInfo()
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Section(header: Text("App Settings")) {
                        Toggle("Enable Notifications", isOn: .constant(true))
                        Toggle("Dark Mode", isOn: .constant(false))
                    }
                    
                    Section(header: Text("About")) {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .navigationTitle("Settings")
                .sheet(isPresented: $showingDebugOutput) {
                    NavigationView {
                        ScrollView {
                            Text(debugText)
                                .jtStyle(.caption)
                                .padding()
                        }
                        .navigationTitle("Debug Info")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingDebugOutput = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func showDebugInfo() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            
            let debugInfo = """
            📱 NOTIFICATION DEBUG INFO
            ═══════════════════════════════
            
            🔔 Permission Status:
            • Authorization: \(authorizationStatusString(settings.authorizationStatus))
            • Alert Setting: \(notificationSettingString(settings.alertSetting))
            • Badge Setting: \(notificationSettingString(settings.badgeSetting))
            • Sound Setting: \(notificationSettingString(settings.soundSetting))
            
            📟 Device Token:
            • Has Token: \(notificationManager.deviceToken != nil ? "YES" : "NO")
            • Token Length: \(notificationManager.deviceToken?.count ?? 0) chars
            • Token Preview: \(notificationManager.deviceToken?.prefix(20) ?? "N/A")...
            
            🔐 Authentication:
            • Is Authenticated: \(authManager.isAuthenticated ? "YES" : "NO")
            • User ID: \(authManager.currentUser?.id ?? "N/A")
            • Has Auth Token: \(AuthenticationManager.shared.storedAuthToken != nil ? "YES" : "NO")
            
            🌐 Backend Configuration:
            • Base URL: \(AppConfig.baseURL)
            • Registration Endpoint: \(AppConfig.baseURL)/notifications/register-device-token
            
            💡 TROUBLESHOOTING STEPS:
            1. Check if notification permission is granted
            2. Verify device token is received from Apple
            3. Confirm authentication is working
            4. Test backend registration endpoint
            5. Check backend logs for errors
            
            📋 NEXT STEPS:
            • If permission not granted: Tap "Request Permission"
            • If no device token: Check Apple Push Notification setup
            • If registration fails: Check network and auth token
            """
            
            await MainActor.run {
                debugText = debugInfo
                showingDebugOutput = true
            }
        }
    }
    
    private func authorizationStatusString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
    
    private func notificationSettingString(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .notSupported: return "Not Supported"
        @unknown default: return "Unknown"
        }
    }
}

// Placeholder detail views ─ replace with real ones
private struct EditProfileView: View {
    var body: some View { Text("Edit Profile") }
}
private struct AboutView: View {
    var body: some View { Text("Version 1.0.0") }
}
