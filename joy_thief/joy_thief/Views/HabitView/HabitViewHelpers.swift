import SwiftUI
import Foundation

// MARK: - HabitView Helpers
struct HabitViewHelpers {
    
    // MARK: - Date Helpers
    
    /// Get the day label for a selected weekday index
    static func getSelectedDayLabel(for selectedWeekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        let calendar = Calendar.current
        let today = Date()
        let weekdayToday = calendar.component(.weekday, from: today)
        let weekStartSunday = calendar.date(byAdding: .day, value: -(weekdayToday - 1), to: calendar.startOfDay(for: today))!
        let date = calendar.date(byAdding: .day, value: selectedWeekday, to: weekStartSunday)!
        return formatter.string(from: date) // keep day capitalization
    }
    
    /// Get week day abbreviations
    static func getWeekDayAbbrevs() -> [String] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let today = Date()
        // Build abbreviations starting Sunday consistently
        let weekdayToday = calendar.component(.weekday, from: today) // 1–7
        guard let weekStartSunday = calendar.date(byAdding: .day, value: -(weekdayToday - 1), to: calendar.startOfDay(for: today)) else {
            return formatter.shortWeekdaySymbols // fallback
        }

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStartSunday) ?? today
            return formatter.string(from: date)
        }
    }
}

// MARK: - Date Extensions
extension Date {
    /// Returns the 7 days of the current week starting Monday.
    static var daysInCurrentWeek: [Date] {
        let cal = Calendar.current
        let today = Date()
        let interval = cal.dateInterval(of: .weekOfYear, for: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }
}

// MARK: - View Mode Switch Component
struct ViewModeSwitch: View {
    @Binding var viewMode: HabitView.ViewMode
    
    var body: some View {
        let boxWidth: CGFloat = 45  // Even smaller width
        let boxHeight: CGFloat = 28  // Slightly reduced height
        let spacing: CGFloat = 0
        let selectedIndex = HabitView.ViewMode.allCases.firstIndex(of: viewMode) ?? 0
        let totalWidth = boxWidth * CGFloat(HabitView.ViewMode.allCases.count) + spacing * CGFloat(HabitView.ViewMode.allCases.count - 1)
        return ZStack(alignment: .leading) {
            // Sliding background
            RoundedRectangle(cornerRadius: 8)  // Slightly smaller corner radius
                .fill(Color.white)
                .frame(width: boxWidth, height: boxHeight)
                .offset(x: CGFloat(selectedIndex) * (boxWidth + spacing))
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewMode)
            HStack(spacing: spacing) {
                ForEach(HabitView.ViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            viewMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.custom("EBGaramond-Regular", size: 14))  // Smaller font size
                            .foregroundColor(viewMode == mode ? .black : .white.opacity(0.8))
                            .frame(width: boxWidth, height: boxHeight)
                    }
                }
            }
        }
        .frame(width: totalWidth, height: boxHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)  // Match inner corner radius
                .fill(Color.white.opacity(0.08))
        )
        .padding(.horizontal, 20)
    }
} 