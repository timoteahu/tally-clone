// import SwiftUI
// import FamilyControls
// import DeviceActivity
// import ManagedSettings
// import Foundation

// // MARK: – Error type ----------------------------------------------------------

// enum ScreenTimeError: Error {
//     case authorizationDenied
//     case monitoringFailed
//     case networkError
// }

// // MARK: – Manager -------------------------------------------------------------

// @MainActor
// final class ScreenTimeManager: ObservableObject {

//     // Singleton
//     static let shared = ScreenTimeManager()

//     // Apple frameworks
//     private let authCenter     = AuthorizationCenter.shared
//     private let deviceActivity = DeviceActivityCenter()
//     private let settingsStore  = ManagedSettingsStore()

//     // Published state
//     @Published var isAuthorized       = false
//     @Published var currentStatus      : ScreenTimeStatus?
//     @Published var monitoringSchedule : DeviceActivitySchedule?

//     // MARK: – Init ------------------------------------------------------------

//     private init() {
//         Task { await refreshAuthorization() }
//     }

//     func refreshAuthorization() async {
//         isAuthorized = authCenter.authorizationStatus == .approved
//     }

//     func requestAuthorization() async throws {
//         do {
//             try await authCenter.requestAuthorization(for: .individual)
//             isAuthorized = true
//         } catch {
//             throw ScreenTimeError.authorizationDenied
//         }
//     }

//     // MARK: – Monitoring ------------------------------------------------------

//     /// Starts daily monitoring and (optionally) applies a shield
//     func startMonitoring(for habit: Habit) async throws {
//         if !isAuthorized { try await requestAuthorization() }

//         do {
//             try deviceActivity.startMonitoring(.daily, during: .daily)
//             monitoringSchedule = .daily
//         } catch {
//             throw ScreenTimeError.monitoringFailed
//         }

//         if habit.requiresShielding { setAppRestrictions(for: habit) }
//     }

//     func stopMonitoring() {
//         deviceActivity.stopMonitoring([.daily])   // ← wrap in square brackets
//         monitoringSchedule = nil
//         settingsStore.shield.applications = nil
//     }


//     // MARK: – App shielding ---------------------------------------------------

//     func setAppRestrictions(for habit: Habit) { /* no-op */ }


//     // MARK: – Backend calls ---------------------------------------------------

//     /// POST /screen-time/{habitId}/update   (returns the latest status)
//     func updateScreenTimeStatus(habitId: String,
//                                 token: String) async throws {

//         let url = URL(string: "\(AppConfig.baseURL)/habit-verification/screen-time/\(habitId)/update")!
//         var req = URLRequest(url: url)
//         req.httpMethod = "POST"
//         req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//         req.setValue("Bearer \(token)",       forHTTPHeaderField: "Authorization")

//         // Build a simple payload from the FamilyControls picker
//         // MARK: – Backend update payload ------------------------------------------

//         let selection = FamilyActivitySelection.shared
//         let payload: [String: Any] = [
//             "total_time_minutes": 0,   // TODO: fill with real data
//             "restricted_apps": selection.applicationTokens.compactMap {
//                 Application(token: $0).bundleIdentifier
//             },
//             "status": "under_limit"
//         ]


//         req.httpBody = try JSONSerialization.data(withJSONObject: payload)

//         let (data, resp) = try await URLSession.shared.data(for: req)
//         guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
//             throw ScreenTimeError.networkError
//         }
//         currentStatus = try JSONDecoder().decode(ScreenTimeStatus.self, from: data)
//     }

//     /// GET /screen-time/{habitId}/status
//     func fetchScreenTimeStatus(habitId: String,
//                                token: String) async throws -> ScreenTimeStatus {

//         let url = URL(string: "\(AppConfig.baseURL)/habit-verification/screen-time/\(habitId)/status")!
//         var req = URLRequest(url: url)
//         req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

//         let (data, resp) = try await URLSession.shared.data(for: req)
//         guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
//             throw ScreenTimeError.networkError
//         }
//         return try JSONDecoder().decode(ScreenTimeStatus.self, from: data)
//     }
// }
