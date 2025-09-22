import SwiftUI
import Charts

// MARK: - Weekly Chart Component
struct WeeklyTasksStickChart: View {
    let completedCounts: [Int]
    let weekDays: [String]
    let selectedWeekday: Int
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let horizontalInset: CGFloat = 30
            let availableWidth = width - 2 * horizontalInset
            let stepX = availableWidth / CGFloat(max(Int(Double(completedCounts.count - 1) * 1.0), 1))
            let maxDataValue = max(completedCounts.max() ?? 1, 1)
            let chartTop = height * 0.18
            let chartBottom = height - 32
            let chartHeight = chartBottom - chartTop
            let points = completedCounts.enumerated().map { (i, count) in
                let x = horizontalInset + CGFloat(i) * stepX
                let y = chartBottom - (CGFloat(count) / CGFloat(maxDataValue)) * chartHeight
                return CGPoint(x: x, y: y)
            }
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                // Sticks (vertical lines)
                ForEach(points.indices, id: \.self) { i in
                    Path { path in
                        path.move(to: CGPoint(x: points[i].x, y: chartBottom))
                        path.addLine(to: points[i])
                    }
                    .stroke(i == selectedWeekday ? Color.white : Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                // Numbers below bars
                ForEach(points.indices, id: \.self) { i in
                    Text("\(completedCounts[i])")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(i == selectedWeekday ? .white : .blue.opacity(0.8))
                        .position(x: points[i].x, y: chartBottom + 14)
                }
            }
        }
    }
} 