// // Models/ScreenTimeStatus.swift
// import Foundation

// struct ScreenTimeStatus: Codable {
//     let totalTimeMinutes: Int
//     let limitMinutes:  Int
//     let restrictedApps: [String]
//     let status: String          // e.g. "under_limit", "over_limit"

//     // Map JSON keys → Swift names
//     private enum CodingKeys: String, CodingKey {
//         case totalTimeMinutes = "total_time_minutes"
//         case limitMinutes    = "limit_minutes"
//         case restrictedApps  = "restricted_apps"
//         case status
//     }
// }
