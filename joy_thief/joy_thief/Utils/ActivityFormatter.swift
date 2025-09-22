import Foundation

// MARK: - Activity Formatter
struct ActivityFormatter {
    /// Convert a Date to a human-readable activity text like "Active 2h ago"
    static func getActivityDisplayText(from date: Date?) -> String {
        guard let date = date else {
            return "Never"
        }
        
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        // Active now (within 5 minutes)
        if diff < 300 {
            return "Active now"
        }
        
        // Calculate time units
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)
        
        // Format activity text
        if minutes < 60 {
            return "Active \(minutes)m ago"
        } else if hours < 24 {
            return "Active \(hours)h ago"
        } else if days == 1 {
            return "Active yesterday"
        } else if days < 7 {
            return "Active \(days)d ago"
        } else if days < 14 {
            return "Active 1w ago"
        } else if days < 30 {
            let weeks = days / 7
            return "Active \(weeks)w ago"
        } else {
            return "Active 2+ weeks ago"
        }
    }
}