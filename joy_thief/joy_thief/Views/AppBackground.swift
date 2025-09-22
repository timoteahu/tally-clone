import SwiftUI

/// A reusable full-screen background gradient used across the app.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color(hex: "161C29"), location: 0.0),
                .init(color: Color(hex: "131824"), location: 0.15),
                .init(color: Color(hex: "0F141F"), location: 0.3),
                .init(color: Color(hex: "0C111A"), location: 0.45),
                .init(color: Color(hex: "0A0F17"), location: 0.6),
                .init(color: Color(hex: "080D15"), location: 0.7),
                .init(color: Color(hex: "060B12"), location: 0.8),
                .init(color: Color(hex: "03070E"), location: 0.9),
                .init(color: Color(hex: "01050B"), location: 1.0)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
} 