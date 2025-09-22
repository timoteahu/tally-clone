import SwiftUI
import Charts

struct ChartsSectionView: View {
    let weeklyGoalsData: [Double]
    let weeklyPaymentsData: [Double]
    let weekDays: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHARTS")
                .jtStyle(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 16)
            
            VStack(spacing: 16) {
                // Goals Progress Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekly Progress")
                        .jtStyle(.body)
                        .foregroundColor(.white)
                    
                    Chart {
                        ForEach(Array(zip(weeklyGoalsData, weekDays)), id: \.1) { goalCount, day in
                            LineMark(
                                x: .value("Day", day),
                                y: .value("Goals", goalCount)
                            )
                            .foregroundStyle(.blue)
                            .symbol(.circle)
                        }
                    }
                    .frame(height: 120)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel()
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel()
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption2)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Payments Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("credits this week")
                        .jtStyle(.body)
                        .foregroundColor(.white)
                    
                    Chart {
                        ForEach(Array(zip(weeklyPaymentsData, weekDays)), id: \.1) { paymentAmount, day in
                            BarMark(
                                x: .value("Day", day),
                                y: .value("Payments", paymentAmount)
                            )
                            .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                    .frame(height: 120)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel()
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(.white.opacity(0.2))
                            AxisValueLabel()
                                .foregroundStyle(.white.opacity(0.7))
                                .font(.caption2)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    ChartsSectionView(
        weeklyGoalsData: [1,2,3,4,5,6,7],
        weeklyPaymentsData: [0,0,1,2,0,3,1],
        weekDays: ["S","M","T","W","T","F","S"]
    )
    .background(Color.black)
} 