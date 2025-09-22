import SwiftUI

struct StatusBadge: View {
    let isCompleted: Bool
    
    var body: some View {
        Text(isCompleted ? "Completed" : "In Progress")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isCompleted ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(isCompleted ? .green : .orange)
            .clipShape(Capsule())
    }
}
