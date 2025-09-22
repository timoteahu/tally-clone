import SwiftUI

struct NotificationDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: 1)
            )
    }
}

#Preview {
    NotificationDot()
        .padding()
        .background(Color.gray)
}