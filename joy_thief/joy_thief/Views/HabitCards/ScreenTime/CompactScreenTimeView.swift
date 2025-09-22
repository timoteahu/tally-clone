// //
// //  CompactScreenTime.swift
// //  joy_thief
// //
// //  Created by Timothy Hu on 6/18/25.
// //

// import SwiftUI

// struct CompactScreenTimeView: View {
//     let cardWidth: CGFloat
//     let cardHeight: CGFloat
//     @ObservedObject var screenTimeManager: ScreenTimeManager
//     let showError: (String) -> Void

//     var body: some View {
//         VStack(spacing: cardHeight * 0.02) {  // 2% spacing
//             if !screenTimeManager.isAuthorized {
//                 VStack(spacing: cardHeight * 0.015) {  // 1.5% spacing
//                     Text("Screen Time Access Required")
//                         .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04)).fontWeight(.semibold)  // Responsive font
//                         .foregroundColor(.white)
//                         .multilineTextAlignment(.center)
                    
//                     Button(action: {
//                         Task {
//                             do {
//                                 try await screenTimeManager.requestAuthorization()
//                             } catch {
//                                 showError("screen time authorization denied. please enable in settings.")
//                             }
//                         }
//                     }) {
//                         Text("Grant Access")
//                             .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.medium)  // Responsive font
//                             .frame(maxWidth: .infinity)
//                             .padding(.vertical, cardHeight * 0.015)  // 1.5% vertical padding
//                             .background(Color.blue)
//                             .foregroundColor(.white)
//                             .cornerRadius(cardWidth * 0.02)  // 2% corner radius
//                     }
//                 }
//                 .padding(cardWidth * 0.04)  // 4% padding
//                 .background(Color.white.opacity(0.05))
//                 .cornerRadius(cardWidth * 0.025)  // 2.5% corner radius
//             } else if let status = screenTimeManager.currentStatus {
//                 VStack(spacing: cardHeight * 0.015) {  // 1.5% spacing
//                     HStack {
//                         VStack(alignment: .leading, spacing: cardHeight * 0.005) {  // 0.5% spacing
//                             Text("Time Used")
//                                 .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))  // Responsive font
//                                 .foregroundColor(.white.opacity(0.7))
//                             Text("\(status.totalTimeMinutes) min")
//                                 .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04)).fontWeight(.bold)  // Responsive font
//                                 .foregroundColor(.white)
//                         }
                        
//                         Spacer()
                        
//                         VStack(alignment: .trailing, spacing: cardHeight * 0.005) {  // 0.5% spacing
//                             Text("Daily Limit")
//                                 .font(.custom("EBGaramond-Regular", size: cardWidth * 0.03))  // Responsive font
//                                 .foregroundColor(.white.opacity(0.7))
//                             Text("\(status.limitMinutes) min")
//                                 .font(.custom("EBGaramond-Regular", size: cardWidth * 0.04)).fontWeight(.bold)  // Responsive font
//                                 .foregroundColor(.white)
//                         }
//                     }
                    
//                     ProgressView(value: Double(status.totalTimeMinutes), total: Double(status.limitMinutes))
//                         .tint(status.status == "over_limit" ? .red : status.status == "near_limit" ? .yellow : .green)
//                         .frame(height: cardHeight * 0.01)  // 1% height
                    
//                     Button(action: { /* Refresh logic */ }) {
//                         Text("Refresh Status")
//                             .font(.custom("EBGaramond-Regular", size: cardWidth * 0.035)).fontWeight(.medium)  // Responsive font
//                             .frame(maxWidth: .infinity)
//                             .padding(.vertical, cardHeight * 0.012)  // 1.2% vertical padding
//                             .background(Color.blue)
//                             .foregroundColor(.white)
//                             .cornerRadius(cardWidth * 0.02)  // 2% corner radius
//                     }
//                 }
//                 .padding(cardWidth * 0.04)  // 4% padding
//                 .background(Color.white.opacity(0.05))
//                 .cornerRadius(cardWidth * 0.025)  // 2.5% corner radius
//             } else {
//                 ProgressView()
//                     .progressViewStyle(CircularProgressViewStyle(tint: .white))
//                     .scaleEffect(1.2)
//             }
//         }
//     }
// }

